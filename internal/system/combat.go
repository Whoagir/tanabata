package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/types"
	"go-tower-defense/pkg/hexmap"
	"log"
	"math"
	"math/rand"
	"sort"
	"time"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// CombatSystem управляет атакой башен
type CombatSystem struct {
	ecs               *entity.ECS
	powerSourceFinder func(towerID types.EntityID) []types.EntityID
	pathFinder        func(towerID types.EntityID) []types.EntityID
}

func NewCombatSystem(ecs *entity.ECS,
	finder func(towerID types.EntityID) []types.EntityID,
	pathFinder func(towerID types.EntityID) []types.EntityID) *CombatSystem {
	rand.Seed(time.Now().UnixNano())
	return &CombatSystem{
		ecs:               ecs,
		powerSourceFinder: finder,
		pathFinder:        pathFinder,
	}
}

func (s *CombatSystem) Update(deltaTime float64) {
	// Сначала обновим вращение всех маяков, это должно происходить всегда
	for id, beam := range s.ecs.RotatingBeams {
		if tower, ok := s.ecs.Towers[id]; ok && tower.IsActive {
			beam.CurrentAngle += beam.RotationSpeed * deltaTime
			beam.CurrentAngle = math.Mod(beam.CurrentAngle, 2*math.Pi)
			if beam.CurrentAngle < 0 {
				beam.CurrentAngle += 2 * math.Pi
			}
		}
	}

	// Затем обрабатываем логику атаки для всех башен
	for id, combat := range s.ecs.Combats {
		tower, hasTower := s.ecs.Towers[id]
		if !hasTower || !tower.IsActive {
			continue
		}

		towerDef, ok := defs.TowerDefs[tower.DefID]
		if !ok {
			log.Printf("CombatSystem: Could not find tower definition for ID %s", tower.DefID)
			continue
		}

		if combat.FireCooldown > 0 {
			combat.FireCooldown -= deltaTime
			continue
		}

		powerSources := s.powerSourceFinder(id)
		if len(powerSources) == 0 {
			continue
		}

		var totalReserve float64
		for _, sourceID := range powerSources {
			if ore, ok := s.ecs.Ores[sourceID]; ok {
				totalReserve += ore.CurrentReserve
			}
		}

		if totalReserve < combat.ShotCost {
			continue
		}

		// --- Логика атаки ---
		attackPerformed := false
		switch combat.Attack.Type {
		case defs.BehaviorProjectile:
			attackPerformed = s.handleProjectileAttack(id, tower, combat, &towerDef)
		case defs.BehaviorLaser:
			attackPerformed = s.handleLaserAttack(id, tower, combat, &towerDef)
		case defs.BehaviorRotatingBeam:
			// Для маяка deltaTime не передаем, т.к. вращение уже произошло
			attackPerformed = s.handleRotatingBeamAttack(id, tower, combat, &towerDef)
		default:
			attackPerformed = s.handleProjectileAttack(id, tower, combat, &towerDef)
		}
		// --- Конец логики атаки ---

		if attackPerformed {
			availableSources := []types.EntityID{}
			for _, sourceID := range powerSources {
				if ore, ok := s.ecs.Ores[sourceID]; ok && ore.CurrentReserve > 0 {
					availableSources = append(availableSources, sourceID)
				}
			}
			if len(availableSources) > 0 {
				chosenSourceID := availableSources[rand.Intn(len(availableSources))]
				chosenOre := s.ecs.Ores[chosenSourceID]
				cost := combat.ShotCost
				if chosenOre.CurrentReserve >= cost {
					chosenOre.CurrentReserve -= cost
				} else {
					chosenOre.CurrentReserve = 0
				}
				fireRate := combat.FireRate
				if auraEffect, ok := s.ecs.AuraEffects[id]; ok {
					fireRate *= auraEffect.SpeedMultiplier
				}
				combat.FireCooldown = 1.0 / fireRate
			}
		}
	}
}

func (s *CombatSystem) handleLaserAttack(towerID types.EntityID, tower *component.Tower, combat *component.Combat, towerDef *defs.TowerDefinition) bool {
	// 1. Найти одну ближайшую цель
	targets := s.findTargetsForSplitAttack(tower.Hex, combat.Range, 1)
	if len(targets) == 0 {
		return false
	}
	targetID := targets[0]
	targetPos, okPos := s.ecs.Positions[targetID]
	targetRenderable, okRender := s.ecs.Renderables[targetID]
	if !okPos || !okRender {
		return false
	}

	// 2. Рассчитать урон (логика аналогична handleProjectileAttack)
	powerSources := s.powerSourceFinder(towerID)
	if len(powerSources) == 0 {
		return false
	}
	chosenSourceID := powerSources[rand.Intn(len(powerSources))]
	chosenOre := s.ecs.Ores[chosenSourceID]
	boostMultiplier := calculateOreBoostMultiplier(chosenOre.CurrentReserve)
	pathToSource := s.pathFinder(towerID)
	degradationMultiplier := s.calculateLineDegradationMultiplier(pathToSource)
	baseDamage := float64(towerDef.Combat.Damage)
	finalDamage := int(math.Round(baseDamage * boostMultiplier * degradationMultiplier))

	// 3. Применить урон и эффекты напрямую
	ApplyDamage(s.ecs, targetID, finalDamage, combat.Attack.DamageType)

	// Применяем замедление, если оно есть
	if combat.Attack.Params != nil && combat.Attack.Params.SlowMultiplier != nil && combat.Attack.Params.SlowDuration != nil {
		slowMultiplier := *combat.Attack.Params.SlowMultiplier
		slowDuration := *combat.Attack.Params.SlowDuration
		if slowMultiplier > 0 && slowDuration > 0 {
			if existingEffect, ok := s.ecs.SlowEffects[targetID]; ok {
				existingEffect.Timer = slowDuration
			} else {
				s.ecs.SlowEffects[targetID] = &component.SlowEffect{
					SlowFactor: 1.0 - slowMultiplier,
					Timer:      slowDuration,
				}
			}
		}
	}

	// 4. Создать сущность с компонентом Laser для визуализации
	laserID := s.ecs.NewEntity()
	towerX, towerY := tower.Hex.ToPixel(float64(config.HexSize))
	towerRenderable := s.ecs.Renderables[towerID]

	// Получаем высоты
	fromHeight := getTowerRenderHeight(tower, towerRenderable)
	toHeight := float32(targetRenderable.Radius * config.CoordScale)

	s.ecs.Lasers[laserID] = &component.Laser{
		FromX:      towerX,
		FromY:      towerY,
		FromHeight: float64(fromHeight),
		ToX:        targetPos.X,
		ToY:        targetPos.Y,
		ToHeight:   float64(toHeight),
		Color:      getProjectileColorByAttackType(combat.Attack.DamageType),
		Duration:   0.15, // Короткая вспышка
		Timer:      0,
	}
	s.ecs.Renderables[laserID] = &component.Renderable{}

	return true
}

// getTowerRenderHeight рассчитывает высоту башни для рендеринга.
// Эта функция является дубликатом из render.go, чтобы избежать циклической зависимости.
func getTowerRenderHeight(tower *component.Tower, renderable *component.Renderable) float32 {
	scaledRadius := float32(renderable.Radius * config.CoordScale)
	towerDef, ok := defs.TowerDefs[tower.DefID]
	if !ok {
		return scaledRadius * 4
	}

	switch {
	case towerDef.Type == defs.TowerTypeWall:
		return scaledRadius * 1.5
	case towerDef.Type == defs.TowerTypeMiner:
		return scaledRadius * 9.0
	case tower.CraftingLevel >= 1:
		return scaledRadius * 4.0
	default:
		return scaledRadius * 7.0
	}
}


func (s *CombatSystem) handleProjectileAttack(towerID types.EntityID, tower *component.Tower, combat *component.Combat, towerDef *defs.TowerDefinition) bool {
	// Для INTERNAL атак цель не нужна, просто считаем выстрел успешным
	if combat.Attack.DamageType == defs.AttackInternal {
		return true
	}

	splitCount := 1
	if combat.Attack.Params != nil && combat.Attack.Params.SplitCount != nil {
		splitCount = *combat.Attack.Params.SplitCount
	}
	if splitCount <= 0 {
		splitCount = 1
	}

	targets := s.findTargetsForSplitAttack(tower.Hex, combat.Range, splitCount)
	if len(targets) == 0 {
		return false
	}
	powerSources := s.powerSourceFinder(towerID)
	if len(powerSources) == 0 {
		return false
	}
	var totalReserve float64
	for _, sourceID := range powerSources {
		if ore, ok := s.ecs.Ores[sourceID]; ok {
			totalReserve += ore.CurrentReserve
		}
	}
	chosenSourceID := powerSources[rand.Intn(len(powerSources))]
	chosenOre := s.ecs.Ores[chosenSourceID]
	boostMultiplier := calculateOreBoostMultiplier(chosenOre.CurrentReserve)
	pathToSource := s.pathFinder(towerID)
	degradationMultiplier := s.calculateLineDegradationMultiplier(pathToSource)
	baseDamage := float64(towerDef.Combat.Damage)
	finalDamage := int(math.Round(baseDamage * boostMultiplier * degradationMultiplier))
	for _, enemyID := range targets {
		s.createProjectile(towerID, tower, enemyID, towerDef, finalDamage)
	}
	return true
}

// findTargetsForSplitAttack находит до `count` ближайших врагов.
func (s *CombatSystem) findTargetsForSplitAttack(towerHex hexmap.Hex, rangeRadius int, count int) []types.EntityID {
	type enemyWithDist struct {
		id   types.EntityID
		dist float64
	}
	var candidates []enemyWithDist

	for enemyID, enemyPos := range s.ecs.Positions {
		if _, isEnemy := s.ecs.Enemies[enemyID]; !isEnemy {
			continue
		}
		// Проверяем, что у врага есть здоровье и оно больше 0
		if health, hasHealth := s.ecs.Healths[enemyID]; !hasHealth || health.Value <= 0 {
			continue
		}
		enemyHex := hexmap.PixelToHex(enemyPos.X, enemyPos.Y, float64(config.HexSize)) // ИСПРАВЛЕНО
		distance := float64(towerHex.Distance(enemyHex))

		if distance <= float64(rangeRadius) {
			candidates = append(candidates, enemyWithDist{id: enemyID, dist: distance})
		}
	}

	// Сортируем врагов по дистанции
	sort.Slice(candidates, func(i, j int) bool {
		return candidates[i].dist < candidates[j].dist
	})

	// Берем первых `count` врагов
	numTargets := count
	if len(candidates) < numTargets {
		numTargets = len(candidates)
	}

	targets := make([]types.EntityID, numTargets)
	for i := 0; i < numTargets; i++ {
		targets[i] = candidates[i].id
	}

	return targets
}

func (s *CombatSystem) createProjectile(towerID types.EntityID, tower *component.Tower, enemyID types.EntityID, towerDef *defs.TowerDefinition, damage int) {
	projID := s.ecs.NewEntity()
	towerX, towerY := tower.Hex.ToPixel(float64(config.HexSize)) // ИСПРАВЛЕНО
	towerPos := &component.Position{X: towerX, Y: towerY}

	predictedPos := s.predictTargetPosition(enemyID, towerPos, config.ProjectileSpeed)
	direction := calculateDirection(towerPos, &predictedPos)

	attackDef := towerDef.Combat.Attack
	projectileColor := getProjectileColorByAttackType(attackDef.DamageType)

	proj := &component.Projectile{
		TargetID:   enemyID,
		Speed:      config.ProjectileSpeed,
		Damage:     damage,
		Color:      projectileColor,
		Direction:  direction,
		AttackType: attackDef.DamageType,
	}

	// --- Инициализация полей для самонаведения ---
	proj.IsConditionallyHoming = true
	if slowEffect, ok := s.ecs.SlowEffects[enemyID]; ok {
		proj.TargetLastSlowFactor = slowEffect.SlowFactor
	} else {
		proj.TargetLastSlowFactor = 1.0 // 1.0 означает отсутствие замедления
	}

	if attackDef.DamageType == defs.AttackSlow {
		proj.SlowsTarget = true
		proj.SlowDuration = 2.0
		proj.SlowFactor = 0.5
	}

	if attackDef.DamageType == defs.AttackPoison {
		proj.AppliesPoison = true
		proj.PoisonDuration = 2.0
		proj.PoisonDPS = 10
	}

	s.ecs.Positions[projID] = &component.Position{X: towerPos.X, Y: towerPos.Y}
	s.ecs.Projectiles[projID] = proj
	s.ecs.Renderables[projID] = &component.Renderable{
		Color:     proj.Color,
		Radius:    config.ProjectileRadius,
		HasStroke: false,
	}
}

// calculateOreBoostMultiplier рассчитывает множитель урона на основе запаса руды.
func calculateOreBoostMultiplier(currentReserve float64) float64 {
	lowT := config.OreBonusLowThreshold
	highT := config.OreBonusHighThreshold
	maxM := config.OreBonusMaxMultiplier
	minM := config.OreBonusMinMultiplier

	if currentReserve <= lowT {
		return maxM
	}
	if currentReserve >= highT {
		return minM
	}
	multiplier := (currentReserve-lowT)*(minM-maxM)/(highT-lowT) + maxM
	return multiplier
}

// calculateLineDegradationMultiplier рассчитывает штраф к урону от длины цепи.
func (s *CombatSystem) calculateLineDegradationMultiplier(path []types.EntityID) float64 {
	if path == nil {
		return 1.0 // Нет пути - нет штрафа
	}

	attackerCount := 0
	for _, towerID := range path {
		if tower, ok := s.ecs.Towers[towerID]; ok {
			if towerDef, ok := defs.TowerDefs[tower.DefID]; ok {
				if towerDef.Type != defs.TowerTypeMiner && towerDef.Type != defs.TowerTypeWall {
					attackerCount++
				}
			}
		}
	}
	return math.Pow(config.LineDegradationFactor, float64(attackerCount))
}

func getProjectileColorByAttackType(attackType defs.AttackDamageType) rl.Color {
	switch attackType {
	case defs.AttackPhysical:
		return config.ProjectileColorPhysicalRL
	case defs.AttackMagical:
		return config.ProjectileColorMagicalRL
	case defs.AttackPure:
		return config.ProjectileColorPureRL
	case defs.AttackSlow:
		return config.ProjectileColorSlowRL
	case defs.AttackPoison:
		return config.ProjectileColorPoisonRL
	default:
		return config.ProjectileColorPureRL // По умолчанию чистый урон
	}
}

// predictTargetPosition рассчитывает точку перехвата цели, учитывая текущее замедление.
func (s *CombatSystem) predictTargetPosition(enemyID types.EntityID, towerPos *component.Position, projSpeed float64) component.Position {
	enemyPos := s.ecs.Positions[enemyID]
	enemyVel := s.ecs.Velocities[enemyID]
	path, hasPath := s.ecs.Paths[enemyID]

	if enemyPos == nil || enemyVel == nil || !hasPath || path.CurrentIndex >= len(path.Hexes) {
		if enemyPos != nil {
			return *enemyPos
		}
		return component.Position{} // Возвращаем нулевую позицию, если данных нет
	}

	// Проверяем, замедлена ли цель
	currentSpeed := enemyVel.Speed
	if slowEffect, ok := s.ecs.SlowEffects[enemyID]; ok {
		currentSpeed *= slowEffect.SlowFactor
	}

	// Итеративн��й расчет точки перехвата
	const maxIterations = 5
	timeToHit := 0.0
	for iter := 0; iter < maxIterations; iter++ {
		predictedPos := simulateEnemyMovement(enemyPos, path, currentSpeed, timeToHit)
		dx := predictedPos.X - towerPos.X
		dy := predictedPos.Y - towerPos.Y
		newTimeToHit := math.Sqrt(dx*dx+dy*dy) / projSpeed
		if math.Abs(newTimeToHit-timeToHit) < 0.01 {
			return predictedPos
		}
		timeToHit = newTimeToHit
	}
	return simulateEnemyMovement(enemyPos, path, currentSpeed, timeToHit)
}

func simulateEnemyMovement(startPos *component.Position, path *component.Path, speed float64, duration float64) component.Position {
	currentPos := *startPos
	remainingTime := duration
	currentIndex := path.CurrentIndex
	for currentIndex < len(path.Hexes) && remainingTime > 0 {
		targetHex := path.Hexes[currentIndex]
		tx, ty := targetHex.ToPixel(float64(config.HexSize)) // ИСПРАВЛЕНО
		dx := tx - currentPos.X
		dy := ty - currentPos.Y
		distToNext := math.Sqrt(dx*dx + dy*dy)
		if distToNext < 0.01 {
			currentIndex++
			continue
		}
		timeToNext := distToNext / speed
		if timeToNext >= remainingTime {
			fraction := remainingTime / timeToNext
			currentPos.X += dx * fraction
			currentPos.Y += dy * fraction
			break
		} else {
			currentPos.X = tx
			currentPos.Y = ty
			currentIndex++
			remainingTime -= timeToNext
		}
	}
	return currentPos
}

func calculateDirection(from, to *component.Position) float64 {
	dx := to.X - from.X
	dy := to.Y - from.Y
	return math.Atan2(dy, dx)
}

func (s *CombatSystem) handleRotatingBeamAttack(towerID types.EntityID, tower *component.Tower, combat *component.Combat, towerDef *defs.TowerDefinition) bool {
	beam, ok := s.ecs.RotatingBeams[towerID]
	if !ok {
		return false
	}

	// Вращение уже произошло в Update. Здесь только логика урона.
	towerX, towerY := tower.Hex.ToPixel(float64(config.HexSize)) // ИСПРАВЛЕНО
	towerPos := &component.Position{X: towerX, Y: towerY}

	enemiesInRange := s.findEnemiesInRadius(tower.Hex, beam.Range)
	if len(enemiesInRange) == 0 {
		return false
	}

	hitOccurred := false
	finalDamage := s.calculateFinalDamage(towerID, towerDef.Combat.Damage)
	damageCooldown := 1.0 / combat.FireRate

	for _, enemyID := range enemiesInRange {
		// Проверяем кулдаун для каждого врага индивидуально
		lastHit, wasHit := beam.LastHitTime[enemyID]
		if wasHit && (s.ecs.GameTime-lastHit) < damageCooldown {
			continue
		}

		enemyPos := s.ecs.Positions[enemyID]
		if enemyPos == nil {
			continue
		}

		angleToEnemy := math.Atan2(enemyPos.Y-towerPos.Y, enemyPos.X-towerPos.X)
		if angleToEnemy < 0 {
			angleToEnemy += 2 * math.Pi
		}

		diff := angleToEnemy - beam.CurrentAngle
		if diff > math.Pi {
			diff -= 2 * math.Pi
		} else if diff < -math.Pi {
			diff += 2 * math.Pi
		}

		if math.Abs(diff) <= beam.ArcAngle/2 {
			ApplyDamage(s.ecs, enemyID, finalDamage, defs.AttackDamageType(beam.DamageType))
			beam.LastHitTime[enemyID] = s.ecs.GameTime // Обновляем время последнего удара для этого врага
			hitOccurred = true
		}
	}

	return hitOccurred
}

func (s *CombatSystem) calculateFinalDamage(towerID types.EntityID, baseDamage int) int {
	powerSources := s.powerSourceFinder(towerID)
	if len(powerSources) == 0 {
		return baseDamage // Возвращаем базовый урон, если нет источников
	}
	// Для упрощения пока берем первый источник
	chosenSourceID := powerSources[0]
	chosenOre, ok := s.ecs.Ores[chosenSourceID]
	if !ok {
		return baseDamage
	}

	boostMultiplier := calculateOreBoostMultiplier(chosenOre.CurrentReserve)
	pathToSource := s.pathFinder(towerID)
	degradationMultiplier := s.calculateLineDegradationMultiplier(pathToSource)

	finalDamage := float64(baseDamage) * boostMultiplier * degradationMultiplier
	return int(math.Round(finalDamage))
}

// findEnemiesInRadius находит всех врагов в заданном радиусе от гекса.
func (s *CombatSystem) findEnemiesInRadius(towerHex hexmap.Hex, rangeRadius int) []types.EntityID {
	var targets []types.EntityID
	for enemyID, enemyPos := range s.ecs.Positions {
		if _, isEnemy := s.ecs.Enemies[enemyID]; !isEnemy {
			continue
		}
		if health, hasHealth := s.ecs.Healths[enemyID]; !hasHealth || health.Value <= 0 {
			continue
		}
		enemyHex := hexmap.PixelToHex(enemyPos.X, enemyPos.Y, float64(config.HexSize)) // ИСПРАВЛЕНО
		if towerHex.Distance(enemyHex) <= rangeRadius {
			targets = append(targets, enemyID)
		}
	}
	return targets
}

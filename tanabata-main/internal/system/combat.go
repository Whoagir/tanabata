package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/event" // Импортируем пакет событий
	"go-tower-defense/internal/types"
	"go-tower-defense/internal/utils"
	"go-tower-defense/pkg/hexmap"
	"log"
	"math"
	"math/rand"
	"sort"
	"time"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// OreConsumptionData содержит информацию о потраченной руде.
type OreConsumptionData struct {
	SourceID types.EntityID
	Amount   float64
}

// CombatSystem управляет атакой башен
type CombatSystem struct {
	ecs               *entity.ECS
	eventDispatcher   *event.Dispatcher // Добавляем диспатчер
	powerSourceFinder func(towerID types.EntityID) []types.EntityID
	pathFinder        func(towerID types.EntityID) []types.EntityID
}

func NewCombatSystem(ecs *entity.ECS, dispatcher *event.Dispatcher,
	finder func(towerID types.EntityID) []types.EntityID,
	pathFinder func(towerID types.EntityID) []types.EntityID) *CombatSystem {
	rand.Seed(time.Now().UnixNano())
	return &CombatSystem{
		ecs:               ecs,
		eventDispatcher:   dispatcher, // Сохраняем диспатчер
		powerSourceFinder: finder,
		pathFinder:        pathFinder,
	}
}

func (s *CombatSystem) Update(deltaTime float64) {
	for id, combat := range s.ecs.Combats {
		tower, hasTower := s.ecs.Towers[id]
		if !hasTower {
			continue
		}

		// --- ОБНОВЛЕННЫЙ БЛОК: Логика вращения турели с "прилипанием" и вертикальным наведением ---
		if turret, hasTurret := s.ecs.Turrets[id]; hasTurret {
			targetIsValid := false
			// 1. Проверяем, есть ли у нас уже цель и валидна ли она.
			if turret.TargetID != 0 {
				if targetPos, exists := s.ecs.Positions[turret.TargetID]; exists {
					if health, hasHealth := s.ecs.Healths[turret.TargetID]; hasHealth && health.Value > 0 {
						towerPosPixelX, towerPosPixelY := tower.Hex.ToPixel(config.HexSize)
						distSq := (targetPos.X-towerPosPixelX)*(targetPos.X-towerPosPixelX) + (targetPos.Y-towerPosPixelY)*(targetPos.Y-towerPosPixelY)
						// Проверяем, что цель все еще в РАДИУСЕ ЗАХВАТА
						if distSq < float64(turret.AcquisitionRange*turret.AcquisitionRange*config.HexSize*config.HexSize) {
							targetIsValid = true
						}
					}
				}
			}

			// 2. Если текущая цель невалидна, ищем новую.
			if !targetIsValid {
				targets := s.findTargetsForSplitAttack(tower.Hex, int(turret.AcquisitionRange), 1)
				if len(targets) > 0 {
					turret.TargetID = targets[0]
				} else {
					turret.TargetID = 0 // Целей нет, сбрасываем
				}
			}

			// 3. Если есть валидная цель (старая или новая), наводимся на нее.
			if turret.TargetID != 0 {
				towerPosX, towerPosY := tower.Hex.ToPixel(config.HexSize)
				startPos := &component.Position{X: towerPosX, Y: towerPosY}
				predictedPos := s.predictTargetPosition(turret.TargetID, startPos, config.ProjectileSpeed)

				// Расчет горизонтального угла (Yaw)
				dx := predictedPos.X - towerPosX
				dy := predictedPos.Y - towerPosY
				turret.TargetAngle = float32(math.Atan2(dy, dx))

				// Расчет вертикального угла (Pitch)
				if towerRenderable, ok := s.ecs.Renderables[id]; ok {
					if targetRenderable, ok := s.ecs.Renderables[turret.TargetID]; ok {
						turretHeadHeight := getTowerRenderHeight(tower, towerRenderable)
						targetHeight := targetRenderable.Radius * float32(config.CoordScale)
						deltaHeight := targetHeight - turretHeadHeight
						horizontalDist := float32(math.Sqrt(dx*dx + dy*dy))
						turret.TargetPitch = float32(math.Atan2(float64(deltaHeight), float64(horizontalDist)))
					}
				}
			} else {
				// Если целей нет, плавно возвращаем башню в нейтральное положение
				turret.TargetAngle = 0 // или любой другой "домашний" угол
				turret.TargetPitch = 0
			}

			// 4. Плавный поворот к цели
			turret.CurrentAngle = utils.LerpAngle(turret.CurrentAngle, turret.TargetAngle, turret.TurnSpeed*float32(deltaTime))
			// Для Pitch используем обычный Lerp, т.к. нам не нужен "заворот" через 360 градусов
			turret.CurrentPitch = utils.Lerp(turret.CurrentPitch, turret.TargetPitch, turret.TurnSpeed*float32(deltaTime))
		}
		// --- КОНЕЦ ОБНОВЛЕННОГО БЛОКА ---

		if !tower.IsActive {
			continue
		}

		towerDef, ok := defs.TowerDefs[tower.DefID]
		if !ok {
			log.Printf("CombatSystem: Could not find tower definition for ID %s", tower.DefID)
			continue
		}

		if combat.Attack.Type == defs.BehaviorAreaOfEffect || combat.Attack.Type == defs.BehaviorNone {
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

		attackPerformed := false
		switch combat.Attack.Type {
		case defs.BehaviorProjectile:
			attackPerformed = s.handleProjectileAttack(id, tower, combat, &towerDef)
		case defs.BehaviorLaser:
			attackPerformed = s.handleLaserAttack(id, tower, combat, &towerDef)
		default:
			attackPerformed = s.handleProjectileAttack(id, tower, combat, &towerDef)
		}

		if attackPerformed {
			availableSources := []types.EntityID{}
			for _, sourceID := range powerSources {
				if ore, ok := s.ecs.Ores[sourceID]; ok && ore.CurrentReserve > 0 {
					availableSources = append(availableSources, sourceID)
				}
			}
			if len(availableSources) > 0 {
				chosenSourceID := availableSources[rand.Intn(len(availableSources))]

				// --- ИЗМЕНЕНИЕ: Отправляем событие вместо прямого вычитания ---
				consumptionData := OreConsumptionData{
					SourceID: chosenSourceID,
					Amount:   combat.ShotCost,
				}
				s.eventDispatcher.Dispatch(event.Event{
					Type: event.OreConsumed,
					Data: consumptionData,
				})
				// --- КОНЕЦ ИЗМЕНЕНИЯ ---

				fireRate := combat.FireRate
				if auraEffect, ok := s.ecs.AuraEffects[id]; ok {
					fireRate *= auraEffect.SpeedMultiplier
				}
				combat.FireCooldown = 1.0 / fireRate
			}
		}
	}
}
// ... (остальная часть файла без изменений)
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

	var targets []types.EntityID

	// --- НОВАЯ ЛОГИКА СИНХРОНИЗАЦИИ С ТУРЕЛЬЮ ---
	// Если у башни есть турель и у нее есть валидная цель
	if turret, hasTurret := s.ecs.Turrets[towerID]; hasTurret && turret.TargetID != 0 {
		// Проверяем, находится ли цель турели в РАДИУСЕ АТАКИ (а не захвата)
		if targetPos, exists := s.ecs.Positions[turret.TargetID]; exists {
			towerPosPixelX, towerPosPixelY := tower.Hex.ToPixel(config.HexSize)
			// Расстояние в пикселях в квадрате
			distSq := (targetPos.X-towerPosPixelX)*(targetPos.X-towerPosPixelX) + (targetPos.Y-towerPosPixelY)*(targetPos.Y-towerPosPixelY)
			// Сравниваем с радиусом атаки, переведенным в пиксели в квадрате
			if distSq < float64(combat.Range*combat.Range*config.HexSize*config.HexSize) {
				// Если да, то это наша единственная цель
				targets = []types.EntityID{turret.TargetID}
			}
		}
	}

	// Если после проверки турели целей нет (или это башня без турели), используем старую логику
	if len(targets) == 0 {
		splitCount := 1
		if combat.Attack.Params != nil && combat.Attack.Params.SplitCount != nil {
			splitCount = *combat.Attack.Params.SplitCount
		}
		if splitCount <= 0 {
			splitCount = 1
		}
		targets = s.findTargetsForSplitAttack(tower.Hex, combat.Range, splitCount)
	}
	// --- КОНЕЦ НОВОЙ ЛОГИКИ ---

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

	towerX, towerY := tower.Hex.ToPixel(float64(config.HexSize))
	startPos := &component.Position{X: towerX, Y: towerY}

	for _, enemyID := range targets {
		s.CreateProjectile(startPos, towerID, enemyID, towerDef.Combat.Attack, finalDamage, 1.0)
	}
	return true
}

// findTargetsForSplitAttack находит до `count` ближайших врагов.
func (s *CombatSystem) findTargetsForSplitAttack(startHex hexmap.Hex, rangeRadius int, count int) []types.EntityID {
	type enemyWithDist struct {
		id   types.EntityID
		dist float64
	}
	var candidates []enemyWithDist

	for enemyID, enemyPos := range s.ecs.Positions {
		if _, isEnemy := s.ecs.Enemies[enemyID]; !isEnemy {
			continue
		}
		if health, hasHealth := s.ecs.Healths[enemyID]; !hasHealth || health.Value <= 0 {
			continue
		}
		enemyHex := hexmap.PixelToHex(enemyPos.X, enemyPos.Y, float64(config.HexSize))
		distance := float64(startHex.Distance(enemyHex))

		if distance <= float64(rangeRadius) {
			candidates = append(candidates, enemyWithDist{id: enemyID, dist: distance})
		}
	}

	sort.Slice(candidates, func(i, j int) bool {
		return candidates[i].dist < candidates[j].dist
	})

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

// CreateProjectile создает новую сущность снаряда.
// radiusMultiplier позволяет создавать снаряды разного размера (например, 1.0 для обычных, 0.5 для мини-снарядов).
func (s *CombatSystem) CreateProjectile(startPos *component.Position, sourceID, targetID types.EntityID, attackDef *defs.AttackDef, damage int, radiusMultiplier float64) {
	projID := s.ecs.NewEntity()

	predictedPos := s.predictTargetPosition(targetID, startPos, config.ProjectileSpeed)
	direction := calculateDirection(startPos, &predictedPos)

	finalSpawnPos := &component.Position{X: startPos.X, Y: startPos.Y}
	var spawnHeight float64

	// --- НОВАЯ ЛОГИКА РАЗДЕЛЕНИЯ ---
	// Проверяем, есть ли у башни турель
	if _, hasTurret := s.ecs.Turrets[sourceID]; hasTurret {
		// Логика для башен с турелью: смещаем позицию и рассчитываем высоту
		offset := config.HexSize * 0.5
		finalSpawnPos.X += math.Cos(direction) * offset
		finalSpawnPos.Y += math.Sin(direction) * offset

		if tower, ok := s.ecs.Towers[sourceID]; ok {
			if renderable, ok := s.ecs.Renderables[sourceID]; ok {
				spawnHeight = float64(getTowerRenderHeight(tower, renderable))
			}
		}
	} else {
		// Старая логика для башен без турели: спавн в центре (finalSpawnPos уже равен startPos),
		// высота 0 (будет обработано в рендере как стандартная низкая высота)
		spawnHeight = 0.0
	}
	// --- КОНЕЦ НОВОЙ ЛОГИКИ ---

	projectileColor := getProjectileColorByAttackType(attackDef.DamageType)

	proj := &component.Projectile{
		SourceID:   sourceID,
		TargetID:   targetID,
		Speed:      config.ProjectileSpeed,
		Damage:     damage,
		Color:      projectileColor,
		Direction:  direction,
		AttackType: attackDef.DamageType,
		// Инициализация полей для визуальных эффектов
		Age:             0.0,
		ScaleUpDuration: 0.15, // 0.15 секунды на анимацию роста
		SpawnHeight:     spawnHeight,
	}

	if attackDef.Params != nil {
		// Переносим параметры ImpactBurst в снаряд, если они есть
		if attackDef.Params.ImpactBurst != nil {
			proj.ImpactBurstRadius = attackDef.Params.ImpactBurst.Radius
			proj.ImpactBurstTargetCount = attackDef.Params.ImpactBurst.TargetCount
			proj.ImpactBurstDamageFactor = attackDef.Params.ImpactBurst.DamageFactor
		}
		// Устанавливаем тип визуала
		if attackDef.Params.VisualType != "" {
			proj.VisualType = attackDef.Params.VisualType
		}
	}

	proj.IsConditionallyHoming = true
	if slowEffect, ok := s.ecs.SlowEffects[targetID]; ok {
		proj.TargetLastSlowFactor = slowEffect.SlowFactor
	} else {
		proj.TargetLastSlowFactor = 1.0
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

	s.ecs.Positions[projID] = &component.Position{X: finalSpawnPos.X, Y: finalSpawnPos.Y}
	s.ecs.Projectiles[projID] = proj
	s.ecs.Renderables[projID] = &component.Renderable{
		Color:     proj.Color,
		Radius:    float32(config.ProjectileRadius * radiusMultiplier),
		HasStroke: false,
	}
}

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
	return (currentReserve-lowT)*(minM-maxM)/(highT-lowT) + maxM
}

func (s *CombatSystem) calculateLineDegradationMultiplier(path []types.EntityID) float64 {
	if path == nil {
		return 1.0
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
		return config.ProjectileColorPureRL
	}
}

func (s *CombatSystem) predictTargetPosition(enemyID types.EntityID, startPos *component.Position, projSpeed float64) component.Position {
	enemyPos := s.ecs.Positions[enemyID]
	enemyVel := s.ecs.Velocities[enemyID]
	path, hasPath := s.ecs.Paths[enemyID]

	if enemyPos == nil || enemyVel == nil || !hasPath || path.CurrentIndex >= len(path.Hexes) {
		if enemyPos != nil {
			return *enemyPos
		}
		return component.Position{}
	}

	currentSpeed := enemyVel.Speed
	if slowEffect, ok := s.ecs.SlowEffects[enemyID]; ok {
		currentSpeed *= slowEffect.SlowFactor
	}
	// Применяем замедление от яда Jade (та же логика, что и в movement.go)
	if poisonContainer, isPoisoned := s.ecs.JadePoisonContainers[enemyID]; isPoisoned {
		numStacks := len(poisonContainer.Instances)
		if numStacks > 0 {
			totalJadeSlow := float64(poisonContainer.SlowFactorPerStack) * float64(numStacks)
			speedMultiplier := 1.0 - totalJadeSlow
			if speedMultiplier < 0.1 {
				speedMultiplier = 0.1
			}
			currentSpeed *= speedMultiplier
		}
	}

	const maxIterations = 5
	timeToHit := 0.0
	for iter := 0; iter < maxIterations; iter++ {
		predictedPos := simulateEnemyMovement(enemyPos, path, currentSpeed, timeToHit)
		dx := predictedPos.X - startPos.X
		dy := predictedPos.Y - startPos.Y
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
		tx, ty := targetHex.ToPixel(float64(config.HexSize))
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

// FindEnemiesInRadius находит всех врагов в заданном радиусе от гекса.
// Сделано публичным для использования в других системах.
func (s *CombatSystem) FindEnemiesInRadius(startHex hexmap.Hex, radius float64) []types.EntityID {
	var targets []types.EntityID
	for enemyID, enemyPos := range s.ecs.Positions {
		if _, isEnemy := s.ecs.Enemies[enemyID]; !isEnemy {
			continue
		}
		if health, hasHealth := s.ecs.Healths[enemyID]; !hasHealth || health.Value <= 0 {
			continue
		}
		enemyHex := hexmap.PixelToHex(enemyPos.X, enemyPos.Y, float64(config.HexSize))
		if float64(startHex.Distance(enemyHex)) <= radius {
			targets = append(targets, enemyID)
		}
	}
	return targets
}

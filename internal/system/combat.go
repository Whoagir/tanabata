package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/types"
	"go-tower-defense/pkg/hexmap"
	"image/color"
	"log"
	"math"
	"math/rand"
	"time"
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
			// Считаем все башни, которые не являются добытчиками или стенами
			if tower.Type != config.TowerTypeMiner && tower.Type != config.TowerTypeWall {
				attackerCount++
			}
		}
	}

	// Формула: Урон * (Factor ^ n), где n - кол-во атакующих башен
	return math.Pow(config.LineDegradationFactor, float64(attackerCount))
}

func (s *CombatSystem) Update(deltaTime float64) {
	for id, combat := range s.ecs.Combats {
		tower, hasTower := s.ecs.Towers[id]
		if !hasTower || !tower.IsActive {
			continue
		}

		towerDefID := mapNumericTypeToTowerID(tower.Type)
		towerDef, ok := defs.TowerLibrary[towerDefID]
		if !ok {
			log.Printf("CombatSystem: Could not find tower definition for ID %s (numeric: %d)", towerDefID, tower.Type)
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

		// Для башен с типом INTERNAL цель не нужна, они просто "стреляют" для списания ресурсов.
		// Для остальных - ищем ближайшего врага.
		targetFound := combat.AttackType == defs.AttackInternal
		var enemyID types.EntityID
		if !targetFound {
			enemyID = s.findNearestEnemyInRange(id, tower.Hex, combat.Range)
			targetFound = enemyID != 0
		}

		if targetFound {
			availableSources := []types.EntityID{}
			for _, sourceID := range powerSources {
				if ore, ok := s.ecs.Ores[sourceID]; ok && ore.CurrentReserve > 0 {
					availableSources = append(availableSources, sourceID)
				}
			}

			if len(availableSources) > 0 {
				chosenSourceID := availableSources[rand.Intn(len(availableSources))]
				chosenOre := s.ecs.Ores[chosenSourceID]

				// Только для "настоящих" атак создаем снаряд
				if combat.AttackType != defs.AttackInternal {
					// --- Расчет финального урона ---
					boostMultiplier := calculateOreBoostMultiplier(chosenOre.CurrentReserve)
					pathToSource := s.pathFinder(id)
					degradationMultiplier := s.calculateLineDegradationMultiplier(pathToSource)
					baseDamage := float64(towerDef.Combat.Damage)
					finalDamage := int(math.Round(baseDamage * boostMultiplier * degradationMultiplier))
					// --- Конец расчета ---
					s.createProjectile(id, enemyID, &towerDef, finalDamage)
				}

				// Применяем эффект ауры к скорости атаки
				fireRate := combat.FireRate
				if auraEffect, ok := s.ecs.AuraEffects[id]; ok {
					fireRate *= auraEffect.SpeedMultiplier
				}
				combat.FireCooldown = 1.0 / fireRate

				cost := combat.ShotCost
				if chosenOre.CurrentReserve >= cost {
					chosenOre.CurrentReserve -= cost
				} else {
					chosenOre.CurrentReserve = 0
				}
			}
		}
	}
}

func (s *CombatSystem) findNearestEnemyInRange(towerID types.EntityID, towerHex hexmap.Hex, rangeRadius int) types.EntityID {
	var nearestEnemy types.EntityID
	minDistance := math.MaxFloat64
	for enemyID, enemyPos := range s.ecs.Positions {
		if _, isTower := s.ecs.Towers[enemyID]; isTower {
			continue
		}
		if _, isEnemy := s.ecs.Enemies[enemyID]; !isEnemy {
			continue
		}
		enemyHex := hexmap.PixelToHex(enemyPos.X, enemyPos.Y, config.HexSize)
		distance := float64(towerHex.Distance(enemyHex))
		if distance <= float64(rangeRadius) && distance < minDistance {
			minDistance = distance
			nearestEnemy = enemyID
		}
	}
	return nearestEnemy
}

func (s *CombatSystem) createProjectile(towerID, enemyID types.EntityID, towerDef *defs.TowerDefinition, damage int) {
	projID := s.ecs.NewEntity()
	towerPos := s.ecs.Positions[towerID]
	enemyPos := s.ecs.Positions[enemyID]
	enemyVel := s.ecs.Velocities[enemyID]

	predictedPos := predictEnemyPosition(s.ecs, enemyID, towerPos, enemyPos, enemyVel, config.ProjectileSpeed)
	direction := calculateDirection(towerPos, &predictedPos)

	projectileColor := getProjectileColorByAttackType(towerDef.Combat.AttackType)

	// Настраиваем снаряд
	proj := &component.Projectile{
		TargetID:   enemyID,
		Speed:      config.ProjectileSpeed,
		Damage:     damage,
		Color:      projectileColor,
		Direction:  direction,
		AttackType: towerDef.Combat.AttackType,
	}

	// Если это башня замедления, добавляем эффект
	if towerDef.ID == "TOWER_SLOW" {
		proj.SlowsTarget = true
		proj.SlowDuration = 2.0 // Как и договаривались, 2 секунды
		proj.SlowFactor = 0.5   // Замедление на 50%
		proj.Color = config.ColorBlue // Синий цвет для снаряда
	}

	s.ecs.Positions[projID] = &component.Position{X: towerPos.X, Y: towerPos.Y}
	s.ecs.Projectiles[projID] = proj
	s.ecs.Renderables[projID] = &component.Renderable{
		Color:     proj.Color,
		Radius:    config.ProjectileRadius,
		HasStroke: false,
	}
}

func getProjectileColorByAttackType(attackType defs.AttackType) color.RGBA {
	switch attackType {
	case defs.AttackPhysical:
		return config.ColorYellow
	case defs.AttackMagical:
		return config.ColorRed
	case defs.AttackPure:
		return config.ColorWhite
	default:
		return config.ColorWhite // По умолчанию
	}
}

// Вспомогательные функции остаются без изменений
func predictEnemyPosition(ecs *entity.ECS, enemyID types.EntityID, towerPos, enemyPos *component.Position, enemyVel *component.Velocity, projSpeed float64) component.Position {
	path, hasPath := ecs.Paths[enemyID]
	if !hasPath || path.CurrentIndex >= len(path.Hexes) {
		return *enemyPos
	}

	const maxIterations = 5
	timeToHit := 0.0

	for iter := 0; iter < maxIterations; iter++ {
		predictedPos := simulateEnemyMovement(enemyPos, path, enemyVel.Speed, timeToHit, config.HexSize)
		dx := predictedPos.X - towerPos.X
		dy := predictedPos.Y - towerPos.Y
		newTimeToHit := math.Sqrt(dx*dx+dy*dy) / projSpeed

		if math.Abs(newTimeToHit-timeToHit) < 0.01 {
			return predictedPos
		}
		timeToHit = newTimeToHit
	}

	return simulateEnemyMovement(enemyPos, path, enemyVel.Speed, timeToHit, config.HexSize)
}

func simulateEnemyMovement(startPos *component.Position, path *component.Path, speed float64, duration float64, hexSize float64) component.Position {
	currentPos := *startPos
	remainingTime := duration
	currentIndex := path.CurrentIndex

	for currentIndex < len(path.Hexes) && remainingTime > 0 {
		targetHex := path.Hexes[currentIndex]
		tx, ty := targetHex.ToPixel(hexSize)
		tx += float64(config.ScreenWidth) / 2
		ty += float64(config.ScreenHeight) / 2

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

// ApplyDamage вызывает общую функцию для нанесения урона.
func (s *CombatSystem) ApplyDamage(entityID types.EntityID, damage int, attackType defs.AttackType) {
	ApplyDamage(s.ecs, entityID, damage, attackType)
}

// mapNumericTypeToTowerID is a temporary helper function.
func mapNumericTypeToTowerID(numericType int) string {
	switch numericType {
	case config.TowerTypeRed:
		return "TOWER_RED"
	case config.TowerTypeGreen:
		return "TOWER_GREEN"
	case config.TowerTypeBlue:
		return "TOWER_BLUE"
	case config.TowerTypePurple:
		return "TOWER_AURA_ATTACK_SPEED"
	case config.TowerTypeCyan:
		return "TOWER_SLOW"
	case config.TowerTypeMiner:
		return "TOWER_MINER"
	case config.TowerTypeWall:
		return "TOWER_WALL"
	default:
		return ""
	}
}

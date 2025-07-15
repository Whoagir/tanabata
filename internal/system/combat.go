package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/types"
	"go-tower-defense/pkg/hexmap"
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

		enemyID := s.findNearestEnemyInRange(id, tower.Hex, combat.Range)
		if enemyID != 0 {
			availableSources := []types.EntityID{}
			for _, sourceID := range powerSources {
				if ore, ok := s.ecs.Ores[sourceID]; ok && ore.CurrentReserve > 0 {
					availableSources = append(availableSources, sourceID)
				}
			}

			if len(availableSources) > 0 {
				chosenSourceID := availableSources[rand.Intn(len(availableSources))]
				chosenOre := s.ecs.Ores[chosenSourceID]

				// --- Расчет финального урона ---
				// 1. Бонус от бедной руды
				boostMultiplier := calculateOreBoostMultiplier(chosenOre.CurrentReserve)

				// 2. Штраф от длины цепи
				pathToSource := s.pathFinder(id)
				degradationMultiplier := s.calculateLineDegradationMultiplier(pathToSource)

				// 3. Итоговый урон
				baseDamage := float64(config.TowerDamage[tower.Type])
				finalDamage := int(math.Round(baseDamage * boostMultiplier * degradationMultiplier))
				// --- Конец расчета ---

				s.createProjectile(id, enemyID, tower.Type, finalDamage)
				combat.FireCooldown = 1.0 / combat.FireRate

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

func (s *CombatSystem) createProjectile(towerID, enemyID types.EntityID, towerType int, damage int) {
	projID := s.ecs.NewEntity()
	towerPos := s.ecs.Positions[towerID]
	enemyPos := s.ecs.Positions[enemyID]
	enemyVel := s.ecs.Velocities[enemyID]

	predictedPos := predictEnemyPosition(s.ecs, enemyID, towerPos, enemyPos, enemyVel, config.ProjectileSpeed)
	direction := calculateDirection(towerPos, &predictedPos)

	s.ecs.Positions[projID] = &component.Position{X: towerPos.X, Y: towerPos.Y}
	s.ecs.Projectiles[projID] = &component.Projectile{
		TargetID:  enemyID,
		Speed:     config.ProjectileSpeed,
		Damage:    damage, // Используем переданный урон
		Color:     config.TowerColors[towerType],
		Direction: direction,
	}
	s.ecs.Renderables[projID] = &component.Renderable{
		Color:     config.TowerColors[towerType],
		Radius:    config.ProjectileRadius,
		HasStroke: false,
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
func (s *CombatSystem) ApplyDamage(entityID types.EntityID, damage int) {
	ApplyDamage(s.ecs, entityID, damage)
}

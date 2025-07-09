package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/types"
	"go-tower-defense/pkg/hexmap"
	"math"
)

// CombatSystem управляет атакой башен
type CombatSystem struct {
	ecs               *entity.ECS
	powerSourceFinder func(towerID types.EntityID) []types.EntityID
	lastLogTime       float64
}

func NewCombatSystem(ecs *entity.ECS, finder func(towerID types.EntityID) []types.EntityID) *CombatSystem {
	return &CombatSystem{
		ecs:               ecs,
		powerSourceFinder: finder,
		lastLogTime:       0.0,
	}
}

const logInterval = 1.0 // Логируем не чаще, чем раз в секунду

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

		// Проверка наличия ресурсов
		powerSources := s.powerSourceFinder(id)
		if len(powerSources) == 0 {
			continue // Нет источников энергии, башня не стреляет
		}

		var totalReserve float64
		for _, sourceID := range powerSources {
			if ore, ok := s.ecs.Ores[sourceID]; ok {
				totalReserve += ore.CurrentReserve
			}
		}

		if totalReserve < combat.ShotCost {
			continue // Недостаточно ресурсов для выстрела
		}

		enemyID := s.findNearestEnemyInRange(id, tower.Hex, combat.Range)
		if enemyID != 0 {
			// Ресурсы есть, враг в зоне досягаемости, производим выстрел
			s.createProjectile(id, enemyID, tower.Type)
			combat.FireCooldown = 1.0 / combat.FireRate

			// Списываем стоимость выстрела
			remainingCost := combat.ShotCost
			for _, sourceID := range powerSources {
				if ore, ok := s.ecs.Ores[sourceID]; ok {
					if ore.CurrentReserve >= remainingCost {
						ore.CurrentReserve -= remainingCost
						break
					} else {
						remainingCost -= ore.CurrentReserve
						ore.CurrentReserve = 0
					}
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
			continue // Пропускаем, если это не враг
		}
		enemyHex := hexmap.PixelToHex(enemyPos.X, enemyPos.Y, config.HexSize)
		distance := float64(towerHex.Distance(enemyHex))
		if distance <= float64(rangeRadius) && distance < minDistance {
			minDistance = distance
			nearestEnemy = enemyID
		}
	}
	if nearestEnemy == 0 {
		// log.Printf("Башня %d не нашла врагов в радиусе %d", towerID, rangeRadius)
	} else {
		// log.Printf("Башня %d нашла врага %d на расстоянии %.2f", towerID, nearestEnemy, minDistance)
	}
	return nearestEnemy
}

func (s *CombatSystem) createProjectile(towerID, enemyID types.EntityID, towerType int) {
	projID := s.ecs.NewEntity()
	towerPos := s.ecs.Positions[towerID]
	enemyPos := s.ecs.Positions[enemyID]
	enemyVel := s.ecs.Velocities[enemyID]

	// Логируем момент создания снаряда
	// log.Printf("Башня %d (%.2f, %.2f) выпустила снаряд по врагу %d (%.2f, %.2f)",
	// towerID, towerPos.X, towerPos.Y, enemyID, enemyPos.X, enemyPos.Y)

	// Вычисляем предсказанную позицию врага
	predictedPos := predictEnemyPosition(s.ecs, enemyID, towerPos, enemyPos, enemyVel, config.ProjectileSpeed)

	// Вычисляем направление к предсказанной позиции
	direction := calculateDirection(towerPos, &predictedPos)

	// Создаём снаряд
	s.ecs.Positions[projID] = &component.Position{X: towerPos.X, Y: towerPos.Y}
	s.ecs.Projectiles[projID] = &component.Projectile{
		TargetID:  enemyID,
		Speed:     config.ProjectileSpeed,
		Damage:    config.TowerDamage[towerType],
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

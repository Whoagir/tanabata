// internal/system/combat.go
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
	ecs *entity.ECS
}

func NewCombatSystem(ecs *entity.ECS) *CombatSystem {
	return &CombatSystem{ecs: ecs}
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

		enemyID := s.findNearestEnemyInRange(tower.Hex, combat.Range)
		if enemyID != 0 {
			if pos, exists := s.ecs.Positions[enemyID]; exists && pos != nil {
				if vel, velExists := s.ecs.Velocities[enemyID]; velExists && vel != nil {
					s.createProjectile(id, enemyID, tower.Type)
					combat.FireCooldown = 1.0 / combat.FireRate
				} else {
					// log.Println("Enemy", enemyID, "has no velocity, skipping projectile")
				}
			} else {
				// log.Println("Enemy", enemyID, "not found or has no position, skipping projectile")
			}
		}
	}
}

func (s *CombatSystem) findNearestEnemyInRange(towerHex hexmap.Hex, rangeRadius int) types.EntityID {
	var nearestEnemy types.EntityID
	minDistance := math.MaxFloat64

	for enemyID, enemyPos := range s.ecs.Positions {
		if _, isTower := s.ecs.Towers[enemyID]; isTower {
			continue // Пропускаем башни
		}
		enemyHex := hexmap.PixelToHex(enemyPos.X, enemyPos.Y, config.HexSize)
		distance := float64(towerHex.Distance(enemyHex)) // Приводим int к float64
		if distance <= float64(rangeRadius) && distance < minDistance {
			minDistance = distance
			nearestEnemy = enemyID
		}
	}

	return nearestEnemy
}

func (s *CombatSystem) createProjectile(towerID, enemyID types.EntityID, towerType int) {
	projID := s.ecs.NewEntity()
	towerPos := s.ecs.Positions[towerID]
	enemyPos := s.ecs.Positions[enemyID]
	enemyVel := s.ecs.Velocities[enemyID]

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

// Вспомогательная функция для предсказания позиции врага
func predictEnemyPosition(ecs *entity.ECS, enemyID types.EntityID, towerPos, enemyPos *component.Position, enemyVel *component.Velocity, projSpeed float64) component.Position {
	path, hasPath := ecs.Paths[enemyID]
	if !hasPath || path.CurrentIndex >= len(path.Hexes) {
		// Если пути нет, возвращаем текущую позицию
		return *enemyPos
	}

	// Итеративно уточняем время встречи
	const maxIterations = 5
	timeToHit := 0.0

	for iter := 0; iter < maxIterations; iter++ {
		// Предсказываем позицию врага через timeToHit секунд
		predictedPos := simulateEnemyMovement(enemyPos, path, enemyVel.Speed, timeToHit, config.HexSize)

		// Вычисляем новое время до этой позиции
		dx := predictedPos.X - towerPos.X
		dy := predictedPos.Y - towerPos.Y
		newTimeToHit := math.Sqrt(dx*dx+dy*dy) / projSpeed

		// Если время сходится, выходим
		if math.Abs(newTimeToHit-timeToHit) < 0.01 {
			return predictedPos
		}

		timeToHit = newTimeToHit
	}

	// Финальная симуляция с уточнённым временем
	return simulateEnemyMovement(enemyPos, path, enemyVel.Speed, timeToHit, config.HexSize)
}

// Симулирует движение врага по пути на заданное время
func simulateEnemyMovement(startPos *component.Position, path *component.Path, speed float64, duration float64, hexSize float64) component.Position {
	currentPos := *startPos
	remainingTime := duration
	currentIndex := path.CurrentIndex

	// Симулируем движение по пути
	for currentIndex < len(path.Hexes) && remainingTime > 0 {
		targetHex := path.Hexes[currentIndex]
		tx, ty := targetHex.ToPixel(hexSize)
		tx += float64(config.ScreenWidth) / 2
		ty += float64(config.ScreenHeight) / 2

		dx := tx - currentPos.X
		dy := ty - currentPos.Y
		distToNext := math.Sqrt(dx*dx + dy*dy)

		if distToNext < 0.01 {
			// Уже в целевой точке, переходим к следующей
			currentIndex++
			continue
		}

		timeToNext := distToNext / speed

		if timeToNext >= remainingTime {
			// Двигаемся частично к следующей точке
			fraction := remainingTime / timeToNext
			currentPos.X += dx * fraction
			currentPos.Y += dy * fraction
			break
		} else {
			// Достигаем следующей точки и продолжаем
			currentPos.X = tx
			currentPos.Y = ty
			currentIndex++
			remainingTime -= timeToNext
		}
	}

	return currentPos
}

// Функция для вычисления направления
func calculateDirection(from, to *component.Position) float64 {
	dx := to.X - from.X
	dy := to.Y - from.Y
	return math.Atan2(dy, dx)
}

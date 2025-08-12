// internal/system/movement.go
package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/types"
	"go-tower-defense/pkg/hexmap"
	"math"
)

// MovementGameContext определяет методы, которые MovementSystem требует от Game.
// Это помогает избежать циклических зависимостей.
type MovementGameContext interface {
	GetHexMap() *hexmap.HexMap
	GetClearedCheckpoints() map[hexmap.Hex]bool
	GetEnemies() map[types.EntityID]*component.Enemy
}

// MovementSystem обновляет позиции сущностей
type MovementSystem struct {
	ecs  *entity.ECS
	game MovementGameContext // Используем интерфейс вместо прямой зависимости
}

func NewMovementSystem(ecs *entity.ECS, game MovementGameContext) *MovementSystem {
	return &MovementSystem{ecs: ecs, game: game}
}

func (s *MovementSystem) Update(deltaTime float64) {
	for id, pos := range s.ecs.Positions {
		if vel, hasVel := s.ecs.Velocities[id]; hasVel {
			if path, hasPath := s.ecs.Paths[id]; hasPath {
				if path.CurrentIndex >= len(path.Hexes) {
					continue
				}
				targetHex := path.Hexes[path.CurrentIndex]
				tx, ty := targetHex.ToPixel(float64(config.HexSize))

				dx := tx - pos.X
				dy := ty - pos.Y
				dist := math.Sqrt(dx*dx + dy*dy)

				currentSpeed := vel.Speed
				if slowEffect, isSlowed := s.ecs.SlowEffects[id]; isSlowed {
					currentSpeed *= slowEffect.SlowFactor
				}

				// Применяем замедление от яда Jade
				if poisonContainer, isPoisoned := s.ecs.JadePoisonContainers[id]; isPoisoned {
					numStacks := len(poisonContainer.Instances)
					if numStacks > 0 {
						// Рассчитываем общий процент замедления от стаков
						totalJadeSlow := float64(poisonContainer.SlowFactorPerStack) * float64(numStacks)
						// Оставшаяся скорость будет (1.0 - totalJadeSlow)
						speedMultiplier := 1.0 - totalJadeSlow
						if speedMultiplier < 0.1 { // Ограничим минимальную скорость (например, 10% от базовой)
							speedMultiplier = 0.1
						}
						currentSpeed *= speedMultiplier
					}
				}

				moveDistance := currentSpeed * deltaTime

				if dist <= moveDistance {
					pos.X = tx
					pos.Y = ty
					path.CurrentIndex++

					// Проверяем, является ли достигнутый гекс чекпоинтом
					hexMap := s.game.GetHexMap()
					for i, cpHex := range hexMap.Checkpoints {
						if targetHex == cpHex {
							if enemy, ok := s.ecs.Enemies[id]; ok {
								enemy.LastCheckpointIndex = i
							}
							break // Выходим из цикла, так как гекс может быть только одним чекпоинтом
						}
					}

				} else {
					pos.X += (dx / dist) * moveDistance
					pos.Y += (dy / dist) * moveDistance
				}
			}
		}
	}
}

// internal/system/movement.go
package system

import (
	// Добавляем импорт для доступа к компонентам
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"math"
)

// MovementSystem обновляет позиции сущностей
type MovementSystem struct {
	ecs *entity.ECS
}

func NewMovementSystem(ecs *entity.ECS) *MovementSystem {
	return &MovementSystem{ecs: ecs}
}

func (s *MovementSystem) Update(deltaTime float64) {
	for id, pos := range s.ecs.Positions {
		if vel, hasVel := s.ecs.Velocities[id]; hasVel {
			if path, hasPath := s.ecs.Paths[id]; hasPath {
				if path.CurrentIndex >= len(path.Hexes) {
					continue
				}
				targetHex := path.Hexes[path.CurrentIndex]
				tx, ty := targetHex.ToPixel(config.HexSize)
				tx += float64(config.ScreenWidth) / 2
				ty += float64(config.ScreenHeight) / 2

				dx := tx - pos.X
				dy := ty - pos.Y
				dist := math.Sqrt(dx*dx + dy*dy)

				// Проверяем наличие эффекта замедления
				currentSpeed := vel.Speed
				if slowEffect, isSlowed := s.ecs.SlowEffects[id]; isSlowed {
					currentSpeed *= slowEffect.SlowFactor
				}
				moveDistance := currentSpeed * deltaTime

				if dist <= moveDistance {
					pos.X = tx
					pos.Y = ty
					path.CurrentIndex++
				} else {
					pos.X += (dx / dist) * moveDistance
					pos.Y += (dy / dist) * moveDistance
				}
			}
		}
	}
}

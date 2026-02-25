// internal/system/movement.go
package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/types"
	"go-tower-defense/internal/utils"
	"go-tower-defense/pkg/hexmap"
	"log"
	"math"
)

// MovementGameContext определяет методы, которые MovementSystem требует от Game.
type MovementGameContext interface {
	GetHexMap() *hexmap.HexMap
	GetClearedCheckpoints() map[hexmap.Hex]bool
	GetEnemies() map[types.EntityID]*component.Enemy
	IsGodMode() bool
}

// MovementSystem обновляет позиции сущностей
type MovementSystem struct {
	ecs  *entity.ECS
	game MovementGameContext
	rng  *utils.PRNGService
}

func NewMovementSystem(ecs *entity.ECS, game MovementGameContext, rng *utils.PRNGService) *MovementSystem {
	return &MovementSystem{ecs: ecs, game: game, rng: rng}
}

func (s *MovementSystem) Update(deltaTime float64) {
	var playerState *component.PlayerStateComponent
	for _, state := range s.ecs.PlayerState {
		playerState = state
		break
	}
	if playerState == nil {
		return
	}

	for id, pos := range s.ecs.Positions {
		vel, hasVel := s.ecs.Velocities[id]
		if !hasVel {
			continue
		}

		path, hasPath := s.ecs.Paths[id]
		if !hasPath {
			continue
		}

		// Если враг уже дошел, но еще не удален, пропускаем его.
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
		if poisonContainer, isPoisoned := s.ecs.JadePoisonContainers[id]; isPoisoned {
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

		moveDistance := currentSpeed * deltaTime

		if dist <= moveDistance {
			pos.X = tx
			pos.Y = ty
			path.CurrentIndex++

			// ПРОВЕРКА КОНЦА ПУТИ СРАЗУ ПОСЛЕ ИНКРЕМЕНТА
			if path.CurrentIndex >= len(path.Hexes) {
				enemy, isEnemy := s.ecs.Enemies[id]
				if isEnemy && !enemy.ReachedEnd {
					enemy.ReachedEnd = true
					if !s.game.IsGodMode() {
						log.Printf("[LOGIC] Враг %d достиг цели. Наносим урон: %d.", id, enemy.Damage)
						playerState.Health -= enemy.Damage
						if playerState.Health < 0 {
							playerState.Health = 0
						}
						log.Printf("[LOGIC] Здоровье игрока теперь: %d", playerState.Health)
					}
				}
				// Враг дошел, больше не обрабатываем его движение
				continue
			}

			// Если не конец пути, проверяем чекпоинты
			hexMap := s.game.GetHexMap()
			// Обновляем targetHex, так как CurrentIndex мог измениться
			newTargetHex := path.Hexes[path.CurrentIndex-1]
			for i, cpHex := range hexMap.Checkpoints {
				if newTargetHex == cpHex {
					if enemy, ok := s.ecs.Enemies[id]; ok {
						enemy.LastCheckpointIndex = i
					}
					break
				}
			}
		} else {
			pos.X += (dx / dist) * moveDistance
			pos.Y += (dy / dist) * moveDistance
		}
	}
}
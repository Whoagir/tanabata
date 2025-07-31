// internal/system/player_system.go
package system

import (
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/event"
)

// PlayerSystem отвечает за логику, связанную с игроком, например, за начисление опыта.
type PlayerSystem struct {
	ecs *entity.ECS
}

func NewPlayerSystem(ecs *entity.ECS) *PlayerSystem {
	return &PlayerSystem{ecs: ecs}
}

// OnEvent обрабатывает события, на которые подписана система.
func (s *PlayerSystem) OnEvent(e event.Event) {
	if e.Type != event.EnemyKilled {
		return
	}

	// Находим компонент состояния игрока.
	// Предполагаем, что он только один.
	for _, playerState := range s.ecs.PlayerState {
		playerState.CurrentXP += config.XPPerKill

		// Проверяем, не пора ли повышать уровень
		if playerState.CurrentXP >= playerState.XPToNextLevel {
			playerState.Level++
			playerState.CurrentXP -= playerState.XPToNextLevel
			playerState.XPToNextLevel = config.CalculateXPForNextLevel(playerState.Level)
		}
		// На��ли и обработали, выходим из цикла
		break
	}
}

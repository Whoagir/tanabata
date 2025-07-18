// internal/system/state.go
package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/event"
	"go-tower-defense/internal/interfaces"
)

type StateSystem struct {
	ecs             *entity.ECS
	game            interfaces.Game
	eventDispatcher *event.Dispatcher
}

func NewStateSystem(ecs *entity.ECS, game interfaces.Game, eventDispatcher *event.Dispatcher) *StateSystem {
	return &StateSystem{
		ecs:             ecs,
		game:            game,
		eventDispatcher: eventDispatcher,
	}
}

func (s *StateSystem) OnEvent(e event.Event) {
	if e.Type == event.WaveEnded {
		// log.Println("Received WaveEnded event, switching to BuildState")
		s.SwitchToBuildState()
	}
}

func (s *StateSystem) Update(deltaTime float64) {
	// Можно добавить дополнительную логику, если нужно
}

func (s *StateSystem) SwitchToBuildState() {
	s.game.ClearEnemies()
	s.game.ClearProjectiles()
	s.ecs.GameState.Phase = component.BuildState
	s.eventDispatcher.Dispatch(event.Event{Type: event.BuildPhaseStarted})
}

func (s *StateSystem) SwitchToWaveState() {
	s.game.StartWave()
	s.ecs.GameState.Phase = component.WaveState
	s.eventDispatcher.Dispatch(event.Event{Type: event.WavePhaseStarted})
}

func (s *StateSystem) GetState() *component.GameState {
	return s.ecs.GameState
}
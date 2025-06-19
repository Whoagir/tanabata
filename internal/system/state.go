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
	gameContext     interfaces.GameContext // Используем интерфейс из interfaces
	eventDispatcher *event.Dispatcher
}

func NewStateSystem(ecs *entity.ECS, gameContext interfaces.GameContext, eventDispatcher *event.Dispatcher) *StateSystem {
	ss := &StateSystem{
		ecs:             ecs,
		gameContext:     gameContext,
		eventDispatcher: eventDispatcher,
	}
	eventDispatcher.Subscribe(event.WaveEnded, ss)
	return ss
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
	s.ecs.GameState = component.BuildState
	s.gameContext.ClearEnemies()
	s.gameContext.ClearProjectiles()
	s.gameContext.SetTowersBuilt(0)
	// log.Println("Switched to BuildState, towersBuilt reset to:", s.gameContext.GetTowersBuilt())
}

func (s *StateSystem) SwitchToWaveState() {
	s.ecs.GameState = component.WaveState
	s.gameContext.StartWave()
	s.gameContext.SetTowersBuilt(0)
	// log.Println("Switched to WaveState, towersBuilt reset to:", s.gameContext.GetTowersBuilt())
}

func (s *StateSystem) Current() component.GameState {
	return s.ecs.GameState
}

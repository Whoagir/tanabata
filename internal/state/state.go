// internal/state/state.go
package state

import (
	"go-tower-defense/internal/app"
	rl "github.com/gen2brain/raylib-go/raylib"
)

// GameInterface определяет методы, которые состояния могут запрашивать у GameState.
// Это нужно, чтобы PauseState мог взаимодействовать с GameState, не создавая циклического импорта.
type GameInterface interface {
	GetGame() *app.Game
	GetFont() rl.Font
}

// State — интерфейс для всех состояний
type State interface {
	Enter()
	Update(deltaTime float64)
	Draw()
	Exit()
	// Добавляем методы для совместимости с PauseState
	GetGame() GameInterface
	GetFont() rl.Font
	Cleanup()
	SetCamera(camera *rl.Camera3D)
}

// StateMachine — структура для управления состояниями
type StateMachine struct {
	current State
}

// NewStateMachine создаёт новую машину состояний без начального состояния
func NewStateMachine() *StateMachine {
	return &StateMachine{}
}

// Current возвращает текущее состояние.
func (sm *StateMachine) Current() State {
	return sm.current
}

// SetState устанавливает новое состояние
func (sm *StateMachine) SetState(newState State) {
	if sm.current != nil {
		sm.current.Exit() // Выход из текущего состояния, если оно есть
	}
	sm.current = newState
	if sm.current != nil {
		sm.current.Enter() // Вход в новое состояние, только если оно не nil
	}
}

// Update обновляет текущее состояние
func (sm *StateMachine) Update(deltaTime float64) {
	if sm.current != nil {
		sm.current.Update(deltaTime)
	}
}

// Draw отрисовывает текущее состояние
func (sm *StateMachine) Draw() {
	if sm.current != nil {
		sm.current.Draw()
	}
}
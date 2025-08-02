// internal/state/menu_state.go
package state

import (
	"go-tower-defense/internal/defs"
	"image/color"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/inpututil"
)

// MenuState — состояние меню (заглушка)
type MenuState struct {
	sm      *StateMachine
	recipes []defs.Recipe
}

func NewMenuState(sm *StateMachine, recipes []defs.Recipe) *MenuState {
	return &MenuState{sm: sm, recipes: recipes}
}

func (m *MenuState) Enter() {
	// Ничего не делаем при входе
}

func (m *MenuState) Update(deltaTime float64) {
	if inpututil.IsKeyJustPressed(ebiten.KeySpace) {
		m.sm.SetState(NewGameState(m.sm, m.recipes))
	}
}

func (m *MenuState) Draw(screen *ebiten.Image) {
	screen.Fill(color.RGBA{0, 0, 0, 255}) // Чёрный экран
}

func (m *MenuState) Exit() {
	// Ничего не делаем при выходе
}
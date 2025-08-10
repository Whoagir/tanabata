// internal/state/pause_state.go
package state

import (
	"go-tower-defense/internal/config"
	"image/color"

	rl "github.com/gen2brain/raylib-go/raylib"
)

type PauseState struct {
	stateMachine *StateMachine
	previousState State
	font rl.Font // Assuming a font is loaded and passed
}

func NewPauseState(sm *StateMachine, prevState State, font rl.Font) *PauseState {
	return &PauseState{
		stateMachine:  sm,
		previousState: prevState,
		font: font,
	}
}

func (s *PauseState) Enter() {}

func (s *PauseState) Update(deltaTime float64) {
	unpause := false
	// Проверяем нажатие клавиш
	if rl.IsKeyPressed(rl.KeyP) || rl.IsKeyPressed(rl.KeyEscape) || rl.IsKeyPressed(rl.KeyF9) {
		unpause = true
	}

	// Проверяем клик по кнопке паузы из предыдущего сост��яния
	if gs, ok := s.previousState.(*GameState); ok {
		if rl.IsMouseButtonPressed(rl.MouseLeftButton) && gs.game.PauseButton.IsClicked(rl.GetMousePosition()) {
			unpause = true
		}
	}

	if unpause {
		// При выходе из паузы, нужно "отжать" кнопку в самом игровом состоянии
		if gs, ok := s.previousState.(*GameState); ok {
			gs.game.HandlePauseClick()
		}
		s.stateMachine.SetState(s.previousState)
	}
}

func (s *PauseState) Draw() {
	// Сначала рисуем 3D сцену предыдущего состояния
	if s.previousState != nil {
		s.previousState.Draw()
	}
}

// DrawUI рисует UI для состояния паузы
func (s *PauseState) DrawUI() {
	// Сначала рисуем UI предыдущего состояния
	if uiDrawable, ok := s.previousState.(interface{ DrawUI() }); ok {
		uiDrawable.DrawUI()
	}

	// Затем рисуем полупрозрачный оверлей
	rl.DrawRectangle(0, 0, int32(config.ScreenWidth), int32(config.ScreenHeight), rl.NewColor(0, 0, 0, 128))

	// Наконец, рисуем текст паузы
	pauseText := "PAUSED"
	fontSize := 40
	textWidth := rl.MeasureTextEx(s.font, pauseText, float32(fontSize), 1)
	rl.DrawTextEx(s.font, pauseText, rl.NewVector2(float32(config.ScreenWidth-int(textWidth.X))/2, float32(config.ScreenHeight)/2-20), float32(fontSize), 1, rl.White)
}

func (s *PauseState) Exit() {}

// Helper to convert color.RGBA to rl.Color
func colorToRL(c color.Color) rl.Color {
	r, g, b, a := c.RGBA()
	return rl.NewColor(uint8(r>>8), uint8(g>>8), uint8(b>>8), uint8(a>>8))
}
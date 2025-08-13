// internal/state/pause_state.go
package state

import (
	"go-tower-defense/internal/config"
	"image/color"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// Убеждаемся, что PauseState соответствует интерфейсу State
var _ State = (*PauseState)(nil)

type PauseState struct {
	stateMachine  *StateMachine
	previousState State
	font          rl.Font
}

func NewPauseState(sm *StateMachine, prevState State, font rl.Font) *PauseState {
	return &PauseState{
		stateMachine:  sm,
		previousState: prevState,
		font:          font,
	}
}

func (s *PauseState) Enter() {}

func (s *PauseState) Update(deltaTime float64) {
	unpause := false
	if rl.IsKeyPressed(rl.KeyP) || rl.IsKeyPressed(rl.KeyEscape) || rl.IsKeyPressed(rl.KeyF9) {
		unpause = true
	}

	// Мы не можем напрямую получить доступ к кнопке паузы, так как previousState - это интерфейс.
	// Логика клика по кнопке должна обрабатываться в GameState до перехода в PauseState.

	if unpause {
		// При выходе из паузы, нужно "отжать" кнопку в самом игровом состоянии
		if gs, ok := s.previousState.(GameInterface); ok {
			if game := gs.GetGame(); game != nil {
				game.HandlePauseClick()
			}
		}
		s.stateMachine.SetState(s.previousState)
	}
}

func (s *PauseState) Draw() {
	if s.previousState != nil {
		s.previousState.Draw()
	}
}

// DrawUI рисует UI для состояния паузы
func (s *PauseState) DrawUI() {
	if uiDrawable, ok := s.previousState.(interface{ DrawUI() }); ok {
		uiDrawable.DrawUI()
	}

	rl.DrawRectangle(0, 0, int32(config.ScreenWidth), int32(config.ScreenHeight), rl.NewColor(0, 0, 0, 128))

	pauseText := "PAUSED"
	fontSize := 40
	textWidth := rl.MeasureTextEx(s.font, pauseText, float32(fontSize), 1)
	rl.DrawTextEx(s.font, pauseText, rl.NewVector2(float32(config.ScreenWidth-int(textWidth.X))/2, float32(config.ScreenHeight)/2-20), float32(fontSize), 1, rl.White)
}

func (s *PauseState) Exit() {}

// --- Методы-заглушки для соответствия интерфейсу State ---

func (s *PauseState) GetGame() GameInterface {
	if gs, ok := s.previousState.(GameInterface); ok {
		return gs
	}
	return nil
}

func (s *PauseState) GetFont() rl.Font {
	return s.font
}

func (s *PauseState) Cleanup() {
	// Пауза не владеет ресурсами, поэтому очищать нечего.
}

func (s *PauseState) SetCamera(camera *rl.Camera3D) {
	// Пауза использует камеру предыдущего состояния, поэтому своя ей не нужна.
}

// Helper to convert color.RGBA to rl.Color
func colorToRL(c color.Color) rl.Color {
	r, g, b, a := c.RGBA()
	return rl.NewColor(uint8(r>>8), uint8(g>>8), uint8(b>>8), uint8(a>>8))
}

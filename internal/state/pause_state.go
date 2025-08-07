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
	if rl.IsKeyPressed(rl.KeyP) || rl.IsKeyPressed(rl.KeyEscape) {
		s.stateMachine.SetState(s.previousState)
	}
}

func (s *PauseState) Draw() {
	// First, draw the previous state to have it in the background
	if s.previousState != nil {
		s.previousState.Draw()
	}

	// Then, draw a semi-transparent overlay
	rl.DrawRectangle(0, 0, int32(config.ScreenWidth), int32(config.ScreenHeight), rl.NewColor(0, 0, 0, 128))

	// Finally, draw the pause text
	pauseText := "PAUSED"
	fontSize := 40
	textWidth := rl.MeasureText(pauseText, int32(fontSize))
	rl.DrawText(pauseText, (int32(config.ScreenWidth)-textWidth)/2, int32(config.ScreenHeight)/2-20, int32(fontSize), rl.White)
}

func (s *PauseState) Exit() {}

// Helper to convert color.RGBA to rl.Color
func colorToRL(c color.Color) rl.Color {
    r, g, b, a := c.RGBA()
    return rl.NewColor(uint8(r>>8), uint8(g>>8), uint8(b>>8), uint8(a>>8))
}
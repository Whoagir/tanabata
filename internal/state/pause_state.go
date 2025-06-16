// internal/state/pause_state.go
package state

import (
	"go-tower-defense/internal/config"
	"image/color"
	"time"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/inpututil"
	"github.com/hajimehoshi/ebiten/v2/text"
	"golang.org/x/image/font/basicfont"
)

// PauseState — состояние паузы
type PauseState struct {
	sm        *StateMachine
	gameState *GameState
}

func NewPauseState(sm *StateMachine, gameState *GameState) *PauseState {
	return &PauseState{sm: sm, gameState: gameState}
}

func (p *PauseState) Enter() {
	// Устанавливаем состояние кнопки как "на паузе" при входе
	p.gameState.game.PauseButton.SetPaused(true)
}

func (p *PauseState) Update(deltaTime float64) {
	// if inpututil.IsKeyJustPressed(ebiten.KeyF9) {
	// 	p.gameState.game.PauseButton.SetPaused(false)
	// 	p.sm.SetState(p.gameState)
	// 	return
	// }
	p.gameState.game.PauseButton.SetPaused(true)

	if inpututil.IsKeyJustPressed(ebiten.KeyF9) {
		p.sm.SetState(p.gameState)
		return
	}
	if ebiten.IsMouseButtonPressed(ebiten.MouseButtonLeft) {
		mx, my := ebiten.CursorPosition()
		if p.isInsidePauseButton(float32(mx), float32(my)) {
			if time.Since(p.gameState.game.PauseButton.LastToggleTime) >= time.Duration(config.ClickCooldown)*time.Millisecond {
				// p.gameState.game.HandlePauseClick()
				// if !p.gameState.game.PauseButton.IsPaused {
				// 	p.sm.SetState(p.gameState)
				// }
				p.gameState.game.HandlePauseClick()
				p.sm.SetState(p.gameState) // Переключаемся в GameState
			}
		}
	}
}

func (p *PauseState) isInsidePauseButton(mx, my float32) bool {
	button := p.gameState.game.PauseButton
	dx := mx - button.X
	dy := my - button.Y
	return dx*dx+dy*dy <= button.Size*button.Size
}

func (p *PauseState) Draw(screen *ebiten.Image) {
	p.gameState.Draw(screen)
	overlay := ebiten.NewImage(config.ScreenWidth, config.ScreenHeight)
	overlay.Fill(color.RGBA{0, 0, 0, 64})
	screen.DrawImage(overlay, nil)
	text.Draw(screen, "Paused", basicfont.Face7x13, config.ScreenWidth/2-30, config.ScreenHeight/2, color.White)
	p.gameState.game.PauseButton.Draw(screen)
}

func (p *PauseState) Exit() {
	// Ничего не делаем при выходе
}

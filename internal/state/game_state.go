// internal/state/game_state.go
package state

import (
	game "go-tower-defense/internal/app"
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/ui"
	"go-tower-defense/pkg/hexmap"
	"go-tower-defense/pkg/render"
	"image/color"
	"time"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/inpututil"
)

// GameState — состояние игры
type GameState struct {
	sm             *StateMachine
	game           *game.Game
	hexMap         *hexmap.HexMap
	renderer       *render.HexRenderer
	indicator      *ui.StateIndicator
	lastClickTime  time.Time
	lastUpdateTime time.Time
}

func NewGameState(sm *StateMachine) *GameState {
	hexMap := hexmap.NewHexMap()
	gameLogic := game.NewGame(hexMap)
	renderer := render.NewHexRenderer(hexMap, config.HexSize, config.ScreenWidth, config.ScreenHeight, gameLogic.FontFace)
	indicator := ui.NewStateIndicator(
		float32(config.ScreenWidth-config.IndicatorOffsetX),
		float32(config.IndicatorOffsetX),
		float32(config.IndicatorRadius),
	)
	return &GameState{
		sm:             sm,
		game:           gameLogic,
		hexMap:         hexMap,
		renderer:       renderer,
		indicator:      indicator,
		lastClickTime:  time.Now(),
		lastUpdateTime: time.Now(),
	}
}

func (g *GameState) Enter() {
	// Ничего не делаем при входе
}

func (g *GameState) Update(deltaTime float64) {
	g.game.PauseButton.SetPaused(false)

	if inpututil.IsKeyJustPressed(ebiten.KeyF9) {
		g.sm.SetState(NewPauseState(g.sm, g))
		return
	}

	g.game.Update(deltaTime)

	// Обработка левой кнопки
	if ebiten.IsMouseButtonPressed(ebiten.MouseButtonLeft) {
		if time.Since(g.lastClickTime) > time.Duration(config.ClickDebounceTime)*time.Millisecond {
			x, y := ebiten.CursorPosition()
			g.handleClick(x, y, ebiten.MouseButtonLeft)
			g.lastClickTime = time.Now()
		}
		mx, my := ebiten.CursorPosition()
		if g.isInsideSpeedButton(float32(mx), float32(my)) {
			if time.Since(g.game.SpeedButton.LastToggleTime) >= time.Duration(config.ClickCooldown)*time.Millisecond {
				g.game.HandleSpeedClick()
			}
		}
		if g.isInsidePauseButton(float32(mx), float32(my)) {
			if time.Since(g.game.PauseButton.LastToggleTime) >= time.Duration(config.ClickCooldown)*time.Millisecond {
				g.handlePauseClick()
			}
		}
	}

	// Обработка правой кнопки
	if ebiten.IsMouseButtonPressed(ebiten.MouseButtonRight) {
		if time.Since(g.lastClickTime) > time.Duration(config.ClickDebounceTime)*time.Millisecond {
			x, y := ebiten.CursorPosition()
			g.handleClick(x, y, ebiten.MouseButtonRight)
			g.lastClickTime = time.Now()
		}
	}

}

func (g *GameState) isInsidePauseButton(mx, my float32) bool {
	button := g.game.PauseButton
	dx := mx - button.X
	dy := my - button.Y
	return dx*dx+dy*dy <= button.Size*button.Size
}

func (g *GameState) isInsideSpeedButton(mx, my float32) bool {
	button := g.game.SpeedButton
	dx := mx - button.X
	dy := my - button.Y
	return dx*dx+dy*dy <= button.Size*button.Size
}

func (g *GameState) handlePauseClick() {

	g.game.HandlePauseClick()             // Обновляем только таймстампы
	g.sm.SetState(NewPauseState(g.sm, g)) // Переключаемся в PauseState
}

func (g *GameState) handleClick(x, y int, button ebiten.MouseButton) {
	indicatorX := float64(g.indicator.X)
	indicatorY := float64(g.indicator.Y)
	indicatorR := float64(g.indicator.Radius)

	dx := float64(x) - indicatorX
	dy := float64(y) - indicatorY
	distanceSquared := dx*dx + dy*dy
	radiusSquared := indicatorR * indicatorR

	if distanceSquared <= radiusSquared {
		// Клики по индикатору (только левой кнопкой)
		if button == ebiten.MouseButtonLeft && time.Since(g.indicator.LastClickTime) >= time.Duration(config.ClickCooldown)*time.Millisecond {
			g.game.HandleIndicatorClick()
			g.indicator.LastClickTime = time.Now()
		}
	} else if g.game.ECS.GameState == component.BuildState {
		hex := hexmap.PixelToHex(float64(x), float64(y), config.HexSize)
		if g.hexMap.Contains(hex) {
			if button == ebiten.MouseButtonLeft {
				g.game.PlaceTower(hex)
			} else if button == ebiten.MouseButtonRight {
				g.game.RemoveTower(hex)
			}
		}
	}
}

func (g *GameState) Draw(screen *ebiten.Image) {
	screen.Fill(config.BackgroundColor)
	towerHexes := g.game.GetTowerHexes()
	g.renderer.Draw(screen, towerHexes, g.game.RenderSystem, g.game.GetGameTime())
	var stateColor color.Color
	switch g.game.ECS.GameState {
	case component.BuildState:
		stateColor = config.BuildStateColor
	case component.WaveState:
		stateColor = config.WaveStateColor
	}
	g.indicator.Draw(screen, stateColor)
	g.game.SpeedButton.Draw(screen)
	g.game.PauseButton.Draw(screen)
}

func (g *GameState) Exit() {
	// Ничего не делаем при выходе
}

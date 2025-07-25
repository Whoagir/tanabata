// internal/state/game_state.go
package state

import (
	"fmt"
	game "go-tower-defense/internal/app"
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/types"
	"go-tower-defense/internal/ui"
	"go-tower-defense/internal/utils"
	"go-tower-defense/pkg/hexmap"
	"go-tower-defense/pkg/render"
	"image"
	"image/color"
	"math"
	"time"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/ebitenutil"
	"github.com/hajimehoshi/ebiten/v2/inpututil"
)

// GameState — состояние игры
type GameState struct {
	sm              *StateMachine
	game            *game.Game
	hexMap          *hexmap.HexMap
	renderer        *render.HexRenderer
	indicator       *ui.StateIndicator
	infoPanel       *ui.InfoPanel
	lastClickTime   time.Time
	lastUpdateTime  time.Time
	wasShiftPressed bool // Отслеживаем состояние Shift
}

func NewGameState(sm *StateMachine) *GameState {
	hexMap := hexmap.NewHexMap()
	gameLogic := game.NewGame(hexMap)

	mapColors := &render.MapColors{
		BackgroundColor:     config.BackgroundColor,
		PassableColor:       config.PassableColor,
		ImpassableColor:     config.ImpassableColor,
		EntryColor:          config.EntryColor,
		ExitColor:           config.ExitColor,
		TextDarkColor:       config.TextDarkColor,
		TextLightColor:      config.TextLightColor,
		CheckpointTextColor: color.RGBA{255, 255, 0, 255},
		StrokeWidth:         float32(config.StrokeWidth),
	}

	offsetX := float64(config.ScreenWidth) / 2
	offsetY := float64(config.ScreenHeight)/2 + config.MapCenterOffsetY
	renderer := render.NewHexRenderer(hexMap, gameLogic.GetOreHexes(), config.HexSize, offsetX, offsetY, config.ScreenWidth, config.ScreenHeight, gameLogic.FontFace, mapColors)
	renderer.RenderMapImage(gameLogic.GetAllTowerHexes())

	indicator := ui.NewStateIndicator(
		float32(config.ScreenWidth-config.IndicatorOffsetX),
		float32(config.IndicatorOffsetX),
		float32(config.IndicatorRadius),
	)
	infoPanel := ui.NewInfoPanel(gameLogic.FontFace, gameLogic.FontFace, gameLogic.EventDispatcher)

	gs := &GameState{
		sm:             sm,
		game:           gameLogic,
		hexMap:         hexMap,
		renderer:       renderer,
		indicator:      indicator,
		infoPanel:      infoPanel,
		lastClickTime:  time.Now(),
		lastUpdateTime: time.Now(),
	}

	return gs
}

func (g *GameState) Enter() {}

func (g *GameState) Update(deltaTime float64) {
	g.game.PauseButton.SetPaused(false)
	g.infoPanel.Update(g.game.ECS)

	// Логика автоматического подтверждения выбора
	if g.game.ECS.GameState.Phase == component.TowerSelectionState {
		selectedCount := 0
		for _, tower := range g.game.ECS.Towers {
			if tower.IsTemporary && tower.IsSelected {
				selectedCount++
			}
		}

		if selectedCount == g.game.ECS.GameState.TowersToKeep {
			g.game.FinalizeTowerSelection()
			g.game.ECS.GameState.Phase = component.WaveState
			g.game.StartWave()
		}
	}

	if inpututil.IsKeyJustPressed(ebiten.KeyF9) {
		g.sm.SetState(NewPauseState(g.sm, g))
		return
	}

	if g.game.ECS.GameState.Phase == component.BuildState && inpututil.IsKeyJustPressed(ebiten.KeyU) {
		g.game.ToggleLineDragMode()
	}

	if g.game.ECS.GameState.Phase == component.BuildState {
		if inpututil.IsKeyJustPressed(ebiten.Key1) {
			g.game.DebugTowerType = config.TowerTypePhysical
		}
		if inpututil.IsKeyJustPressed(ebiten.Key2) {
			g.game.DebugTowerType = config.TowerTypeMiner
		}
		if inpututil.IsKeyJustPressed(ebiten.Key3) {
			g.game.DebugTowerType = config.TowerTypeWall
		}
		if inpututil.IsKeyJustPressed(ebiten.Key0) {
			g.game.DebugTowerType = config.TowerTypeSilver
		}
	}

	g.game.Update(deltaTime)

	if inpututil.IsMouseButtonJustPressed(ebiten.MouseButtonLeft) {
		x, y := ebiten.CursorPosition()
		if g.isClickOnUI(x, y) {
			g.handleUIClick(x, y)
		} else {
			g.handleGameClick(x, y, ebiten.MouseButtonLeft)
		}
		g.lastClickTime = time.Now()
	}

	if inpututil.IsMouseButtonJustPressed(ebiten.MouseButtonRight) {
		x, y := ebiten.CursorPosition()
		g.handleGameClick(x, y, ebiten.MouseButtonRight)
		g.lastClickTime = time.Now()
	}
}

func (g *GameState) isClickOnUI(x, y int) bool {
	p := image.Point{X: x, Y: y}
	if g.isInsideSpeedButton(float32(x), float32(y)) || g.isInsidePauseButton(float32(x), float32(y)) {
		return true
	}
	indicatorX, indicatorY, indicatorR := float64(g.indicator.X), float64(g.indicator.Y), float64(g.indicator.Radius)
	if (float64(x)-indicatorX)*(float64(x)-indicatorX)+(float64(y)-indicatorY)*(float64(y)-indicatorY) <= indicatorR*indicatorR {
		return true
	}
	if g.infoPanel.IsVisible && p.In(g.infoPanel.SelectButton.Rect) {
		// Клик по кнопке "Выбрать" в панели теперь не считается общим UI-кликом,
		// так как он обрабатывается внутри infoPanel.Update
		return false
	}
	return false
}

func (g *GameState) handleUIClick(x, y int) {
	if g.isInsideSpeedButton(float32(x), float32(y)) {
		g.game.HandleSpeedClick()
	} else if g.isInsidePauseButton(float32(x), float32(y)) {
		g.handlePauseClick()
	} else {
		indicatorX, indicatorY, indicatorR := float64(g.indicator.X), float64(g.indicator.Y), float64(g.indicator.Radius)
		if (float64(x)-indicatorX)*(float64(x)-indicatorX)+(float64(y)-indicatorY)*(float64(y)-indicatorY) <= indicatorR*indicatorR {
			g.game.HandleIndicatorClick()
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
	g.game.HandlePauseClick()
	g.sm.SetState(NewPauseState(g.sm, g))
}

func (g *GameState) findEntityAt(x, y int) (types.EntityID, bool) {
	for id, pos := range g.game.ECS.Positions {
		if _, isTower := g.game.ECS.Towers[id]; isTower {
			dist := math.Hypot(pos.X-float64(x), pos.Y-float64(y))
			if dist < config.HexSize*0.5 {
				return id, true
			}
		}
	}
	for id, pos := range g.game.ECS.Positions {
		if _, isEnemy := g.game.ECS.Enemies[id]; isEnemy {
			dist := math.Hypot(pos.X-float64(x), pos.Y-float64(y))
			if dist < config.HexSize*0.5 {
				return id, true
			}
		}
	}
	return 0, false
}

func (g *GameState) handleGameClick(x, y int, button ebiten.MouseButton) {
	isShiftPressed := ebiten.IsKeyPressed(ebiten.KeyShiftLeft) || ebiten.IsKeyPressed(ebiten.KeyShiftRight)

	if button == ebiten.MouseButtonLeft {
		if entityID, found := g.findEntityAt(x, y); found {
			// Если нажат Shift, добавляем башню в ручной выбор
			if isShiftPressed {
				g.game.AddToManualSelection(entityID)
				return // Выходим, чтобы не обрабатывать клик дальше
			}
			// Иначе, показываем инфо-панель как обычно
			g.infoPanel.SetTarget(entityID)
			return
		} else {
			g.infoPanel.Hide()
		}
	}

	hex := utils.ScreenToHex(float64(x), float64(y))
	if !g.hexMap.Contains(hex) {
		return
	}

	if g.game.IsInLineDragMode() {
		if button == ebiten.MouseButtonLeft {
			g.game.HandleLineDragClick(hex, x, y)
		}
		return
	}

	if g.game.ECS.GameState.Phase == component.BuildState {
		if button == ebiten.MouseButtonLeft {
			g.game.PlaceTower(hex)
		} else if button == ebiten.MouseButtonRight {
			g.game.RemoveTower(hex)
		}
	}
}

func (g *GameState) Draw(screen *ebiten.Image) {
	wallHexes, typeAHexes, typeBHexes := g.game.GetTowerHexesByType()
	outlineColors := render.TowerOutlineColors{
		WallColor:  config.TowerStrokeColor,
		TypeAColor: config.TowerAStrokeColor,
		TypeBColor: config.TowerBStrokeColor,
	}
	g.renderer.Draw(screen, wallHexes, typeAHexes, typeBHexes, outlineColors, g.game.RenderSystem, g.game.GetGameTime(), g.game.IsInLineDragMode(), g.game.GetDragSourceTowerID(), g.game.GetHiddenLineID(), g.game.ECS.GameState.Phase, g.game.CancelLineDrag)

	var stateColor color.Color
	switch g.game.ECS.GameState.Phase {
	case component.BuildState:
		stateColor = config.BuildStateColor
	case component.WaveState:
		stateColor = config.WaveStateColor
	case component.TowerSelectionState:
		stateColor = config.SelectionStateColor
	}
	g.indicator.Draw(screen, stateColor)
	g.game.SpeedButton.Draw(screen)
	g.game.PauseButton.Draw(screen)
	g.infoPanel.Draw(screen, g.game.ECS)

	ebitenutil.DebugPrint(screen, fmt.Sprintf("Wave: %d", g.game.Wave))
}

func (g *GameState) Exit() {}

// internal/state/game_state.go
package state

import (
	"go-tower-defense/internal/app"
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/types"
	"go-tower-defense/internal/ui"
	"go-tower-defense/internal/utils"
	"go-tower-defense/pkg/hexmap"
	"go-tower-defense/pkg/render"
	"image/color"
	"time"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// GameState — состояние игры
type GameState struct {
	sm                   *StateMachine
	game                 *app.Game
	hexMap               *hexmap.HexMap
	renderer             *render.HexRendererRL
	indicator            *ui.StateIndicatorRL
	waveIndicator        *ui.WaveIndicatorRL
	playerLevelIndicator *ui.PlayerLevelIndicatorRL
	infoPanel            *ui.InfoPanelRL
	recipeBook           *ui.RecipeBookRL
	lastClickTime        time.Time
	camera               *rl.Camera3D
}

// NewGameState создает новое состояние игры для Raylib
func NewGameState(sm *StateMachine, recipeLibrary *defs.CraftingRecipeLibrary, camera *rl.Camera3D) *GameState {
	hexMap := hexmap.NewHexMap()
	font := rl.LoadFont("assets/fonts/arial.ttf")
	gameLogic := app.NewGame(hexMap, font)
	renderer := render.NewHexRendererRL(hexMap, gameLogic.GetOreHexes(), float32(config.HexSize), font)

	indicator := ui.NewStateIndicatorRL(
		float32(config.ScreenWidth-config.IndicatorOffsetX),
		float32(config.IndicatorOffsetX),
		float32(config.IndicatorRadius),
	)
	waveIndicator := ui.NewWaveIndicatorRL(0, 0, font)
	playerLevelIndicator := ui.NewPlayerLevelIndicatorRL(
		float32(config.ScreenWidth-ui.XpBarWidth-config.IndicatorOffsetX+10),
		float32(config.IndicatorOffsetX+28),
		font,
	)
	infoPanel := ui.NewInfoPanelRL(font, gameLogic.EventDispatcher)

	// Центрируем книгу рецептов
	recipeBookWidth := float32(400)
	recipeBookHeight := float32(600)
	recipeBookX := (float32(config.ScreenWidth) - recipeBookWidth) / 2
	recipeBookY := (float32(config.ScreenHeight) - recipeBookHeight) / 2
	recipeBook := ui.NewRecipeBookRL(recipeBookX, recipeBookY, recipeBookWidth, recipeBookHeight, recipeLibrary.Recipes, font)

	gs := &GameState{
		sm:                   sm,
		game:                 gameLogic,
		hexMap:               hexMap,
		renderer:             renderer,
		indicator:            indicator,
		waveIndicator:        waveIndicator,
		playerLevelIndicator: playerLevelIndicator,
		infoPanel:            infoPanel,
		recipeBook:           recipeBook,
		lastClickTime:        time.Now(),
		camera:               camera,
	}

	return gs
}

func (g *GameState) SetCamera(camera *rl.Camera3D) {
	g.camera = camera
	if g.game != nil && g.game.RenderSystem != nil {
		g.game.RenderSystem.SetCamera(camera)
	}
}

func (g *GameState) Enter() {}

func (g *GameState) Update(deltaTime float64) {
	if g.camera == nil {
		return
	}

	g.game.PauseButton.SetPaused(false)
	g.infoPanel.Update(g.game.ECS)

	if rl.IsKeyPressed(rl.KeyR) {
		g.recipeBook.Toggle()
	}

	if g.recipeBook.IsVisible {
		g.recipeBook.Update()
		if rl.IsKeyPressed(rl.KeyEscape) {
			g.recipeBook.Toggle()
		}
		return
	}

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

	if rl.IsKeyPressed(rl.KeyF9) {
		return
	}

	if g.game.ECS.GameState.Phase == component.BuildState {
		g.handleDebugKeys()
		if rl.IsKeyPressed(rl.KeyU) {
			g.game.ToggleLineDragMode()
		}
	}

	g.game.Update(deltaTime)

	isShiftPressed := rl.IsKeyDown(rl.KeyLeftShift) || rl.IsKeyDown(rl.KeyRightShift)
	mousePos := rl.GetMousePosition()

	if isShiftPressed {
		if rl.IsMouseButtonPressed(rl.MouseLeftButton) {
			hex := g.getHexUnderCursor()
			g.game.HandleShiftClick(hex, true, false)
		}
		if rl.IsMouseButtonPressed(rl.MouseRightButton) {
			hex := g.getHexUnderCursor()
			g.game.HandleShiftClick(hex, false, true)
		}
	} else {
		if rl.IsMouseButtonPressed(rl.MouseLeftButton) {
			if g.isClickOnUI(mousePos) {
				g.handleUIClick(mousePos)
			} else {
				g.handleGameClick(rl.MouseLeftButton)
			}
			g.lastClickTime = time.Now()
		}
		if rl.IsMouseButtonPressed(rl.MouseRightButton) {
			g.handleGameClick(rl.MouseRightButton)
			g.lastClickTime = time.Now()
		}
	}
}

func (g *GameState) getHexUnderCursor() hexmap.Hex {
	if g.camera == nil {
		return hexmap.Hex{}
	}
	ray := rl.GetMouseRay(rl.GetMousePosition(), *g.camera)
	t := -ray.Position.Y / ray.Direction.Y
	if t > 0 {
		hitPoint := rl.Vector3Add(ray.Position, rl.Vector3Scale(ray.Direction, t))
		return g.renderer.WorldToHex(hitPoint)
	}
	return hexmap.Hex{}
}

func (g *GameState) handleDebugKeys() {
	if rl.IsKeyPressed(rl.KeyOne) {
		g.game.DebugTowerID = "RANDOM_ATTACK"
	}
	if rl.IsKeyPressed(rl.KeyTwo) {
		g.game.DebugTowerID = "TOWER_MINER"
	}
	if rl.IsKeyPressed(rl.KeyThree) {
		g.game.DebugTowerID = "TOWER_WALL"
	}
	if rl.IsKeyPressed(rl.KeyZero) {
		g.game.DebugTowerID = "TOWER_SILVER"
	}
}

func (g *GameState) isClickOnUI(mousePos rl.Vector2) bool {
	if g.game.SpeedButton.IsClicked(mousePos) || g.game.PauseButton.IsClicked(mousePos) {
		return true
	}
	if g.indicator.IsClicked(mousePos) {
		return true
	}
	if g.infoPanel.IsVisible && g.infoPanel.IsClicked(mousePos) {
		return true
	}
	return false
}

func (g *GameState) handleUIClick(mousePos rl.Vector2) {
	if g.game.SpeedButton.IsClicked(mousePos) {
		g.game.HandleSpeedClick()
	} else if g.game.PauseButton.IsClicked(mousePos) {
		g.game.HandlePauseClick()
	} else if g.indicator.IsClicked(mousePos) {
		g.indicator.HandleClick()
		g.game.HandleIndicatorClick()
	}
}

func (g *GameState) findEntityAtCursor() (types.EntityID, bool) {
	hex := g.getHexUnderCursor()
	for id, t := range g.game.ECS.Towers {
		if t.Hex == hex {
			return id, true
		}
	}
	for id := range g.game.ECS.Enemies {
		if pos, ok := g.game.ECS.Positions[id]; ok {
			enemyHex := utils.ScreenToHex(pos.X, pos.Y)
			if enemyHex == hex {
				return id, true
			}
		}
	}
	return 0, false
}

func (g *GameState) handleGameClick(button rl.MouseButton) {
	hex := g.getHexUnderCursor()

	if button == rl.MouseLeftButton {
		entityID, entityFound := g.findEntityAtCursor()
		if entityFound {
			g.infoPanel.SetTarget(entityID)
			g.game.SetHighlightedTower(entityID)
		} else {
			g.infoPanel.Hide()
			g.game.ClearAllSelections()
		}
	}

	if !g.hexMap.Contains(hex) {
		g.game.ClearAllSelections()
		return
	}

	if g.game.IsInLineDragMode() {
		if button == rl.MouseLeftButton {
			// g.game.HandleLineDragClick(hex, x, y)
		}
		return
	}

	if g.game.ECS.GameState.Phase == component.BuildState || g.game.ECS.GameState.Phase == component.TowerSelectionState {
		if button == rl.MouseLeftButton {
			if g.game.DebugTowerID != "" {
				g.game.CreateDebugTower(hex, g.game.DebugTowerID)
				g.game.DebugTowerID = ""
			} else {
				g.game.PlaceTower(hex)
			}
		} else if button == rl.MouseRightButton {
			g.game.RemoveTower(hex)
		}
	}
}

func (g *GameState) Draw() {
	if g.camera == nil {
		return
	}
	g.renderer.Draw(g.game.RenderSystem, g.game.GetGameTime(), g.game.IsInLineDragMode(), g.game.GetDragSourceTowerID(), g.game.GetHiddenLineID(), g.game.ECS.GameState.Phase, g.game.CancelLineDrag)

	// Отрисовка выделения башен в 3D
	for _, tower := range g.game.ECS.Towers {
		if tower.IsHighlighted || tower.IsManuallySelected {
			worldPos := g.renderer.HexToWorld(tower.Hex)
			// Рисуем выделение чуть выше, чтобы было видно
			highlightPos := rl.Vector3Add(worldPos, rl.NewVector3(0, 0.5, 0))
			rl.DrawCylinderWires(highlightPos, float32(config.HexSize)*1.1, float32(config.HexSize)*1.1, 2.0, 6, config.HighlightColorRL)
		}
	}
}

// DrawUI рисует все элементы интерфейса в 2D
func (g *GameState) DrawUI() {
	var stateColor color.RGBA
	switch g.game.ECS.GameState.Phase {
	case component.BuildState:
		stateColor = config.BuildStateColor
	case component.WaveState:
		stateColor = config.WaveStateColor
	case component.TowerSelectionState:
		stateColor = config.SelectionStateColor
	}
	g.indicator.Draw(stateColor)

	waveTextWidth := g.waveIndicator.GetTextWidth(g.game.Wave)
	levelIndicatorCenterX := g.playerLevelIndicator.X + (ui.XpBarWidth / 2)
	g.waveIndicator.X = levelIndicatorCenterX - (waveTextWidth / 2)
	g.waveIndicator.Y = g.playerLevelIndicator.Y + 25
	g.waveIndicator.Draw(g.game.Wave)

	g.game.SpeedButton.Draw()
	g.game.PauseButton.Draw()
	g.infoPanel.Draw(g.game.ECS)

	if playerState, ok := g.game.ECS.PlayerState[g.game.PlayerID]; ok {
		g.playerLevelIndicator.Draw(playerState.Level, playerState.CurrentXP, playerState.XPToNextLevel)
	}

	if g.recipeBook.IsVisible {
		availableTowers := make(map[string]int)
		for _, tower := range g.game.ECS.Towers {
			availableTowers[tower.DefID]++
		}
		g.recipeBook.Draw(availableTowers)
	}
}

func (g *GameState) Exit() {
	g.renderer.Unload()
}
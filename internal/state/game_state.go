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
	"strings"
	"time"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// GameState — состояние игры
type GameState struct {
	sm                   *StateMachine
	game                 *app.Game
	hexMap               *hexmap.HexMap
	renderer             *render.HexRenderer
	indicator            *ui.StateIndicatorRL
	waveIndicator        *ui.WaveIndicatorRL
	playerLevelIndicator *ui.PlayerLevelIndicatorRL
	infoPanel            *ui.InfoPanelRL
	recipeBook           *ui.RecipeBookRL
	lastClickTime        time.Time
	camera               *rl.Camera3D
	font                 rl.Font
	checkpointTextures   map[int]rl.Texture2D // Текстуры для номеров чекпоинтов
}

// intToRoman конвертирует целое число в римскую цифру (для чисел от 1 до 10)
func intToRoman(num int) string {
	if num < 1 || num > 10 {
		return "" // Поддерживаем только небольшие числа для чекпоинтов
	}
	val := []int{10, 9, 5, 4, 1}
	syms := []string{"X", "IX", "V", "IV", "I"}
	var roman strings.Builder
	for i := 0; i < len(val); i++ {
		for num >= val[i] {
			roman.WriteString(syms[i])
			num -= val[i]
		}
	}
	return roman.String()
}

// NewGameState создает новое состояние игры для Raylib
func NewGameState(sm *StateMachine, recipeLibrary *defs.CraftingRecipeLibrary, camera *rl.Camera3D) *GameState {
	hexMap := hexmap.NewHexMap()

	// Загрузка шрифта с поддержкой кириллицы
	var fontChars []rune
	for i := 32; i <= 127; i++ {
		fontChars = append(fontChars, rune(i))
	}
	for i := 0x0400; i <= 0x04FF; i++ {
		fontChars = append(fontChars, rune(i))
	}
	fontChars = append(fontChars, '₽', '«', '»', '(', ')', '.', ',')
	font := rl.LoadFontEx("assets/fonts/arial.ttf", 64, fontChars, int32(len(fontChars))) // Увеличим размер для качества

	gameLogic := app.NewGame(hexMap, font)

	// Собираем информацию о цветах для руды перед созданием рендерера
	oreHexColors := make(map[hexmap.Hex]rl.Color)
	specialHexes := make(map[hexmap.Hex]struct{})
	specialHexes[hexMap.Entry] = struct{}{}
	specialHexes[hexMap.Exit] = struct{}{}
	for _, cp := range hexMap.Checkpoints {
		specialHexes[cp] = struct{}{}
	}

	for _, oreComp := range gameLogic.ECS.Ores {
		hex := hexmap.PixelToHex(oreComp.Position.X, oreComp.Position.Y, config.HexSize)
		if _, isSpecial := specialHexes[hex]; !isSpecial {
			oreHexColors[hex] = config.OreHexBackgroundColorRL
		}
	}

	renderer := render.NewHexRenderer(hexMap, oreHexColors)

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

	recipeBookWidth := float32(400)
	recipeBookHeight := float32(600)
	recipeBookX := (float32(config.ScreenWidth) - recipeBookWidth) / 2
	recipeBookY := (float32(config.ScreenHeight) - recipeBookHeight) / 2
	recipeBook := ui.NewRecipeBookRL(recipeBookX, recipeBookY, recipeBookWidth, recipeBookHeight, recipeLibrary.Recipes, font)

	// --- Генерация текстур для чекпоинтов ---
	checkpointTextures := make(map[int]rl.Texture2D)
	for i := 0; i < len(hexMap.Checkpoints); i++ {
		romanNumeral := intToRoman(i + 1)
		img := rl.ImageTextEx(font, romanNumeral, 64, 1, rl.White)
		tex := rl.LoadTextureFromImage(img)
		checkpointTextures[i] = tex
		rl.UnloadImage(img) // Освобождаем память CPU
	}

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
		font:                 font,
		checkpointTextures:   checkpointTextures, // Сохраняем текстуры
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

	// Управление масштабированием камеры
	if rl.IsKeyPressed(rl.KeyR) {
		g.camera.Fovy -= config.CameraZoomStep
		if g.camera.Fovy < config.CameraFovyMin {
			g.camera.Fovy = config.CameraFovyMin
		}
	}
	if rl.IsKeyPressed(rl.KeyT) {
		g.camera.Fovy += config.CameraZoomStep
		if g.camera.Fovy > config.CameraFovyMax {
			g.camera.Fovy = config.CameraFovyMax
		}
	}
	if rl.IsKeyPressed(rl.KeyY) {
		g.camera.Fovy = config.CameraFovyDefault
	}

	g.game.PauseButton.SetPaused(false)
	g.infoPanel.Update(g.game.ECS)

	if rl.IsKeyPressed(rl.KeyB) { // Используем 'B' для книги рецептов, чтобы не конфликтовать с зумом
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
		px := hitPoint.X / float32(config.CoordScale)
		py := hitPoint.Z / float32(config.CoordScale)
		return hexmap.PixelToHex(float64(px), float64(py), float64(config.HexSize))
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
	// Шаг 1: Отрисовка основной сцены (земля, башни, враги, эффекты)
	g.renderer.Draw()
	g.game.RenderSystem.Draw(g.game.GetGameTime(), g.game.IsInLineDragMode(), g.game.GetDragSourceTowerID(), g.game.GetHiddenLineID(), g.game.ECS.GameState.Phase, g.game.CancelLineDrag)

	// Шаг 2: Отрисовка выделения башен
	for id, tower := range g.game.ECS.Towers {
		if tower.IsHighlighted || tower.IsManuallySelected {
			x, y := tower.Hex.ToPixel(config.HexSize)
			worldX := float32(x * config.CoordScale)
			worldZ := float32(y * config.CoordScale)

			var height float32 = 2.0
			if renderable, ok := g.game.ECS.Renderables[id]; ok {
				height = g.game.RenderSystem.GetTowerRenderHeight(tower, renderable)
			}

			highlightPos := rl.NewVector3(worldX, height+0.5, worldZ)
			rl.DrawCylinderWires(highlightPos, float32(config.HexSize*config.CoordScale)*1.1, float32(config.HexSize*config.CoordScale)*1.1, 2.0, 6, config.HighlightColorRL)
		}
	}

	// Шаг 3: Отрисовка номеров чекпоинтов как билбордов
	for i, checkpoint := range g.hexMap.Checkpoints {
		if tex, ok := g.checkpointTextures[i]; ok {
			px, py := checkpoint.ToPixel(config.HexSize)
			worldPos := rl.NewVector3(float32(px*config.CoordScale), 4.0, float32(py*config.CoordScale))
			rl.DrawBillboard(*g.camera, tex, worldPos, 10.0, config.GridColorRL)
		}
	}

	// --- Финальный рендеринг снарядов ---
	rl.DrawRenderBatchActive()
	rl.DisableDepthTest()
	g.game.RenderSystem.DrawProjectiles()
	rl.DrawRenderBatchActive()
	rl.EnableDepthTest()
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
}

// Cleanup освобождает ресурсы, используемые состоянием
func (g *GameState) Cleanup() {
	g.renderer.Cleanup()
	// Выгружаем текстуры чекпоинтов
	for _, tex := range g.checkpointTextures {
		rl.UnloadTexture(tex)
	}
	// В будущем здесь можно будет выгружать и другие ресурсы, например, шрифт
}

// internal/state/game_state.go
package state

import (
	"go-tower-defense/internal/app"
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/types"
	"go-tower-defense/internal/ui"
	"go-tower-defense/pkg/hexmap"
	"go-tower-defense/pkg/render"
	"strings"
	"time"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// Убеждаемся, что GameState соответствует интерфейсу State
var _ State = (*GameState)(nil)

// GameState — состояние игры
type GameState struct {
	sm                    *StateMachine
	game                  *app.Game
	hexMap                *hexmap.HexMap
	renderer              *render.HexRenderer
	indicator             *ui.StateIndicatorRL
	playerLevelIndicator  *ui.PlayerLevelIndicatorRL
	playerHealthIndicator *ui.PlayerHealthIndicator
	infoPanel             *ui.InfoPanelRL
	recipeBook            *ui.RecipeBookRL
	uIndicator            *ui.UIndicatorRL
	waveIndicator         *ui.WaveIndicator
	oreSectorIndicator    *ui.OreSectorIndicatorRL // Индикатор состояния жил
	lastClickTime         time.Time
	camera                *rl.Camera3D
	font                  rl.Font
	checkpointTextures    map[int]rl.Texture2D
	isGameOver            bool // Флаг окончания игры
	restartButton         rl.Rectangle
}

// intToRoman конвертирует целое число в римску�� цифру (для чисел от 1 до 10)
func intToRoman(num int) string {
	if num < 1 || num > 10 {
		return ""
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
func NewGameState(sm *StateMachine, recipeLibrary *defs.CraftingRecipeLibrary, towerDefs map[string]*defs.TowerDefinition, camera *rl.Camera3D) *GameState {
	hexMap := hexmap.NewHexMap()

	var fontChars []rune
	for i := 32; i <= 127; i++ {
		fontChars = append(fontChars, rune(i))
	}
	for i := 0x0400; i <= 0x04FF; i++ {
		fontChars = append(fontChars, rune(i))
	}
	fontChars = append(fontChars, '₽', '«', '»', '(', ')', '.', ',')
	font := rl.LoadFontEx("assets/fonts/arial.ttf", 64, fontChars, int32(len(fontChars)))

	gameLogic := app.NewGame(hexMap, font, towerDefs)

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

	pauseButtonX := float32(config.ScreenWidth - config.IndicatorOffsetX - 90)
	pauseButtonSize := float32(config.IndicatorRadius)
	indicatorX := float32(config.ScreenWidth - config.IndicatorOffsetX)
	indicatorRadius := float32(config.IndicatorRadius)

	levelIndicatorLeftEdge := pauseButtonX - pauseButtonSize
	levelIndicatorRightEdge := indicatorX + indicatorRadius
	levelIndicatorWidth := levelIndicatorRightEdge - levelIndicatorLeftEdge

	indicator := ui.NewStateIndicatorRL(
		indicatorX,
		float32(config.IndicatorOffsetX),
		indicatorRadius,
	)
	playerLevelIndicator := ui.NewPlayerLevelIndicatorRL(
		levelIndicatorLeftEdge,
		float32(config.IndicatorOffsetX+35),
		levelIndicatorWidth,
	)

	waveIndicatorY := playerLevelIndicator.Y + 44
	waveIndicator := ui.NewWaveIndicator(
		levelIndicatorLeftEdge+levelIndicatorWidth/2,
		waveIndicatorY,
		28,
	)

	// Рассчитываем позицию для индикатора здоровья под индикатором волны
	healthIndicatorY := waveIndicator.Y + waveIndicator.FontSize + 40 // Y волны + ее высота + отступ
	// Центрируем по горизонтали так же, как и индикатор волны
	healthIndicatorX := waveIndicator.X - (float32(ui.HealthCols*(ui.HealthCircleRadius*2+ui.HealthCircleSpacing)-ui.HealthCircleSpacing))/2

	playerHealthIndicator := ui.NewPlayerHealthIndicator(healthIndicatorX, healthIndicatorY)
	infoPanel := ui.NewInfoPanelRL(font, gameLogic.EventDispatcher)

	recipeBookWidth := float32(400)
	recipeBookHeight := float32(600)
	recipeBookX := (float32(config.ScreenWidth) - recipeBookWidth) / 2
	recipeBookY := (float32(config.ScreenHeight) - recipeBookHeight) / 2
	recipeBook := ui.NewRecipeBookRL(recipeBookX, recipeBookY, recipeBookWidth, recipeBookHeight, recipeLibrary.Recipes, font)

	// Размещаем индикатор "U" слева от кнопки паузы
	uIndicatorSize := float32(30)
	uIndicatorX := pauseButtonX - 20 - uIndicatorSize/2 // X кнопки паузы - отступ - половина размера индикатора
	uIndicator := ui.NewUIndicatorRL(
		uIndicatorX,
		float32(config.IndicatorOffsetX), // Y на том же уровне, что и другие иконки
		uIndicatorSize,
		font,
	)

	// --- Индикатор состояния жил ---
	oreIndicatorWidth := float32(100)
	oreIndicatorHeight := float32(80)
	oreIndicatorX := float32(20)
	oreIndicatorY := float32(config.ScreenHeight) - oreIndicatorHeight - 20
	oreSectorIndicator := ui.NewOreSectorIndicatorRL(oreIndicatorX, oreIndicatorY, oreIndicatorWidth, oreIndicatorHeight)

	checkpointTextures := make(map[int]rl.Texture2D)
	for i := 0; i < len(hexMap.Checkpoints); i++ {
		romanNumeral := intToRoman(i + 1)
		img := rl.ImageTextEx(font, romanNumeral, 64, 1, rl.White)
		tex := rl.LoadTextureFromImage(img)
		rl.SetTextureFilter(tex, rl.FilterPoint)
		checkpointTextures[i] = tex
		rl.UnloadImage(img)
	}

	// --- Кнопка рестарта ---
	btnWidth := float32(200)
	btnHeight := float32(50)
	restartButton := rl.NewRectangle(
		(float32(config.ScreenWidth)-btnWidth)/2,
		(float32(config.ScreenHeight)-btnHeight)/2+50, // Чуть ниже текста
		btnWidth,
		btnHeight,
	)

	gs := &GameState{
		sm:                    sm,
		game:                  gameLogic,
		hexMap:                hexMap,
		renderer:              renderer,
		indicator:             indicator,
		playerLevelIndicator:  playerLevelIndicator,
		playerHealthIndicator: playerHealthIndicator,
		infoPanel:             infoPanel,
		recipeBook:            recipeBook,
		uIndicator:            uIndicator,
		waveIndicator:         waveIndicator,
		oreSectorIndicator:    oreSectorIndicator,
		lastClickTime:         time.Now(),
		camera:                camera,
		font:                  font,
		checkpointTextures:    checkpointTextures,
		isGameOver:            false,
		restartButton:         restartButton,
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

	// Если игра окончена, блокируем все обновления, кроме клика по рестарту
	if g.isGameOver {
		if rl.IsMouseButtonPressed(rl.MouseLeftButton) {
			if rl.CheckCollisionPointRec(rl.GetMousePosition(), g.restartButton) {
				// Создаем карту указателей для передачи в системы
				towerDefPtrs := make(map[string]*defs.TowerDefinition)
				for id, def := range defs.TowerDefs {
					d := def
					towerDefPtrs[id] = &d
				}
				// Пересоздаем состояние игры
				newState := NewGameState(g.sm, defs.RecipeLibrary, towerDefPtrs, g.camera)
				newState.SetCamera(g.camera)
				g.sm.SetState(newState)
			}
		}
		return
	}

	// Проверяем условие проигрыша
	if playerState, ok := g.game.ECS.PlayerState[g.game.PlayerID]; ok {
		if playerState.Health <= 0 {
			g.isGameOver = true
			return // Останавливаем дальнейшее обновление
		}
	}

	// Управление масштабированием камеры
	if g.camera.Projection == rl.CameraPerspective {
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
	} else if g.camera.Projection == rl.CameraOrthographic {
		if rl.IsKeyPressed(rl.KeyR) {
			g.camera.Fovy -= config.CameraOrthoZoomStep
			if g.camera.Fovy < config.CameraOrthoFovyMin {
				g.camera.Fovy = config.CameraOrthoFovyMin
			}
		}
		if rl.IsKeyPressed(rl.KeyT) {
			g.camera.Fovy += config.CameraOrthoZoomStep
			if g.camera.Fovy > config.CameraOrthoFovyMax {
				g.camera.Fovy = config.CameraOrthoFovyMax
			}
		}
	}

	if rl.IsKeyPressed(rl.KeyY) {
		if g.camera.Projection == rl.CameraPerspective {
			g.camera.Fovy = config.CameraFovyDefault
		} else {
			g.camera.Fovy = config.CameraOrthoFovyDefault
		}
	}

	if rl.IsKeyPressed(rl.KeyP) {
		if g.camera.Projection == rl.CameraPerspective {
			g.camera.Projection = rl.CameraOrthographic
			g.camera.Fovy = config.CameraOrthoFovyDefault
		} else {
			g.camera.Projection = rl.CameraPerspective
			g.camera.Fovy = config.CameraFovyDefault
		}
	}

	g.infoPanel.Update(g.game.ECS)

	if rl.IsKeyPressed(rl.KeyB) {
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
		g.game.HandlePauseClick()
		g.sm.SetState(NewPauseState(g.sm, g, g.font))
		return
	}

	if rl.IsKeyPressed(rl.KeyF10) {
		g.game.ToggleGodMode()
	}

	if g.game.ECS.GameState.Phase == component.BuildState || g.game.ECS.GameState.Phase == component.TowerSelectionState {
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
			ray := rl.GetMouseRay(rl.GetMousePosition(), *g.camera)
			hex := g.getHexUnderCursor(ray)
			g.game.HandleShiftClick(hex, true, false)
		}
		if rl.IsMouseButtonPressed(rl.MouseRightButton) {
			ray := rl.GetMouseRay(rl.GetMousePosition(), *g.camera)
			hex := g.getHexUnderCursor(ray)
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

func (g *GameState) getHexUnderCursor(ray rl.Ray) hexmap.Hex {
	if g.camera == nil {
		return hexmap.Hex{}
	}
	t := -ray.Position.Y / ray.Direction.Y
	if t > 0 {
		hitPoint := rl.Vector3Add(ray.Position, rl.Vector3Scale(ray.Direction, t))
		px := hitPoint.X / float32(config.CoordScale)
		py := hitPoint.Z / float32(config.CoordScale)
		return hexmap.PixelToHex(float64(px), float64(py), float64(config.HexSize))
	}
	return hexmap.Hex{}
}

func (g *GameState) getHitPointUnderCursor(ray rl.Ray) (rl.Vector3, bool) {
	if g.camera == nil {
		return rl.Vector3{}, false
	}
	t := -ray.Position.Y / ray.Direction.Y
	if t > 0 {
		hitPoint := rl.Vector3Add(ray.Position, rl.Vector3Scale(ray.Direction, t))
		return hitPoint, true
	}
	return rl.Vector3{}, false
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
		g.game.DebugTowerID = "TOWER_LIGHTHOUSE"
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
		g.sm.SetState(NewPauseState(g.sm, g, g.font))
	} else if g.indicator.IsClicked(mousePos) {
		g.indicator.HandleClick()
		g.game.HandleIndicatorClick()
	}
}

func (g *GameState) findEntityAtCursor(ray rl.Ray) (types.EntityID, bool) {
	hex := g.getHexUnderCursor(ray)
	for id, t := range g.game.ECS.Towers {
		if t.Hex == hex {
			return id, true
		}
	}

	var closestEntity types.EntityID
	closestDistance := float32(-1.0)
	found := false

	for id := range g.game.ECS.Enemies {
		if pos, ok := g.game.ECS.Positions[id]; ok {
			if renderable, okRender := g.game.ECS.Renderables[id]; okRender {
				scaledRadius := renderable.Radius * float32(config.CoordScale)
				enemyPosition := rl.NewVector3(float32(pos.X*config.CoordScale), scaledRadius, float32(pos.Y*config.CoordScale))
				collision := rl.GetRayCollisionSphere(ray, enemyPosition, scaledRadius)
				if collision.Hit {
					distance := rl.Vector3DistanceSqr(g.camera.Position, enemyPosition)
					if !found || distance < closestDistance {
						closestDistance = distance
						closestEntity = id
						found = true
					}
				}
			}
		}
	}

	if found {
		return closestEntity, true
	}

	return 0, false
}

func (g *GameState) handleGameClick(button rl.MouseButton) {
	ray := rl.GetMouseRay(rl.GetMousePosition(), *g.camera)
	hex := g.getHexUnderCursor(ray)
	hitPoint, hasHit := g.getHitPointUnderCursor(ray)

	if button == rl.MouseLeftButton {
		entityID, entityFound := g.findEntityAtCursor(ray)
		if entityFound {
			if _, isEnemy := g.game.ECS.Enemies[entityID]; isEnemy {
				g.infoPanel.SetTarget(entityID)
			} else if _, isTower := g.game.ECS.Towers[entityID]; isTower {
				g.infoPanel.SetTarget(entityID)
				g.game.SetHighlightedTower(entityID)
			}
		} else {
			g.infoPanel.Hide()
			g.game.ClearAllSelections()
		}
	}

	if !g.hexMap.Contains(hex) {
		g.game.ClearAllSelections()
		if g.game.IsInLineDragMode() {
			g.game.CancelLineDrag()
		}
		return
	}

	if g.game.IsInLineDragMode() {
		if button == rl.MouseLeftButton && hasHit {
			g.game.HandleLineDragClick(hex, hitPoint)
		} else if button == rl.MouseRightButton {
			g.game.CancelLineDrag()
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

	g.renderer.Draw()
	g.game.RenderSystem.Draw(
		g.game.GetGameTime(),
		g.game.IsInLineDragMode(),
		g.game.GetDragSourceTowerID(),
		g.game.GetHiddenLineID(),
		g.game.ECS.GameState.Phase,
		g.game.CancelLineDrag,
		g.game.ClearedCheckpoints,
		g.game.FuturePath,
	)

	selectedID := g.infoPanel.TargetEntity
	if selectedID != 0 {
		var worldPos rl.Vector3
		var radius float32
		var found bool

		if tower, ok := g.game.ECS.Towers[selectedID]; ok {
			x, y := tower.Hex.ToPixel(config.HexSize)
			worldPos = rl.NewVector3(float32(x*config.CoordScale), 0, float32(y*config.CoordScale))
			if renderable, ok := g.game.ECS.Renderables[selectedID]; ok {
				radius = renderable.Radius * float32(config.CoordScale) * 2.0
			} else {
				radius = float32(config.HexSize*config.CoordScale) * 1.35
			}
			found = true
		} else if pos, ok := g.game.ECS.Positions[selectedID]; ok {
			worldPos = rl.NewVector3(float32(pos.X*config.CoordScale), 0, float32(pos.Y*config.CoordScale))
			if renderable, ok := g.game.ECS.Renderables[selectedID]; ok {
				radius = renderable.Radius * float32(config.CoordScale) * 1.6
			}
			found = true
		}

		if found {
			highlightPos := rl.NewVector3(worldPos.X, 0.5, worldPos.Z)
			fillColor := rl.NewColor(255, 255, 224, 100)
			rl.DrawCylinder(highlightPos, radius, radius, 0.2, 12, fillColor)
			rl.DrawCylinderWires(highlightPos, radius, radius, 0.2, 12, config.HighlightColorRL)
		}
	}

	rl.DrawRenderBatchActive()
	rl.DisableDepthTest()

	for i, checkpoint := range g.hexMap.Checkpoints {
		if tex, ok := g.checkpointTextures[i]; ok {
			px, py := checkpoint.ToPixel(config.HexSize)
			worldPos := rl.NewVector3(float32(px*config.CoordScale), 5.0, float32(py*config.CoordScale))
			camMatrix := rl.GetCameraMatrix(*g.camera)
			camRight := rl.NewVector3(camMatrix.M0, camMatrix.M4, camMatrix.M8)
			camUp := rl.NewVector3(camMatrix.M1, camMatrix.M5, camMatrix.M9)
			aspectRatio := float32(tex.Width) / float32(tex.Height)
			height := float32(9.0)
			width := height * aspectRatio
			v1 := rl.Vector3Add(worldPos, rl.Vector3Add(rl.Vector3Scale(camRight, -width/2), rl.Vector3Scale(camUp, -height/2)))
			v2 := rl.Vector3Add(worldPos, rl.Vector3Add(rl.Vector3Scale(camRight, width/2), rl.Vector3Scale(camUp, -height/2)))
			v3 := rl.Vector3Add(worldPos, rl.Vector3Add(rl.Vector3Scale(camRight, width/2), rl.Vector3Scale(camUp, height/2)))
			v4 := rl.Vector3Add(worldPos, rl.Vector3Add(rl.Vector3Scale(camRight, -width/2), rl.Vector3Scale(camUp, height/2)))
			rl.SetTexture(tex.ID)
			rl.Begin(rl.Quads)
			rl.Color4ub(config.GridColorRL.R, config.GridColorRL.G, config.GridColorRL.B, config.GridColorRL.A)
			rl.TexCoord2f(0.0, 1.0)
			rl.Vertex3f(v1.X, v1.Y, v1.Z)
			rl.TexCoord2f(1.0, 1.0)
			rl.Vertex3f(v2.X, v2.Y, v2.Z)
			rl.TexCoord2f(1.0, 0.0)
			rl.Vertex3f(v3.X, v3.Y, v3.Z)
			rl.TexCoord2f(0.0, 0.0)
			rl.Vertex3f(v4.X, v4.Y, v4.Z)
			rl.End()
			rl.SetTexture(0)
		}
	}
	rl.DrawRenderBatchActive()
	rl.EnableDepthTest()

	rl.DrawRenderBatchActive()
	rl.DisableDepthTest()
	g.game.RenderSystem.DrawProjectiles()
	rl.DrawRenderBatchActive()
	rl.EnableDepthTest()
}

// DrawUI рисует все элементы интерфейса в 2D
func (g *GameState) DrawUI() {
	// Сначала рисуем основной UI
	var stateColor rl.Color
	switch g.game.ECS.GameState.Phase {
	case component.BuildState:
		stateColor = config.BuildStateColor
	case component.WaveState:
		stateColor = config.WaveStateColor
	case component.TowerSelectionState:
		stateColor = config.SelectionStateColor
	}
	g.indicator.Draw(stateColor)

	g.game.SpeedButton.Draw()
	g.game.PauseButton.Draw()
	g.infoPanel.Draw(g.game.ECS)

	if playerState, ok := g.game.ECS.PlayerState[g.game.PlayerID]; ok {
		g.playerLevelIndicator.Draw(playerState.Level, playerState.CurrentXP, playerState.XPToNextLevel)
		g.playerHealthIndicator.Draw(playerState.Health, 20)
	}

	g.waveIndicator.Draw(g.game.Wave, g.font)

	if g.recipeBook.IsVisible {
		availableTowers := make(map[string]int)
		for _, tower := range g.game.ECS.Towers {
			availableTowers[tower.DefID]++
		}
		g.recipeBook.Draw(availableTowers)
	}

	if g.game.ECS.GameState.Phase == component.BuildState || g.game.ECS.GameState.Phase == component.TowerSelectionState {
		g.uIndicator.Draw(g.game.IsInLineDragMode())
	}

	// Отрисовка индикатора состояния жил
	percentages := g.game.GetOreSectorPercentages()
	g.oreSectorIndicator.Draw(percentages[0], percentages[1], percentages[2])

	// Если игра окончена, рисуем оверлей
	if g.isGameOver {
		rl.DrawRectangle(0, 0, int32(config.ScreenWidth), int32(config.ScreenHeight), rl.NewColor(0, 0, 0, 180))
		
		// Текст "Вы проиграли!"
		gameOverText := "Вы проиграли!"
		textSize := int32(60)
		textWidth := rl.MeasureTextEx(g.font, gameOverText, float32(textSize), 1).X
		rl.DrawTextEx(g.font, gameOverText, rl.NewVector2((float32(config.ScreenWidth)-textWidth)/2, float32(config.ScreenHeight)/2-80), float32(textSize), 1, rl.White)

		// Кнопка "Рестарт"
		rl.DrawRectangleRec(g.restartButton, rl.Gray)
		rl.DrawRectangleLinesEx(g.restartButton, 2, rl.LightGray)
		restartText := "Рестарт"
		restartTextSize := int32(30)
		restartTextWidth := rl.MeasureTextEx(g.font, restartText, float32(restartTextSize), 1).X
		rl.DrawTextEx(
			g.font,
			restartText,
			rl.NewVector2(
				g.restartButton.X+(g.restartButton.Width-restartTextWidth)/2,
				g.restartButton.Y+(g.restartButton.Height-float32(restartTextSize))/2,
			),
			float32(restartTextSize),
			1,
			rl.Black,
		)
	}
}

func (g *GameState) Exit() {}

// Cleanup освобождает ресурсы, используемые состоянием
func (g *GameState) Cleanup() {
	g.renderer.Cleanup()
	for _, tex := range g.checkpointTextures {
		rl.UnloadTexture(tex)
	}
}

// GetGame возвращает текущий экземпляр игры.
// Возвращаем GameInterface, чтобы соответствовать интерфейсу State.
func (g *GameState) GetGame() GameInterface {
	return g.game
}

// GetFont возвращает шрифт, используемый в состоянии
func (g *GameState) GetFont() rl.Font {
	return g.font
}
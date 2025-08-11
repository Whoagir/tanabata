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

// GameState — состояние игры
type GameState struct {
	sm                   *StateMachine
	game                 *app.Game
	hexMap               *hexmap.HexMap
	renderer             *render.HexRenderer
	indicator            *ui.StateIndicatorRL
	playerLevelIndicator *ui.PlayerLevelIndicatorRL
	infoPanel            *ui.InfoPanelRL
	recipeBook           *ui.RecipeBookRL
	uIndicator           *ui.UIndicatorRL
	waveIndicator        *ui.WaveIndicator // Добавлено
	lastClickTime        time.Time
	camera               *rl.Camera3D
	font                 rl.Font
	checkpointTextures   map[int]rl.Texture2D // Текстуры для номеров чекпоинтов
}

// intToRoman конв��ртирует целое число в римскую цифру (для чисел от 1 до 10)
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

	// --- Расчет позиций и размеров для UI ---
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
		float32(config.IndicatorOffsetX+35), // Смещаем ниже кнопок
		levelIndicatorWidth,
	)
	infoPanel := ui.NewInfoPanelRL(font, gameLogic.EventDispatcher)

	recipeBookWidth := float32(400)
	recipeBookHeight := float32(600)
	recipeBookX := (float32(config.ScreenWidth) - recipeBookWidth) / 2
	recipeBookY := (float32(config.ScreenHeight) - recipeBookHeight) / 2
	recipeBook := ui.NewRecipeBookRL(recipeBookX, recipeBookY, recipeBookWidth, recipeBookHeight, recipeLibrary.Recipes, font)

	waveIndicatorY := playerLevelIndicator.Y + 44 // Располагаем ниже индикатора уровня
	waveIndicator := ui.NewWaveIndicator(
		levelIndicatorLeftEdge+levelIndicatorWidth/2, // Центрируем по горизонтали
		waveIndicatorY,
		28, // Размер шрифта
	)

	uIndicator := ui.NewUIndicatorRL(
		float32(config.IndicatorOffsetX),
		float32(config.IndicatorOffsetX),
		40, // Размер шрифта для "U"
		font,
	)

	// --- Генерация текстур для чекпоинтов ---
	checkpointTextures := make(map[int]rl.Texture2D)
	for i := 0; i < len(hexMap.Checkpoints); i++ {
		romanNumeral := intToRoman(i + 1)
		img := rl.ImageTextEx(font, romanNumeral, 64, 1, rl.White)
		tex := rl.LoadTextureFromImage(img)
		rl.SetTextureFilter(tex, rl.FilterPoint) // Используем точечную фильтрацию для четкости
		checkpointTextures[i] = tex
		rl.UnloadImage(img) // Освобождаем память CPU
	}

	gs := &GameState{
		sm:                   sm,
		game:                 gameLogic,
		hexMap:               hexMap,
		renderer:             renderer,
		indicator:            indicator,
		playerLevelIndicator: playerLevelIndicator,
		infoPanel:            infoPanel,
		recipeBook:           recipeBook,
		uIndicator:           uIndicator,
		waveIndicator:        waveIndicator, // Добавлено
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
		// Добавляем управление зумом для ортографической камеры
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
		// Сбрасываем зум в зависимости от текущего режима
		if g.camera.Projection == rl.CameraPerspective {
			g.camera.Fovy = config.CameraFovyDefault
		} else {
			g.camera.Fovy = config.CameraOrthoFovyDefault
		}
	}

	// Переключение режима проекции камеры
	if rl.IsKeyPressed(rl.KeyP) {
		if g.camera.Projection == rl.CameraPerspective {
			g.camera.Projection = rl.CameraOrthographic
			g.camera.Fovy = config.CameraOrthoFovyDefault // Устанавливаем "зум" для ортографического вида
		} else {
			g.camera.Projection = rl.CameraPerspective
			g.camera.Fovy = config.CameraFovyDefault // Возвращаем стандартный "зум" для перспективы
		}
	}

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
		g.game.HandlePauseClick()
		g.sm.SetState(NewPauseState(g.sm, g, g.font))
		return
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
	// Рассчитываем пересечение с плоскостью y=0
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
		g.sm.SetState(NewPauseState(g.sm, g, g.font)) // Переключаемся в состояние паузы
	} else if g.indicator.IsClicked(mousePos) {
		g.indicator.HandleClick()
		g.game.HandleIndicatorClick()
	}
}

func (g *GameState) findEntityAtCursor(ray rl.Ray) (types.EntityID, bool) {
	// Шаг 1: Проверка башен (быстрая, на основе гексов)
	hex := g.getHexUnderCursor(ray)
	for id, t := range g.game.ECS.Towers {
		if t.Hex == hex {
			return id, true
		}
	}

	// Шаг 2: Проверка врагов (медленная, на основе столкновений луча со сферой)
	var closestEntity types.EntityID
	closestDistance := float32(-1.0)
	found := false

	for id := range g.game.ECS.Enemies {
		if pos, ok := g.game.ECS.Positions[id]; ok {
			if renderable, okRender := g.game.ECS.Renderables[id]; okRender {
				// Определяем Bounding Sphere для врага, точно как в RenderSystem
				scaledRadius := renderable.Radius * float32(config.CoordScale)
				enemyPosition := rl.NewVector3(float32(pos.X*config.CoordScale), scaledRadius, float32(pos.Y*config.CoordScale))

				// Проверяем столкновение
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

	// Ничего не найдено
	return 0, false
}

func (g *GameState) handleGameClick(button rl.MouseButton) {
	ray := rl.GetMouseRay(rl.GetMousePosition(), *g.camera)
	hex := g.getHexUnderCursor(ray)
	hitPoint, hasHit := g.getHitPointUnderCursor(ray)

	if button == rl.MouseLeftButton {
		entityID, entityFound := g.findEntityAtCursor(ray)
		if entityFound {
			// Проверяем, является ли сущность врагом, чтобы не сбрасывать выделение башни
			if _, isEnemy := g.game.ECS.Enemies[entityID]; isEnemy {
				g.infoPanel.SetTarget(entityID)
				// Не сбрасываем выделение башни, если кликнули на врага
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
		// Если мы в режиме перетаскивания и кликнули вне карты, отменяем его
		if g.game.IsInLineDragMode() {
			g.game.CancelLineDrag()
		}
		return
	}

	if g.game.IsInLineDragMode() {
		if button == rl.MouseLeftButton && hasHit {
			g.game.HandleLineDragClick(hex, hitPoint)
		} else if button == rl.MouseRightButton {
			// Отмена перетаскивания по правому клику
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
	// Шаг 1: Отрисовка основной сцены (земля, башни, враги, эффекты)
	g.renderer.Draw()
	g.game.RenderSystem.Draw(g.game.GetGameTime(), g.game.IsInLineDragMode(), g.game.GetDragSourceTowerID(), g.game.GetHiddenLineID(), g.game.ECS.GameState.Phase, g.game.CancelLineDrag, g.game.ClearedCheckpoints)

	// Шаг 2: Отрисовка выделения для выбранной сущности
	selectedID := g.infoPanel.TargetEntity
	if selectedID != 0 {
		var worldPos rl.Vector3
		var radius float32
		var found bool

		if tower, ok := g.game.ECS.Towers[selectedID]; ok {
			x, y := tower.Hex.ToPixel(config.HexSize)
			worldPos = rl.NewVector3(float32(x*config.CoordScale), 0, float32(y*config.CoordScale))
			if renderable, ok := g.game.ECS.Renderables[selectedID]; ok {
				radius = renderable.Radius * float32(config.CoordScale) * 2.0 // Делаем круг выделения чуть больше
			} else {
				radius = float32(config.HexSize*config.CoordScale) * 1.35
			}
			found = true
		} else if pos, ok := g.game.ECS.Positions[selectedID]; ok {
			// Это для ��рагов, если мы решим их тоже выделять кругом
			worldPos = rl.NewVector3(float32(pos.X*config.CoordScale), 0, float32(pos.Y*config.CoordScale))
			if renderable, ok := g.game.ECS.Renderables[selectedID]; ok {
				radius = renderable.Radius * float32(config.CoordScale) * 1.6 // Чуть больше радиуса врага
			}
			found = true
		}

		if found {
			highlightPos := rl.NewVector3(worldPos.X, 0.5, worldPos.Z)
			fillColor := rl.NewColor(255, 255, 224, 100) // Полупрозрачный светло-желтый

			// Рисуем заливку
			rl.DrawCylinder(highlightPos, radius, radius, 0.2, 12, fillColor)
			// Рисуем обводку
			rl.DrawCylinderWires(highlightPos, radius, radius, 0.2, 12, config.HighlightColorRL)
		}
	}

	// Шаг 3: Отрисовка номеров чекпоинтов как сферических билбордов
	rl.DrawRenderBatchActive() // Принудительно отрисовываем все, что было до этого
	rl.DisableDepthTest()      // Отключаем тест глубины, чтобы номера были видны сквозь другие объекты

	for i, checkpoint := range g.hexMap.Checkpoints {
		if tex, ok := g.checkpointTextures[i]; ok {
			px, py := checkpoint.ToPixel(config.HexSize)
			worldPos := rl.NewVector3(float32(px*config.CoordScale), 5.0, float32(py*config.CoordScale))
			
			// Ручная отрисовка сферического билборда с учетом соотношения сторон
			camMatrix := rl.GetCameraMatrix(*g.camera)
			
			// Векторы камеры в мировом пространстве
			camRight := rl.NewVector3(camMatrix.M0, camMatrix.M4, camMatrix.M8)
			camUp := rl.NewVector3(camMatrix.M1, camMatrix.M5, camMatrix.M9)

			// Сохраняем соотношение сторон текстуры
			aspectRatio := float32(tex.Width) / float32(tex.Height)
			height := float32(9.0) // Уменьшили на 10%
			width := height * aspectRatio
			
			// Вычисляем 4 угла квада
			v1 := rl.Vector3Add(worldPos, rl.Vector3Add(rl.Vector3Scale(camRight, -width/2), rl.Vector3Scale(camUp, -height/2))) // Bottom-Left
			v2 := rl.Vector3Add(worldPos, rl.Vector3Add(rl.Vector3Scale(camRight, width/2), rl.Vector3Scale(camUp, -height/2)))  // Bottom-Right
			v3 := rl.Vector3Add(worldPos, rl.Vector3Add(rl.Vector3Scale(camRight, width/2), rl.Vector3Scale(camUp, height/2)))   // Top-Right
			v4 := rl.Vector3Add(worldPos, rl.Vector3Add(rl.Vector3Scale(camRight, -width/2), rl.Vector3Scale(camUp, height/2)))  // Top-Left

			rl.SetTexture(tex.ID)
			rl.Begin(rl.Quads)
			
			rl.Color4ub(config.GridColorRL.R, config.GridColorRL.G, config.GridColorRL.B, config.GridColorRL.A)

			// Bottom-left corner for texture and quad
			rl.TexCoord2f(0.0, 1.0)
			rl.Vertex3f(v1.X, v1.Y, v1.Z)

			// Bottom-right corner for texture and quad
			rl.TexCoord2f(1.0, 1.0)
			rl.Vertex3f(v2.X, v2.Y, v2.Z)

			// Top-right corner for texture and quad
			rl.TexCoord2f(1.0, 0.0)
			rl.Vertex3f(v3.X, v3.Y, v3.Z)

			// Top-left corner for texture and quad
			rl.TexCoord2f(0.0, 0.0)
			rl.Vertex3f(v4.X, v4.Y, v4.Z)
			
			rl.End()
			rl.SetTexture(0)
		}
	}
	rl.DrawRenderBatchActive() // Завершаем ручную отрисовку
	rl.EnableDepthTest()       // Включаем тест глубины обратно

	// --- Финальный рендеринг снарядов ---
	rl.DrawRenderBatchActive()
	rl.DisableDepthTest()
	g.game.RenderSystem.DrawProjectiles()
	rl.DrawRenderBatchActive()
	rl.EnableDepthTest()
}

// DrawUI рисует все элементы интерфейса в 2D
func (g *GameState) DrawUI() {
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
	}

	// Отрисовка номера волны
	g.waveIndicator.Draw(g.game.Wave, g.font)

	if g.recipeBook.IsVisible {
		availableTowers := make(map[string]int)
		for _, tower := range g.game.ECS.Towers {
			availableTowers[tower.DefID]++
		}
		g.recipeBook.Draw(availableTowers)
	}

	// Отрисовка индикатора режима "U"
	if g.game.ECS.GameState.Phase == component.BuildState || g.game.ECS.GameState.Phase == component.TowerSelectionState {
		g.uIndicator.Draw(g.game.IsInLineDragMode())
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

// GetGame возвращает текущий экземпляр игры
func (g *GameState) GetGame() *app.Game {
	return g.game
}

// GetFont возвращает шрифт, используемый в состоянии
func (g *GameState) GetFont() rl.Font {
	return g.font
}

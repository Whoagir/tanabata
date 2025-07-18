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
	"image/color"
	"math"
	"time"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/ebitenutil"
	"github.com/hajimehoshi/ebiten/v2/inpututil"
)

// GameState — состояние игры
type GameState struct {
	sm             *StateMachine
	game           *game.Game
	hexMap         *hexmap.HexMap
	renderer       *render.HexRenderer
	indicator      *ui.StateIndicator
	infoPanel      *ui.InfoPanel // <-- Новая панель
	lastClickTime  time.Time
	lastUpdateTime time.Time
}

func NewGameState(sm *StateMachine) *GameState {
	hexMap := hexmap.NewHexMap()
	gameLogic := game.NewGame(hexMap)

	// Создаем и заполняем структуру с цветами для рендерера
	mapColors := &render.MapColors{
		BackgroundColor:      config.BackgroundColor,
		PassableColor:        config.PassableColor,
		ImpassableColor:      config.ImpassableColor,
		EntryColor:           config.EntryColor,
		ExitColor:            config.ExitColor,
		TextDarkColor:        config.TextDarkColor,
		TextLightColor:       config.TextLightColor,
		CheckpointTextColor:  color.RGBA{255, 255, 0, 255}, // Example, can be moved to config
		StrokeWidth:          float32(config.StrokeWidth),
	}

	// Передаем актуальные данные о руде и цвета в рендерер
	offsetX := float64(config.ScreenWidth) / 2
	offsetY := float64(config.ScreenHeight)/2 + config.MapCenterOffsetY
	renderer := render.NewHexRenderer(hexMap, gameLogic.GetOreHexes(), config.HexSize, offsetX, offsetY, config.ScreenWidth, config.ScreenHeight, gameLogic.FontFace, mapColors)
	renderer.RenderMapImage(gameLogic.GetAllTowerHexes()) // <-- Явный вызов отрисовки карты

	indicator := ui.NewStateIndicator(
		float32(config.ScreenWidth-config.IndicatorOffsetX),
		float32(config.IndicatorOffsetX),
		float32(config.IndicatorRadius),
	)
	// Создаем панель
	infoPanel := ui.NewInfoPanel(gameLogic.FontFace, gameLogic.FontFace) // Используем один и тот же шрифт

	gs := &GameState{
		sm:             sm,
		game:           gameLogic,
		hexMap:         hexMap,
		renderer:       renderer,
		indicator:      indicator,
		infoPanel:      infoPanel, // <-- Инициализация
		lastClickTime:  time.Now(),
		lastUpdateTime: time.Now(),
	}

	return gs
}

func (g *GameState) Enter() {
	// Ничего не делаем при входе
}

func (g *GameState) Update(deltaTime float64) {
	g.game.PauseButton.SetPaused(false)
	g.infoPanel.Update() // Обновляем панель

	if inpututil.IsKeyJustPressed(ebiten.KeyF9) {
		g.sm.SetState(NewPauseState(g.sm, g))
		return
	}

	// --- Новая логика для режима перетаскивания ---
	if g.game.ECS.GameState.Phase == component.BuildState && inpututil.IsKeyJustPressed(ebiten.KeyU) {
		g.game.ToggleLineDragMode()
	}
	// --- Конец новой логики ---

	// Handle debug tower selection
	if g.game.ECS.GameState.Phase == component.BuildState {
		if inpututil.IsKeyJustPressed(ebiten.Key1) {
			g.game.DebugTowerType = config.TowerTypePhysical // Represents any random attacker
		}
		if inpututil.IsKeyJustPressed(ebiten.Key2) {
			g.game.DebugTowerType = config.TowerTypeMiner
		}
		if inpututil.IsKeyJustPressed(ebiten.Key3) {
			g.game.DebugTowerType = config.TowerTypeWall
		}
	}

	g.game.Update(deltaTime)

	// Обработка ле��ой кнопки
	if inpututil.IsMouseButtonJustPressed(ebiten.MouseButtonLeft) {
		x, y := ebiten.CursorPosition()
		// Проверяем клик по UI элементам в первую очередь
		if g.isClickOnUI(x, y) {
			g.handleUIClick(x, y)
		} else {
			// Если не по UI, то это игровой клик
			g.handleGameClick(x, y, ebiten.MouseButtonLeft)
		}
		g.lastClickTime = time.Now()
	}

	// Обработка правой кнопки
	if inpututil.IsMouseButtonJustPressed(ebiten.MouseButtonRight) {
		x, y := ebiten.CursorPosition()
		// Правый клик всегда игровой (например, для отмены или удаления)
		g.handleGameClick(x, y, ebiten.MouseButtonRight)
		g.lastClickTime = time.Now()
	}
}

// isClickOnUI ��роверяет, был ли клик по какому-либо элементу UI
func (g *GameState) isClickOnUI(x, y int) bool {
	mx, my := float32(x), float32(y)
	if g.isInsideSpeedButton(mx, my) {
		return true
	}
	if g.isInsidePauseButton(mx, my) {
		return true
	}
	indicatorX, indicatorY, indicatorR := float64(g.indicator.X), float64(g.indicator.Y), float64(g.indicator.Radius)
	if (float64(x)-indicatorX)*(float64(x)-indicatorX)+(float64(y)-indicatorY)*(float64(y)-indicatorY) <= indicatorR*indicatorR {
		return true
	}
	// Проверяем, видим ли мы панель и находится ли клик внутри нее
	if g.infoPanel.IsVisible && y > (config.ScreenHeight-150) { // 150 - высота панели
		return true
	}
	return false
}

// handleUIClick обрабатывает клики, которые точно попали в UI
func (g *GameState) handleUIClick(x, y int) {
	mx, my := float32(x), float32(y)
	if g.isInsideSpeedButton(mx, my) {
		if time.Since(g.game.SpeedButton.LastToggleTime) >= time.Duration(config.ClickCooldown)*time.Millisecond {
			g.game.HandleSpeedClick()
		}
	} else if g.isInsidePauseButton(mx, my) {
		if time.Since(g.game.PauseButton.LastToggleTime) >= time.Duration(config.ClickCooldown)*time.Millisecond {
			g.handlePauseClick()
		}
	} else {
		indicatorX, indicatorY, indicatorR := float64(g.indicator.X), float64(g.indicator.Y), float64(g.indicator.Radius)
		if (float64(x)-indicatorX)*(float64(x)-indicatorX)+(float64(y)-indicatorY)*(float64(y)-indicatorY) <= indicatorR*indicatorR {
			if time.Since(g.indicator.LastClickTime) >= time.Duration(config.ClickCooldown)*time.Millisecond {
				g.game.HandleIndicatorClick()
				g.indicator.LastClickTime = time.Now()
			}
		}
	}
	// Клик по инфо-панели обрабатывается внутри самой панели (в будущем)
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

// findEntityAt a helper function to find an entity at a given screen coordinate.
func (g *GameState) findEntityAt(x, y int) (types.EntityID, bool) {
	// Проверяем башни
	for id, pos := range g.game.ECS.Positions {
		if _, isTower := g.game.ECS.Towers[id]; isTower {
			dist := math.Hypot(pos.X-float64(x), pos.Y-float64(y))
			if dist < config.HexSize*0.5 { // Примерный радиус клика
				return id, true
			}
		}
	}
	// Проверяем врагов
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
	// --- Логика выбора сущности ---
	if button == ebiten.MouseButtonLeft {
		if entityID, found := g.findEntityAt(x, y); found {
			g.infoPanel.SetTarget(entityID)
			return // Клик был по сущности, выходим
		} else {
			g.infoPanel.Hide() // Клик по пустой местности, скрываем панель
		}
	}

	// --- Основная игровая логика клика ---
	hex := utils.ScreenToHex(float64(x), float64(y))
	if !g.hexMap.Contains(hex) {
		return // Клик вне карты
	}

	// Если мы в режиме перетаскивания линии
	if g.game.IsInLineDragMode() {
		if button == ebiten.MouseButtonLeft {
			g.game.HandleLineDragClick(hex, x, y)
		}
		return
	}

	// Стандартная логика для фазы строительства
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
		stateColor = config.SelectionStateColor // Новый цвет
	}
	g.indicator.Draw(screen, stateColor)
	g.game.SpeedButton.Draw(screen)
	g.game.PauseButton.Draw(screen)
	g.infoPanel.Draw(screen, g.game.ECS) // <-- Рисуем панель

	// Debug text
	ebitenutil.DebugPrint(screen, fmt.Sprintf("Wave: %d", g.game.Wave))
}

func (g *GameState) Exit() {
	// Ничего не делаем при выходе
}

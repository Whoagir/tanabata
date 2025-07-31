// internal/ui/info_panel.go
package ui

import (
	"fmt"
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/event"
	"go-tower-defense/internal/types"
	"image"
	"image/color"
	"log"
	"math"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/inpututil"
	"github.com/hajimehoshi/ebiten/v2/text"
	"github.com/hajimehoshi/ebiten/v2/vector"
	"golang.org/x/image/font"
)

const (
	panelHeight     = 150
	panelMargin     = 5
	animationSpeed  = 10.0
	lineHeight      = 20
	columnSpacing   = 200
	titleFontSize   = 18
	regularFontSize = 14
)

// Button представляет кликабельную кнопку в UI.
type Button struct {
	Rect image.Rectangle
	Text string
}

// InfoPanel displays information about a selected entity.
type InfoPanel struct {
	IsVisible       bool
	TargetEntity    types.EntityID
	fontFace        font.Face
	titleFontFace   font.Face
	currentY        float64
	targetY         float64
	SelectButton    Button
	CombineButton   Button
	eventDispatcher *event.Dispatcher
}

// NewInfoPanel creates a new information panel.
func NewInfoPanel(font font.Face, titleFont font.Face, dispatcher *event.Dispatcher) *InfoPanel {
	return &InfoPanel{
		IsVisible:       false,
		fontFace:        font,
		titleFontFace:   titleFont,
		currentY:        config.ScreenHeight,
		targetY:         config.ScreenHeight,
		eventDispatcher: dispatcher,
	}
}

func (p *InfoPanel) SetTarget(entityID types.EntityID) {
	p.TargetEntity = entityID
	p.IsVisible = true
	p.targetY = config.ScreenHeight - panelHeight
}

func (p *InfoPanel) Hide() {
	p.targetY = config.ScreenHeight
}

func (p *InfoPanel) Update(ecs *entity.ECS) {
	// Анимация панели
	if p.currentY != p.targetY {
		diff := p.targetY - p.currentY
		if math.Abs(diff) < animationSpeed {
			p.currentY = p.targetY
		} else if diff > 0 {
			p.currentY += animationSpeed
		} else {
			p.currentY -= animationSpeed
		}

		if p.currentY >= config.ScreenHeight {
			p.IsVisible = false
			p.TargetEntity = 0
		}
	}

	// Обработка кликов по кнопкам
	if p.IsVisible && inpututil.IsMouseButtonJustPressed(ebiten.MouseButtonLeft) {
		cursorX, cursorY := ebiten.CursorPosition()
		clickPoint := image.Point{X: cursorX, Y: cursorY}

		// Клик по кнопке выбора
		if clickPoint.In(p.SelectButton.Rect) {
			p.handleSelectClick(ecs)
		}

		// Клик по кнопке объединения
		if clickPoint.In(p.CombineButton.Rect) {
			p.handleCombineClick(ecs)
		}
	}
}

func (p *InfoPanel) handleCombineClick(ecs *entity.ECS) {
	if _, ok := ecs.Combinables[p.TargetEntity]; ok {
		p.eventDispatcher.Dispatch(event.Event{
			Type: event.CombineTowersRequest,
			Data: p.TargetEntity,
		})
		log.Printf("CombineTowersRequest event dispatched for entity %d", p.TargetEntity)
		p.Hide() // Скрываем панель после клика
	}
}

func (p *InfoPanel) handleSelectClick(ecs *entity.ECS) {
	if tower, ok := ecs.Towers[p.TargetEntity]; ok {
		if towerDef, ok := defs.TowerLibrary[tower.DefID]; ok {
			// Можно выбирать только временные атакующие башни
			if tower.IsTemporary && towerDef.Type != defs.TowerTypeMiner {
				// Отправляем событие, вместо прямого изменения состояния
				p.eventDispatcher.Dispatch(event.Event{
					Type: event.ToggleTowerSelectionForSaveRequest,
					Data: p.TargetEntity,
				})
			}
		}
	}
}

func (p *InfoPanel) Draw(screen *ebiten.Image, ecs *entity.ECS) {
	if !p.IsVisible && p.currentY >= config.ScreenHeight {
		return
	}

	panelRect := image.Rect(
		panelMargin,
		int(p.currentY)+panelMargin,
		config.ScreenWidth-panelMargin,
		int(p.currentY)+panelHeight-panelMargin,
	)

	bgColor := color.RGBA{R: 25, G: 35, B: 45, A: 230}
	vector.DrawFilledRect(screen, float32(panelRect.Min.X), float32(panelRect.Min.Y), float32(panelRect.Dx()), float32(panelRect.Dy()), bgColor, true)
	borderColor := color.RGBA{R: 70, G: 130, B: 180, A: 255}
	vector.StrokeRect(screen, float32(panelRect.Min.X), float32(panelRect.Min.Y), float32(panelRect.Dx()), float32(panelRect.Dy()), 2, borderColor, true)

	if p.TargetEntity == 0 {
		return
	}

	p.drawEntityInfo(screen, ecs, panelRect.Min.X+15, panelRect.Min.Y+15)

	// Рисуем кнопки в зависимости от состояния игры
	if ecs.GameState.Phase == component.TowerSelectionState {
		if tower, ok := ecs.Towers[p.TargetEntity]; ok {
			if towerDef, ok := defs.TowerLibrary[tower.DefID]; ok && tower.IsTemporary && towerDef.Type != defs.TowerTypeMiner {
				p.drawSelectButton(screen, panelRect, tower.IsSelected)
			}
		}
	} else if ecs.GameState.Phase == component.WaveState {
		if _, ok := ecs.Combinables[p.TargetEntity]; ok {
			p.drawCombineButton(screen, panelRect)
		}
	}
}

func (p *InfoPanel) drawCombineButton(screen *ebiten.Image, panelRect image.Rectangle) {
	btnWidth := 150
	btnHeight := 40
	// Смещаем кнопку "Объединить" влево, чтобы она не перекрывала другие кнопки
	p.CombineButton.Rect = image.Rect(
		panelRect.Max.X-btnWidth*2-40,
		panelRect.Max.Y-btnHeight-20,
		panelRect.Max.X-btnWidth-40,
		panelRect.Max.Y-20,
	)
	p.CombineButton.Text = "Объединить"

	btnColor := color.RGBA{R: 180, G: 140, B: 20, A: 255} // Золотой цвет
	vector.DrawFilledRect(screen, float32(p.CombineButton.Rect.Min.X), float32(p.CombineButton.Rect.Min.Y), float32(btnWidth), float32(btnHeight), btnColor, true)

	textBounds := text.BoundString(p.fontFace, p.CombineButton.Text)
	textX := p.CombineButton.Rect.Min.X + (btnWidth-textBounds.Dx())/2
	textY := p.CombineButton.Rect.Min.Y + (btnHeight-textBounds.Dy())/2 - textBounds.Min.Y
	text.Draw(screen, p.CombineButton.Text, p.fontFace, textX, textY, color.White)
}

func (p *InfoPanel) drawSelectButton(screen *ebiten.Image, panelRect image.Rectangle, isSelected bool) {
	btnWidth := 150
	btnHeight := 40
	p.SelectButton.Rect = image.Rect(
		panelRect.Max.X-btnWidth-20,
		panelRect.Max.Y-btnHeight-20,
		panelRect.Max.X-20,
		panelRect.Max.Y-20,
	)

	btnColor := color.RGBA{R: 100, G: 60, B: 60, A: 255}
	p.SelectButton.Text = "Выбрать"
	if isSelected {
		btnColor = color.RGBA{R: 60, G: 120, B: 60, A: 255}
		p.SelectButton.Text = "Выбрано"
	}

	vector.DrawFilledRect(screen, float32(p.SelectButton.Rect.Min.X), float32(p.SelectButton.Rect.Min.Y), float32(btnWidth), float32(btnHeight), btnColor, true)

	textBounds := text.BoundString(p.fontFace, p.SelectButton.Text)
	textX := p.SelectButton.Rect.Min.X + (btnWidth-textBounds.Dx())/2
	textY := p.SelectButton.Rect.Min.Y + (btnHeight-textBounds.Dy())/2 - textBounds.Min.Y
	text.Draw(screen, p.SelectButton.Text, p.fontFace, textX, textY, color.White)
}

func (p *InfoPanel) drawEntityInfo(screen *ebiten.Image, ecs *entity.ECS, startX, startY int) {
	title := "Unknown Entity"
	yPos := startY + titleFontSize

	if tower, ok := ecs.Towers[p.TargetEntity]; ok {
		if towerDef, defOk := defs.TowerLibrary[tower.DefID]; defOk {
			title = towerDef.Name
			text.Draw(screen, title, p.titleFontFace, startX, yPos, config.TextLightColor)
			p.drawTowerInfo(screen, ecs, &towerDef, startX, yPos+lineHeight)
		}
	} else if enemy, ok := ecs.Enemies[p.TargetEntity]; ok {
		if enemyDef, defOk := defs.EnemyLibrary[enemy.DefID]; defOk {
			title = enemyDef.Name
			text.Draw(screen, title, p.titleFontFace, startX, yPos, config.TextLightColor)
			p.drawEnemyInfo(screen, ecs, &enemyDef, startX, yPos+lineHeight)
		}
	} else {
		text.Draw(screen, title, p.titleFontFace, startX, yPos, config.TextLightColor)
	}
}

func (p *InfoPanel) drawTowerInfo(screen *ebiten.Image, ecs *entity.ECS, towerDef *defs.TowerDefinition, startX, startY int) {
	y := startY
	if combat, ok := ecs.Combats[p.TargetEntity]; ok {
		if towerDef.Combat != nil {
			text.Draw(screen, fmt.Sprintf("Damage: %d", towerDef.Combat.Damage), p.fontFace, startX, y, config.TextLightColor)
			y += lineHeight
			text.Draw(screen, fmt.Sprintf("Fire Rate: %.2f/s", combat.FireRate), p.fontFace, startX, y, config.TextLightColor)
			y += lineHeight
			text.Draw(screen, fmt.Sprintf("Range: %d", combat.Range), p.fontFace, startX, y, config.TextLightColor)
			y += lineHeight
			text.Draw(screen, fmt.Sprintf("Damage Type: %s", towerDef.Combat.Attack.DamageType), p.fontFace, startX, y, config.TextLightColor)
		}
	}
}

func (p *InfoPanel) drawEnemyInfo(screen *ebiten.Image, ecs *entity.ECS, enemyDef *defs.EnemyDefinition, startX, startY int) {
	y := startY
	col1X := startX
	col2X := startX + columnSpacing

	// Health
	if health, ok := ecs.Healths[p.TargetEntity]; ok {
		healthStr := fmt.Sprintf("Health: %d / %d", health.Value, enemyDef.Health)
		text.Draw(screen, healthStr, p.fontFace, col1X, y, config.TextLightColor)
	}

	// Speed
	if velocity, ok := ecs.Velocities[p.TargetEntity]; ok {
		speedStr := fmt.Sprintf("Speed: %.2f", velocity.Speed)
		text.Draw(screen, speedStr, p.fontFace, col2X, y, config.TextLightColor)
	}
	y += lineHeight

	// Armor
	physArmorStr := fmt.Sprintf("Physical Armor: %d", enemyDef.PhysicalArmor)
	text.Draw(screen, physArmorStr, p.fontFace, col1X, y, config.TextLightColor)

	magArmorStr := fmt.Sprintf("Magical Armor: %d", enemyDef.MagicalArmor)
	text.Draw(screen, magArmorStr, p.fontFace, col2X, y, config.TextLightColor)
}

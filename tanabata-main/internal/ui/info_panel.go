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
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
)

const (
	panelHeightRL     = 150
	panelMarginRL     = 5
	animationSpeedRL  = 10.0
	lineHeightRL      = 20
	columnSpacingRL   = 200
	titleFontSizeRL   = 18
	regularFontSizeRL = 14
)

// ButtonRL представляет кликабельную кнопку в UI Raylib.
type ButtonRL struct {
	Rect rl.Rectangle
	Text string
}

// InfoPanelRL - версия InfoPanel для Raylib
type InfoPanelRL struct {
	IsVisible       bool
	TargetEntity    types.EntityID
	font            rl.Font
	currentY        float32
	targetY         float32
	SelectButton    ButtonRL
	CombineButton   ButtonRL
	eventDispatcher *event.Dispatcher
}

// NewInfoPanelRL создает новую информационную панель.
func NewInfoPanelRL(font rl.Font, dispatcher *event.Dispatcher) *InfoPanelRL {
	return &InfoPanelRL{
		IsVisible:       false,
		font:            font,
		currentY:        config.ScreenHeight,
		targetY:         config.ScreenHeight,
		eventDispatcher: dispatcher,
	}
}

func (p *InfoPanelRL) SetTarget(entityID types.EntityID) {
	p.TargetEntity = entityID
	p.IsVisible = true
	p.targetY = config.ScreenHeight - panelHeightRL
}

func (p *InfoPanelRL) Hide() {
	p.targetY = config.ScreenHeight
}

func (p *InfoPanelRL) Update(ecs *entity.ECS) {
	// Анимация панели
	if p.currentY != p.targetY {
		diff := p.targetY - p.currentY
		if float32(math.Abs(float64(diff))) < animationSpeedRL {
			p.currentY = p.targetY
		} else if diff > 0 {
			p.currentY += animationSpeedRL
		} else {
			p.currentY -= animationSpeedRL
		}

		if p.currentY >= config.ScreenHeight {
			p.IsVisible = false
			p.TargetEntity = 0
		}
	}

	// Обработка кликов по кнопкам
	if p.IsVisible && rl.IsMouseButtonPressed(rl.MouseLeftButton) {
		mousePos := rl.GetMousePosition()
		if rl.CheckCollisionPointRec(mousePos, p.SelectButton.Rect) {
			p.handleSelectClick(ecs)
		}
		if rl.CheckCollisionPointRec(mousePos, p.CombineButton.Rect) {
			p.handleCombineClick(ecs)
		}
	}
}

// IsClicked пров��ряет, был ли клик внутри одной из кнопок панели.
func (p *InfoPanelRL) IsClicked(mousePos rl.Vector2) bool {
	return rl.CheckCollisionPointRec(mousePos, p.SelectButton.Rect) ||
		rl.CheckCollisionPointRec(mousePos, p.CombineButton.Rect)
}

func (p *InfoPanelRL) handleCombineClick(ecs *entity.ECS) {
	if _, ok := ecs.Combinables[p.TargetEntity]; ok {
		p.eventDispatcher.Dispatch(event.Event{
			Type: event.CombineTowersRequest,
			Data: p.TargetEntity,
		})
		p.Hide()
	}
}

func (p *InfoPanelRL) handleSelectClick(ecs *entity.ECS) {
	if tower, ok := ecs.Towers[p.TargetEntity]; ok {
		if towerDef, ok := defs.TowerDefs[tower.DefID]; ok {
			if tower.IsTemporary && towerDef.Type != defs.TowerTypeMiner {
				p.eventDispatcher.Dispatch(event.Event{
					Type: event.ToggleTowerSelectionForSaveRequest,
					Data: p.TargetEntity,
				})
			}
		}
	}
}

func (p *InfoPanelRL) Draw(ecs *entity.ECS) {
	if !p.IsVisible && p.currentY >= config.ScreenHeight {
		return
	}

	panelRect := rl.NewRectangle(
		panelMarginRL,
		p.currentY+panelMarginRL,
		config.ScreenWidth-panelMarginRL*2,
		panelHeightRL-panelMarginRL*2,
	)

	rl.DrawRectangleRec(panelRect, config.InfoPanelBgColorRL)
	rl.DrawRectangleLinesEx(panelRect, 2, config.InfoPanelBorderColorRL)

	if p.TargetEntity == 0 {
		return
	}

	p.drawEntityInfo(ecs, panelRect.X+15, panelRect.Y+15)

	if ecs.GameState.Phase == component.TowerSelectionState {
		if tower, ok := ecs.Towers[p.TargetEntity]; ok {
			if towerDef, ok := defs.TowerDefs[tower.DefID]; ok && tower.IsTemporary && towerDef.Type != defs.TowerTypeMiner {
				p.drawSelectButton(panelRect, tower.IsSelected)
			}
		}
	} else if ecs.GameState.Phase == component.WaveState {
		if _, ok := ecs.Combinables[p.TargetEntity]; ok {
			p.drawCombineButton(panelRect)
		}
	}
}

func (p *InfoPanelRL) drawCombineButton(panelRect rl.Rectangle) {
	btnWidth := float32(150)
	btnHeight := float32(40)
	p.CombineButton.Rect = rl.NewRectangle(
		panelRect.X+panelRect.Width-btnWidth*2-40,
		panelRect.Y+panelRect.Height-btnHeight-20,
		btnWidth,
		btnHeight,
	)
	p.CombineButton.Text = "Объединить"

	rl.DrawRectangleRec(p.CombineButton.Rect, config.CombineButtonColorRL)
	textPos := rl.NewVector2(
		p.CombineButton.Rect.X+(p.CombineButton.Rect.Width-float32(rl.MeasureText(p.CombineButton.Text, regularFontSizeRL)))/2,
		p.CombineButton.Rect.Y+(p.CombineButton.Rect.Height-regularFontSizeRL)/2,
	)
	rl.DrawTextEx(p.font, p.CombineButton.Text, textPos, regularFontSizeRL, 1.0, rl.White)
}

func (p *InfoPanelRL) drawSelectButton(panelRect rl.Rectangle, isSelected bool) {
	btnWidth := float32(150)
	btnHeight := float32(40)
	p.SelectButton.Rect = rl.NewRectangle(
		panelRect.X+panelRect.Width-btnWidth-20,
		panelRect.Y+panelRect.Height-btnHeight-20,
		btnWidth,
		btnHeight,
	)

	btnColor := config.SelectButtonColorRL
	p.SelectButton.Text = "Выбрать"
	if isSelected {
		btnColor = config.SelectButtonActiveColorRL
		p.SelectButton.Text = "Выбрано"
	}

	rl.DrawRectangleRec(p.SelectButton.Rect, btnColor)
	textPos := rl.NewVector2(
		p.SelectButton.Rect.X+(p.SelectButton.Rect.Width-float32(rl.MeasureText(p.SelectButton.Text, regularFontSizeRL)))/2,
		p.SelectButton.Rect.Y+(p.SelectButton.Rect.Height-regularFontSizeRL)/2,
	)
	rl.DrawTextEx(p.font, p.SelectButton.Text, textPos, regularFontSizeRL, 1.0, rl.White)
}

func (p *InfoPanelRL) drawEntityInfo(ecs *entity.ECS, startX, startY float32) {
	title := "Unknown Entity"
	yPos := startY

	if tower, ok := ecs.Towers[p.TargetEntity]; ok {
		if towerDef, defOk := defs.TowerDefs[tower.DefID]; defOk {
			title = towerDef.Name
			rl.DrawTextEx(p.font, title, rl.NewVector2(startX, yPos), titleFontSizeRL, 1.0, config.TextLightColorRL)
			p.drawTowerInfo(ecs, &towerDef, startX, yPos+lineHeightRL)
		}
	} else if enemy, ok := ecs.Enemies[p.TargetEntity]; ok {
		if enemyDef, defOk := defs.EnemyDefs[enemy.DefID]; defOk {
			title = enemyDef.Name
			rl.DrawTextEx(p.font, title, rl.NewVector2(startX, yPos), titleFontSizeRL, 1.0, config.TextLightColorRL)
			p.drawEnemyInfo(ecs, &enemyDef, startX, yPos+lineHeightRL)
		}
	} else {
		rl.DrawTextEx(p.font, title, rl.NewVector2(startX, yPos), titleFontSizeRL, 1.0, config.TextLightColorRL)
	}
}

func (p *InfoPanelRL) drawTowerInfo(ecs *entity.ECS, towerDef *defs.TowerDefinition, startX, startY float32) {
	y := startY
	tower, _ := ecs.Towers[p.TargetEntity]

	rl.DrawTextEx(p.font, fmt.Sprintf("Level: %d", tower.Level), rl.NewVector2(startX, y), regularFontSizeRL, 1.0, config.TextLightColorRL)
	y += lineHeightRL

	if combat, ok := ecs.Combats[p.TargetEntity]; ok {
		if towerDef.Combat != nil {
			rl.DrawTextEx(p.font, fmt.Sprintf("Damage: %d", towerDef.Combat.Damage), rl.NewVector2(startX, y), regularFontSizeRL, 1.0, config.TextLightColorRL)
			y += lineHeightRL
			rl.DrawTextEx(p.font, fmt.Sprintf("Fire Rate: %.2f/s", combat.FireRate), rl.NewVector2(startX, y), regularFontSizeRL, 1.0, config.TextLightColorRL)
			y += lineHeightRL
			rl.DrawTextEx(p.font, fmt.Sprintf("Range: %d", combat.Range), rl.NewVector2(startX, y), regularFontSizeRL, 1.0, config.TextLightColorRL)
			y += lineHeightRL
			rl.DrawTextEx(p.font, fmt.Sprintf("Damage Type: %s", towerDef.Combat.Attack.DamageType), rl.NewVector2(startX, y), regularFontSizeRL, 1.0, config.TextLightColorRL)
		}
	}
}

func (p *InfoPanelRL) drawEnemyInfo(ecs *entity.ECS, enemyDef *defs.EnemyDefinition, startX, startY float32) {
	y := startY
	col1X := startX
	col2X := startX + columnSpacingRL

	if health, ok := ecs.Healths[p.TargetEntity]; ok {
		healthStr := fmt.Sprintf("Health: %d / %d", health.Value, enemyDef.Health)
		rl.DrawTextEx(p.font, healthStr, rl.NewVector2(col1X, y), regularFontSizeRL, 1.0, config.TextLightColorRL)
	}

	if velocity, ok := ecs.Velocities[p.TargetEntity]; ok {
		speedStr := fmt.Sprintf("Speed: %.2f", velocity.Speed)
		rl.DrawTextEx(p.font, speedStr, rl.NewVector2(col2X, y), regularFontSizeRL, 1.0, config.TextLightColorRL)
	}
	y += lineHeightRL

	physArmorStr := fmt.Sprintf("Physical Armor: %d", enemyDef.PhysicalArmor)
	rl.DrawTextEx(p.font, physArmorStr, rl.NewVector2(col1X, y), regularFontSizeRL, 1.0, config.TextLightColorRL)

	magArmorStr := fmt.Sprintf("Magical Armor: %d", enemyDef.MagicalArmor)
	rl.DrawTextEx(p.font, magArmorStr, rl.NewVector2(col2X, y), regularFontSizeRL, 1.0, config.TextLightColorRL)
}
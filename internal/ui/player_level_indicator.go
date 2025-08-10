// internal/ui/player_level_indicator.go
package ui

import (
	"go-tower-defense/internal/config"

	rl "github.com/gen2brain/raylib-go/raylib"
)

const (
	xpBarHeight     = 12
	levelRectHeight = 12
	levelRectGap    = 10
	maxPlayerLevel  = 5
)

// PlayerLevelIndicatorRL - новая версия индикатора уровня для Raylib
type PlayerLevelIndicatorRL struct {
	X, Y  float32
	Width float32
}

// NewPlayerLevelIndicatorRL создает новый индикатор уровня
func NewPlayerLevelIndicatorRL(x, y, width float32) *PlayerLevelIndicatorRL {
	return &PlayerLevelIndicatorRL{
		X:     x,
		Y:     y,
		Width: width,
	}
}

// Draw отрисовывает индикатор уровня и опыта
func (i *PlayerLevelIndicatorRL) Draw(level, currentXP, xpToNextLevel int) {
	// 1. Отрисовка полосы опыта
	// Фон
	rl.DrawRectangle(int32(i.X), int32(i.Y), int32(i.Width), xpBarHeight, config.XpBarBackgroundColorRL)

	// Заполнение
	progress := float32(0)
	if xpToNextLevel > 0 {
		progress = float32(currentXP) / float32(xpToNextLevel)
	}
	if progress > 1.0 {
		progress = 1.0
	}
	currentXpWidth := i.Width * progress
	if currentXpWidth > 0 {
		rl.DrawRectangle(int32(i.X), int32(i.Y), int32(currentXpWidth), xpBarHeight, config.XpBarForegroundColorRL)
	}

	// Обводка
	rl.DrawRectangleLinesEx(rl.NewRectangle(i.X, i.Y, i.Width, xpBarHeight), config.UIBorderWidth, config.UIBorderColor)

	// 2. Отрисовка квадратов уровней
	rectY := i.Y + xpBarHeight + 10
	
	// Общая ширина всех квадратов и промежутков
	totalRectsWidth := float32(maxPlayerLevel*levelRectHeight + (maxPlayerLevel-1)*levelRectGap)
	// Начальная позиция X для первого квадрата, чтобы вся группа была по центру
	startX := i.X + (i.Width-totalRectsWidth)/2

	for j := 0; j < maxPlayerLevel; j++ {
		rectX := startX + float32(j)*(levelRectHeight+levelRectGap)
		
		// Рисуем обводку квадрата
		rl.DrawRectangleLinesEx(rl.NewRectangle(rectX, rectY, levelRectHeight, levelRectHeight), config.UIBorderWidth, config.UIBorderColor)
		
		// Если уровень достигнут, рисуем заливку
		if j < level {
			rl.DrawRectangle(
				int32(rectX+config.UIBorderWidth),
				int32(rectY+config.UIBorderWidth),
				int32(levelRectHeight-config.UIBorderWidth*2),
				int32(levelRectHeight-config.UIBorderWidth*2),
				config.XpBarForegroundColorRL,
			)
		}
	}
}

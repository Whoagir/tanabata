// internal/ui/player_level_indicator.go
package ui

import (
	"go-tower-defense/internal/config"

	rl "github.com/gen2brain/raylib-go/raylib"
)

const (
	xpBarHeight     = 12
	levelRectHeight = 12
	levelRectWidth  = 14 // Делаем квадрат чуть шире для визуальной компенсации
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
		// Изменен цвет на синий
		rl.DrawRectangle(int32(i.X), int32(i.Y), int32(currentXpWidth), xpBarHeight, rl.Blue)
	}

	// Обводка
	rl.DrawRectangleLinesEx(rl.NewRectangle(i.X, i.Y, i.Width, xpBarHeight), config.UIBorderWidth, config.UIBorderColor)

	// 2. Отрисовка квадратов уровней
	rectY := i.Y + xpBarHeight + 10

	// Общая ширина всех квадратов и промежутков
	totalRectsWidth := float32(maxPlayerLevel*levelRectWidth + (maxPlayerLevel-1)*levelRectGap)
	// Начальная позиция X для первого квадрата, чтобы вся группа была по центру
	startX := i.X + (i.Width-totalRectsWidth)/2

	for j := 0; j < maxPlayerLevel; j++ {
		rectX := startX + float32(j)*(levelRectWidth+levelRectGap)

		// Если уровень достигнут, рисуем заливку ПОД обводкой
		if j < level {
			// Рисуем полный квадрат, чтобы толщина соответствовала полосе опыта
			rl.DrawRectangle(
				int32(rectX),
				int32(rectY),
				int32(levelRectWidth),
				int32(levelRectHeight),
				rl.Blue, // Используем тот же синий цвет
			)
		}

		// Рисуем обводку квадрата поверх всего, для всех квадратов
		rl.DrawRectangleLinesEx(rl.NewRectangle(rectX, rectY, levelRectWidth, levelRectHeight), config.UIBorderWidth, config.UIBorderColor)
	}
}

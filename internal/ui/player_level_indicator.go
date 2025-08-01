// internal/ui/player_level_indicator.go
package ui

import (
	"image/color"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/vector"
)

// PlayerLevelIndicator отображает уровень и опыт игрока.
type PlayerLevelIndicator struct {
	X, Y float32
}

const (
	// Новые размеры (уменьшены на 5%)
	xpBarWidth      = 118
	xpBarHeight     = 12
	levelRectWidth  = 16
	levelRectHeight = 12
	levelRectGap    = 9
	maxPlayerLevel  = 5
	borderWidth     = 1
)

var (
	// Новый цвет, как у проходимых гексов
	xpBarColorFill = color.RGBA{70, 100, 120, 220}
	borderColor    = color.White
)

// NewPlayerLevelIndicator создает новый индикатор уровня.
func NewPlayerLevelIndicator(x, y float32) *PlayerLevelIndicator {
	return &PlayerLevelIndicator{X: x, Y: y}
}

// Draw отрисовывает индикатор.
func (i *PlayerLevelIndicator) Draw(screen *ebiten.Image, level, currentXP, xpToNext int) {
	// 1. Рисуем белую обводку для полосы опыта
	vector.StrokeRect(screen, i.X, i.Y, xpBarWidth, xpBarHeight, borderWidth, borderColor, true)

	// 2. Р��суем заполненную часть полосы опыта
	fillRatio := 0.0
	if xpToNext > 0 {
		fillRatio = float64(currentXP) / float64(xpToNext)
	}
	if fillRatio > 1.0 {
		fillRatio = 1.0
	}
	fillWidth := float32(float64(xpBarWidth-borderWidth*2) * fillRatio)
	if fillWidth > 0 {
		vector.DrawFilledRect(screen, i.X+borderWidth, i.Y+borderWidth, fillWidth, xpBarHeight-borderWidth*2, xpBarColorFill, true)
	}

	// 3. Рисуем прямоугольники уровня
	rectY := i.Y + xpBarHeight + 10 // 10 пикселей отступ вниз
	for j := 0; j < maxPlayerLevel; j++ {
		rectX := i.X + float32(j)*(levelRectWidth+levelRectGap)
		// Рисуем обводку для каждого прямоугольника
		vector.StrokeRect(screen, rectX, rectY, levelRectWidth, levelRectHeight, borderWidth, borderColor, true)
		if j < level {
			// Заполненный прямоугольник (внутри обводки)
			vector.DrawFilledRect(screen, rectX+borderWidth, rectY+borderWidth, levelRectWidth-borderWidth*2, levelRectHeight-borderWidth*2, xpBarColorFill, true)
		}
	}
}
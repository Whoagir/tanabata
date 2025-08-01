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
	XpBarWidth      = 110
	xpBarHeight     = 12
	levelRectWidth  = 14
	levelRectHeight = 12
	levelRectGap    = 10
	maxPlayerLevel  = 5
	borderWidth     = 2 // Обводка стала толще
)

var (
	xpBarColorFill = color.RGBA{R: 70, G: 100, B: 120, A: 220}
	borderColor    = color.RGBA{R: 255, G: 255, B: 255, A: 255}
)

// NewPlayerLevelIndicator создает новый индикатор уровня.
func NewPlayerLevelIndicator(x, y float32) *PlayerLevelIndicator {
	return &PlayerLevelIndicator{X: x, Y: y}
}

// Draw отрисовывает индикатор.
func (i *PlayerLevelIndicator) Draw(screen *ebiten.Image, level, currentXP, xpToNext int) {
	vector.StrokeRect(screen, i.X, i.Y, XpBarWidth, xpBarHeight, borderWidth, borderColor, false)

	fillRatio := 0.0
	if xpToNext > 0 {
		fillRatio = float64(currentXP) / float64(xpToNext)
	}
	if fillRatio > 1.0 {
		fillRatio = 1.0
	}
	fillWidth := float32(float64(XpBarWidth-borderWidth*2) * fillRatio)
	if fillWidth > 0 {
		vector.DrawFilledRect(screen, i.X+borderWidth, i.Y+borderWidth, fillWidth, xpBarHeight-borderWidth*2, xpBarColorFill, true)
	}

	rectY := i.Y + xpBarHeight + 10
	for j := 0; j < maxPlayerLevel; j++ {
		rectX := i.X + float32(j)*(levelRectWidth+levelRectGap)
		vector.StrokeRect(screen, rectX, rectY, levelRectWidth, levelRectHeight, borderWidth, borderColor, false)
		if j < level {
			vector.DrawFilledRect(screen, rectX+borderWidth, rectY+borderWidth, levelRectWidth-borderWidth*2, levelRectHeight-borderWidth*2, xpBarColorFill, true)
		}
	}
}

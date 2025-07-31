// internal/ui/indicator.go
package ui

import (
	"image/color"
	"math"
	"time"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/vector"
)

type StateIndicator struct {
	X, Y          float32   // Сделать публичными
	Radius        float32   // Сделать публичным
	LastClickTime time.Time // Время последнего клика для анимации
}

func NewStateIndicator(x, y, radius float32) *StateIndicator {
	return &StateIndicator{
		X:      x,
		Y:      y,
		Radius: radius,
	}
}

func (i *StateIndicator) Draw(screen *ebiten.Image, stateColor color.Color) {
	// Анимация при клике
	elapsed := time.Since(i.LastClickTime).Seconds()
	scale := 1.0 + 0.3*math.Exp(-elapsed*8)
	currentRadius := i.Radius * float32(scale)

	// Рисуем основную заливку
	vector.DrawFilledCircle(screen, i.X, i.Y, currentRadius, stateColor, true)

	// Рисуем обводку
	vector.StrokeCircle(screen, i.X, i.Y, currentRadius, 2, color.White, true)
}

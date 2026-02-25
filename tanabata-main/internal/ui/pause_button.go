// internal/ui/pause_button.go
package ui

import (
	"go-tower-defense/internal/config"
	"math"
	"time"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// PauseButtonRL - версия кнопки паузы для Raylib
type PauseButtonRL struct {
	X, Y          float32
	Size          float32
	LastClickTime time.Time
}

func NewPauseButtonRL(x, y, size float32) *PauseButtonRL {
	return &PauseButtonRL{
		X:             x,
		Y:             y,
		Size:          size,
		LastClickTime: time.Time{},
	}
}

// Draw отрисовывает кнопку в зависимости от переданного состояния паузы.
func (b *PauseButtonRL) Draw(isPaused bool) {
	elapsed := time.Since(b.LastClickTime).Seconds()
	scale := 1.0 + 0.3*math.Exp(-elapsed*8)
	rectSize := b.Size * float32(scale)

	if isPaused {
		// Треугольник (play)
		p1 := rl.NewVector2(b.X-rectSize*0.8, b.Y-rectSize*1.1)
		p2 := rl.NewVector2(b.X-rectSize*0.8, b.Y+rectSize*1.1)
		p3 := rl.NewVector2(b.X+rectSize*1.1, b.Y)
		rl.DrawTriangle(p1, p2, p3, config.PauseButtonPauseColor)
		// Рисуем обводку вручную
		rl.DrawLineEx(p1, p2, config.UIBorderWidth, config.UIBorderColor)
		rl.DrawLineEx(p2, p3, config.UIBorderWidth, config.UIBorderColor)
		rl.DrawLineEx(p3, p1, config.UIBorderWidth, config.UIBorderColor)
	} else {
		// Два прямоугольника (pause)
		width := rectSize * 0.6
		height := rectSize * 2.0
		spacing := rectSize * 0.4

		leftRect := rl.NewRectangle(b.X-width-spacing/2, b.Y-height/2, width, height)
		rightRect := rl.NewRectangle(b.X+spacing/2, b.Y-height/2, width, height)

		rl.DrawRectangleRec(leftRect, config.PauseButtonPlayColor)
		rl.DrawRectangleRec(rightRect, config.PauseButtonPlayColor)

		rl.DrawRectangleLinesEx(leftRect, config.UIBorderWidth, config.UIBorderColor)
		rl.DrawRectangleLinesEx(rightRect, config.UIBorderWidth, config.UIBorderColor)
	}
}

// IsClicked проверяет, был ли клик по кнопке.
func (b *PauseButtonRL) IsClicked(mousePos rl.Vector2) bool {
	clicked := rl.CheckCollisionPointCircle(mousePos, rl.NewVector2(b.X, b.Y), b.Size)
	if clicked {
		b.LastClickTime = time.Now()
	}
	return clicked
}

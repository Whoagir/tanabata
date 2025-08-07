// internal/ui/indicator.go
package ui

import (
	"image/color"
	"math"
	"time"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// StateIndicatorRL - версия индикатора для Raylib
type StateIndicatorRL struct {
	X, Y          float32
	Radius        float32
	LastClickTime time.Time
}

func NewStateIndicatorRL(x, y, radius float32) *StateIndicatorRL {
	return &StateIndicatorRL{
		X:      x,
		Y:      y,
		Radius: radius,
	}
}

// Draw отрисовывает индикатор
func (i *StateIndicatorRL) Draw(stateColor color.RGBA) {
	elapsed := time.Since(i.LastClickTime).Seconds()
	scale := 1.0 + 0.3*math.Exp(-elapsed*8)
	currentRadius := i.Radius * float32(scale)

	rlColor := rl.NewColor(stateColor.R, stateColor.G, stateColor.B, stateColor.A)

	rl.DrawCircleV(rl.NewVector2(i.X, i.Y), currentRadius, rlColor)
	rl.DrawCircleLines(int32(i.X), int32(i.Y), currentRadius, rl.White)
}

// IsClicked проверяет, был ли клик внутри индикатора
func (i *StateIndicatorRL) IsClicked(mousePos rl.Vector2) bool {
	return rl.CheckCollisionPointCircle(mousePos, rl.NewVector2(i.X, i.Y), i.Radius)
}

// HandleClick обрабатывает клик
func (i *StateIndicatorRL) HandleClick() {
	i.LastClickTime = time.Now()
	// Логика смены состояния теперь в game.go
}
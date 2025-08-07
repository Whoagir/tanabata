// internal/ui/pause_button.go
package ui

import (
	"image/color"
	"math"
	"time"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// PauseButtonRL - версия кнопки паузы для Raylib
type PauseButtonRL struct {
	X, Y           float32
	Size           float32
	LastClickTime  time.Time
	LastToggleTime time.Time
	IsPaused       bool
	PauseColor     color.Color
	PlayColor      color.Color
}

func NewPauseButtonRL(x, y, size float32, pauseColor, playColor color.Color) *PauseButtonRL {
	return &PauseButtonRL{
		X:              x,
		Y:              y,
		Size:           size,
		LastClickTime:  time.Time{},
		LastToggleTime: time.Time{},
		PauseColor:     pauseColor,
		PlayColor:      playColor,
		IsPaused:       false,
	}
}

func (b *PauseButtonRL) Draw() {
	elapsed := time.Since(b.LastClickTime).Seconds()
	scale := 1.0 + 0.3*math.Exp(-elapsed*8)
	rectSize := b.Size * float32(scale)

	if b.IsPaused {
		// Треугольник (play)
		rlColor := colorToRL(b.PlayColor)
		p1 := rl.NewVector2(b.X-rectSize, b.Y-rectSize*1.2)
		p2 := rl.NewVector2(b.X-rectSize, b.Y+rectSize*1.2)
		p3 := rl.NewVector2(b.X+rectSize, b.Y)
		rl.DrawTriangle(p1, p2, p3, rlColor)
		rl.DrawTriangleLines(p1, p2, p3, rl.White)
	} else {
		// Два прямоугольника (pause)
		rlColor := colorToRL(b.PauseColor)
		width := rectSize * 0.6
		height := rectSize * 2.0
		spacing := rectSize * 0.4
		// Левый
		rl.DrawRectangleV(rl.NewVector2(b.X-width-spacing/2, b.Y-height/2), rl.NewVector2(width, height), rlColor)
		rl.DrawRectangleLines(int32(b.X-width-spacing/2), int32(b.Y-height/2), int32(width), int32(height), rl.White)
		// Правый
		rl.DrawRectangleV(rl.NewVector2(b.X+spacing/2, b.Y-height/2), rl.NewVector2(width, height), rlColor)
		rl.DrawRectangleLines(int32(b.X+spacing/2), int32(b.Y-height/2), int32(width), int32(height), rl.White)
	}
}

func (b *PauseButtonRL) IsClicked(mousePos rl.Vector2) bool {
	return rl.CheckCollisionPointCircle(mousePos, rl.NewVector2(b.X, b.Y), b.Size)
}

func (b *PauseButtonRL) TogglePause() {
	b.IsPaused = !b.IsPaused
	b.LastClickTime = time.Now()
	b.LastToggleTime = time.Now()
}

func (b *PauseButtonRL) SetPaused(paused bool) {
	b.IsPaused = paused
}

// colorToRL преобразует стандартный color.Color в rl.Color
func colorToRL(c color.Color) rl.Color {
	r, g, b, a := c.RGBA()
	return rl.NewColor(uint8(r>>8), uint8(g>>8), uint8(b>>8), uint8(a>>8))
}
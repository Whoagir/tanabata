// internal/ui/speed_button.go
package ui

import (
	"go-tower-defense/internal/config"
	"math"
	"time"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// SpeedButtonRL - версия кнопки скорости для Raylib
type SpeedButtonRL struct {
	X, Y           float32
	Size           float32
	LastClickTime  time.Time
	LastToggleTime time.Time
	CurrentState   int
}

func NewSpeedButtonRL(x, y, size float32) *SpeedButtonRL {
	return &SpeedButtonRL{
		X:              x,
		Y:              y,
		Size:           size,
		LastClickTime:  time.Time{},
		LastToggleTime: time.Time{},
		CurrentState:   0,
	}
}

func (b *SpeedButtonRL) Draw() {
	elapsed := time.Since(b.LastClickTime).Seconds()
	scale := 1.0 + 0.3*math.Exp(-elapsed*8)
	triangleSize := b.Size * float32(scale)

	rlColor := config.SpeedButtonColorsRL[b.CurrentState]

	// Параметры треугольников
	height := triangleSize * 1.2
	width := triangleSize
	offset := width * 0.8

	// Левый треугольник
	p1_left := rl.NewVector2(b.X-width, b.Y-height/2)
	p2_left := rl.NewVector2(b.X, b.Y)
	p3_left := rl.NewVector2(b.X-width, b.Y+height/2)
	// ИСПРАВЛЕНИЕ: Рисуем заливку и обводку. Меняем порядок вершин для заливки.
	rl.DrawTriangle(p1_left, p3_left, p2_left, rlColor) // p3 и p2 поменялись местами
	rl.DrawLineEx(p1_left, p2_left, config.UIBorderWidth, config.UIBorderColor)
	rl.DrawLineEx(p2_left, p3_left, config.UIBorderWidth, config.UIBorderColor)
	rl.DrawLineEx(p3_left, p1_left, config.UIBorderWidth, config.UIBorderColor)

	// Правый треугольник
	p1_right := rl.NewVector2(b.X-width+offset, b.Y-height/2)
	p2_right := rl.NewVector2(b.X+offset, b.Y)
	p3_right := rl.NewVector2(b.X-width+offset, b.Y+height/2)
	// ИСПРАВЛЕНИЕ: Рисуем заливку и обводку. Меняем порядок вершин для заливки.
	rl.DrawTriangle(p1_right, p3_right, p2_right, rlColor) // p3 и p2 поменялись местами
	rl.DrawLineEx(p1_right, p2_right, config.UIBorderWidth, config.UIBorderColor)
	rl.DrawLineEx(p2_right, p3_right, config.UIBorderWidth, config.UIBorderColor)
	rl.DrawLineEx(p3_right, p1_right, config.UIBorderWidth, config.UIBorderColor)
}

func (b *SpeedButtonRL) IsClicked(mousePos rl.Vector2) bool {
	// Используем круг для определения попадания, так как форма сложная
	return rl.CheckCollisionPointCircle(mousePos, rl.NewVector2(b.X, b.Y), b.Size*1.5)
}

func (b *SpeedButtonRL) ToggleState() {
	b.CurrentState = (b.CurrentState + 1) % len(config.SpeedButtonColorsRL)
	b.LastClickTime = time.Now()
	b.LastToggleTime = time.Now()
}
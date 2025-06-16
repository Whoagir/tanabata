// internal/ui/speed_button.go
package ui

import (
	"image/color"
	"math"
	"time"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/vector"
)

type SpeedButton struct {
	X, Y           float32
	Size           float32
	LastClickTime  time.Time
	LastToggleTime time.Time // Новое поле для кулдауна
	StateColors    []color.Color
	CurrentState   int
}

func NewSpeedButton(x, y, size float32, stateColors []color.Color) *SpeedButton {
	return &SpeedButton{
		X:              x,
		Y:              y,
		Size:           size,
		LastClickTime:  time.Time{},
		LastToggleTime: time.Time{}, // Инициализируем нулевым значением
		StateColors:    stateColors,
		CurrentState:   0,
	}
}

func (b *SpeedButton) Draw(screen *ebiten.Image) {
	elapsed := time.Since(b.LastClickTime).Seconds()
	scale := 1.0 + 0.3*math.Exp(-elapsed*8)
	triangleSize := b.Size * float32(scale)

	stateColor := b.StateColors[b.CurrentState]

	// Создаем белое изображение для текстуры
	whiteImage := ebiten.NewImage(1, 1)
	whiteImage.Fill(color.White)

	// Задаём параметры треугольников
	height := triangleSize
	baseWidth := triangleSize * 1.2 // Делаем шире, чтобы приблизить к равностороннему
	offset := baseWidth * 0.6       // Смещение для правого треугольника

	// Вычисляем цвет один раз
	r := float32(stateColor.(color.RGBA).R) / 255
	g := float32(stateColor.(color.RGBA).G) / 255
	bb := float32(stateColor.(color.RGBA).B) / 255
	a := float32(stateColor.(color.RGBA).A) / 255

	// Параметры обводки
	strokeOptions := &vector.StrokeOptions{
		Width:    2,
		LineJoin: vector.LineJoinRound,
	}

	// --- Левый треугольник ---
	leftPath := &vector.Path{}
	leftPath.MoveTo(b.X-baseWidth/2, b.Y-height/2)
	leftPath.LineTo(b.X+baseWidth/2, b.Y)
	leftPath.LineTo(b.X-baseWidth/2, b.Y+height/2)
	leftPath.Close()

	// Заливка левого треугольника
	vs, is := leftPath.AppendVerticesAndIndicesForFilling(nil, nil)
	for j := range vs {
		vs[j].ColorR = r
		vs[j].ColorG = g
		vs[j].ColorB = bb
		vs[j].ColorA = a
	}
	screen.DrawTriangles(vs, is, whiteImage, &ebiten.DrawTrianglesOptions{})

	// Обводка левого треугольника
	leftStroke := &vector.Path{}
	leftStroke.MoveTo(b.X-baseWidth/2, b.Y-height/2)
	leftStroke.LineTo(b.X+baseWidth/2, b.Y)
	leftStroke.LineTo(b.X-baseWidth/2, b.Y+height/2)
	leftStroke.Close()

	strokeVs, strokeIs := leftStroke.AppendVerticesAndIndicesForStroke(nil, nil, strokeOptions)
	for j := range strokeVs {
		strokeVs[j].ColorR = 1.0
		strokeVs[j].ColorG = 1.0
		strokeVs[j].ColorB = 1.0
		strokeVs[j].ColorA = 1.0
	}
	screen.DrawTriangles(strokeVs, strokeIs, whiteImage, &ebiten.DrawTrianglesOptions{})

	// --- Правый треугольник ---
	rightPath := &vector.Path{}
	rightPath.MoveTo(b.X-baseWidth/2+offset, b.Y-height/2)
	rightPath.LineTo(b.X+baseWidth/2+offset, b.Y)
	rightPath.LineTo(b.X-baseWidth/2+offset, b.Y+height/2)
	rightPath.Close()

	// Заливка правого треугольника
	vs, is = rightPath.AppendVerticesAndIndicesForFilling(nil, nil)
	for j := range vs {
		vs[j].ColorR = r
		vs[j].ColorG = g
		vs[j].ColorB = bb
		vs[j].ColorA = a
	}
	screen.DrawTriangles(vs, is, whiteImage, &ebiten.DrawTrianglesOptions{})

	// Обводка правого треугольника
	rightStroke := &vector.Path{}
	rightStroke.MoveTo(b.X-baseWidth/2+offset, b.Y-height/2)
	rightStroke.LineTo(b.X+baseWidth/2+offset, b.Y)
	rightStroke.LineTo(b.X-baseWidth/2+offset, b.Y+height/2)
	rightStroke.Close()

	strokeVs, strokeIs = rightStroke.AppendVerticesAndIndicesForStroke(nil, nil, strokeOptions)
	for j := range strokeVs {
		strokeVs[j].ColorR = 1.0
		strokeVs[j].ColorG = 1.0
		strokeVs[j].ColorB = 1.0
		strokeVs[j].ColorA = 1.0
	}
	screen.DrawTriangles(strokeVs, strokeIs, whiteImage, &ebiten.DrawTrianglesOptions{})
}

func (b *SpeedButton) ToggleState() {
	b.CurrentState = (b.CurrentState + 1) % len(b.StateColors)
	b.LastClickTime = time.Now()  // Для анимации
	b.LastToggleTime = time.Now() // Для кулдауна
}

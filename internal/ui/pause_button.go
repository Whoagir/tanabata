// internal/ui/pause_button.go
package ui

import (
	"image/color"
	"math"
	"time"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/vector"
)

type PauseButton struct {
	X, Y           float32
	Size           float32
	LastClickTime  time.Time
	LastToggleTime time.Time // Добавлено для защиты от многоклика
	IsPaused       bool
	PauseColor     color.Color
	PlayColor      color.Color
}

func NewPauseButton(x, y, size float32, pauseColor, playColor color.Color) *PauseButton {
	return &PauseButton{
		X:              x,
		Y:              y,
		Size:           size,
		LastClickTime:  time.Time{},
		LastToggleTime: time.Time{}, // Инициализируем нулевым значением
		PauseColor:     pauseColor,
		PlayColor:      playColor,
		IsPaused:       false,
	}
}

func (b *PauseButton) Draw(screen *ebiten.Image) {
	elapsed := time.Since(b.LastClickTime).Seconds()
	scale := 1.0 + 0.3*math.Exp(-elapsed*8)
	rectSize := b.Size * float32(scale) // Убрали *2 для нормального размера

	whiteImage := ebiten.NewImage(1, 1)
	whiteImage.Fill(color.White)

	baseWidth := rectSize * 1.5 // Уменьшили размеры для аккуратности
	height := rectSize * 1.5

	strokeOptions := &vector.StrokeOptions{
		Width:    2,
		LineJoin: vector.LineJoinRound,
	}

	if b.IsPaused {
		// Треугольник (play)
		path := vector.Path{}
		path.MoveTo(b.X-baseWidth/2, b.Y-height/2)
		path.LineTo(b.X+baseWidth/2, b.Y)
		path.LineTo(b.X-baseWidth/2, b.Y+height/2)
		path.Close()

		// Заливка
		vs, is := path.AppendVerticesAndIndicesForFilling(nil, nil)
		for j := range vs {
			vs[j].ColorR = float32(b.PlayColor.(color.RGBA).R) / 255
			vs[j].ColorG = float32(b.PlayColor.(color.RGBA).G) / 255
			vs[j].ColorB = float32(b.PlayColor.(color.RGBA).B) / 255
			vs[j].ColorA = float32(b.PlayColor.(color.RGBA).A) / 255
		}
		screen.DrawTriangles(vs, is, whiteImage, &ebiten.DrawTrianglesOptions{})

		// Обводка
		strokePath := vector.Path{}
		strokePath.MoveTo(b.X-baseWidth/2, b.Y-height/2)
		strokePath.LineTo(b.X+baseWidth/2, b.Y)
		strokePath.LineTo(b.X-baseWidth/2, b.Y+height/2)
		strokePath.Close()
		strokeVs, strokeIs := strokePath.AppendVerticesAndIndicesForStroke(nil, nil, strokeOptions)
		for j := range strokeVs {
			strokeVs[j].ColorR = 1.0
			strokeVs[j].ColorG = 1.0
			strokeVs[j].ColorB = 1.0
			strokeVs[j].ColorA = 1.0
		}
		screen.DrawTriangles(strokeVs, strokeIs, whiteImage, &ebiten.DrawTrianglesOptions{})
	} else {
		// Два прямоугольника (pause)
		path := vector.Path{}
		// Левый прямоугольник
		path.MoveTo(b.X-rectSize*0.75, b.Y-rectSize)
		path.LineTo(b.X-rectSize*0.25, b.Y-rectSize)
		path.LineTo(b.X-rectSize*0.25, b.Y+rectSize)
		path.LineTo(b.X-rectSize*0.75, b.Y+rectSize)
		path.Close()
		// Правый прямоугольник
		path.MoveTo(b.X+rectSize*0.25, b.Y-rectSize)
		path.LineTo(b.X+rectSize*0.75, b.Y-rectSize)
		path.LineTo(b.X+rectSize*0.75, b.Y+rectSize)
		path.LineTo(b.X+rectSize*0.25, b.Y+rectSize)
		path.Close()

		// Заливка
		vs, is := path.AppendVerticesAndIndicesForFilling(nil, nil)
		for j := range vs {
			vs[j].ColorR = float32(b.PauseColor.(color.RGBA).R) / 255
			vs[j].ColorG = float32(b.PauseColor.(color.RGBA).G) / 255
			vs[j].ColorB = float32(b.PauseColor.(color.RGBA).B) / 255
			vs[j].ColorA = float32(b.PauseColor.(color.RGBA).A) / 255
		}
		screen.DrawTriangles(vs, is, whiteImage, &ebiten.DrawTrianglesOptions{})

		// Обводка
		strokePath := vector.Path{}
		strokePath.MoveTo(b.X-rectSize*0.75, b.Y-rectSize)
		strokePath.LineTo(b.X-rectSize*0.25, b.Y-rectSize)
		strokePath.LineTo(b.X-rectSize*0.25, b.Y+rectSize)
		strokePath.LineTo(b.X-rectSize*0.75, b.Y+rectSize)
		strokePath.Close()
		strokePath.MoveTo(b.X+rectSize*0.25, b.Y-rectSize)
		strokePath.LineTo(b.X+rectSize*0.75, b.Y-rectSize)
		strokePath.LineTo(b.X+rectSize*0.75, b.Y+rectSize)
		strokePath.LineTo(b.X+rectSize*0.25, b.Y+rectSize)
		strokePath.Close()
		strokeVs, strokeIs := strokePath.AppendVerticesAndIndicesForStroke(nil, nil, strokeOptions)
		for j := range strokeVs {
			strokeVs[j].ColorR = 1.0
			strokeVs[j].ColorG = 1.0
			strokeVs[j].ColorB = 1.0
			strokeVs[j].ColorA = 1.0
		}
		screen.DrawTriangles(strokeVs, strokeIs, whiteImage, &ebiten.DrawTrianglesOptions{})
	}
}

func (b *PauseButton) TogglePause() {
	b.IsPaused = !b.IsPaused
	b.LastClickTime = time.Now()
	b.LastToggleTime = time.Now() // Обновляем время переключения

}

func (b *PauseButton) SetPaused(paused bool) {
	b.IsPaused = paused
}

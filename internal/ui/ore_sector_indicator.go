// internal/ui/ore_sector_indicator.go
package ui

import (
	"go-tower-defense/internal/config"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// OreSectorIndicatorRL отображает состояние рудных жил в трех секторах.
type OreSectorIndicatorRL struct {
	X, Y         float32
	Width, Height float32
	BarWidth     float32
	Spacing      float32
}

// NewOreSectorIndicatorRL создает новый индикатор состояния рудных жил.
func NewOreSectorIndicatorRL(x, y, width, height float32) *OreSectorIndicatorRL {
	return &OreSectorIndicatorRL{
		X:        x,
		Y:        y,
		Width:    width,
		Height:   height,
		BarWidth: (width - 2*10) / 3, // 3 бара с отступами по 10
		Spacing:  10,
	}
}

// Draw отрисовывает индикатор.
// centralPct, midPct, farPct - процент оставшейся руды (от 0.0 до 1.0).
func (i *OreSectorIndicatorRL) Draw(centralPct, midPct, farPct float32) {
	percentages := []float32{centralPct, midPct, farPct}
	startX := i.X

	for _, pct := range percentages {
		// Фон для полосы (пустой)
		rl.DrawRectangle(int32(startX), int32(i.Y), int32(i.BarWidth), int32(i.Height), config.XpBarBackgroundColorRL)

		if pct > 0 {
			// Высота заполнения в зависимости от процента
			fillHeight := i.Height * pct
			// Y-координата начала заполнения (снизу вверх)
			fillY := i.Y + (i.Height - fillHeight)

			// Новая логика цвета
			var fillColor rl.Color
			if pct > 0.66 {
				fillColor = rl.Blue // Больше 66% - синий
			} else if pct > 0.33 {
				fillColor = rl.Red // От 33% до 66% - красный
			} else {
				fillColor = rl.Yellow // Меньше 33% - желтый
			}

			// Рисуем заполнение
			rl.DrawRectangle(int32(startX), int32(fillY), int32(i.BarWidth), int32(fillHeight), fillColor)
		}

		// Обводка для каждой полосы
		rl.DrawRectangleLinesEx(
			rl.NewRectangle(startX, i.Y, i.BarWidth, i.Height),
			config.UIBorderWidth,
			config.UIBorderColor,
		)

		// Сдвигаем X для следующей полосы
		startX += i.BarWidth + i.Spacing
	}
}

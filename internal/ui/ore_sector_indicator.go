// internal/ui/ore_sector_indicator.go
package ui

import (
	"go-tower-defense/internal/config"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// OreSectorIndicatorRL отображает состояние рудных жил в виде двух горизонтальных баров.
type OreSectorIndicatorRL struct {
	X, Y          float32
	TotalWidth    float32
	SegmentHeight float32
	Spacing       float32
}

// NewOreSectorIndicatorRL создает новый индикатор состояния рудных жил.
func NewOreSectorIndicatorRL(x, y, totalWidth, segmentHeight float32) *OreSectorIndicatorRL {
	return &OreSectorIndicatorRL{
		X:             x,
		Y:             y,
		TotalWidth:    totalWidth,
		SegmentHeight: segmentHeight,
		Spacing:       2.0,
	}
}

// Draw отрисовывает индикатор.
func (i *OreSectorIndicatorRL) Draw(centralPct, midPct, farPct float32) {
	// --- Верхний ряд: Центральная (3) и Средняя (4) жилы ---
	topRowSegments := 7
	segmentWidthTop := (i.TotalWidth - float32(topRowSegments-1)*i.Spacing) / float32(topRowSegments)
	currentX := i.X

	i.drawVeinSegments(&currentX, i.Y, segmentWidthTop, 3, centralPct)
	i.drawVeinSegments(&currentX, i.Y, segmentWidthTop, 4, midPct)

	// --- Нижний ряд: Крайняя (7) жила ---
	bottomRowSegments := 7
	segmentWidthBottom := (i.TotalWidth - float32(bottomRowSegments-1)*i.Spacing) / float32(bottomRowSegments)
	currentX = i.X
	currentY := i.Y + i.SegmentHeight + i.Spacing*2

	i.drawVeinSegments(&currentX, currentY, segmentWidthBottom, 7, farPct)
}

// getVeinState определяет, сколько сегментов должно быть пустым и какой цвет у активных.
func (i *OreSectorIndicatorRL) getVeinState(numSegments int, percentage float32) (int, rl.Color) {
	var emptyCount int
	var activeColor rl.Color

	// Определяем количество пустых сегментов слева направо
	thresholds := make([]float32, numSegments)
	for k := 0; k < numSegments; k++ {
		thresholds[k] = 1.0 - (float32(k+1) / float32(numSegments))
	}

	emptyCount = 0
	for _, t := range thresholds {
		if percentage < t {
			emptyCount++
		}
	}

	// Определяем цвет для активных сегментов
	// Эта логика теперь применяется только к последнему активному сегменту.
	// Адаптируем вашу логику для 4-сегментной жилы: 40% и 20%
	redThreshold := float32(0.40)
	yellowThreshold := float32(0.20)

	if percentage <= 0 {
		activeColor = config.OreIndicatorDepletedColor
	} else if percentage < yellowThreshold {
		activeColor = config.OreIndicatorCriticalColor
	} else if percentage < redThreshold {
		activeColor = config.OreIndicatorWarningColor
	} else {
		activeColor = config.OreIndicatorFullColor
	}

	return emptyCount, activeColor
}

func (i *OreSectorIndicatorRL) drawVeinSegments(currentX *float32, currentY, segmentWidth float32, numSegments int, percentage float32) {
	emptySegments, activeColor := i.getVeinState(numSegments, percentage)

	for j := 0; j < numSegments; j++ {
		rect := rl.NewRectangle(*currentX, currentY, segmentWidth, i.SegmentHeight)
		var fillColor rl.Color

		if j < emptySegments {
			fillColor = config.OreIndicatorEmptyColor // Пустой
		} else {
			// Если сегмент не пустой, он получает общий цвет состояния жилы
			fillColor = activeColor
		}

		if percentage <= 0 {
			fillColor = config.OreIndicatorDepletedColor
		}

		rl.DrawRectangleRec(rect, fillColor)
		rl.DrawRectangleLinesEx(rect, 2, config.UIBorderColor)

		*currentX += segmentWidth + i.Spacing
	}
}

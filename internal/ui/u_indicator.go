// internal/ui/u_indicator.go
package ui

import (
	"go-tower-defense/internal/config"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// UIndicatorRL представляет UI-элемент для отображения режима перетаскивания линий.
type UIndicatorRL struct {
	X, Y float32
	Size float32
	Font rl.Font
}

// NewUIndicatorRL создает новый индикатор режима "U".
func NewUIndicatorRL(x, y, size float32, font rl.Font) *UIndicatorRL {
	return &UIndicatorRL{
		X:    x,
		Y:    y,
		Size: size,
		Font: font,
	}
}

// Draw отрисовывает индикатор с обводкой и жирным шрифтом.
func (i *UIndicatorRL) Draw(isLineDragMode bool) {
	text := "U"
	color := config.UIndicatorInactiveColor
	outlineColor := rl.White

	if isLineDragMode {
		color = config.UIndicatorActiveColor
	}

	textSize := rl.MeasureTextEx(i.Font, text, i.Size, 1.0)
	basePos := rl.NewVector2(i.X-textSize.X/2, i.Y-textSize.Y/2)

	// --- Обводка и жирность ---
	offsets := []rl.Vector2{
		{X: -2, Y: -2}, {X: 2, Y: -2}, {X: -2, Y: 2}, {X: 2, Y: 2}, // Обводка
		{X: -1, Y: 0}, {X: 1, Y: 0}, {X: 0, Y: -1}, {X: 0, Y: 1}, // Жирность
	}

	// Рисуем обводку
	for _, offset := range offsets[:4] {
		pos := rl.Vector2Add(basePos, offset)
		rl.DrawTextEx(i.Font, text, pos, i.Size, 1.0, outlineColor)
	}

	// Рисуем основной текст (несколько раз для жирности)
	rl.DrawTextEx(i.Font, text, basePos, i.Size, 1.0, color)
	for _, offset := range offsets[4:] {
		pos := rl.Vector2Add(basePos, offset)
		rl.DrawTextEx(i.Font, text, pos, i.Size, 1.0, color)
	}


	// Если режим неактивен, рисуем горизонтальную перечеркивающую линию
	if !isLineDragMode {
		// Координаты для горизонтальной линии по центру
		lineY := i.Y
		lineStart := rl.NewVector2(i.X-textSize.X/2, lineY)
		lineEnd := rl.NewVector2(i.X+textSize.X/2, lineY)

		// Рисуем сначала толстую линию-обводку
		rl.DrawLineEx(lineStart, lineEnd, config.UIBorderWidth+2, outlineColor)
		// Затем рисуем основную линию поверх
		rl.DrawLineEx(lineStart, lineEnd, config.UIBorderWidth, config.UIndicatorStrikethroughColorRL)
	}
}

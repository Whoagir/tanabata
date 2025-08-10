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

// Draw отрисовывает индикатор.
func (i *UIndicatorRL) Draw(isLineDragMode bool) {
	text := "U"
	color := config.UIndicatorInactiveColor

	if isLineDragMode {
		color = config.UIndicatorActiveColor
	}

	// Рисуем букву "U"
	textSize := rl.MeasureTextEx(i.Font, text, i.Size, 1.0)
	textPos := rl.NewVector2(i.X-textSize.X/2, i.Y-textSize.Y/2)
	rl.DrawTextEx(i.Font, text, textPos, i.Size, 1.0, color)

	// Если режим неактивен, рисуем перечеркивающую линию
	if !isLineDragMode {
		lineStart := rl.NewVector2(i.X-textSize.X/2, i.Y+textSize.Y/2)
		lineEnd := rl.NewVector2(i.X+textSize.X/2, i.Y-textSize.Y/2)
		rl.DrawLineEx(lineStart, lineEnd, config.UIBorderWidth, config.UIndicatorStrikethroughColorRL)
	}
}

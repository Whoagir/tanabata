// internal/ui/menu_button.go
package ui

import (
	rl "github.com/gen2brain/raylib-go/raylib"
)

// MenuButton представляет собой простую кнопку для использования в меню.
type MenuButton struct {
	Rect    rl.Rectangle
	Text    string
	bgColor rl.Color
	fgColor rl.Color
	font    rl.Font
}

// NewMenuButton создает новую кнопку меню.
func NewMenuButton(rect rl.Rectangle, text string, font rl.Font) *MenuButton {
	return &MenuButton{
		Rect:    rect,
		Text:    text,
		bgColor: rl.Gray,
		fgColor: rl.Black,
		font:    font,
	}
}

// Draw отрисовывает кнопку.
func (b *MenuButton) Draw() {
	rl.DrawRectangleRec(b.Rect, b.bgColor)
	rl.DrawRectangleLinesEx(b.Rect, 2, rl.LightGray)

	textSize := int32(30)
	textWidth := rl.MeasureTextEx(b.font, b.Text, float32(textSize), 1).X
	rl.DrawTextEx(
		b.font,
		b.Text,
		rl.NewVector2(
			b.Rect.X+(b.Rect.Width-textWidth)/2,
			b.Rect.Y+(b.Rect.Height-float32(textSize))/2,
		),
		float32(textSize),
		1,
		b.fgColor,
	)
}

// IsClicked проверяет, был ли клик по кнопке.
func (b *MenuButton) IsClicked(mousePos rl.Vector2) bool {
	return rl.CheckCollisionPointRec(mousePos, b.Rect)
}

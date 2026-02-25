// internal/ui/button.go
package ui

import (
	rl "github.com/gen2brain/raylib-go/raylib"
)

// Button представляет собой кликабельную кнопку в UI.
type Button struct {
	Rect      rl.Rectangle
	Text      string
	TextColor rl.Color
	BgColor   rl.Color
	HoverColor rl.Color
	Font      rl.Font
	FontSize  float32
}

// NewButton создает новую кнопку.
func NewButton(rect rl.Rectangle, text string, font rl.Font) *Button {
	return &Button{
		Rect:      rect,
		Text:      text,
		TextColor: rl.Black,
		BgColor:   rl.LightGray,
		HoverColor: rl.Gray,
		Font:      font,
		FontSize:  20,
	}
}

// IsClicked проверяет, был ли сделан клик по кнопке.
func (b *Button) IsClicked(mousePos rl.Vector2) bool {
	return rl.CheckCollisionPointRec(mousePos, b.Rect) && rl.IsMouseButtonPressed(rl.MouseLeftButton)
}

// Draw отрисовывает кнопку.
func (b *Button) Draw(mousePos rl.Vector2) {
	bgColor := b.BgColor
	if rl.CheckCollisionPointRec(mousePos, b.Rect) {
		bgColor = b.HoverColor
	}

	rl.DrawRectangleRec(b.Rect, bgColor)
	rl.DrawRectangleLinesEx(b.Rect, 2, rl.DarkGray)

	textSize := rl.MeasureTextEx(b.Font, b.Text, b.FontSize, 1)
	textX := b.Rect.X + (b.Rect.Width-textSize.X)/2
	textY := b.Rect.Y + (b.Rect.Height-textSize.Y)/2

	rl.DrawTextEx(b.Font, b.Text, rl.NewVector2(textX, textY), b.FontSize, 1, b.TextColor)
}

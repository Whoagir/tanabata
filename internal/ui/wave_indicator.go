package ui

import (
	"go-tower-defense/internal/config"
	"strings"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// WaveIndicator отображает номер текущей волны римскими цифрами.
type WaveIndicator struct {
	X, Y             float32
	FontSize         float32
	Color            rl.Color
	OutlineColor     rl.Color
	OutlineThickness int32
}

// NewWaveIndicator создает новый индикатор волны.
func NewWaveIndicator(x, y, fontSize float32) *WaveIndicator {
	return &WaveIndicator{
		X:                x,
		Y:                y,
		FontSize:         fontSize,
		Color:            config.UIColorBlue, // Используем цвет из конфига
		OutlineColor:     rl.White,
		OutlineThickness: 2, // Явная толщина обводки
	}
}

// toRoman конвертирует целое число в римское.
func toRoman(num int) string {
	if num <= 0 {
		return ""
	}
	val := []int{1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1}
	syb := []string{"M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"}

	var roman strings.Builder
	for i := 0; i < len(val); i++ {
		for num >= val[i] {
			roman.WriteString(syb[i])
			num -= val[i]
		}
	}
	return roman.String()
}

// Draw отрисовывает индикатор на экране.
func (i *WaveIndicator) Draw(waveNumber int, font rl.Font) {
	if waveNumber <= 0 {
		return
	}

	text := toRoman(waveNumber) // Убрали "Wave: "

	// Определяем цвет в зависимости от номера волны
	textColor := i.Color
	if waveNumber%10 == 0 && waveNumber > 0 {
		textColor = rl.Red // Красный для босс-волн
	}

	// Центрируем текст
	textSize := rl.MeasureTextEx(font, text, i.FontSize, 1)
	textX := i.X - textSize.X/2
	textY := i.Y

	// Рисуем обводку
	for y := -i.OutlineThickness; y <= i.OutlineThickness; y++ {
		for x := -i.OutlineThickness; x <= i.OutlineThickness; x++ {
			if x == 0 && y == 0 {
				continue
			}
			rl.DrawTextEx(font, text, rl.NewVector2(textX+float32(x), textY+float32(y)), i.FontSize, 1, i.OutlineColor)
		}
	}

	// Рисуем основной текст
	rl.DrawTextEx(font, text, rl.NewVector2(textX, textY), i.FontSize, 1, textColor)
}

// internal/ui/wave_indicator.go
package ui

import (
	"image"
	"image/color"
	"strings"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/text"
	"golang.org/x/image/font"
)

// WaveIndicator отображает номер текущей волны.
type WaveIndicator struct {
	X, Y   float32
	Radius float32
	Color  color.Color
}

// NewWaveIndicator создает новый индикатор волны.
func NewWaveIndicator(x, y, radius float32, clr color.Color) *WaveIndicator {
	return &WaveIndicator{
		X:      x,
		Y:      y,
		Radius: radius,
		Color:  clr,
	}
}

// toRoman конвертирует целое число в римское.
func toRoman(num int) string {
	if num <= 0 {
		return "N/A"
	}
	// Простая реализация для чисел до 3999
	val := []int{
		1000, 900, 500, 400,
		100, 90, 50, 40,
		10, 9, 5, 4,
		1,
	}
	syb := []string{
		"M", "CM", "D", "CD",
		"C", "XC", "L", "XL",
		"X", "IX", "V", "IV",
		"I",
	}

	var roman strings.Builder
	for i := 0; i < len(val); i++ {
		for num >= val[i] {
			roman.WriteString(syb[i])
			num -= val[i]
		}
	}
	return roman.String()
}

// GetTextBounds вычисляет и возвращает границы для текста волны.
func (i *WaveIndicator) GetTextBounds(waveNumber int, fontFace font.Face) image.Rectangle {
	waveStr := toRoman(waveNumber)
	bounds := text.BoundString(fontFace, waveStr)
	return bounds
}

// Draw отрисовывает индикатор на экране.
func (i *WaveIndicator) Draw(screen *ebiten.Image, waveNumber int, fontFace font.Face) {
	waveStr := toRoman(waveNumber)
	x := int(i.X)
	y := int(i.Y)

	// Цвета
	strokeColor := color.White
	fillColor := color.RGBA{70, 130, 180, 255} // Синий цвет, как у индикатора фазы

	// Рисуем обводку (смещаем на 1 пиксель в 8 направлениях)
	text.Draw(screen, waveStr, fontFace, x-1, y, strokeColor)
	text.Draw(screen, waveStr, fontFace, x+1, y, strokeColor)
	text.Draw(screen, waveStr, fontFace, x, y-1, strokeColor)
	text.Draw(screen, waveStr, fontFace, x, y+1, strokeColor)
	text.Draw(screen, waveStr, fontFace, x-1, y-1, strokeColor)
	text.Draw(screen, waveStr, fontFace, x+1, y-1, strokeColor)
	text.Draw(screen, waveStr, fontFace, x-1, y+1, strokeColor)
	text.Draw(screen, waveStr, fontFace, x+1, y+1, strokeColor)

	// Рисуем основной текст, немного "ужирняя" его
	text.Draw(screen, waveStr, fontFace, x, y, fillColor)
	text.Draw(screen, waveStr, fontFace, x+1, y, fillColor) // Смещаем на 1 пиксель вправо для жирности
}
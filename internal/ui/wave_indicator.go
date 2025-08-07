// internal/ui/wave_indicator.go
package ui

import (
	"fmt"
	"go-tower-defense/internal/config"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// WaveIndicatorRL - версия индикатора волны для Raylib
type WaveIndicatorRL struct {
	X, Y float32
	font rl.Font
}

// NewWaveIndicatorRL создает новый индикатор волны
func NewWaveIndicatorRL(x, y float32, font rl.Font) *WaveIndicatorRL {
	return &WaveIndicatorRL{
		X:    x,
		Y:    y,
		font: font,
	}
}

// Draw отрисовывает индикатор волны
func (i *WaveIndicatorRL) Draw(waveNumber int) {
	waveText := fmt.Sprintf("Wave: %d", waveNumber)
	rl.DrawTextEx(i.font, waveText, rl.NewVector2(i.X, i.Y), config.WaveIndicatorFontSizeRL, 1.0, config.WaveIndicatorColorRL)
}

// GetTextWidth возвращает ширину текста для указанного номера волны
func (i *WaveIndicatorRL) GetTextWidth(waveNumber int) float32 {
	waveText := fmt.Sprintf("Wave: %d", waveNumber)
	return rl.MeasureTextEx(i.font, waveText, config.WaveIndicatorFontSizeRL, 1.0).X
}

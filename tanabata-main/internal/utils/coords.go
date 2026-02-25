package utils

import (
	"go-tower-defense/internal/config"
	"go-tower-defense/pkg/hexmap"
)

// HexToScreen преобразует гексовые координаты в абсолютные пиксельные координаты на экране.
// Эта функция инкапсулирует логику центрирования карты и ее смещения.
func HexToScreen(h hexmap.Hex) (float64, float64) {
	px, py := h.ToPixel(config.HexSize)
	px += float64(config.ScreenWidth) / 2
	py += float64(config.ScreenHeight)/2 + config.MapCenterOffsetY
	return px, py
}

// ScreenToHex преобразует абсолютные пиксельные координаты экрана в гексовые координаты.
// Эта функция выполняет операцию, обратную HexToScreen.
func ScreenToHex(x, y float64) hexmap.Hex {
	// Сначала убираем смещение и центрирование, чтобы получить локальные координаты относительно центра карты
	localX := x - float64(config.ScreenWidth)/2
	localY := y - (float64(config.ScreenHeight)/2 + config.MapCenterOffsetY)
	return hexmap.PixelToHex(localX, localY, config.HexSize)
}

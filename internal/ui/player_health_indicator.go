// internal/ui/player_health_indicator.go
package ui

import (
	"go-tower-defense/internal/config"

	rl "github.com/gen2brain/raylib-go/raylib"
)

const (
	HealthSegments    = 7
	HealthBarHeight   = 10.0
	HealthBarSpacing  = 2.0
	HealthBarYOffset  = 25.0
	HealthTotalWidth  = 120.0 // Ширина, аналогичная одной жиле в индикаторе руды
)

// PlayerHealthIndicator отображает здоровье игрока в виде сегментированного бара.
type PlayerHealthIndicator struct {
	X, Y float32
}

// NewPlayerHealthIndicator создает новый индикатор здоровья.
func NewPlayerHealthIndicator(x, y float32) *PlayerHealthIndicator {
	return &PlayerHealthIndicator{
		X: x,
		Y: y,
	}
}

// Draw рисует индикатор здоровья игрока в виде сегментированного бара.
func (i *PlayerHealthIndicator) Draw(health int, maxHealth int) {
	percentage := float32(health) / float32(maxHealth)
	if health < 0 {
		percentage = 0
	}

	segmentWidth := (HealthTotalWidth - float32(HealthSegments-1)*HealthBarSpacing) / float32(HealthSegments)
	currentX := i.X

	emptySegments, activeColor := i.getHealthState(percentage)

	for j := 0; j < HealthSegments; j++ {
		rect := rl.NewRectangle(currentX, i.Y, segmentWidth, HealthBarHeight)
		var fillColor rl.Color

		if j < emptySegments {
			fillColor = config.HealthIndicatorEmptyColor
		} else {
			fillColor = activeColor
		}

		if health <= 0 {
			fillColor = config.OreIndicatorDepletedColor
		}

		rl.DrawRectangleRec(rect, fillColor)
		rl.DrawRectangleLinesEx(rect, 2, config.UIBorderColor)

		currentX += segmentWidth + HealthBarSpacing
	}
}

// getHealthState определяет, сколько сегментов должно быть пустым и какой цвет у активных.
func (i *PlayerHealthIndicator) getHealthState(percentage float32) (int, rl.Color) {
	var emptyCount int
	var activeColor rl.Color

	// Определяем количество пустых сегментов (справа налево)
	thresholds := make([]float32, HealthSegments)
	for k := 0; k < HealthSegments; k++ {
		// Сегменты пустеют справа налево
		thresholds[k] = (float32(k) / float32(HealthSegments))
	}

	activeSegments := 0
	for _, t := range thresholds {
		if percentage > t {
			activeSegments++
		}
	}
    // Инвертируем, так как мы считаем пустые сегменты СЛЕВА
    emptyCount = HealthSegments - activeSegments


	// Определяем цвет для активных сегментов
	redThreshold := float32(0.20)
	yellowThreshold := float32(0.50)

	if percentage <= 0 {
		activeColor = config.OreIndicatorDepletedColor
	} else if percentage < redThreshold {
		activeColor = config.HealthIndicatorCriticalColor
	} else if percentage < yellowThreshold {
		activeColor = config.HealthIndicatorWarningColor
	} else {
		activeColor = config.HealthIndicatorFullColor
	}

	return emptyCount, activeColor
}

// GetHeight возвращает общую высоту индикатора.
func (i *PlayerHealthIndicator) GetHeight() float32 {
	return HealthBarHeight
}

// GetWidth возвращает общую ширину индикатора.
func (i *PlayerHealthIndicator) GetWidth() float32 {
	return HealthTotalWidth
}

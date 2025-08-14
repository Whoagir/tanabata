// internal/ui/player_health_indicator.go
package ui

import (
	"strconv"

	rl "github.com/gen2brain/raylib-go/raylib"
)

const (
	HealthRows          = 5
	HealthCols          = 4
	HealthCircleRadius  = 8.0
	HealthCircleSpacing = 4.0
)

// PlayerHealthIndicator отображает здоровье игрока.
type PlayerHealthIndicator struct {
	Position rl.Vector2
}

// NewPlayerHealthIndicator создает новый индикатор здоровья.
func NewPlayerHealthIndicator(x, y float32) *PlayerHealthIndicator {
	return &PlayerHealthIndicator{
		Position: rl.NewVector2(x, y),
	}
}

// Draw рисует индикатор здоровья игрока в виде сетки кружков.
func (i *PlayerHealthIndicator) Draw(health int, maxHealth int) {
	startX := i.Position.X
	startY := i.Position.Y
	halfHealth := maxHealth / 2

	for j := 0; j < maxHealth; j++ {
		row := j / HealthCols
		col := j % HealthCols

		x := startX + float32(col*(HealthCircleRadius*2+HealthCircleSpacing))
		y := startY + float32(row*(HealthCircleRadius*2+HealthCircleSpacing))

		var color rl.Color
		if j < health {
			// Если текущий кружок меньше или равен половине здоровья, он красный
			if health <= halfHealth {
				color = rl.Red
			} else {
				// Если здоровье больше половины, то "избыток" синий, остальное красное
				if j < (health - halfHealth) {
					color = rl.Blue
				} else {
					color = rl.Red
				}
			}
		} else {
			// Пустые ячейки - черные
			color = rl.Black
		}

		// Рисуем сам кружок
		rl.DrawCircle(int32(x+HealthCircleRadius), int32(y+HealthCircleRadius), HealthCircleRadius, color)
		// Рисуем белую обводку
		rl.DrawCircleLines(int32(x+HealthCircleRadius), int32(y+HealthCircleRadius), HealthCircleRadius, rl.White)
	}

	// Текстовое отображение здоровья над сеткой
	healthText := strconv.Itoa(health) + "/" + strconv.Itoa(maxHealth)
	textWidth := rl.MeasureText(healthText, 20)
	rl.DrawText(healthText, int32(startX+((HealthCols*(HealthCircleRadius*2+HealthCircleSpacing))-float32(textWidth))/2), int32(startY)-25, 20, rl.White)
}

// GetHeight возвращает общую высоту индикатора.
func (i *PlayerHealthIndicator) GetHeight() float32 {
	// Высота текста над сеткой + отступ + высота самой сетки
	textHeight := float32(25)
	gridHeight := float32(HealthRows*(HealthCircleRadius*2+HealthCircleSpacing))
	return textHeight + gridHeight
}
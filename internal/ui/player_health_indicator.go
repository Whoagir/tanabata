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

	for j := 0; j < maxHealth; j++ {
		row := j / HealthCols
		col := j % HealthCols

		x := startX + float32(col*(HealthCircleRadius*2+HealthCircleSpacing))
		y := startY + float32(row*(HealthCircleRadius*2+HealthCircleSpacing))

		color := rl.DarkGray
		if j < health {
			color = rl.Red
		}

		rl.DrawCircle(int32(x+HealthCircleRadius), int32(y+HealthCircleRadius), HealthCircleRadius, color)
		rl.DrawCircleLines(int32(x+HealthCircleRadius), int32(y+HealthCircleRadius), HealthCircleRadius, rl.Black)
	}

	// Текстовое отображение здоровья над сеткой
	healthText := strconv.Itoa(health) + "/" + strconv.Itoa(maxHealth)
	textWidth := rl.MeasureText(healthText, 20)
	rl.DrawText(healthText, int32(startX+( (HealthCols*(HealthCircleRadius*2+HealthCircleSpacing)) - float32(textWidth) )/2), int32(startY)-25, 20, rl.White)
}
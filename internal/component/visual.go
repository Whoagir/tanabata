// internal/component/visual.go
package component

import "image/color"

// DamageFlash указывает, что сущность должна быть отрисована цветом урона.
type DamageFlash struct {
	Timer    float64 // Сколько времени эффект уже активен
	Duration float64 // Общая продолжительность эффекта
}

// Laser представляет собой визуальный эффект лазерного луча.
type Laser struct {
	FromX, FromY float64
	ToX, ToY     float64
	Color        color.Color
	Timer        float64 // Сколько времени эффект уже активен
	Duration     float64 // Общая продолжительность эффекта
}

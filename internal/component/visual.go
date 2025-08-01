// internal/component/visual.go
package component

import "image/color"

// DamageFlashComponent используется для визуального эффекта получения урона.
type DamageFlashComponent struct {
	Timer float64
}

// AoeEffectComponent используется для визуального эффекта атаки по области.
type AoeEffectComponent struct {
	MaxRadius    float64 // Максимальный радиус эффекта
	Duration     float64 // Общая длительность эффекта
	CurrentTimer float64 // Текущий таймер жизни эффекта
}


// Laser представляет собой визуальный эффект лазерного луча.
type Laser struct {
	FromX, FromY float64
	ToX, ToY     float64
	Color        color.Color
	Timer        float64 // Сколько времени эффект уже активен
	Duration     float64 // Общая продолжительность эффекта
}

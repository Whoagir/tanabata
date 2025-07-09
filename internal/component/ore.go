// internal/component/ore.go
package component

import "image/color"

type Ore struct {
	Power          float64    // Мощность жилы (0.05–0.70)
	MaxReserve     float64    // Максимальный запас руды
	CurrentReserve float64    // Текущий запас руды
	Position       Position   // Позиция в пикселях
	Radius         float32    // Радиус кружка
	Color          color.RGBA // Цвет руды
	PulseRate      float64    // Частота пульсации
}

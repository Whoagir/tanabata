// internal/component/ore.go
package component

import (
	"go-tower-defense/pkg/hexmap"
	"image/color"
)

type Ore struct {
	Power          float64    // Мощность жилы (0.05–0.70)
	MaxReserve     float64    // Максимальный запас руды
	CurrentReserve float64    // Текущий запас руды
	Hex            hexmap.Hex // Гекс, на котором находится руда
	Position       Position   // Позиция в пикселях
	Radius         float32    // Радиус кружка
	Color          color.RGBA // Цвет руды
	PulseRate      float64    // Частота пульсации
}

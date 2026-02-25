// component/movement.go
package component

import "go-tower-defense/pkg/hexmap"

// Position — компонент позиции
type Position struct {
	X, Y float64
}

// Velocity — компонент скорости
type Velocity struct {
	Speed float64
}

// Path — компонент пути
type Path struct {
	Hexes        []hexmap.Hex
	CurrentIndex int
}

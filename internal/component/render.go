// component/render.go
package component

import "image/color"

// Renderable — компонент для отрисовки
type Renderable struct {
	Color     color.RGBA
	Radius    float32
	HasStroke bool
}

// internal/component/line.go
package component

import (
	"go-tower-defense/internal/types"
	"image/color"
)

type LineRender struct {
	StartX, StartY float64
	EndX, EndY     float64
	Color          color.Color
	Tower1ID       types.EntityID // ID первой башни
	Tower2ID       types.EntityID // ID второй башни
}

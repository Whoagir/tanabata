// pkg/render/color.go
package render

import "image/color"

// DarkenColor reduces the brightness of a color.
func DarkenColor(c color.RGBA) color.RGBA {
	return color.RGBA{
		R: uint8(float64(c.R) * 0.5),
		G: uint8(float64(c.G) * 0.5),
		B: uint8(float64(c.B) * 0.5),
		A: c.A,
	}
}
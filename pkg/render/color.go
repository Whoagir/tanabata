// pkg/render/color.go
package render

import "image/color"

// MapColors holds all the color definitions needed to render the static map background.
type MapColors struct {
	BackgroundColor      color.RGBA
	PassableColor        color.RGBA
	ImpassableColor      color.RGBA
	EntryColor           color.RGBA
	ExitColor            color.RGBA
	TextDarkColor        color.RGBA
	TextLightColor       color.RGBA
	CheckpointTextColor  color.RGBA
	StrokeWidth          float32
}

// TowerOutlineColors holds the colors for dynamic tower outlines.
type TowerOutlineColors struct {
	WallColor   color.Color
	TypeAColor  color.Color
	TypeBColor  color.Color
}

// DarkenColor reduces the brightness of a color.
func DarkenColor(c color.RGBA) color.RGBA {
	return color.RGBA{
		R: uint8(float64(c.R) * 0.5),
		G: uint8(float64(c.G) * 0.5),
		B: uint8(float64(c.B) * 0.5),
		A: c.A,
	}
}

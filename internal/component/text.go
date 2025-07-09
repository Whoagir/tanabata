// internal/component/text.go
package component

import "image/color"

// Text holds all data needed to render a piece of text on the screen.
type Text struct {
	Value    string
	Position Position
	Color    color.RGBA
	IsUI     bool // To ensure it's rendered on top
}

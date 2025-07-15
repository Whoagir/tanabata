// internal/component/projectile.go
package component

import (
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/types"
	"image/color"
)

// Projectile представляет летящий снаряд.
type Projectile struct {
	TargetID   types.EntityID
	Speed      float64
	Damage     int
	Color      color.RGBA
	Direction  float64
	AttackType defs.AttackType
}

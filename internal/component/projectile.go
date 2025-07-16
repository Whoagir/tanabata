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
	Direction    float64
	AttackType   defs.AttackType
	SlowsTarget  bool    // Замедляет ли этот снаряд цель
	SlowDuration float64 // На какое время замедляет
	SlowFactor   float64 // Насколько замедляет (например, 0.5)
}

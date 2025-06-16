// internal/component/projectile.go
package component

import (
	"go-tower-defense/internal/types"
	"image/color"
)

type Projectile struct {
	TargetID  types.EntityID // Теперь используем types.EntityID
	Speed     float64
	Damage    int
	Color     color.RGBA
	Direction float64 // Направление (в радианах)
}

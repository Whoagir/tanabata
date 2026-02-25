// internal/component/rotating_beam.go
package component

import "go-tower-defense/internal/types"

// RotatingBeamComponent holds the state for a tower with a rotating beam attack.
type RotatingBeamComponent struct {
	CurrentAngle  float64
	RotationSpeed float64
	ArcAngle      float64
	Damage        float64
	DamageType    string
	Range         int
	// LastHitTime tracks when each enemy was last hit to prevent continuous damage.
	LastHitTime map[types.EntityID]float64
}

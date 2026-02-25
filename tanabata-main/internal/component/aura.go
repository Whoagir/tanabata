// internal/component/aura.go
package component

// Aura indicates that an entity projects an aura.
type Aura struct {
	Radius          int
	SpeedMultiplier float64
}

// AuraEffect indicates that an entity is currently affected by one or more auras.
type AuraEffect struct {
	// SpeedMultiplier is the combined multiplier from all auras affecting the entity.
	// A value of 1.0 means no effect.
	SpeedMultiplier float64
}

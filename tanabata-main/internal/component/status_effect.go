// internal/component/status_effect.go
package component

import "go-tower-defense/internal/types"

// SlowEffect indicates that an entity is slowed.
type SlowEffect struct {
	Timer      float64 // How much time is left for the effect.
	SlowFactor float64 // Multiplier for speed (e.g., 0.5 for 50% slow).
}

// PoisonEffect indicates that an entity is poisoned.
type PoisonEffect struct {
	Timer        float64 // How much time is left for the effect.
	DamagePerSec int     // Damage dealt per second.
	TickTimer    float64 // Timer to control damage ticks.
}

// JadePoisonInstance represents a single stack of Jade Poison.
type JadePoisonInstance struct {
	Duration  float32 // Remaining time for this specific stack.
	TickTimer float32 // Independent timer for this stack's damage tick.
}

// JadePoisonContainer holds all poison stacks for a single entity.
type JadePoisonContainer struct {
	Target             types.EntityID
	Instances          []JadePoisonInstance
	DamagePerStack     float32
	SlowFactorPerStack float32
}

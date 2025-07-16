// internal/component/status_effect.go
package component

// SlowEffect indicates that an entity is slowed.
type SlowEffect struct {
	Timer      float64 // How much time is left for the effect.
	SlowFactor float64 // Multiplier for speed (e.g., 0.5 for 50% slow).
}

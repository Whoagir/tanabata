// internal/defs/enemies.go
package defs

// EnemyDefinition holds all the static data for a specific type of enemy.
type EnemyDefinition struct {
	ID            string  `json:"id"`
	Name          string  `json:"name"`
	Health        int     `json:"health"`
	Speed         float64 `json:"speed"`
	PhysicalArmor int     `json:"physical_armor"`
	MagicalArmor  int     `json:"magical_armor"`
	Visuals       Visuals `json:"visuals"`
}

// EnemyDefs is the library of all enemy definitions, mapped by their ID.
var EnemyDefs map[string]EnemyDefinition

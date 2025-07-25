// internal/defs/towers.go
package defs

import (
	"encoding/json"
	"image/color"
)

// TowerType defines the category of a tower.
type TowerType string

const (
	TowerTypeAttack TowerType = "ATTACK"
	TowerTypeMiner  TowerType = "MINER"
	TowerTypeWall   TowerType = "WALL"
)

// TowerDefinition holds all the static data for a specific type of tower.
type TowerDefinition struct {
	ID      string       `json:"id"`
	Name    string       `json:"name"`
	Type    TowerType    `json:"type"`
	Combat  *CombatStats `json:"combat,omitempty"`
	Aura    *AuraDef     `json:"aura,omitempty"`
	Energy  *EnergyStats `json:"energy,omitempty"`
	Visuals Visuals      `json:"visuals"`
}

// AuraDef defines the properties of an aura tower.
type AuraDef struct {
	Radius          int     `json:"radius"`
	SpeedMultiplier float64 `json:"speed_multiplier"`
}

// AttackDef describes how a tower attacks.
type AttackDef struct {
	Type       AttackBehaviorType `json:"type"`
	DamageType AttackDamageType   `json:"damage_type"`
	Params     json.RawMessage    `json:"params,omitempty"` // Flexible parameters for different attack types
}

// CombatStats contains parameters related to a tower's combat abilities.
type CombatStats struct {
	Damage   int       `json:"damage"`
	FireRate float64   `json:"fire_rate"` // Shots per second
	Range    int       `json:"range"`
	ShotCost float64   `json:"shot_cost"`
	Attack   *AttackDef `json:"attack"`
}

// EnergyStats contains parameters related to the energy network.
type EnergyStats struct {
	TransferRadius      int     `json:"transfer_radius"`
	LineDegradationFactor float64 `json:"line_degradation_factor"`
}

// Visuals contains parameters for rendering a tower.
type Visuals struct {
	Color        color.RGBA `json:"color"`
	RadiusFactor float64    `json:"radius_factor"`
	StrokeWidth  float64    `json:"stroke_width"`
}

// ProjectileAttackParams defines parameters for a projectile-based attack.
type ProjectileAttackParams struct {
	SplitCount int `json:"split_count"`
}

// LaserAttackParams defines parameters for a laser-based attack.
type LaserAttackParams struct {
	SlowMultiplier float64 `json:"slow_multiplier"`
	SlowDuration   float64 `json:"slow_duration"`
}

// internal/component/combat.go
package component

import "go-tower-defense/internal/defs"

// Health представляет здоровье сущности.
type Health struct {
	Value int
}

// Combat представляет боевые возможности сущности.
type Combat struct {
	FireRate     float64
	FireCooldown float64
	Range        int
	ShotCost     float64 // Стоимость одного выстрела в единицах руды
	Attack       defs.AttackDef
}

// internal/defs/types.go
package defs

// AttackType defines the type of damage dealt.
type AttackType string

const (
	AttackPhysical AttackType = "PHYSICAL"
	AttackMagical  AttackType = "MAGICAL"
	AttackPure     AttackType = "PURE"
)

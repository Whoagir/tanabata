// internal/defs/types.go
package defs

// AttackDamageType defines the type of damage dealt.
type AttackDamageType string

const (
	AttackPhysical AttackDamageType = "PHYSICAL"
	AttackMagical  AttackDamageType = "MAGICAL"
	AttackPure     AttackDamageType = "PURE"
	AttackInternal AttackDamageType = "INTERNAL" // Служебный тип для внутренних механик, не наносит урон
	AttackSlow     AttackDamageType = "SLOW"
	AttackPoison   AttackDamageType = "POISON"
)

// AttackBehaviorType defines how an attack is performed.
type AttackBehaviorType string

const (
	// BehaviorProjectile fires a projectile at a single target. This is the default.
	BehaviorProjectile AttackBehaviorType = "PROJECTILE"
	// BehaviorAoe affects an area around the tower.
	BehaviorAoe AttackBehaviorType = "AOE"
	// BehaviorBeacon applies a continuous effect to a single target.
	BehaviorBeacon AttackBehaviorType = "BEACON"
	// BehaviorLaser creates an instantaneous line effect.
	BehaviorLaser AttackBehaviorType = "LASER"
	// BehaviorAreaOfEffect affects an area around the tower.
	BehaviorAreaOfEffect AttackBehaviorType = "AREA_OF_EFFECT"
)

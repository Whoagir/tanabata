// internal/component/projectile.go
package component

import (
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/types"
	"image/color"
)

// Projectile представляет летящий снаряд.
type Projectile struct {
	TargetID     types.EntityID
	Speed        float64
	Damage       int
	Color        color.RGBA
	Direction    float64
	AttackType   defs.AttackDamageType
	SlowsTarget  bool    // Замедляет ли этот снаряд цель
	SlowDuration float64 // На какое время замедляет
	SlowFactor   float64 // Насколько замедляет (например, 0.5)
	AppliesPoison bool   // Накладывает ли этот снаряд яд
	PoisonDuration float64 // Длительность яда
	PoisonDPS      int     // Урон в секунду от яда

	// Для условного самонаведения
	IsConditionallyHoming bool    // Включена ли логика самонаведения
	TargetLastSlowFactor  float64 // Множитель замедления цели в момент последнего расчета
}

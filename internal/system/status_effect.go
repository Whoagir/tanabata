// internal/system/status_effect.go
package system

import "go-tower-defense/internal/entity"

// StatusEffectSystem управляет жизненным циклом эффектов, таких как замедление.
type StatusEffectSystem struct {
	ecs *entity.ECS
}

func NewStatusEffectSystem(ecs *entity.ECS) *StatusEffectSystem {
	return &StatusEffectSystem{ecs: ecs}
}

// Update обрабатывает все активные эффекты.
func (s *StatusEffectSystem) Update(deltaTime float64) {
	// Обновление эффектов замедления
	for id, effect := range s.ecs.SlowEffects {
		effect.Timer -= deltaTime
		if effect.Timer <= 0 {
			delete(s.ecs.SlowEffects, id)
		}
	}

	// Обновление эффектов отравления
	for id, effect := range s.ecs.PoisonEffects {
		effect.Timer -= deltaTime
		if effect.Timer <= 0 {
			delete(s.ecs.PoisonEffects, id)
			continue
		}

		effect.TickTimer -= deltaTime
		if effect.TickTimer <= 0 {
			// Наносим урон от яда (чистый урон)
			ApplyDamage(s.ecs, id, effect.DamagePerSec, "PURE")
			effect.TickTimer = 1.0 // Сбрасываем таймер тика
		}
	}
}

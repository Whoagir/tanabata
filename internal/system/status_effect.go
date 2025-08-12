// internal/system/status_effect.go
package system

import (
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
	"math"
)

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
			ApplyDamage(s.ecs, id, effect.DamagePerSec, defs.AttackPure)
			effect.TickTimer = 1.0 // Сбрасываем таймер тика
		}
	}

	// Обновление эффектов Jade Poison
	for id, container := range s.ecs.JadePoisonContainers {
		// Создаем новый срез для хранения только активных стаков
		activeInstances := container.Instances[:0]

		for i := range container.Instances {
			instance := &container.Instances[i]
			instance.Duration -= float32(deltaTime)

			if instance.Duration > 0 {
				instance.TickTimer -= float32(deltaTime)
				if instance.TickTimer <= 0 {
					// Рассчитываем урон
					stacks := float64(len(container.Instances))
					damage := (float64(container.DamagePerStack) * stacks) * math.Pow(1.1, stacks-1)
					ApplyDamage(s.ecs, id, int(damage), defs.AttackMagical)
					instance.TickTimer = 1.0 // Сбрасываем таймер тика
				}
				activeInstances = append(activeInstances, *instance)
			}
		}

		container.Instances = activeInstances

		// Если все стаки истекли, удаляем контейнер
		if len(container.Instances) == 0 {
			delete(s.ecs.JadePoisonContainers, id)
		}
	}
}

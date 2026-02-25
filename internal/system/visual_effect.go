// internal/system/visual_effect.go
package system

import (
	"go-tower-defense/internal/entity"
)

// VisualEffectSystem управляет визуальными эффектами, такими как вспышки урона.
type VisualEffectSystem struct {
	ecs *entity.ECS
}

// NewVisualEffectSystem создает новую систему визуальных эффектов.
func NewVisualEffectSystem(ecs *entity.ECS) *VisualEffectSystem {
	return &VisualEffectSystem{ecs: ecs}
}

// Update обновляет все активные визуальные эффекты.
func (s *VisualEffectSystem) Update(deltaTime float64) {
	// Обновляем таймеры вспышек урона
	for id, flash := range s.ecs.DamageFlashes {
		flash.Timer -= deltaTime
		if flash.Timer <= 0 {
			delete(s.ecs.DamageFlashes, id)
		}
	}

	// Обновляем эффекты атаки по области (Вулкан)
	for id, aoeEffect := range s.ecs.AoeEffects {
		aoeEffect.CurrentTimer += deltaTime

		if aoeEffect.CurrentTimer >= aoeEffect.Duration {
			// Эффект завершился, удаляем его
			delete(s.ecs.AoeEffects, id)
			delete(s.ecs.Renderables, id)
			delete(s.ecs.Positions, id)
			continue
		}

		// Обновляем радиус для анимации
		renderable, ok := s.ecs.Renderables[id]
		if ok {
			progress := aoeEffect.CurrentTimer / aoeEffect.Duration
			renderable.Radius = float32(progress * aoeEffect.MaxRadius)
		}
	}
}

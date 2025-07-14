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
		flash.Timer += deltaTime
		if flash.Timer >= flash.Duration {
			delete(s.ecs.DamageFlashes, id)
		}
	}
}

// internal/system/projectile.go
package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/event"
	"go-tower-defense/internal/types"
	"math"
)

// ProjectileSystem управляет движением снарядов и нанесением урона
type ProjectileSystem struct {
	ecs             *entity.ECS
	eventDispatcher *event.Dispatcher
	combatSystem    *CombatSystem
}

func NewProjectileSystem(ecs *entity.ECS, eventDispatcher *event.Dispatcher, combatSystem *CombatSystem) *ProjectileSystem {
	return &ProjectileSystem{
		ecs:             ecs,
		eventDispatcher: eventDispatcher,
		combatSystem:    combatSystem,
	}
}

func (s *ProjectileSystem) Update(deltaTime float64) {
	for id, proj := range s.ecs.Projectiles {
		pos := s.ecs.Positions[id]
		if pos == nil {
			// log.Println("Projectile", id, "has no position, removing")
			delete(s.ecs.Positions, id)
			delete(s.ecs.Projectiles, id)
			delete(s.ecs.Renderables, id)
			continue
		}

		// Проверяем, существует ли цель
		targetPos, targetExists := s.ecs.Positions[proj.TargetID]
		if !targetExists || targetPos == nil {
			// Цель пропала, сразу удаляем снаряд
			// log.Println("Target", proj.TargetID, "for projectile", id, "is gone, removing projectile")
			s.removeProjectile(id)
			continue
		}

		// Проверяем расстояние до цели
		dx := targetPos.X - pos.X
		dy := targetPos.Y - pos.Y
		dist := math.Sqrt(dx*dx + dy*dy)

		// Увеличиваем радиус засчитывания до 15
		if dist <= proj.Speed*deltaTime || dist < 15.0 {
			s.hitTarget(id, proj)
		} else {
			pos.X += math.Cos(proj.Direction) * proj.Speed * deltaTime
			pos.Y += math.Sin(proj.Direction) * proj.Speed * deltaTime
		}
	}
}

// Вспомогательная функция для удаления снаряда
func (s *ProjectileSystem) removeProjectile(id types.EntityID) {
	delete(s.ecs.Positions, id)
	delete(s.ecs.Projectiles, id)
	delete(s.ecs.Renderables, id)
}

func (s *ProjectileSystem) hitTarget(projectileID types.EntityID, proj *component.Projectile) {
	// На��осим урон через CombatSystem, передавая тип атаки
	s.combatSystem.ApplyDamage(proj.TargetID, proj.Damage, proj.AttackType)

	// Удаляем снаряд
	s.removeProjectile(projectileID)

	// Проверяем, жив ли еще враг, чтобы обновить его радиус
	if health, exists := s.ecs.Healths[proj.TargetID]; exists {
		// TODO: Get enemy definition properly instead of hardcoding
		def, ok := defs.EnemyLibrary["DEFAULT_ENEMY"]
		if !ok {
			return // or log error
		}

		healthf := float32(health.Value)
		health_m := float32(def.Health)
		if renderable, ok := s.ecs.Renderables[proj.TargetID]; ok {
			newRadius := (0.6 + 0.4*(healthf/health_m)) * float32(config.HexSize*def.Visuals.RadiusFactor)
			renderable.Radius = newRadius
		}
	} else {
		// Враг был уничтожен, отправляем событие
		s.eventDispatcher.Dispatch(event.Event{Type: event.EnemyDestroyed, Data: proj.TargetID})
	}
}

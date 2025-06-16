// internal/system/projectile.go
package system

import (
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/event"
	"go-tower-defense/internal/types"
	"math"
)

// ProjectileSystem управляет движением снарядов и нанесением урона
type ProjectileSystem struct {
	ecs             *entity.ECS
	eventDispatcher *event.Dispatcher
}

func NewProjectileSystem(ecs *entity.ECS, eventDispatcher *event.Dispatcher) *ProjectileSystem {
	return &ProjectileSystem{ecs: ecs, eventDispatcher: eventDispatcher}
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
			s.hitTarget(proj.TargetID, proj.Damage)
			delete(s.ecs.Positions, id)
			delete(s.ecs.Projectiles, id)
			delete(s.ecs.Renderables, id)
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

func (s *ProjectileSystem) hitTarget(enemyID types.EntityID, damage int) {
	health, exists := s.ecs.Healths[enemyID]
	if !exists || health == nil {
		// log.Println("Enemy", enemyID, "has no health or was already removed")
		return
	}

	health.Value -= damage
	if health.Value <= 0 {
		// log.Println("Enemy", enemyID, "destroyed")
		// Удаляем врага из всех компонентов
		delete(s.ecs.Positions, enemyID)
		delete(s.ecs.Velocities, enemyID)
		delete(s.ecs.Paths, enemyID)
		delete(s.ecs.Healths, enemyID)
		delete(s.ecs.Renderables, enemyID)
		s.eventDispatcher.Dispatch(event.Event{Type: event.EnemyDestroyed, Data: enemyID})
	}
}

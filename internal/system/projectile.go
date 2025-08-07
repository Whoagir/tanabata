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
	combatSystem    *CombatSystem // Добавляем ссылку на CombatSystem для доступа к predictTargetPosition
}

func NewProjectileSystem(ecs *entity.ECS, eventDispatcher *event.Dispatcher, combatSystem *CombatSystem) *ProjectileSystem {
	return &ProjectileSystem{
		ecs:             ecs,
		eventDispatcher: eventDispatcher,
		combatSystem:    combatSystem,
	}
}

// OnEvent реализует интерфейс event.Listener
func (s *ProjectileSystem) OnEvent(e event.Event) {
	if e.Type == event.EnemyKilled {
		deadEnemyID, ok := e.Data.(types.EntityID)
		if !ok {
			return
		}
		// Проходим по всем снарядам и удаляем те, что летят в мёртвого врага
		for projID, proj := range s.ecs.Projectiles {
			if proj.TargetID == deadEnemyID {
				s.removeProjectile(projID)
			}
		}
	}
}

func (s *ProjectileSystem) Update(deltaTime float64) {
	for id, proj := range s.ecs.Projectiles {
		pos := s.ecs.Positions[id]
		if pos == nil {
			s.removeProjectile(id)
			continue
		}

		// Проверяем, существует ли цель
		targetPos, targetExists := s.ecs.Positions[proj.TargetID]
		if !targetExists || targetPos == nil {
			s.removeProjectile(id)
			continue
		}

		// --- Логика условного самонаведения ---
		s.handleHoming(id, proj, pos)
		// --- Конец логики ---

		// Проверяем расстояние до цели
		dx := targetPos.X - pos.X
		dy := targetPos.Y - pos.Y
		dist := math.Sqrt(dx*dx + dy*dy)

		if dist <= proj.Speed*deltaTime || dist < 15.0 {
			s.hitTarget(id, proj)
		} else {
			pos.X += math.Cos(proj.Direction) * proj.Speed * deltaTime
			pos.Y += math.Sin(proj.Direction) * proj.Speed * deltaTime
		}
	}
}

func (s *ProjectileSystem) handleHoming(projID types.EntityID, proj *component.Projectile, projPos *component.Position) {
	if !proj.IsConditionallyHoming {
		return
	}

	// Определяем текущий фактор замедления цели
	var currentSlowFactor float64 = 1.0
	if slowEffect, ok := s.ecs.SlowEffects[proj.TargetID]; ok {
		currentSlowFactor = slowEffect.SlowFactor
	}

	// Если состояние замедления изменилось, пересчитываем курс
	if math.Abs(currentSlowFactor-proj.TargetLastSlowFactor) > 0.001 {
		// Используем predictTargetPosition из CombatSystem, но с текущей позицией снаряда
		predictedPos := s.combatSystem.predictTargetPosition(proj.TargetID, projPos, proj.Speed)

		// Обновляем направление и состояние снаряда
		proj.Direction = math.Atan2(predictedPos.Y-projPos.Y, predictedPos.X-projPos.X)
		proj.TargetLastSlowFactor = currentSlowFactor
	}
}


// Вспомогательная функция для удаления снаряда
func (s *ProjectileSystem) removeProjectile(id types.EntityID) {
	delete(s.ecs.Positions, id)
	delete(s.ecs.Projectiles, id)
	delete(s.ecs.Renderables, id)
}

func (s *ProjectileSystem) hitTarget(projectileID types.EntityID, proj *component.Projectile) {
	// Применяем эффект замедления, если он есть
	if proj.SlowsTarget {
		s.ecs.SlowEffects[proj.TargetID] = &component.SlowEffect{
			Timer:      proj.SlowDuration,
			SlowFactor: proj.SlowFactor,
		}
	}

	// Применяем эффект отравления, если он есть
	if proj.AppliesPoison {
		s.ecs.PoisonEffects[proj.TargetID] = &component.PoisonEffect{
			Timer:        proj.PoisonDuration,
			DamagePerSec: proj.PoisonDPS,
			TickTimer:    1.0, // Первый тик урона будет через 1 секунду
		}
	}

	// Наносим урон
	ApplyDamage(s.ecs, proj.TargetID, proj.Damage, proj.AttackType)

	// Удаляем снаряд
	s.removeProjectile(projectileID)

	// Проверяем, жив ли еще враг, чтобы обновить его радиус
	if health, exists := s.ecs.Healths[proj.TargetID]; exists {
		// Получаем компонент врага, чтобы узнать его DefID
		enemy, isEnemy := s.ecs.Enemies[proj.TargetID]
		if !isEnemy {
			return // Цель больше не враг
		}

		// Получаем правильное определение врага из библиотеки
		def, ok := defs.EnemyDefs[enemy.DefID]
		if !ok {
			return // Не удалось найти определение
		}

		healthf := float32(health.Value)
		health_m := float32(def.Health)
		if renderable, ok := s.ecs.Renderables[proj.TargetID]; ok {
			// Используем правильный RadiusFactor из определения врага
			newRadius := (0.6 + 0.4*(healthf/health_m)) * float32(config.HexSize*def.Visuals.RadiusFactor)
			renderable.Radius = newRadius
		}
	} else {
		// ��раг был уничтожен, отправляем событие
		s.eventDispatcher.Dispatch(event.Event{Type: event.EnemyRemovedFromGame, Data: proj.TargetID})
	}
}

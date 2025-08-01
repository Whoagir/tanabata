// internal/system/area_attack_system.go
package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
)

// AreaAttackSystem управляет башнями, которые наносят урон по области.
type AreaAttackSystem struct {
	ecs *entity.ECS
}

func NewAreaAttackSystem(ecs *entity.ECS) *AreaAttackSystem {
	return &AreaAttackSystem{ecs: ecs}
}

func (s *AreaAttackSystem) Update(deltaTime float64) {
	// Перебираем все башни с боевым компонентом
	for id, combat := range s.ecs.Combats {
		// Проверяем, что это наша башня
		if combat.Attack.Type != defs.BehaviorAreaOfEffect {
			continue
		}

		// Проверяем, активна ли башня
		tower, ok := s.ecs.Towers[id]
		if !ok || !tower.IsActive {
			continue
		}

		// Обновляем таймер перезарядки
		combat.FireCooldown -= deltaTime
		if combat.FireCooldown > 0 {
			continue
		}

		// Перезарядка
		combat.FireCooldown = 1.0 / combat.FireRate

		// Находим по��ицию башни
		towerPos, ok := s.ecs.Positions[id]
		if !ok {
			continue
		}

		// --- Создание визуального эффекта ---
		effectID := s.ecs.NewEntity()
		towerDef := defs.TowerLibrary[tower.DefID]
		s.ecs.Positions[effectID] = towerPos // Эффект в той же позиции, что и башня
		s.ecs.Renderables[effectID] = &component.Renderable{
			Color:     towerDef.Visuals.Color,
			Radius:    0, // Начнет с нуля и будет расти
			HasStroke: false,
		}
		s.ecs.AoeEffects[effectID] = &component.AoeEffectComponent{
			MaxRadius:    float64(combat.Range) * config.HexSize,
			Duration:     0.4, // Длительность эффекта в секундах
			CurrentTimer: 0,
		}
		// --- Конец создания эффекта ---


		// Находим всех врагов в радиусе и наносим урон
		for enemyID, enemyPos := range s.ecs.Positions {
			// Убеждаемся, что это враг
			if _, isEnemy := s.ecs.Enemies[enemyID]; !isEnemy {
				continue
			}

			dx := towerPos.X - enemyPos.X
			dy := towerPos.Y - enemyPos.Y
			distSq := dx*dx + dy*dy
			rangePixels := float64(combat.Range) * config.HexSize

			if distSq <= rangePixels*rangePixels {
				ApplyDamage(s.ecs, enemyID, towerDef.Combat.Damage, combat.Attack.DamageType)
			}
		}
	}
}
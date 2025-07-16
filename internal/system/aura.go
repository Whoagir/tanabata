// internal/system/aura.go
package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
)

// AuraSystem обрабатывает логику башен-аур.
type AuraSystem struct {
	ecs *entity.ECS
}

func NewAuraSystem(ecs *entity.ECS) *AuraSystem {
	return &AuraSystem{ecs: ecs}
}

// RecalculateAuras полностью пересчитывает эффекты всех аур в игре.
// Этот метод следует вызывать только при изменении расположения башен (постройка, удаление).
func (s *AuraSystem) RecalculateAuras() {
	// Шаг 1: Очистить все существующие эффекты аур перед пересчетом.
	for id := range s.ecs.AuraEffects {
		delete(s.ecs.AuraEffects, id)
	}

	// Шаг 2: Найти все активные башни-ауры и применить их эффекты.
	for auraTowerID, aura := range s.ecs.Auras {
		auraTower, hasTower := s.ecs.Towers[auraTowerID]
		if !hasTower || !auraTower.IsActive {
			continue
		}

		// Найти все атакующие башни в радиусе.
		for targetID, targetTower := range s.ecs.Towers {
			// Эффект не применяется к самой башне-ауре, стенам и добытчикам.
			if targetID == auraTowerID || targetTower.Type == config.TowerTypeWall || targetTower.Type == config.TowerTypeMiner {
				continue
			}
			// Проверяем, является ли цель атакующей башней
			if _, isAttacker := s.ecs.Combats[targetID]; !isAttacker {
				continue
			}

			distance := auraTower.Hex.Distance(targetTower.Hex)
			if distance <= aura.Radius {
				// Применить или обновить эффект ауры.
				effect, hasEffect := s.ecs.AuraEffects[targetID]
				if !hasEffect {
					// Если эффекта еще нет, создаем его с базовым множителем 1.0.
					effect = &component.AuraEffect{SpeedMultiplier: 1.0}
					s.ecs.AuraEffects[targetID] = effect
				}
				// Умножаем существующий множитель на множитель от этой ауры.
				effect.SpeedMultiplier *= aura.SpeedMultiplier
			}
		}
	}
}
// internal/system/utils.go
package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/types"
)

// ApplyDamage наносит урон сущности, учитывая типы атаки и брони.
func ApplyDamage(ecs *entity.ECS, entityID types.EntityID, damage int, attackType defs.AttackType) {
	// Атаки типа INTERNAL - служебные и никогда не наносят урон.
	if attackType == defs.AttackInternal {
		return
	}

	health, hasHealth := ecs.Healths[entityID]
	enemy, isEnemy := ecs.Enemies[entityID]
	if !hasHealth {
		return
	}

	finalDamage := damage

	// Рассчитываем урон только если это враг с компонентом брони
	if isEnemy {
		switch attackType {
		case defs.AttackPhysical:
			finalDamage -= enemy.PhysicalArmor
		case defs.AttackMagical:
			finalDamage -= enemy.MagicalArmor
		case defs.AttackPure:
			// Чистый урон не уменьшается
		}
	}

	// Урон не может быть отрицательным
	if finalDamage < 1 && damage > 0 {
		finalDamage = 1 // Минимальный урон 1, если начальный урон был > 0
	} else if finalDamage < 0 {
		finalDamage = 0
	}


	health.Value -= finalDamage
	if health.Value <= 0 {
		health.Value = 0
	}

	// Добавляем или сбрасываем компонент "вспышки"
	if isEnemy {
		ecs.DamageFlashes[entityID] = &component.DamageFlash{
			Timer:    0,
			Duration: config.DamageFlashDuration,
		}
	}
}
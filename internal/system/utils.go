// internal/system/utils.go
package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/types"
)

// ApplyDamage наносит урон сущности. Если здоровье падает до 0 или ниже,
// оно просто устанавливается в 0. Основная логика очистки мертвых сущностей
// должна находиться в другом месте (например, в конце кадра), чтобы избежать
// проблем с доступом к уже удаленным компонентам в том же кадре.
func ApplyDamage(ecs *entity.ECS, entityID types.EntityID, damage int) {
	if health, ok := ecs.Healths[entityID]; ok {
		health.Value -= damage
		if health.Value <= 0 {
			health.Value = 0
			// Мы не удаляем компоненты здесь.
			// Логика в game.cleanupDestroyedEntities() или projectile.System
			// позаботится об удалении на основе здоровья или других условий.
		}

		// Добавляем или сбрасываем компонент "вс��ышки"
		if _, isEnemy := ecs.Enemies[entityID]; isEnemy {
			ecs.DamageFlashes[entityID] = &component.DamageFlash{
				Timer:    0,
				Duration: config.DamageFlashDuration,
			}
		}
	}
}

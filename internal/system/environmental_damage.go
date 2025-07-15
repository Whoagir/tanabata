// internal/system/environmental_damage.go
package system

import (
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
	"go-tower-defense/pkg/hexmap"
)

type EnvironmentalDamageSystem struct {
	ecs *entity.ECS
}

func NewEnvironmentalDamageSystem(ecs *entity.ECS) *EnvironmentalDamageSystem {
	return &EnvironmentalDamageSystem{ecs: ecs}
}

func (s *EnvironmentalDamageSystem) Update(deltaTime float64) {
	// --- 1. Собираем информацию об опасных зонах ---

	// Гексы с линиями между добытчиками
	lineHexes := make(map[hexmap.Hex]bool)
	for _, line := range s.ecs.LineRenders {
		tower1, ok1 := s.ecs.Towers[line.Tower1ID]
		tower2, ok2 := s.ecs.Towers[line.Tower2ID]
		if ok1 && ok2 && tower1.Type == config.TowerTypeMiner && tower2.Type == config.TowerTypeMiner {
			for _, hex := range tower1.Hex.LineTo(tower2.Hex) {
				lineHexes[hex] = true
			}
		}
	}

	// Гексы с рудой и её мощностью
	oreHexes := make(map[hexmap.Hex]float64)
	for _, ore := range s.ecs.Ores {
		hex := hexmap.PixelToHex(ore.Position.X, ore.Position.Y, config.HexSize)
		oreHexes[hex] = ore.Power
	}

	// --- 2. Применяем урон к врагам ---

	for id, enemy := range s.ecs.Enemies {
		pos, hasPos := s.ecs.Positions[id]
		if !hasPos {
			continue
		}
		// ИСПРАВЛЕНО: Координаты врага уже в мировом пространстве.
		// Раньше здесь была ошибка с вычитанием размеров экрана.
		enemyHex := hexmap.PixelToHex(pos.X, pos.Y, config.HexSize)

		// --- Логика урона от руды (исправлена) ---
		if orePower, isOnOre := oreHexes[enemyHex]; isOnOre {
			if enemy.OreDamageCooldown > 0 {
				enemy.OreDamageCooldown -= deltaTime
			}
			if enemy.OreDamageCooldown <= 0 {
				// Формула: (Базовый урон * Мощность руды) / Тики в секунду
				damagePerSecond := config.OreDamagePerSecond * orePower
				damagePerTick := damagePerSecond / config.OreDamageTicksPerSecond
				damage := int(damagePerTick)
				if damage < 1 {
					damage = 1 // Минимальный урон - 1
				}
				ApplyDamage(s.ecs, id, damage, defs.AttackPure)
				enemy.OreDamageCooldown = 1.0 / config.OreDamageTicksPerSecond
			}
		}

		// --- Логика урона от линий ---
		if _, isOnLine := lineHexes[enemyHex]; isOnLine {
			if enemy.LineDamageCooldown > 0 {
				enemy.LineDamageCooldown -= deltaTime
			}
			if enemy.LineDamageCooldown <= 0 {
				// ОБНОВЛЕНО: Используем LineDamagePerSecond из конфига
				damagePerSecond := config.LineDamagePerSecond
				damagePerTick := damagePerSecond / config.LineDamageTicksPerSecond
				damage := int(damagePerTick)
				if damage < 1 {
					damage = 1 // Минимальный урон
				}
				ApplyDamage(s.ecs, id, damage, defs.AttackPure)
				enemy.LineDamageCooldown = 1.0 / config.LineDamageTicksPerSecond
			}
		}
	}
}
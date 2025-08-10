// internal/system/volcano_system.go
package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/types"
	"go-tower-defense/pkg/hexmap"
	"image/color"
	"math/rand"
)

const volcanoTickRate = 4.0 // 4 тика в секунду

// VolcanoSystem управляет башнями "Вулкан"
type VolcanoSystem struct {
	ecs               *entity.ECS
	powerSourceFinder func(towerID types.EntityID) []types.EntityID
}

func NewVolcanoSystem(ecs *entity.ECS, finder func(towerID types.EntityID) []types.EntityID) *VolcanoSystem {
	return &VolcanoSystem{
		ecs:               ecs,
		powerSourceFinder: finder,
	}
}

func (s *VolcanoSystem) Update(deltaTime float64) {
	for id, tower := range s.ecs.Towers {
		if tower.DefID != "TOWER_VOLCANO" || !tower.IsActive {
			continue
		}

		aura, ok := s.ecs.VolcanoAuras[id]
		if !ok {
			aura = &component.VolcanoAura{}
			s.ecs.VolcanoAuras[id] = aura
		}

		aura.TickTimer -= deltaTime
		if aura.TickTimer > 0 {
			continue
		}
		aura.TickTimer = 1.0 / volcanoTickRate

		combat, ok := s.ecs.Combats[id]
		if !ok {
			continue
		}

		powerSources := s.powerSourceFinder(id)
		if len(powerSources) == 0 {
			continue
		}

		var totalReserve float64
		for _, sourceID := range powerSources {
			if ore, ok := s.ecs.Ores[sourceID]; ok {
				totalReserve += ore.CurrentReserve
			}
		}

		tickCost := combat.ShotCost / 4.0
		if totalReserve < tickCost {
			continue
		}

		// --- ИСПРАВЛЕННАЯ ЛОГИКА ПОИСКА ЦЕЛЕЙ ---
		targets := make([]types.EntityID, 0)
		towerHex := tower.Hex // Используем гекс башни

		for enemyID, enemyPos := range s.ecs.Positions {
			if _, isEnemy := s.ecs.Enemies[enemyID]; !isEnemy {
				continue
			}
			if health, hasHealth := s.ecs.Healths[enemyID]; !hasHealth || health.Value <= 0 {
				continue
			}

			// Конвертируем позицию врага в гекс и считаем дистанцию
			enemyHex := hexmap.PixelToHex(enemyPos.X, enemyPos.Y, float64(config.HexSize))
			if towerHex.Distance(enemyHex) <= combat.Range {
				targets = append(targets, enemyID)
			}
		}
		// --- КОНЕЦ ИСПРАВЛЕННОЙ ЛОГИКИ ---

		if len(targets) > 0 {
			availableSources := []types.EntityID{}
			for _, sourceID := range powerSources {
				if ore, ok := s.ecs.Ores[sourceID]; ok && ore.CurrentReserve > 0 {
					availableSources = append(availableSources, sourceID)
				}
			}
			if len(availableSources) > 0 {
				chosenSourceID := availableSources[rand.Intn(len(availableSources))]
				chosenOre := s.ecs.Ores[chosenSourceID]
				if chosenOre.CurrentReserve >= tickCost {
					chosenOre.CurrentReserve -= tickCost
				} else {
					chosenOre.CurrentReserve = 0
				}
			}

			towerDef := defs.TowerDefs[tower.DefID]
			tickDamage := towerDef.Combat.Damage / 4
			if tickDamage < 1 {
				tickDamage = 1
			}

			for _, targetID := range targets {
				ApplyDamage(s.ecs, targetID, tickDamage, combat.Attack.DamageType)

				if enemyRenderable, ok := s.ecs.Renderables[targetID]; ok {
					if enemyPos, ok := s.ecs.Positions[targetID]; ok {
						effectID := s.ecs.NewEntity()
						s.ecs.VolcanoEffects[effectID] = &component.VolcanoEffect{
							X:         enemyPos.X,
							Y:         enemyPos.Y,
							Z:         float64(enemyRenderable.Radius * config.CoordScale),
							MaxRadius: float64(enemyRenderable.Radius * 1.5),
							Duration:  0.25,
							Color:     color.RGBA{R: 255, G: 69, B: 0, A: 255},
						}
					}
				}
			}
		}
	}
}

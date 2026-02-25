package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/types"
	"image/color"
	"math"
	"math/rand"

	rl "github.com/gen2brain/raylib-go/raylib"
)

const beaconTickRate = 24.0 // 24 раза в секунду

// BeaconSystem управляет башнями "Маяк".
type BeaconSystem struct {
	ecs               *entity.ECS
	powerSourceFinder func(towerID types.EntityID) []types.EntityID
}

// NewBeaconSystem создает новую систему для маяков.
func NewBeaconSystem(ecs *entity.ECS, finder func(towerID types.EntityID) []types.EntityID) *BeaconSystem {
	return &BeaconSystem{
		ecs:               ecs,
		powerSourceFinder: finder,
	}
}

// Update обновляет состояние всех маяков.
func (s *BeaconSystem) Update(deltaTime float64) {
	for id, tower := range s.ecs.Towers {
		if tower.DefID != "TOWER_LIGHTHOUSE" || !tower.IsActive {
			if _, hasSector := s.ecs.BeaconAttackSectors[id]; hasSector {
				s.ecs.BeaconAttackSectors[id].IsVisible = false
			}
			continue
		}

		towerDef := defs.TowerDefs[tower.DefID]
		combat := s.ecs.Combats[id]

		beacon, ok := s.ecs.Beacons[id]
		if !ok {
			beacon = &component.Beacon{
				RotationSpeed: towerDef.Combat.Attack.Params.RotationSpeed,
				ArcAngle:      towerDef.Combat.Attack.Params.ArcAngle * rl.Deg2rad, // Конвертируем градусы в радианы
			}
			s.ecs.Beacons[id] = beacon
		}

		sector, ok := s.ecs.BeaconAttackSectors[id]
		if !ok {
			sector = &component.BeaconAttackSector{}
			s.ecs.BeaconAttackSectors[id] = sector
		}
		sector.IsVisible = true
		sector.Range = float32(combat.Range)
		sector.Arc = beacon.ArcAngle
		sector.Angle = beacon.CurrentAngle + math.Pi // <-- КОРРЕКЦИЯ УГЛА

		beacon.CurrentAngle += beacon.RotationSpeed * deltaTime
		if beacon.CurrentAngle > 2*math.Pi {
			beacon.CurrentAngle -= 2 * math.Pi
		}

		beacon.TickTimer -= deltaTime
		if beacon.TickTimer > 0 {
			continue
		}
		beacon.TickTimer = 1.0 / beaconTickRate

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

		tickCost := combat.ShotCost / beaconTickRate
		if totalReserve < tickCost {
			continue
		}

		targets := s.findTargetsInSector(id, tower, beacon, combat)
		if len(targets) == 0 {
			continue
		}

		s.spendPower(powerSources, tickCost)

		// Урон в 4 раза больше базового, но распределен по тикам
		tickDamage := (float64(towerDef.Combat.Damage) * 4) / beaconTickRate
		if tickDamage < 1 {
			tickDamage = 1
		}
		for _, targetID := range targets {
			ApplyDamage(s.ecs, targetID, int(tickDamage), combat.Attack.DamageType)

			// Создаем белый визуальный эффект на враге
			if enemyRenderable, ok := s.ecs.Renderables[targetID]; ok {
				if enemyPos, ok := s.ecs.Positions[targetID]; ok {
					effectID := s.ecs.NewEntity()
					s.ecs.VolcanoEffects[effectID] = &component.VolcanoEffect{
						X:         enemyPos.X,
						Y:         enemyPos.Y,
						Z:         float64(enemyRenderable.Radius * config.CoordScale),
						MaxRadius: float64(enemyRenderable.Radius * 1.5),
						Duration:  0.25, // Длительность равна тику
						Color:     color.RGBA{R: 255, G: 255, B: 224, A: 255}, // Бело-желтый
					}
				}
			}
		}
	}
}

// isPointInTriangle проверяет, находится ли точка (px, py) внутри треугольника,
// определенного вершинами a, b, и c, используя барицентрические координаты.
func isPointInTriangle(px, py, ax, ay, bx, by, cx, cy float64) bool {
	// Вычисляем векторы
	v0x, v0y := cx-ax, cy-ay
	v1x, v1y := bx-ax, by-ay
	v2x, v2y := px-ax, py-ay

	// Вычисляем скалярные произведения
	dot00 := v0x*v0x + v0y*v0y
	dot01 := v0x*v1x + v0y*v1y
	dot02 := v0x*v2x + v0y*v2y
	dot11 := v1x*v1x + v1y*v1y
	dot12 := v1x*v2x + v1y*v2y

	// Вычисляем барицентрические координаты
	invDenom := 1 / (dot00*dot11 - dot01*dot01)
	u := (dot11*dot02 - dot01*dot12) * invDenom
	v := (dot00*dot12 - dot01*dot02) * invDenom

	// Проверяем, находится ли точка внутри треугольника
	return (u >= 0) && (v >= 0) && (u+v < 1)
}

func (s *BeaconSystem) findTargetsInSector(towerID types.EntityID, tower *component.Tower, beacon *component.Beacon, combat *component.Combat) []types.EntityID {
	targets := make([]types.EntityID, 0)

	// Получаем позицию башни из ее гекса - это правильный способ
	ax, ay := tower.Hex.ToPixel(float64(config.HexSize))

	// Вершины B и C - это концы дуги сектора
	rangePixels := float64(combat.Range) * config.HexSize
	startAngle := beacon.CurrentAngle - beacon.ArcAngle/2
	endAngle := beacon.CurrentAngle + beacon.ArcAngle/2

	bx := ax + rangePixels*math.Cos(startAngle)
	by := ay + rangePixels*math.Sin(startAngle)
	cx := ax + rangePixels*math.Cos(endAngle)
	cy := ay + rangePixels*math.Sin(endAngle)

	for enemyID, enemyPos := range s.ecs.Positions {
		if _, isEnemy := s.ecs.Enemies[enemyID]; !isEnemy {
			continue
		}
		if s.ecs.Healths[enemyID].Value <= 0 {
			continue
		}

		// Проверяем, находится ли враг внутри треугольника атаки
		if isPointInTriangle(enemyPos.X, enemyPos.Y, ax, ay, bx, by, cx, cy) {
			targets = append(targets, enemyID)
		}
	}
	return targets
}

func (s *BeaconSystem) spendPower(powerSources []types.EntityID, cost float64) {
	availableSources := []types.EntityID{}
	for _, sourceID := range powerSources {
		if ore, ok := s.ecs.Ores[sourceID]; ok && ore.CurrentReserve > 0 {
			availableSources = append(availableSources, sourceID)
		}
	}
	if len(availableSources) > 0 {
		chosenSourceID := availableSources[rand.Intn(len(availableSources))]
		chosenOre := s.ecs.Ores[chosenSourceID]
		if chosenOre.CurrentReserve >= cost {
			chosenOre.CurrentReserve -= cost
		} else {
			chosenOre.CurrentReserve = 0
		}
	}
}

// internal/app/tower_management.go
package app

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/event"
	"go-tower-defense/internal/types"
	"go-tower-defense/pkg/hexmap"
	"image/color"
	"math/rand"
)

// PlaceTower attempts to place a tower at the given hex.
func (g *Game) PlaceTower(hex hexmap.Hex) bool {
	if !g.canPlaceTower(hex) {
		return false
	}

	id := g.createTowerEntity(hex)

	tile := g.HexMap.Tiles[hex]
	g.HexMap.Tiles[hex] = hexmap.Tile{Passable: false, CanPlaceTower: tile.CanPlaceTower}
	g.towersBuilt++

	g.addTowerToEnergyNetwork(id)

	g.EventDispatcher.Dispatch(event.Event{Type: event.TowerPlaced, Data: hex})

	if g.towersBuilt >= config.MaxTowersInBuildPhase {
		g.StateSystem.SwitchToWaveState()
	}
	return true
}

// RemoveTower removes a tower from the given hex.
func (g *Game) RemoveTower(hex hexmap.Hex) bool {
	if g.ECS.GameState != component.BuildState {
		return false
	}

	var towerIDToRemove types.EntityID
	for id, tower := range g.ECS.Towers {
		if tower.Hex == hex {
			towerIDToRemove = id
			break
		}
	}

	if towerIDToRemove != 0 {
		g.deleteTowerEntity(towerIDToRemove)

		if tile, exists := g.HexMap.Tiles[hex]; exists {
			tile.Passable = true
			g.HexMap.Tiles[hex] = tile
		}

		g.handleTowerRemoval(towerIDToRemove)

		g.EventDispatcher.Dispatch(event.Event{Type: event.TowerRemoved, Data: hex})
		return true
	}
	return false
}

func (g *Game) canPlaceTower(hex hexmap.Hex) bool {
	if g.ECS.GameState != component.BuildState || g.towersBuilt >= config.MaxTowersInBuildPhase {
		return false
	}

	tile, exists := g.HexMap.Tiles[hex]
	if !exists || !tile.Passable || !tile.CanPlaceTower {
		return false
	}

	for id, pos := range g.ECS.Positions {
		if _, hasTower := g.ECS.Towers[id]; hasTower {
			px, py := hex.ToPixel(config.HexSize)
			px += float64(config.ScreenWidth) / 2
			py += float64(config.ScreenHeight) / 2
			if pos.X == px && pos.Y == py {
				return false
			}
		}
	}

	if g.isPathBlockedBy(hex) {
		return false
	}

	return true
}

func (g *Game) isPathBlockedBy(hex hexmap.Hex) bool {
	originalTile := g.HexMap.Tiles[hex]
	g.HexMap.Tiles[hex] = hexmap.Tile{Passable: false, CanPlaceTower: originalTile.CanPlaceTower}
	defer func() {
		g.HexMap.Tiles[hex] = originalTile
	}()

	current := g.HexMap.Entry
	for _, cp := range g.HexMap.Checkpoints {
		if path := hexmap.AStar(current, cp, g.HexMap); path == nil {
			return true
		}
		current = cp
	}

	if path := hexmap.AStar(current, g.HexMap.Exit, g.HexMap); path == nil {
		return true
	}

	return false
}

func (g *Game) createTowerEntity(hex hexmap.Hex) types.EntityID {
	id := g.ECS.NewEntity()
	px, py := hex.ToPixel(config.HexSize)
	px += float64(config.ScreenWidth) / 2
	py += float64(config.ScreenHeight) / 2
	g.ECS.Positions[id] = &component.Position{X: px, Y: py}

	towerType := g.determineTowerType()

	g.ECS.Towers[id] = &component.Tower{
		Type:     towerType,
		Range:    config.TowerRange,
		Hex:      hex,
		IsActive: false,
	}

	if towerType >= 0 && towerType < config.TowerTypeMiner {
		g.ECS.Combats[id] = &component.Combat{
			FireRate:     config.TowerFireRate[towerType],
			FireCooldown: 0,
			Range:        config.TowerRange,
			ShotCost:     config.TowerShotCost,
		}
		_ = g.ECS.Combats[id].ShotCost // Эта строка заставит IDE "увидеть" поле
	}

	var c color.RGBA
	if towerType >= 0 && towerType < len(config.TowerColors)-1 {
		c = config.TowerColors[towerType]
	} else {
		c = config.TowerColors[len(config.TowerColors)-1]
	}

	g.ECS.Renderables[id] = &component.Renderable{
		Color:     c,
		Radius:    float32(config.HexSize * config.TowerRadiusFactor),
		HasStroke: true,
	}
	return id
}

func (g *Game) deleteTowerEntity(id types.EntityID) {
	delete(g.ECS.Positions, id)
	delete(g.ECS.Towers, id)
	delete(g.ECS.Combats, id)
	delete(g.ECS.Renderables, id)

	linesToRemove := []types.EntityID{}
	for lineID, line := range g.ECS.LineRenders {
		if line.Tower1ID == id || line.Tower2ID == id {
			linesToRemove = append(linesToRemove, lineID)
		}
	}
	for _, lineID := range linesToRemove {
		delete(g.ECS.LineRenders, lineID)
	}
}

func (g *Game) determineTowerType() int {
	if g.towersBuilt == 0 {
		return rand.Intn(4)
	}
	if g.towersBuilt == 1 {
		return config.TowerTypeMiner
	}
	return config.TowerTypeWall
}

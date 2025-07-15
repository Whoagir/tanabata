// internal/app/tower_management.go
package app

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/event"
	"go-tower-defense/internal/types"
	"go-tower-defense/pkg/hexmap"
	"log"
	"math/rand"
)

// PlaceTower attempts to place a tower at the given hex.
func (g *Game) PlaceTower(hex hexmap.Hex) bool {
	if !g.canPlaceTower(hex) {
		return false
	}

	towerID := g.determineTowerID()
	if towerID == "" {
		log.Println("Could not determine tower type to place.")
		return false
	}

	id := g.createTowerEntity(hex, towerID)

	tile := g.HexMap.Tiles[hex]
	g.HexMap.Tiles[hex] = hexmap.Tile{Passable: false, CanPlaceTower: tile.CanPlaceTower}

	// Only increment tower count and check for wave start in normal mode
	if g.DebugTowerType == config.TowerTypeNone {
		g.towersBuilt++
		if g.towersBuilt >= config.MaxTowersInBuildPhase {
			g.StateSystem.SwitchToWaveState()
		}
	} else {
		// Reset debug mode after placing the tower
		g.DebugTowerType = config.TowerTypeNone
	}

	g.addTowerToEnergyNetwork(id)
	g.EventDispatcher.Dispatch(event.Event{Type: event.TowerPlaced, Data: hex})

	return true
}

// RemoveTower removes a tower from the given hex.
func (g *Game) RemoveTower(hex hexmap.Hex) bool {
	if g.ECS.GameState != component.BuildState {
		return false
	}

	var towerIDToRemove types.EntityID
	var towerToRemove *component.Tower
	for id, tower := range g.ECS.Towers {
		if tower.Hex == hex {
			towerIDToRemove = id
			towerToRemove = tower
			break
		}
	}

	if towerIDToRemove != 0 {
		// Get neighbors before deleting the entity
		neighbors := g.findPotentialNeighbors(towerToRemove.Hex, towerToRemove.Type)

		// Delete the entity and its direct connections
		g.deleteTowerEntity(towerIDToRemove)

		// Now, handle the network update for the neighbors
		g.handleTowerRemoval(neighbors)

		if tile, exists := g.HexMap.Tiles[hex]; exists {
			tile.Passable = true
			g.HexMap.Tiles[hex] = tile
		}

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

func (g *Game) createTowerEntity(hex hexmap.Hex, towerDefID string) types.EntityID {
	def, ok := defs.TowerLibrary[towerDefID]
	if !ok {
		log.Printf("Error: Tower definition not found for ID: %s", towerDefID)
		return 0
	}

	id := g.ECS.NewEntity()
	px, py := hex.ToPixel(config.HexSize)
	px += float64(config.ScreenWidth) / 2
	py += float64(config.ScreenHeight) / 2
	g.ECS.Positions[id] = &component.Position{X: px, Y: py}

	// The old numeric type is now a string ID, but we still need the numeric one for some legacy logic.
	// We'll need to refactor this away later. For now, we map it.
	numericType := g.mapTowerIDToNumericType(def.ID)

	g.ECS.Towers[id] = &component.Tower{
		Type:     numericType, // TODO: Refactor to use string ID or defs.TowerType
		Hex:      hex,
		IsActive: false,
	}

	if def.Type == defs.TowerTypeAttack {
		g.ECS.Combats[id] = &component.Combat{
			FireRate:     def.Combat.FireRate,
			FireCooldown: 0,
			Range:        def.Combat.Range,
			ShotCost:     def.Combat.ShotCost,
			AttackType:   def.Combat.AttackType,
		}
	}

	g.ECS.Renderables[id] = &component.Renderable{
		Color:     def.Visuals.Color,
		Radius:    float32(config.HexSize * def.Visuals.RadiusFactor),
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

func (g *Game) determineTowerID() string {
	// Handle debug tower placement
	if g.DebugTowerType != config.TowerTypeNone {
		switch g.DebugTowerType {
		case config.TowerTypeRed: // Represents any random attacker for debug
			attackerIDs := []string{"TOWER_RED", "TOWER_GREEN", "TOWER_BLUE", "TOWER_PURPLE"}
			return attackerIDs[rand.Intn(len(attackerIDs))]
		case config.TowerTypeMiner:
			return "TOWER_MINER"
		case config.TowerTypeWall:
			return "TOWER_WALL"
		}
	}

	// Standard tower placement logic based on the current wave number
	waveMod10 := (g.Wave - 1) % 10
	positionInBlock := g.towersBuilt

	// Waves 1-4, 11-14, etc.
	if waveMod10 < 4 {
		// Pattern: A, B, D, D, D
		switch positionInBlock {
		case 0: // Attacker
			attackerIDs := []string{"TOWER_RED", "TOWER_GREEN", "TOWER_BLUE", "TOWER_PURPLE"}
			return attackerIDs[rand.Intn(len(attackerIDs))]
		case 1: // Miner
			return "TOWER_MINER"
		default: // Wall (positions 2, 3, 4)
			return "TOWER_WALL"
		}
	} else {
		// Pattern for waves 5-10, 15-20, etc.: A, A, D, D, D
		switch positionInBlock {
		case 0, 1: // Attacker
			attackerIDs := []string{"TOWER_RED", "TOWER_GREEN", "TOWER_BLUE", "TOWER_PURPLE"}
			return attackerIDs[rand.Intn(len(attackerIDs))]
		default: // Wall (positions 2, 3, 4)
			return "TOWER_WALL"
		}
	}
}

func (g *Game) createPermanentWall(hex hexmap.Hex) {
	id := g.createTowerEntity(hex, "TOWER_WALL")
	if id == 0 {
		return // Failed to create wall
	}
	// Mark the tile as occupied
	if tile, exists := g.HexMap.Tiles[hex]; exists {
		tile.Passable = false
		g.HexMap.Tiles[hex] = tile
	}
}

// canPlaceWall checks if a wall can be placed at a given hex.
func (g *Game) canPlaceWall(hex hexmap.Hex) bool {
	tile, exists := g.HexMap.Tiles[hex]
	if !exists || !tile.Passable || !tile.CanPlaceTower {
		return false
	}

	// Check if any other entity is already there
	for _, tower := range g.ECS.Towers {
		if tower.Hex == hex {
			return false
		}
	}

	// Most importantly, check if it blocks the path for creeps
	if g.isPathBlockedBy(hex) {
		return false
	}

	return true
}

// mapTowerIDToNumericType is a temporary helper to bridge the old system with the new.
// TODO: This should be removed once all systems use string IDs or defs.TowerType.
func (g *Game) mapTowerIDToNumericType(id string) int {
	switch id {
	case "TOWER_RED":
		return config.TowerTypeRed
	case "TOWER_GREEN":
		return config.TowerTypeGreen
	case "TOWER_BLUE":
		return config.TowerTypeBlue
	case "TOWER_PURPLE":
		return config.TowerTypePurple
	case "TOWER_MINER":
		return config.TowerTypeMiner
	case "TOWER_WALL":
		return config.TowerTypeWall
	default:
		return config.TowerTypeNone
	}
}

// internal/app/tower_management.go
package app

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/event"
	"go-tower-defense/internal/types"
	"go-tower-defense/internal/utils"
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

	// Запоминаем, был ли это отладочный вызов
	wasDebug := g.DebugTowerID != ""

	id := g.createTowerEntity(hex, towerID)
	tower := g.ECS.Towers[id]
	tower.IsTemporary = true
	towerDef, ok := defs.TowerLibrary[tower.DefID]
	if !ok {
		// This should not happen if determineTowerID is correct
		return false
	}
	if towerDef.Type == defs.TowerTypeMiner {
		tower.IsSelected = true // Шахтеры выбираются автоматически
	}

	tile := g.HexMap.Tiles[hex]
	g.HexMap.Tiles[hex] = hexmap.Tile{Passable: false, CanPlaceTower: tile.CanPlaceTower}

	// Only increment tower count and check for wave start in normal mode
	if !wasDebug {
		g.towersBuilt++
		if g.towersBuilt >= config.MaxTowersInBuildPhase {
			g.ECS.GameState.TowersToKeep = 2                      // Устанавливаем, сколько башен нужно сохранить
			g.ECS.GameState.Phase = component.TowerSelectionState // <-- Переключаемся в режим выбора
		}
	}
	// Сброс g.DebugTowerID теперь происходит в determineTowerID

	g.addTowerToEnergyNetwork(id)
	g.AuraSystem.RecalculateAuras()
	g.EventDispatcher.Dispatch(event.Event{Type: event.TowerPlaced, Data: hex})

	return true
}

// RemoveTower removes a tower from the given hex.
func (g *Game) RemoveTower(hex hexmap.Hex) bool {
	// Удалять можно только в фазе строительства.
	if g.ECS.GameState.Phase != component.BuildState {
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

	// Если башня найдена, проверяем, не временная ли она.
	if towerIDToRemove != 0 {
		// Запрещаем удаление временных башен (в процессе выбора).
		if towerToRemove.IsTemporary {
			return false
		}
		towerDef, ok := defs.TowerLibrary[towerToRemove.DefID]
		if !ok {
			return false
		}

		// Get neighbors before deleting the entity
		neighbors := g.findPotentialNeighbors(towerToRemove.Hex, towerDef.Type)

		// Delete the entity and its direct connections
		g.deleteTowerEntity(towerIDToRemove)

		// Now, handle the network update for the neighbors
		g.handleTowerRemoval(neighbors)
		g.AuraSystem.RecalculateAuras()

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
	if g.ECS.GameState.Phase != component.BuildState || g.towersBuilt >= config.MaxTowersInBuildPhase {
		return false
	}

	tile, exists := g.HexMap.Tiles[hex]
	if !exists || !tile.Passable || !tile.CanPlaceTower {
		return false
	}

	for id, pos := range g.ECS.Positions {
		if _, hasTower := g.ECS.Towers[id]; hasTower {
			px, py := utils.HexToScreen(hex)
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
	px, py := utils.HexToScreen(hex)
	g.ECS.Positions[id] = &component.Position{X: px, Y: py}

	g.ECS.Towers[id] = &component.Tower{
		DefID:         towerDefID, // <-- Сохраняем ID определения
		CraftingLevel: def.CraftingLevel,
		Hex:           hex,
		IsActive:      false,
	}

	if def.Combat != nil {
		combatComponent := &component.Combat{
			FireRate: def.Combat.FireRate,
			Range:    def.Combat.Range,
			ShotCost: def.Combat.ShotCost,
		}
		if def.Combat.Attack != nil {
			combatComponent.Attack = *def.Combat.Attack
		}
		g.ECS.Combats[id] = combatComponent
	}

	if def.Aura != nil {
		g.ECS.Auras[id] = &component.Aura{
			Radius:          def.Aura.Radius,
			SpeedMultiplier: def.Aura.SpeedMultiplier,
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
	if g.DebugTowerID != "" {
		id := g.DebugTowerID
		g.DebugTowerID = "" // Reset debug mode
		return id
	}

	// Standard tower placement logic
	attackerIDs := []string{
		"TA", "TE", "TO", "DE", "NI", "NU", "PO", "PA", "PE",
	}
	waveMod10 := (g.Wave - 1) % 10
	positionInBlock := g.towersBuilt

	if waveMod10 < 4 { // Pattern: B, A, A, A, A
		switch positionInBlock {
		case 0:
			return "TOWER_MINER"
		default:
			return attackerIDs[rand.Intn(len(attackerIDs))]
		}
	} else { // Pattern: A, A, A, A, A
		return attackerIDs[rand.Intn(len(attackerIDs))]
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

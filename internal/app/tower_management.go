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

	g.towersBuilt++
	if g.towersBuilt >= config.MaxTowersInBuildPhase {
		g.ECS.GameState.TowersToKeep = 2                      // Устанавливаем, сколько башен нужно сохранить
		g.ECS.GameState.Phase = component.TowerSelectionState // <-- Переключаемся в режим выбора
	}

	g.addTowerToEnergyNetwork(id)
	g.AuraSystem.RecalculateAuras()
	g.EventDispatcher.Dispatch(event.Event{Type: event.TowerPlaced, Data: hex})

	return true
}

// RemoveTower removes a tower from the given hex.
func (g *Game) RemoveTower(hex hexmap.Hex) bool {
	// Разрешаем удаление в фазах строительства и выбора.
	if g.ECS.GameState.Phase != component.BuildState && g.ECS.GameState.Phase != component.TowerSelectionState {
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
		// Если удаляем временную башню, уменьшаем счетчик построенных.
		if towerToRemove.IsTemporary {
			g.towersBuilt--
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
		Level:         def.Level,
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
	// Новая логика определения башни
	waveMod10 := (g.Wave - 1) % 10
	positionInBlock := g.towersBuilt

	// Специальное правило для Шахтера в начале блока
	if waveMod10 < 4 && positionInBlock == 0 {
		return "TOWER_MINER"
	}

	// Получаем уровень игрока.
	// Так как сущность игрока у нас одна, мы можем просто найти ее.
	var playerLevel int = 1 // Уровень по умолчанию, если что-то пойдет не так
	for _, state := range g.ECS.PlayerState {
		playerLevel = state.Level
		break // Нашли, выходим
	}

	// Получаем соответствующую таблицу выпадения.
	// Если для текущего уровня нет таблицы, пытаемся использовать таблицу более низкого уровня.
	var lootTable defs.LootTable
	found := false
	for level := playerLevel; level >= 1; level-- {
		if table, ok := defs.LootTableLibrary[level]; ok {
			lootTable = table
			found = true
			break
		}
	}

	if !found {
		log.Println("Error: No suitable loot table found for any player level.")
		return "" // Не можем определить башню
	}

	// Используем наш новый сервис для взвешенного выбора
	return g.Rng.ChooseWeighted(lootTable.Entries)
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
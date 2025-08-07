// internal/app/energy_network.go
package app

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/types"
	"go-tower-defense/internal/utils"
	"go-tower-defense/pkg/hexmap"
	pkgRender "go-tower-defense/pkg/render"
	"sort"
)

// energyEdge represents a potential connection in the energy network.
type energyEdge struct {
	Tower1ID types.EntityID
	Tower2ID types.EntityID
	Type1    defs.TowerType
	Type2    defs.TowerType
	Distance float64
}

// calculateEdgeWeight determines the priority of a connection. Lower is better.
func calculateEdgeWeight(type1, type2 defs.TowerType, distance float64) float64 {
	isT1Miner := type1 == defs.TowerTypeMiner
	isT2Miner := type2 == defs.TowerTypeMiner

	// Miner-to-Miner connections are highest priority
	if isT1Miner && isT2Miner {
		return 100 + distance
	}
	// Miner-to-Attacker connections are second priority
	if isT1Miner || isT2Miner {
		return 200 + distance
	}
	// Attacker-to-Attacker connections are lowest priority
	return 300 + distance
}

// sortEnergyEdges provides a deterministic sort for energy edges.
// It sorts by weight first, then by the tower IDs to resolve ties.
func sortEnergyEdges(edges []energyEdge) {
	sort.Slice(edges, func(i, j int) bool {
		edgeA := edges[i]
		edgeB := edges[j]
		weightA := calculateEdgeWeight(edgeA.Type1, edgeA.Type2, edgeA.Distance)
		weightB := calculateEdgeWeight(edgeB.Type1, edgeB.Type2, edgeB.Distance)

		if weightA != weightB {
			return weightA < weightB
		}

		// Tie-breaking logic using tower IDs for determinism.
		// We sort the IDs within each edge to ensure consistency.
		minA, maxA := edgeA.Tower1ID, edgeA.Tower2ID
		if minA > maxA {
			minA, maxA = maxA, minA
		}
		minB, maxB := edgeB.Tower1ID, edgeB.Tower2ID
		if minB > maxB {
			minB, maxB = maxB, minB
		}

		if minA != minB {
			return minA < minB
		}
		return maxA < maxB
	})
}

// rebuildEnergyNetwork orchestrates a full energy network rebuild using Kruskal's algorithm.
// This is expensive and should be used only when necessary (e.g., tower removal).
func (g *Game) rebuildEnergyNetwork() {
	allTowers := g.collectAndResetTowers()
	if len(allTowers) == 0 {
		g.clearAllLines()
		return
	}

	potentiallyActiveTowers := g.getPotentiallyActiveTowers(allTowers)
	possibleEdges := g.collectPossibleEdges(allTowers, potentiallyActiveTowers)

	uf, mstEdges := g.buildMinimumSpanningTree(possibleEdges, potentiallyActiveTowers)

	g.activateNetworkTowers(allTowers, potentiallyActiveTowers, uf)
	g.updateTowerAppearances(allTowers)
	g.rebuildEnergyLines(mstEdges)
}

// addTowerToEnergyNetwork incrementally adds a new tower to the energy network.
// It connects the new tower to the best available active neighbor that doesn't
// form a visual triangle, and then expands the network from that new point.
// This function also handles merging previously disconnected networks.
func (g *Game) addTowerToEnergyNetwork(newTowerID types.EntityID) {
	newTower, exists := g.ECS.Towers[newTowerID]
	if !exists {
		return
	}
	newTowerDef, defExists := defs.TowerDefs[newTower.DefID]
	if !defExists || newTowerDef.Type == defs.TowerTypeWall {
		return // Do nothing for walls or non-existent towers
	}

	// --- Start of interception logic for Miners ---
	if newTowerDef.Type == defs.TowerTypeMiner {
		if g.handleMinerIntercept(newTowerID, newTower) {
			g.expandNetworkFrom(newTowerID)
			return // Interception handled, expansion complete.
		}
	}
	// --- End of interception logic ---

	// 1. Find all possible connections from the new tower to EXISTING ACTIVE towers.
	connections := g.findPossibleConnections(newTowerID, newTower)

	// A new tower can become active if it's a miner on ore (a root) or can connect to the grid.
	isNewRoot := newTowerDef.Type == defs.TowerTypeMiner && g.isOnOre(newTower.Hex)
	if len(connections) == 0 && !isNewRoot {
		g.updateTowerAppearance(newTowerID) // Ensure it's colored as inactive
		return
	}

	// 2. Activate the new tower.
	newTower.IsActive = true
	g.updateTowerAppearance(newTowerID)

	// 3. Connect to neighbors, handling network merges.
	if len(connections) > 0 {
		g.connectToNetworks(newTowerID, connections)
	}

	// 4. Expand the network from the newly activated tower to connect any nearby inactive towers.
	g.expandNetworkFrom(newTowerID)
}

// handleMinerIntercept checks if a new miner tower intercepts an existing miner-to-miner line.
// If it does, it reroutes the line through the new tower. Returns true if an interception occurred.
func (g *Game) handleMinerIntercept(newTowerID types.EntityID, newTower *component.Tower) bool {
	newTowerDef := defs.TowerDefs[newTower.DefID]
	for lineID, line := range g.ECS.LineRenders {
		t1, ok1 := g.ECS.Towers[line.Tower1ID]
		t2, ok2 := g.ECS.Towers[line.Tower2ID]
		if !ok1 || !ok2 {
			continue
		}
		def1, ok1 := defs.TowerDefs[t1.DefID]
		def2, ok2 := defs.TowerDefs[t2.DefID]

		if !ok1 || !ok2 || def1.Type != defs.TowerTypeMiner || def2.Type != defs.TowerTypeMiner {
			continue
		}

		dist12 := t1.Hex.Distance(t2.Hex)
		dist1New := t1.Hex.Distance(newTower.Hex)
		distNew2 := newTower.Hex.Distance(t2.Hex)

		if dist1New > 0 && distNew2 > 0 && dist1New+distNew2 == dist12 {
			// Interception found.
			delete(g.ECS.LineRenders, lineID)
			newTower.IsActive = true
			g.updateTowerAppearance(newTowerID)

			g.createLine(energyEdge{
				Tower1ID: line.Tower1ID, Tower2ID: newTowerID,
				Type1: def1.Type, Type2: newTowerDef.Type,
				Distance: float64(dist1New),
			})
			g.createLine(energyEdge{
				Tower1ID: newTowerID, Tower2ID: line.Tower2ID,
				Type1: newTowerDef.Type, Type2: def2.Type,
				Distance: float64(distNew2),
			})
			return true
		}
	}
	return false
}

// findPossibleConnections finds and sorts all valid connections from a new tower to existing active towers.
func (g *Game) findPossibleConnections(newTowerID types.EntityID, newTower *component.Tower) []energyEdge {
	var connections []energyEdge
	newTowerDef := defs.TowerDefs[newTower.DefID]
	for otherID, otherTower := range g.ECS.Towers {
		if newTowerID == otherID || !otherTower.IsActive {
			continue
		}
		otherTowerDef := defs.TowerDefs[otherTower.DefID]

		distance := newTower.Hex.Distance(otherTower.Hex)
		isNeighbor := distance == 1
		isMinerConnection := newTowerDef.Type == defs.TowerTypeMiner &&
			otherTowerDef.Type == defs.TowerTypeMiner &&
			distance <= config.EnergyTransferRadius &&
			newTower.Hex.IsOnSameLine(otherTower.Hex)

		if isNeighbor || isMinerConnection {
			connections = append(connections, energyEdge{
				Tower1ID: newTowerID, Tower2ID: otherID,
				Type1: newTowerDef.Type, Type2: otherTowerDef.Type,
				Distance: float64(distance),
			})
		}
	}

	sortEnergyEdges(connections)
	return connections
}

// connectToNetworks connects a tower to one or more existing networks, preventing cycles.
func (g *Game) connectToNetworks(towerID types.EntityID, connections []energyEdge) {
	// Build a Union-Find structure to identify the separate networks based on existing lines.
	uf := utils.NewUnionFind()
	for id := range g.ECS.Towers {
		uf.Find(id) // Initialize all towers.
	}
	for _, line := range g.ECS.LineRenders {
		uf.Union(line.Tower1ID, line.Tower2ID)
	}

	adj := g.buildAdjacencyList()
	connectionMade := false

	for _, edge := range connections {
		neighborID := edge.Tower2ID

		// Primary cycle prevention: only connect if the towers are in different components.
		if uf.Find(towerID) != uf.Find(neighborID) {
			// Secondary aesthetic check: avoid creating small, visually cluttered triangles.
			if !g.formsTriangle(towerID, neighborID, adj) {
				g.createLine(edge)
				uf.Union(towerID, neighborID) // Update the UF structure with the new connection.
				connectionMade = true

				// Update adjacency list for subsequent triangle checks in this same operation.
				adj[towerID] = append(adj[towerID], neighborID)
				adj[neighborID] = append(adj[neighborID], towerID)
			}
		}
	}

	// Fallback: if all possible connections form triangles, make the best one
	// that connects to a different component, ignoring the triangle rule.
	if !connectionMade {
		for _, edge := range connections {
			neighborID := edge.Tower2ID
			if uf.Find(towerID) != uf.Find(neighborID) {
				g.createLine(edge)
				// No need to union or update adj here, we're just making one connection.
				break
			}
		}
	}
}

// expandNetworkFrom performs a BFS starting from a newly activated tower
// to activate any other towers that are now reachable.
func (g *Game) expandNetworkFrom(startNode types.EntityID) {
	queue := []types.EntityID{startNode}
	visited := map[types.EntityID]bool{startNode: true}

	// Build adjacency list once to use for all checks.
	adj := g.buildAdjacencyList()

	for len(queue) > 0 {
		currentID := queue[0]
		queue = queue[1:]
		currentTower := g.ECS.Towers[currentID]
		currentTowerDef := defs.TowerDefs[currentTower.DefID]

		// Find all inactive neighbors
		for otherID, otherTower := range g.ECS.Towers {
			otherTowerDef, ok := defs.TowerDefs[otherTower.DefID]
			if !ok {
				continue
			}
			if visited[otherID] || otherTower.IsActive || otherTowerDef.Type == defs.TowerTypeWall {
				continue
			}

			distance := currentTower.Hex.Distance(otherTower.Hex)
			isNeighbor := distance == 1
			isMinerConnection := currentTowerDef.Type == defs.TowerTypeMiner &&
				otherTowerDef.Type == defs.TowerTypeMiner &&
				distance <= config.EnergyTransferRadius &&
				currentTower.Hex.IsOnSameLine(otherTower.Hex)

			if isNeighbor || isMinerConnection {
				// Check for triangles before creating the line
				if !g.formsTriangle(currentID, otherID, adj) {
					// Activate the neighbor, create the line, and add to queue
					otherTower.IsActive = true
					g.updateTowerAppearance(otherID)
					edge := energyEdge{
						Tower1ID: currentID,
						Tower2ID: otherID,
						Type1:    currentTowerDef.Type,
						Type2:    otherTowerDef.Type,
						Distance: float64(distance),
					}
					g.createLine(edge)

					// Update adjacency list for subsequent checks in the same expansion
					adj[currentID] = append(adj[currentID], otherID)
					adj[otherID] = append(adj[otherID], currentID)

					visited[otherID] = true
					queue = append(queue, otherID)
				}
			}
		}
	}
}

// formsTriangle checks if adding an edge between id1 and id2 would create a 3-cycle.
func (g *Game) formsTriangle(id1, id2 types.EntityID, adj map[types.EntityID][]types.EntityID) bool {
	neighbors1, ok1 := adj[id1]
	if !ok1 {
		return false
	}
	neighbors2, ok2 := adj[id2]
	if !ok2 {
		return false
	}

	set1 := make(map[types.EntityID]struct{}, len(neighbors1))
	for _, n := range neighbors1 {
		set1[n] = struct{}{}
	}

	for _, n2 := range neighbors2 {
		if _, exists := set1[n2]; exists {
			// Found a common neighbor that is already connected to both.
			return true
		}
	}

	return false
}

// updateTowerAppearance updates the color of a single tower based on its state.
func (g *Game) updateTowerAppearance(id types.EntityID) {
	tower, ok := g.ECS.Towers[id]
	if !ok {
		return
	}
	render, ok := g.ECS.Renderables[id]
	if !ok {
		return
	}

	def, ok := defs.TowerDefs[tower.DefID]
	if !ok {
		return // Definition not found, do nothing.
	}

	c := def.Visuals.Color
	if def.Type != defs.TowerTypeWall && !tower.IsActive {
		c = pkgRender.DarkenColor(def.Visuals.Color) // Используем затемненный цвет самой башни
	}
	render.Color = c
}

// collectEdgesForNewTower finds all valid connections from a new tower to the existing ones.
func (g *Game) collectEdgesForNewTower(newTower *component.Tower, allTowers map[hexmap.Hex]types.EntityID, potentiallyActive map[types.EntityID]bool) []energyEdge {
	var edges []energyEdge
	newTowerID := allTowers[newTower.Hex]
	newTowerDef := defs.TowerDefs[newTower.DefID]

	for otherHex, otherID := range allTowers {
		if newTowerID == otherID || !potentiallyActive[otherID] {
			continue
		}

		otherTower := g.ECS.Towers[otherID]
		otherTowerDef := defs.TowerDefs[otherTower.DefID]
		distance := newTower.Hex.Distance(otherHex)

		isNeighbor := distance == 1
		isMinerConnection := newTowerDef.Type == defs.TowerTypeMiner &&
			otherTowerDef.Type == defs.TowerTypeMiner &&
			distance <= config.EnergyTransferRadius &&
			newTower.Hex.IsOnSameLine(otherHex) &&
			!g.hasActiveTowerBetween(newTower.Hex, otherHex, allTowers, potentiallyActive)

		if isNeighbor || isMinerConnection {
			edges = append(edges, energyEdge{
				Tower1ID: newTowerID,
				Tower2ID: otherID,
				Type1:    newTowerDef.Type,
				Type2:    otherTowerDef.Type,
				Distance: float64(distance),
			})
		}
	}

	sortEnergyEdges(edges)
	return edges
}

func (g *Game) collectAndResetTowers() map[hexmap.Hex]types.EntityID {
	allTowers := make(map[hexmap.Hex]types.EntityID)
	for id, tower := range g.ECS.Towers {
		allTowers[tower.Hex] = id
		tower.IsActive = false // Reset state
	}
	return allTowers
}

func (g *Game) getPotentiallyActiveTowers(allTowers map[hexmap.Hex]types.EntityID) map[types.EntityID]bool {
	potentiallyActive := make(map[types.EntityID]bool)
	for _, id := range allTowers {
		towerDef, ok := defs.TowerDefs[g.ECS.Towers[id].DefID]
		if ok && towerDef.Type != defs.TowerTypeWall {
			potentiallyActive[id] = true
		}
	}
	return potentiallyActive
}

func (g *Game) collectPossibleEdges(allTowers map[hexmap.Hex]types.EntityID, potentiallyActive map[types.EntityID]bool) []energyEdge {
	var edges []energyEdge
	var activeHexes []hexmap.Hex
	for hex, id := range allTowers {
		if potentiallyActive[id] {
			activeHexes = append(activeHexes, hex)
		}
	}

	for i := 0; i < len(activeHexes); i++ {
		for j := i + 1; j < len(activeHexes); j++ {
			hexA, hexB := activeHexes[i], activeHexes[j]
			idA, idB := allTowers[hexA], allTowers[hexB]
			towerA, towerB := g.ECS.Towers[idA], g.ECS.Towers[idB]
			defA := defs.TowerDefs[towerA.DefID]
			defB := defs.TowerDefs[towerB.DefID]
			distance := hexA.Distance(hexB)

			isNeighbor := distance == 1
			isMinerConnection := defA.Type == defs.TowerTypeMiner &&
				defB.Type == defs.TowerTypeMiner &&
				distance <= config.EnergyTransferRadius &&
				hexA.IsOnSameLine(hexB) &&
				!g.hasActiveTowerBetween(hexA, hexB, allTowers, potentiallyActive)

			if isNeighbor || isMinerConnection {
				edges = append(edges, energyEdge{
					Tower1ID: idA,
					Tower2ID: idB,
					Type1:    defA.Type,
					Type2:    defB.Type,
					Distance: float64(distance),
				})
			}
		}
	}
	return edges
}

func (g *Game) hasActiveTowerBetween(hexA, hexB hexmap.Hex, allTowers map[hexmap.Hex]types.EntityID, potentiallyActive map[types.EntityID]bool) bool {
	line := hexA.LineTo(hexB)
	for i := 1; i < len(line)-1; i++ {
		if id, exists := allTowers[line[i]]; exists && potentiallyActive[id] {
			// Проверяем тип башни, которая стоит на пути
			towerOnPath := g.ECS.Towers[id]
			towerOnPathDef := defs.TowerDefs[towerOnPath.DefID]
			// Линия блокируется ТОЛЬКО если на пути стоит другая башня типа Б (Miner)
			if towerOnPathDef.Type == defs.TowerTypeMiner {
				return true
			}
		}
	}
	return false
}

func (g *Game) buildMinimumSpanningTree(edges []energyEdge, potentiallyActive map[types.EntityID]bool) (*utils.UnionFind, []energyEdge) {
	sortEnergyEdges(edges)

	uf := utils.NewUnionFind()
	for id := range potentiallyActive {
		uf.Find(id)
	}

	var mstEdges []energyEdge
	for _, e := range edges {
		if uf.Find(e.Tower1ID) != uf.Find(e.Tower2ID) {
			uf.Union(e.Tower1ID, e.Tower2ID)
			mstEdges = append(mstEdges, e)
		}
	}
	return uf, mstEdges
}

func (g *Game) activateNetworkTowers(allTowers map[hexmap.Hex]types.EntityID, potentiallyActive map[types.EntityID]bool, uf *utils.UnionFind) {
	energySourceRoots := make(map[types.EntityID]bool)
	for hex, id := range allTowers {
		tower := g.ECS.Towers[id]
		towerDef := defs.TowerDefs[tower.DefID]
		if towerDef.Type == defs.TowerTypeMiner && g.isOnOre(hex) {
			energySourceRoots[uf.Find(id)] = true
		}
	}

	for id := range potentiallyActive {
		if energySourceRoots[uf.Find(id)] {
			g.ECS.Towers[id].IsActive = true
		}
	}
}

func (g *Game) updateTowerAppearances(allTowers map[hexmap.Hex]types.EntityID) {
	for _, id := range allTowers {
		g.updateTowerAppearance(id)
	}
}

func (g *Game) rebuildEnergyLines(mstEdges []energyEdge) {
	g.clearAllLines()
	for _, edge := range mstEdges {
		tower1, ok1 := g.ECS.Towers[edge.Tower1ID]
		tower2, ok2 := g.ECS.Towers[edge.Tower2ID]
		if !ok1 || !ok2 || !tower1.IsActive || !tower2.IsActive {
			continue
		}
		g.createLine(edge)
	}
}

func (g *Game) createLine(edge energyEdge) {
	// У башен нет компонента Position, их позиция определяется гексом.
	// Поэтому мы не можем использовать g.ECS.Positions.
	// Вместо этого, мы должны хранить ID башен и вычислять их позицию в системе рендеринга.
	lineID := g.ECS.NewEntity()
	g.ECS.LineRenders[lineID] = &component.LineRender{
		// StartX, StartY, EndX, EndY больше не нужны, так как мы используем ID
		Color:    config.LineColorRL,
		Tower1ID: edge.Tower1ID,
		Tower2ID: edge.Tower2ID,
	}
}

func (g *Game) clearAllLines() {
	for id := range g.ECS.LineRenders {
		delete(g.ECS.LineRenders, id)
	}
}

func (g *Game) isOnOre(hex hexmap.Hex) bool {
	for _, ore := range g.ECS.Ores {
		// ИСПРАВЛЕНО: Используем правильную функцию для преобразования координат
		oreHex := hexmap.PixelToHex(ore.Position.X, ore.Position.Y, float64(config.HexSize))
		if oreHex == hex {
			return ore.CurrentReserve >= config.OreDepletionThreshold
		}
	}
	return false
}

// handleTowerRemoval orchestrates the reconnection of the energy network after a tower is removed.
// It iteratively finds the single best bridge to build and then re-evaluates the entire
// network state, guaranteeing a cycle-free and complete reconnection.
func (g *Game) handleTowerRemoval(orphanedNeighbors []types.EntityID) {
	// --- 1. Establish Ground Truth: Determine which towers are powered from a source ---
	poweredSet := g.findPoweredTowers()
	for id, tower := range g.ECS.Towers {
		tower.IsActive = poweredSet[id]
	}

	// --- 2. Reconnect Disjoint Active Networks ---
	// This safely merges any separate, but still powered, network components into a single grid.
	g.mergeActiveNetworks()

	// --- 3. Iteratively Connect All Reachable Inactive Components ---
	// This loop ensures that after each new connection is made, the entire network state
	// is re-evaluated before finding the next best connection. This is crucial for preventing cycles.
	for {
		// a. Find all possible bridges in the current state.
		bridges := g.findAllPossibleBridges()
		if len(bridges) == 0 {
			break // No more connections can be made.
		}

		// b. Build a fresh UnionFind for the current network topology to detect cycles.
		uf := utils.NewUnionFind()
		for id := range g.ECS.Towers {
			uf.Find(id)
		}
		for _, line := range g.ECS.LineRenders {
			uf.Union(line.Tower1ID, line.Tower2ID)
		}

		// c. Find the single best bridge that doesn't form a cycle and build it.
		bridgeBuilt := false
		for _, bridge := range bridges {
			if uf.Find(bridge.Tower1ID) != uf.Find(bridge.Tower2ID) {
				g.createLine(bridge)
				bridgeBuilt = true
				break // IMPORTANT: Build only one bridge per iteration.
			}
		}

		if !bridgeBuilt {
			// If no non-cyclic bridges were found among the possibilities, we're done.
			break
		}

		// d. CRITICAL: Re-evaluate the entire power network from scratch.
		// This updates the IsActive status of all towers based on the new connection.
		newPoweredSet := g.findPoweredTowers()
		for id, tower := range g.ECS.Towers {
			tower.IsActive = newPoweredSet[id]
		}
	}

	// --- 4. Final Cleanup ---
	g.cleanupOrphanedLines()
	g.updateAllTowerAppearances()
}

// findAllPossibleBridges collects and sorts all potential connections from any active
// tower to any inactive tower.
func (g *Game) findAllPossibleBridges() []energyEdge {
	var bridges []energyEdge
	activeTowers := g.getActiveTowers()
	inactiveTowers := g.getInactiveTowers()

	if len(activeTowers) == 0 || len(inactiveTowers) == 0 {
		return bridges
	}

	for _, activeID := range activeTowers {
		activeTower := g.ECS.Towers[activeID]
		activeTowerDef := defs.TowerDefs[activeTower.DefID]
		for _, inactiveID := range inactiveTowers {
			inactiveTower := g.ECS.Towers[inactiveID]
			inactiveTowerDef := defs.TowerDefs[inactiveTower.DefID]

			if g.isValidConnection(activeTower, inactiveTower) {
				bridges = append(bridges, energyEdge{
					Tower1ID: activeID,
					Tower2ID: inactiveID,
					Type1:    activeTowerDef.Type,
					Type2:    inactiveTowerDef.Type,
					Distance: float64(activeTower.Hex.Distance(inactiveTower.Hex)),
				})
			}
		}
	}

	sortEnergyEdges(bridges)
	return bridges
}

// getActiveTowers returns a slice of IDs for all towers that are currently active.
func (g *Game) getActiveTowers() []types.EntityID {
	var activeTowers []types.EntityID
	for id, tower := range g.ECS.Towers {
		if tower.IsActive {
			activeTowers = append(activeTowers, id)
		}
	}
	return activeTowers
}

// updateAllTowerAppearances iterates through all towers and updates their color.
func (g *Game) updateAllTowerAppearances() {
	for id := range g.ECS.Towers {
		g.updateTowerAppearance(id)
	}
}

// getInactiveTowers returns a slice of IDs for all towers that are currently inactive.
func (g *Game) getInactiveTowers() []types.EntityID {
	var inactiveTowers []types.EntityID
	for id, tower := range g.ECS.Towers {
		if !tower.IsActive {
			inactiveTowers = append(inactiveTowers, id)
		}
	}
	return inactiveTowers
}

// mergeActiveNetworks finds and connects any separate, active network components using a
// Kruskal-like algorithm to prevent cycles.
func (g *Game) mergeActiveNetworks() {
	activeTowers := make(map[types.EntityID]*component.Tower)
	for id, tower := range g.ECS.Towers {
		if tower.IsActive {
			activeTowers[id] = tower
		}
	}

	// If there's 1 or 0 active towers, there's nothing to merge.
	if len(activeTowers) <= 1 {
		return
	}

	// 1. Initialize Union-Find to determine the initial set of disconnected components.
	uf := utils.NewUnionFind()
	for id := range activeTowers {
		uf.Find(id)
	}
	for _, line := range g.ECS.LineRenders {
		// Only consider lines between two active towers.
		if _, ok1 := activeTowers[line.Tower1ID]; ok1 {
			if _, ok2 := activeTowers[line.Tower2ID]; ok2 {
				uf.Union(line.Tower1ID, line.Tower2ID)
			}
		}
	}

	// 2. Collect all possible "bridge" edges between different active components.
	var bridgeEdges []energyEdge
	activeTowerIDs := make([]types.EntityID, 0, len(activeTowers))
	for id := range activeTowers {
		activeTowerIDs = append(activeTowerIDs, id)
	}

	for i := 0; i < len(activeTowerIDs); i++ {
		for j := i + 1; j < len(activeTowerIDs); j++ {
			id1, id2 := activeTowerIDs[i], activeTowerIDs[j]
			// If they are already connected, skip.
			if uf.Find(id1) == uf.Find(id2) {
				continue
			}

			tower1, tower2 := activeTowers[id1], activeTowers[id2]
			def1 := defs.TowerDefs[tower1.DefID]
			def2 := defs.TowerDefs[tower2.DefID]
			if g.isValidConnection(tower1, tower2) {
				bridgeEdges = append(bridgeEdges, energyEdge{
					Tower1ID: id1,
					Tower2ID: id2,
					Type1:    def1.Type,
					Type2:    def2.Type,
					Distance: float64(tower1.Hex.Distance(tower2.Hex)),
				})
			}
		}
	}

	sortEnergyEdges(bridgeEdges)

	// 4. Add the best bridges that don't form a cycle.
	for _, edge := range bridgeEdges {
		// The Union-Find structure is the sole authority on cycle prevention.
		// If they are not in the same set, adding this edge will not create a cycle.
		if uf.Find(edge.Tower1ID) != uf.Find(edge.Tower2ID) {
			g.createLine(edge)
			uf.Union(edge.Tower1ID, edge.Tower2ID)
		}
	}
}

// isValidConnection checks if two towers can be connected according to game rules.
func (g *Game) isValidConnection(tower1, tower2 *component.Tower) bool {
	def1, ok1 := defs.TowerDefs[tower1.DefID]
	def2, ok2 := defs.TowerDefs[tower2.DefID]
	if !ok1 || !ok2 {
		return false
	}
	// Стены не могут быть частью энергосети
	if def1.Type == defs.TowerTypeWall || def2.Type == defs.TowerTypeWall {
		return false
	}

	distance := tower1.Hex.Distance(tower2.Hex)
	isAdjacent := distance == 1
	isMinerConnection := def1.Type == defs.TowerTypeMiner &&
		def2.Type == defs.TowerTypeMiner &&
		distance <= config.EnergyTransferRadius &&
		tower1.Hex.IsOnSameLine(tower2.Hex)
	return isAdjacent || isMinerConnection
}

// findPotentialNeighbors finds all towers that could have been connected to a tower
// at a given hex with a given type.
func (g *Game) findPotentialNeighbors(removedTowerHex hexmap.Hex, removedTowerType defs.TowerType) []types.EntityID {
	potentialNeighborIDs := []types.EntityID{}
	for otherID, otherTower := range g.ECS.Towers {
		otherTowerDef, ok := defs.TowerDefs[otherTower.DefID]
		if !ok {
			continue
		}
		distance := removedTowerHex.Distance(otherTower.Hex)
		isAdjacent := distance == 1

		isMinerConnection := removedTowerType == defs.TowerTypeMiner &&
			otherTowerDef.Type == defs.TowerTypeMiner &&
			distance <= config.EnergyTransferRadius &&
			removedTowerHex.IsOnSameLine(otherTower.Hex)

		if isAdjacent || isMinerConnection {
			potentialNeighborIDs = append(potentialNeighborIDs, otherID)
		}
	}
	return potentialNeighborIDs
}

// findPoweredTowers performs a BFS from all energy sources to find all towers
// that should remain active.
func (g *Game) findPoweredTowers() map[types.EntityID]bool {
	powered := make(map[types.EntityID]bool)
	queue := []types.EntityID{}

	// Find all root energy sources and add them to the queue.
	for id, tower := range g.ECS.Towers {
		towerDef, ok := defs.TowerDefs[tower.DefID]
		if !ok {
			continue
		}
		if towerDef.Type == defs.TowerTypeMiner && g.isOnOre(tower.Hex) {
			queue = append(queue, id)
			powered[id] = true
		}
	}

	// Build an adjacency list for quick lookups during traversal.
	adj := g.buildAdjacencyList()

	head := 0
	for head < len(queue) {
		currentID := queue[head]
		head++

		// Look at all neighbors of the current tower.
		if neighbors, ok := adj[currentID]; ok {
			for _, neighborID := range neighbors {
				if !powered[neighborID] {
					powered[neighborID] = true
					queue = append(queue, neighborID)
				}
			}
		}
	}

	return powered
}

// buildAdjacencyList creates a map of tower connections for graph traversal.
func (g *Game) buildAdjacencyList() map[types.EntityID][]types.EntityID {
	adj := make(map[types.EntityID][]types.EntityID)
	for _, line := range g.ECS.LineRenders {
		// Ensure both towers still exist before creating the edge
		if _, ok1 := g.ECS.Towers[line.Tower1ID]; ok1 {
			if _, ok2 := g.ECS.Towers[line.Tower2ID]; ok2 {
				adj[line.Tower1ID] = append(adj[line.Tower1ID], line.Tower2ID)
				adj[line.Tower2ID] = append(adj[line.Tower2ID], line.Tower1ID)
			}
		}
	}
	return adj
}

// cleanupOrphanedLines removes any lines connected to an inactive tower.
func (g *Game) cleanupOrphanedLines() {
	linesToRemove := []types.EntityID{}
	for lineID, line := range g.ECS.LineRenders {
		tower1, ok1 := g.ECS.Towers[line.Tower1ID]
		tower2, ok2 := g.ECS.Towers[line.Tower2ID]
		if !ok1 || !ok2 || !tower1.IsActive || !tower2.IsActive {
			linesToRemove = append(linesToRemove, lineID)
		}
	}
	for _, lineID := range linesToRemove {
		delete(g.ECS.LineRenders, lineID)
	}
}

// getAllTowerIDs returns a slice of all tower IDs.
func (g *Game) getAllTowerIDs() []types.EntityID {
	ids := make([]types.EntityID, 0, len(g.ECS.Towers))
	for id := range g.ECS.Towers {
		ids = append(ids, id)
	}
	return ids
}

// getAllTowersByHex returns a map of all towers keyed by their hex coordinates.
func (g *Game) getAllTowersByHex() map[hexmap.Hex]types.EntityID {
	towers := make(map[hexmap.Hex]types.EntityID, len(g.ECS.Towers))
	for id, tower := range g.ECS.Towers {
		towers[tower.Hex] = id
	}
	return towers
}

// FindPowerSourcesForTower traverses the energy network from a given tower
// to find all connected ore entities that act as power sources.
func (g *Game) FindPowerSourcesForTower(startNode types.EntityID) []types.EntityID {
	var sources []types.EntityID
	if _, exists := g.ECS.Towers[startNode]; !exists {
		return sources
	}

	visited := make(map[types.EntityID]bool)
	queue := []types.EntityID{startNode}
	visited[startNode] = true

	adj := g.buildAdjacencyList()
	head := 0

	for head < len(queue) {
		currentID := queue[head]
		head++

		tower := g.ECS.Towers[currentID]
		towerDef := defs.TowerDefs[tower.DefID]
		if towerDef.Type == defs.TowerTypeMiner && g.isOnOre(tower.Hex) {
			// This tower is a miner on an ore vein, find the corresponding ore entity.
			for oreID, ore := range g.ECS.Ores {
				oreHex := hexmap.PixelToHex(ore.Position.X, ore.Position.Y, float64(config.HexSize)) // ИСПРАВЛЕНО
				if oreHex == tower.Hex {
					sources = append(sources, oreID)
					break
				}
			}
		}

		if neighbors, ok := adj[currentID]; ok {
			for _, neighborID := range neighbors {
				if !visited[neighborID] {
					visited[neighborID] = true
					queue = append(queue, neighborID)
				}
			}
		}
	}
	return sources
}
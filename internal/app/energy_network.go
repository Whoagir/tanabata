// internal/app/energy_network.go
package app

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/types"
	"go-tower-defense/pkg/hexmap"
	pkgRender "go-tower-defense/pkg/render"
	"go-tower-defense/pkg/utils"
	"image/color"
	"sort"
)

// energyEdge represents a potential connection in the energy network.
type energyEdge struct {
	Tower1ID types.EntityID
	Tower2ID types.EntityID
	Type1    int
	Type2    int
	Distance float64
}

// calculateEdgeWeight determines the priority of a connection. Lower is better.
func calculateEdgeWeight(type1, type2 int, distance float64) float64 {
	isT1Miner := type1 == config.TowerTypeMiner
	isT2Miner := type2 == config.TowerTypeMiner

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
func (g *Game) addTowerToEnergyNetwork(newTowerID types.EntityID) {
	newTower, exists := g.ECS.Towers[newTowerID]
	if !exists || newTower.Type == config.TowerTypeWall {
		return // Do nothing for walls or non-existent towers
	}

	// --- Start of interception logic ---
	// If the new tower is a Miner, check if it lies on an existing Miner-to-Miner line.
	// If so, intercept the line instead of finding a new connection.
	if newTower.Type == config.TowerTypeMiner {
		var interceptedLineID types.EntityID
		var tower1ID, tower2ID types.EntityID

		for lineID, line := range g.ECS.LineRenders {
			t1, ok1 := g.ECS.Towers[line.Tower1ID]
			t2, ok2 := g.ECS.Towers[line.Tower2ID]

			// Ensure both towers of the line are also miners.
			if !ok1 || !ok2 || t1.Type != config.TowerTypeMiner || t2.Type != config.TowerTypeMiner {
				continue
			}

			dist12 := t1.Hex.Distance(t2.Hex)
			dist1New := t1.Hex.Distance(newTower.Hex)
			distNew2 := newTower.Hex.Distance(t2.Hex)

			// Check for collinearity and betweenness. If the new tower is on the segment,
			// the sum of distances from the ends to the new tower will equal the total distance.
			if dist1New > 0 && distNew2 > 0 && dist1New+distNew2 == dist12 {
				interceptedLineID = lineID
				tower1ID = line.Tower1ID
				tower2ID = line.Tower2ID
				break // Found a line to intercept, no need to check others.
			}
		}

		if interceptedLineID != 0 {
			// A line was intercepted. Reroute it through the new tower.
			delete(g.ECS.LineRenders, interceptedLineID)

			newTower.IsActive = true
			g.updateTowerAppearance(newTowerID)

			// Create the two new line segments.
			t1 := g.ECS.Towers[tower1ID]
			g.createLine(energyEdge{
				Tower1ID: tower1ID, Tower2ID: newTowerID,
				Type1: t1.Type, Type2: newTower.Type,
				Distance: float64(t1.Hex.Distance(newTower.Hex)),
			})
			t2 := g.ECS.Towers[tower2ID]
			g.createLine(energyEdge{
				Tower1ID: newTowerID, Tower2ID: tower2ID,
				Type1: newTower.Type, Type2: t2.Type,
				Distance: float64(newTower.Hex.Distance(t2.Hex)),
			})

			// Expand the network from the newly added tower to connect any other nearby towers.
			g.expandNetworkFrom(newTowerID)
			return // The tower has been added and integrated.
		}
	}
	// --- End of interception logic ---

	// 1. Find all possible connections from the new tower to EXISTING ACTIVE towers.
	var connections []energyEdge
	for otherID, otherTower := range g.ECS.Towers {
		if newTowerID == otherID || !otherTower.IsActive {
			continue
		}

		distance := newTower.Hex.Distance(otherTower.Hex)
		isNeighbor := distance == 1
		isMinerConnection := newTower.Type == config.TowerTypeMiner &&
			otherTower.Type == config.TowerTypeMiner &&
			distance <= config.EnergyTransferRadius &&
			newTower.Hex.IsOnSameLine(otherTower.Hex)

		if isNeighbor || isMinerConnection {
			connections = append(connections, energyEdge{
				Tower1ID: newTowerID,
				Tower2ID: otherID,
				Type1:    newTower.Type,
				Type2:    otherTower.Type,
				Distance: float64(distance),
			})
		}
	}

	// Also check if the new tower is a miner on an ore vein, making it a root.
	isNewRoot := newTower.Type == config.TowerTypeMiner && g.isOnOre(newTower.Hex)

	// If there are no connections and it's not a new root, it remains inactive.
	if len(connections) == 0 && !isNewRoot {
		g.updateTowerAppearance(newTowerID) // Ensure it's colored as inactive
		return
	}

	// 2. Activate the new tower.
	newTower.IsActive = true
	g.updateTowerAppearance(newTowerID)

	// 3. If it can connect to the grid, create the best connection that doesn't form a triangle.
	if len(connections) > 0 {
		sort.Slice(connections, func(i, j int) bool {
			edgeA := connections[i]
			edgeB := connections[j]
			weightA := calculateEdgeWeight(edgeA.Type1, edgeA.Type2, edgeA.Distance)
			weightB := calculateEdgeWeight(edgeB.Type1, edgeB.Type2, edgeB.Distance)
			return weightA < weightB
		})

		adj := g.buildAdjacencyList()
		connectionMade := false
		for _, edge := range connections {
			if !g.formsTriangle(edge.Tower1ID, edge.Tower2ID, adj) {
				g.createLine(edge)
				connectionMade = true
				break // Make only one connection
			}
		}

		// Fallback: if all possible connections form triangles,
		// make the best one anyway to ensure connectivity.
		if !connectionMade {
			g.createLine(connections[0])
		}
	}

	// 4. Expand the network from the newly activated tower(s).
	g.expandNetworkFrom(newTowerID)
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

		// Find all inactive neighbors
		for otherID, otherTower := range g.ECS.Towers {
			if visited[otherID] || otherTower.IsActive || otherTower.Type == config.TowerTypeWall {
				continue
			}

			distance := currentTower.Hex.Distance(otherTower.Hex)
			isNeighbor := distance == 1
			isMinerConnection := currentTower.Type == config.TowerTypeMiner &&
				otherTower.Type == config.TowerTypeMiner &&
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
						Type1:    currentTower.Type,
						Type2:    otherTower.Type,
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
	tower := g.ECS.Towers[id]
	if render, exists := g.ECS.Renderables[id]; exists {
		var c color.RGBA
		if tower.Type >= 0 && tower.Type < len(config.TowerColors)-1 {
			c = config.TowerColors[tower.Type]
		} else {
			c = config.TowerColors[len(config.TowerColors)-1]
		}

		if tower.Type != config.TowerTypeWall && !tower.IsActive {
			c = pkgRender.DarkenColor(c)
		}
		render.Color = c
	}
}


// collectEdgesForNewTower finds all valid connections from a new tower to the existing ones.
func (g *Game) collectEdgesForNewTower(newTower *component.Tower, allTowers map[hexmap.Hex]types.EntityID, potentiallyActive map[types.EntityID]bool) []energyEdge {
	var edges []energyEdge
	newTowerID := allTowers[newTower.Hex]

	for otherHex, otherID := range allTowers {
		if newTowerID == otherID || !potentiallyActive[otherID] {
			continue
		}

		otherTower := g.ECS.Towers[otherID]
		distance := newTower.Hex.Distance(otherHex)

		isNeighbor := distance == 1
		isMinerConnection := newTower.Type == config.TowerTypeMiner &&
			otherTower.Type == config.TowerTypeMiner &&
			distance <= config.EnergyTransferRadius &&
			newTower.Hex.IsOnSameLine(otherHex) &&
			!g.hasActiveTowerBetween(newTower.Hex, otherHex, allTowers, potentiallyActive)

		if isNeighbor || isMinerConnection {
			edges = append(edges, energyEdge{
				Tower1ID: newTowerID,
				Tower2ID: otherID,
				Type1:    newTower.Type,
				Type2:    otherTower.Type,
				Distance: float64(distance),
			})
		}
	}

	sort.Slice(edges, func(i, j int) bool {
		edgeA, edgeB := edges[i], edges[j]
		isMinerA := edgeA.Type1 == config.TowerTypeMiner || edgeA.Type2 == config.TowerTypeMiner
		isMinerB := edgeB.Type1 == config.TowerTypeMiner || edgeB.Type2 == config.TowerTypeMiner
		if isMinerA != isMinerB {
			return isMinerA
		}
		return edgeA.Distance < edgeB.Distance
	})

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
		if g.ECS.Towers[id].Type != config.TowerTypeWall {
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
			distance := hexA.Distance(hexB)

			isNeighbor := distance == 1
			isMinerConnection := towerA.Type == config.TowerTypeMiner &&
				towerB.Type == config.TowerTypeMiner &&
				distance <= config.EnergyTransferRadius &&
				hexA.IsOnSameLine(hexB) &&
				!g.hasActiveTowerBetween(hexA, hexB, allTowers, potentiallyActive)

			if isNeighbor || isMinerConnection {
				edges = append(edges, energyEdge{
					Tower1ID: idA,
					Tower2ID: idB,
					Type1:    towerA.Type,
					Type2:    towerB.Type,
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
			return true
		}
	}
	return false
}

func (g *Game) buildMinimumSpanningTree(edges []energyEdge, potentiallyActive map[types.EntityID]bool) (*utils.UnionFind, []energyEdge) {
	sort.Slice(edges, func(i, j int) bool {
		edgeA := edges[i]
		edgeB := edges[j]
		weightA := calculateEdgeWeight(edgeA.Type1, edgeA.Type2, edgeA.Distance)
		weightB := calculateEdgeWeight(edgeB.Type1, edgeB.Type2, edgeB.Distance)
		return weightA < weightB
	})

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
		if tower.Type == config.TowerTypeMiner && g.isOnOre(hex) {
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
	posA := g.ECS.Positions[edge.Tower1ID]
	posB := g.ECS.Positions[edge.Tower2ID]
	lineID := g.ECS.NewEntity()
	g.ECS.LineRenders[lineID] = &component.LineRender{
		StartX:   posA.X,
		StartY:   posA.Y,
		EndX:     posB.X,
		EndY:     posB.Y,
		Color:    config.LineColor,
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
	_, exists := g.HexMap.EnergyVeins[hex]
	return exists
}

// handleTowerRemoval intelligently deactivates parts of the energy network
// after a tower is removed, avoiding a full, disruptive rebuild.
func (g *Game) handleTowerRemoval(removedTowerID types.EntityID) {
	// 1. Explicitly remove lines connected to the deleted tower.
	linesToRemove := []types.EntityID{}
	for lineID, line := range g.ECS.LineRenders {
		if line.Tower1ID == removedTowerID || line.Tower2ID == removedTowerID {
			linesToRemove = append(linesToRemove, lineID)
		}
	}
	for _, lineID := range linesToRemove {
		delete(g.ECS.LineRenders, lineID)
	}

	// 2. Perform a "keep-alive" traversal from all energy sources.
	poweredTowers := g.findPoweredTowers()

	// 3. Deactivate any tower that is no longer in the powered set.
	allTowerIDs := g.getAllTowerIDs()
	for _, towerID := range allTowerIDs {
		tower := g.ECS.Towers[towerID]
		// Also ensure towers that are powered are marked active
		// (in case they were part of a deactivated branch that got reconnected)
		if _, isPowered := poweredTowers[towerID]; !isPowered {
			tower.IsActive = false
		} else {
			tower.IsActive = true
		}
	}

	// 4. Clean up any lines that are now connected to a deactivated tower.
	g.cleanupOrphanedLines()

	// 5. Update visuals for all towers.
	g.updateTowerAppearances(g.getAllTowersByHex())
}

// findPoweredTowers performs a BFS from all energy sources to find all towers
// that should remain active.
func (g *Game) findPoweredTowers() map[types.EntityID]bool {
	powered := make(map[types.EntityID]bool)
	queue := []types.EntityID{}

	// Find all root energy sources and add them to the queue.
	for id, tower := range g.ECS.Towers {
		if tower.Type == config.TowerTypeMiner && g.isOnOre(tower.Hex) {
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
		if tower.Type == config.TowerTypeMiner && g.isOnOre(tower.Hex) {
			// This tower is a miner on an ore vein, find the corresponding ore entity.
			for oreID, ore := range g.ECS.Ores {
				oreHex := hexmap.PixelToHex(ore.Position.X, ore.Position.Y, config.HexSize)
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

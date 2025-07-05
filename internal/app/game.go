// internal/app/game.go
package app

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/event"
	"go-tower-defense/internal/system"
	"go-tower-defense/internal/types"
	"go-tower-defense/internal/ui"
	"go-tower-defense/pkg/hexmap"
	"image/color"
	"math/rand"
)

type Game struct {
	HexMap           *hexmap.HexMap
	Wave             int
	BaseHealth       int
	ECS              *entity.ECS
	MovementSystem   *system.MovementSystem
	RenderSystem     *system.RenderSystem
	WaveSystem       *system.WaveSystem
	CombatSystem     *system.CombatSystem
	ProjectileSystem *system.ProjectileSystem
	StateSystem      *system.StateSystem
	EventDispatcher  *event.Dispatcher
	towersBuilt      int
	SpeedButton      *ui.SpeedButton
	SpeedMultiplier  float64
	PauseButton      *ui.PauseButton
	gameTime         float64 // Накопленное игровое время
}

func NewGame(hexMap *hexmap.HexMap) *Game {
	if hexMap == nil {
		panic("hexMap cannot be nil")
	}
	ecs := entity.NewECS()
	eventDispatcher := event.NewDispatcher()
	g := &Game{
		HexMap:           hexMap,
		Wave:             1,
		BaseHealth:       config.BaseHealth,
		ECS:              ecs,
		MovementSystem:   system.NewMovementSystem(ecs),
		RenderSystem:     system.NewRenderSystem(ecs),
		WaveSystem:       system.NewWaveSystem(ecs, hexMap, eventDispatcher),
		CombatSystem:     system.NewCombatSystem(ecs),
		ProjectileSystem: system.NewProjectileSystem(ecs, eventDispatcher),
		EventDispatcher:  eventDispatcher,
		towersBuilt:      0,
		gameTime:         0.0, // Инициализация игрового времени
	}
	g.StateSystem = system.NewStateSystem(ecs, g, eventDispatcher)

	// Создание сущностей руды
	for hex, power := range hexMap.EnergyVeins {
		id := ecs.NewEntity()
		px, py := hex.ToPixel(config.HexSize)
		px += float64(config.ScreenWidth) / 2
		py += float64(config.ScreenHeight) / 2
		ecs.Positions[id] = &component.Position{X: px, Y: py}
		ecs.Ores[id] = &component.Ore{
			Power:     power,
			Position:  component.Position{X: px, Y: py},
			Radius:    float32(config.HexSize*0.2 + power*config.HexSize),
			Color:     color.RGBA{0, 0, 255, 128},
			PulseRate: 2.0,
		}
	}

	g.SpeedButton = ui.NewSpeedButton(
		float32(config.ScreenWidth-config.SpeedButtonOffsetX),
		float32(config.SpeedButtonY),
		float32(config.SpeedButtonSize),
		config.SpeedButtonColors,
	)
	g.SpeedMultiplier = 1.0

	g.PauseButton = ui.NewPauseButton(
		float32(config.ScreenWidth-config.IndicatorOffsetX-90),
		float32(config.IndicatorOffsetX),
		float32(config.IndicatorRadius),
		config.BuildStateColor,
		config.WaveStateColor,
	)

	return g
}

func (g *Game) Update(deltaTime float64) {
	dt := deltaTime * g.SpeedMultiplier
	g.gameTime += dt            // Накапливаем игровое время
	g.ECS.GameTime = g.gameTime // Синхронизируем с ECS
	if g.ECS.GameState == component.WaveState {
		g.CombatSystem.Update(dt)
		g.ProjectileSystem.Update(dt)
		g.WaveSystem.Update(dt, g.ECS.Wave)
		g.MovementSystem.Update(dt)

		for id := range g.ECS.Positions {
			if _, isTower := g.ECS.Towers[id]; isTower {
				continue
			}
			if _, isProjectile := g.ECS.Projectiles[id]; isProjectile {
				continue
			}
			if path, hasPath := g.ECS.Paths[id]; hasPath && path.CurrentIndex >= len(path.Hexes) {
				delete(g.ECS.Positions, id)
				delete(g.ECS.Velocities, id)
				delete(g.ECS.Paths, id)
				delete(g.ECS.Healths, id)
				delete(g.ECS.Renderables, id)
				g.EventDispatcher.Dispatch(event.Event{Type: event.EnemyDestroyed, Data: id})
			}
		}

	}
}
func (g *Game) StartWave() {
	g.ECS.Wave = g.WaveSystem.StartWave(g.Wave)
	g.WaveSystem.ResetActiveEnemies()
	g.Wave++
}

func (g *Game) isOnOre(hex hexmap.Hex) bool {
	_, exists := g.HexMap.EnergyVeins[hex]
	return exists
}

// Edge представляет ребро между двумя башнями
type Edge struct {
	Tower1ID types.EntityID
	Tower2ID types.EntityID
	Distance float64
}

// UnionFind уже есть в твоём коде, оставляем как есть
type UnionFind struct {
	parent map[types.EntityID]types.EntityID
	rank   map[types.EntityID]int
}

func NewUnionFind() *UnionFind {
	return &UnionFind{
		parent: make(map[types.EntityID]types.EntityID),
		rank:   make(map[types.EntityID]int),
	}
}

func (uf *UnionFind) Find(id types.EntityID) types.EntityID {
	if _, exists := uf.parent[id]; !exists {
		uf.parent[id] = id
		uf.rank[id] = 0
	}
	if uf.parent[id] != id {
		uf.parent[id] = uf.Find(uf.parent[id]) // Сжатие пути
	}
	return uf.parent[id]
}

func (uf *UnionFind) Union(idA, idB types.EntityID) {
	rootA := uf.Find(idA)
	rootB := uf.Find(idB)
	if rootA == rootB {
		return
	}
	if uf.rank[rootA] < uf.rank[rootB] {
		uf.parent[rootA] = rootB
	} else if uf.rank[rootA] > uf.rank[rootB] {
		uf.parent[rootB] = rootA
	} else {
		uf.parent[rootB] = rootA
		uf.rank[rootA]++
	}
}

// collectPossibleEdges собирает все возможные рёбра между башнями
func (g *Game) collectPossibleEdges(allTowers map[hexmap.Hex]types.EntityID) []Edge {
	var edges []Edge
	towerHexes := make([]hexmap.Hex, 0, len(allTowers))
	for hex := range allTowers {
		towerHexes = append(towerHexes, hex)
	}

	for i := 0; i < len(towerHexes); i++ {
		for j := i + 1; j < len(towerHexes); j++ {
			hexA := towerHexes[i]
			hexB := towerHexes[j]
			idA := allTowers[hexA]
			idB := allTowers[hexB]
			towerA := g.ECS.Towers[idA]
			towerB := g.ECS.Towers[idB]
			distance := hexA.Distance(hexB)

			if distance == 1 {
				edges = append(edges, Edge{Tower1ID: idA, Tower2ID: idB, Distance: float64(distance)})
			} else if towerA.Type == config.TowerTypeMiner && towerB.Type == config.TowerTypeMiner &&
				distance <= config.EnergyTransferRadius && isOnSameLine(hexA, hexB) {
				edges = append(edges, Edge{Tower1ID: idA, Tower2ID: idB, Distance: float64(distance)})
			}
		}
	}
	return edges
}

// updateTowerActivations обновляет активацию башен и линии с использованием алгоритма Крускала
func (g *Game) updateTowerActivations() {
	// 1. Собираем информацию обо всех башнях
	allTowers := make(map[hexmap.Hex]types.EntityID)
	for id, tower := range g.ECS.Towers {
		allTowers[tower.Hex] = id
		tower.IsActive = false
	}

	if len(allTowers) == 0 {
		return
	}

	// 2. Определяем, какие башни могут быть активными (исключаем стены)
	potentiallyActiveTowers := make(map[types.EntityID]bool)
	for _, id := range allTowers {
		tower := g.ECS.Towers[id]
		// Только башни с типом >= 0 могут быть активными (стены имеют тип -1)
		if tower.Type >= 0 {
			potentiallyActiveTowers[id] = true
		}
	}

	// 3. Инициализация Union-Find только для потенциально активных башен
	uf := NewUnionFind()
	for id := range potentiallyActiveTowers {
		uf.Find(id)
	}

	// 4. Собираем существующие линии в граф (только между активными башнями)
	existingEdges := make(map[types.EntityID]map[types.EntityID]bool)
	linesToRemove := make([]types.EntityID, 0)

	for lineID, line := range g.ECS.LineRenders {
		tower1, exists1 := g.ECS.Towers[line.Tower1ID]
		tower2, exists2 := g.ECS.Towers[line.Tower2ID]

		// Удаляем линии, если башни не существуют или являются стенами
		if !exists1 || !exists2 || tower1.Type == -1 || tower2.Type == -1 {
			linesToRemove = append(linesToRemove, lineID)
			continue
		}

		if existingEdges[line.Tower1ID] == nil {
			existingEdges[line.Tower1ID] = make(map[types.EntityID]bool)
		}
		if existingEdges[line.Tower2ID] == nil {
			existingEdges[line.Tower2ID] = make(map[types.EntityID]bool)
		}
		existingEdges[line.Tower1ID][line.Tower2ID] = true
		existingEdges[line.Tower2ID][line.Tower1ID] = true
		uf.Union(line.Tower1ID, line.Tower2ID)
	}

	// Удаляем недействительные линии
	for _, lineID := range linesToRemove {
		delete(g.ECS.LineRenders, lineID)
	}

	// 5. Собираем все возможные новые рёбра (только между потенциально активными башнями)
	newEdges := g.collectPossibleEdgesFiltered(allTowers, potentiallyActiveTowers)

	// 6. Применяем алгоритм Крускала для добавления новых рёбер
	var mstEdges []Edge
	for _, edge := range newEdges {
		idA := edge.Tower1ID
		idB := edge.Tower2ID
		if uf.Find(idA) != uf.Find(idB) {
			uf.Union(idA, idB)
			mstEdges = append(mstEdges, edge)
		}
	}

	// 7. Активируем башни на основе компонент связности
	roots := make(map[types.EntityID]bool)
	for hex, id := range allTowers {
		tower := g.ECS.Towers[id]
		// Только добытчики на руде могут быть корнями сети
		if tower.Type == config.TowerTypeMiner && g.isOnOre(hex) {
			roots[uf.Find(id)] = true
		}
	}

	// Активируем только те башни, которые связаны с корнями
	for id := range potentiallyActiveTowers {
		if roots[uf.Find(id)] {
			g.ECS.Towers[id].IsActive = true
		}
	}

	// 8. Обновляем внешний вид башен
	for _, id := range allTowers {
		tower := g.ECS.Towers[id]
		if render, exists := g.ECS.Renderables[id]; exists {
			var color color.RGBA
			if tower.Type >= 0 && tower.Type < len(config.TowerColors)-1 {
				color = config.TowerColors[tower.Type]
			} else {
				color = config.TowerColors[len(config.TowerColors)-1]
			}
			if tower.Type != -1 && !tower.IsActive {
				color = darkenColor(color)
			}
			render.Color = color
		}
	}

	// 9. Добавляем новые линии только для новых рёбер между активными башнями
	for _, edge := range mstEdges {
		// Проверяем, что обе башни активны
		tower1 := g.ECS.Towers[edge.Tower1ID]
		tower2 := g.ECS.Towers[edge.Tower2ID]

		if tower1.IsActive && tower2.IsActive {
			if _, exists := existingEdges[edge.Tower1ID][edge.Tower2ID]; !exists {
				posA := g.ECS.Positions[edge.Tower1ID]
				posB := g.ECS.Positions[edge.Tower2ID]
				lineID := g.ECS.NewEntity()
				g.ECS.LineRenders[lineID] = &component.LineRender{
					StartX:   posA.X,
					StartY:   posA.Y,
					EndX:     posB.X,
					EndY:     posB.Y,
					Color:    color.RGBA{255, 255, 0, 128},
					Tower1ID: edge.Tower1ID,
					Tower2ID: edge.Tower2ID,
				}
			}
		}
	}

	// 10. Удаляем линии между неактивными башнями
	g.removeInactiveLines(allTowers)
}

// collectPossibleEdgesFiltered собирает все возможные рёбра только между потенциально активными башнями
func (g *Game) collectPossibleEdgesFiltered(allTowers map[hexmap.Hex]types.EntityID, potentiallyActive map[types.EntityID]bool) []Edge {
	var edges []Edge
	towerHexes := make([]hexmap.Hex, 0, len(allTowers))

	// Собираем только гексы потенциально активных башен
	for hex, id := range allTowers {
		if potentiallyActive[id] {
			towerHexes = append(towerHexes, hex)
		}
	}

	for i := 0; i < len(towerHexes); i++ {
		for j := i + 1; j < len(towerHexes); j++ {
			hexA := towerHexes[i]
			hexB := towerHexes[j]
			idA := allTowers[hexA]
			idB := allTowers[hexB]
			towerA := g.ECS.Towers[idA]
			towerB := g.ECS.Towers[idB]
			distance := hexA.Distance(hexB)

			// Проверка для соседних башен
			if distance == 1 {
				edges = append(edges, Edge{Tower1ID: idA, Tower2ID: idB, Distance: float64(distance)})
			} else if towerA.Type == config.TowerTypeMiner && towerB.Type == config.TowerTypeMiner &&
				distance <= config.EnergyTransferRadius && isOnSameLine(hexA, hexB) {
				// Для башен типа Б на расстоянии > 1, проверяем, что между ними нет активных башен
				if !g.hasActiveTowerBetween(hexA, hexB, allTowers, potentiallyActive) {
					edges = append(edges, Edge{Tower1ID: idA, Tower2ID: idB, Distance: float64(distance)})
				}
			}
		}
	}
	return edges
}

// Добавь это в internal/app/game.go перед методом connectMinersOnOre
func (g *Game) wouldCreateCycle(idA, idB types.EntityID, existingLines map[types.EntityID]map[types.EntityID]bool) bool {
	visited := make(map[types.EntityID]bool)
	var dfs func(currentID, parentID, targetID types.EntityID) bool
	dfs = func(currentID, parentID, targetID types.EntityID) bool {
		if visited[currentID] {
			return currentID == targetID
		}
		visited[currentID] = true
		if neighbors, exists := existingLines[currentID]; exists {
			for neighborID := range neighbors {
				if neighborID != parentID { // Избегаем возврата к родителю
					if dfs(neighborID, currentID, targetID) {
						return true
					}
				}
			}
		}
		return false
	}
	// Добавляем временную линию между idA и idB для проверки
	if existingLines[idA] == nil {
		existingLines[idA] = make(map[types.EntityID]bool)
	}
	if existingLines[idB] == nil {
		existingLines[idB] = make(map[types.EntityID]bool)
	}
	existingLines[idA][idB] = true
	existingLines[idB][idA] = true
	result := dfs(idA, idB, idB)
	// Удаляем временную линию
	delete(existingLines[idA], idB)
	delete(existingLines[idB], idA)
	return result
}

// connectMinersOnOre соединяет активные добытчики на рудах линиями, если они на одной линии и в радиусе действия, и если это не создаст цикл
func (g *Game) connectMinersOnOre(allTowers map[hexmap.Hex]types.EntityID, activeTowers map[hexmap.Hex]bool, uf *UnionFind) {
	minersOnOre := make([]hexmap.Hex, 0)
	for hex, id := range allTowers {
		tower := g.ECS.Towers[id]
		if tower.Type == config.TowerTypeMiner && g.isOnOre(hex) && activeTowers[hex] {
			minersOnOre = append(minersOnOre, hex)
		}
	}

	// Собираем существующие линии в граф
	existingLines := make(map[types.EntityID]map[types.EntityID]bool)
	for _, line := range g.ECS.LineRenders {
		if existingLines[line.Tower1ID] == nil {
			existingLines[line.Tower1ID] = make(map[types.EntityID]bool)
		}
		if existingLines[line.Tower2ID] == nil {
			existingLines[line.Tower2ID] = make(map[types.EntityID]bool)
		}
		existingLines[line.Tower1ID][line.Tower2ID] = true
		existingLines[line.Tower2ID][line.Tower1ID] = true
	}

	for i := 0; i < len(minersOnOre); i++ {
		for j := i + 1; j < len(minersOnOre); j++ {
			hexA := minersOnOre[i]
			hexB := minersOnOre[j]
			idA := allTowers[hexA]
			idB := allTowers[hexB]

			if hexA.Distance(hexB) <= config.EnergyTransferRadius && isOnSameLine(hexA, hexB) {
				if uf.Find(idA) != uf.Find(idB) && !g.wouldCreateCycle(idA, idB, existingLines) {
					uf.Union(idA, idB)
					posA := g.ECS.Positions[idA]
					posB := g.ECS.Positions[idB]
					lineID := g.ECS.NewEntity()
					g.ECS.LineRenders[lineID] = &component.LineRender{
						StartX:   posA.X,
						StartY:   posA.Y,
						EndX:     posB.X,
						EndY:     posB.Y,
						Color:    color.RGBA{255, 255, 0, 128},
						Tower1ID: idA,
						Tower2ID: idB,
					}
					// Обновляем граф после добавления линии
					existingLines[idA][idB] = true
					existingLines[idB][idA] = true
				}
			}
		}
	}
}

func (g *Game) createActivationLines(parent map[hexmap.Hex]hexmap.Hex, allTowers map[hexmap.Hex]types.EntityID, uf *UnionFind) {
	for childHex, parentHex := range parent {
		if parentHex != (hexmap.Hex{}) {
			childID := allTowers[childHex]
			parentID := allTowers[parentHex]
			// Линия уже учтена в BFS через uf.Union, просто добавляем её визуально
			childPos := g.ECS.Positions[childID]
			parentPos := g.ECS.Positions[parentID]
			id := g.ECS.NewEntity()
			g.ECS.LineRenders[id] = &component.LineRender{
				StartX:   parentPos.X,
				StartY:   parentPos.Y,
				EndX:     childPos.X,
				EndY:     childPos.Y,
				Color:    color.RGBA{255, 255, 0, 128},
				Tower1ID: parentID,
				Tower2ID: childID,
			}
		}
	}
}

// isOnSameLine проверяет, лежат ли два гекса на одной прямой линии в гексагональной сетке
func isOnSameLine(a, b hexmap.Hex) bool {
	// Башни на одном и том же месте считаются на одной линии.
	if a == b {
		return true
	}

	dQ := a.Q - b.Q
	dR := a.R - b.R
	dS := (-a.Q - a.R) - (-b.Q - b.R) // S = -Q - R

	// Если все дельты 0, то это тот же гекс (обработано выше, но для надежности)
	if dQ == 0 && dR == 0 && dS == 0 {
		return true
	}

	// Находим НОД, чтобы нормализовать вектор направления
	commonDivisor := gcd(abs(dQ), gcd(abs(dR), abs(dS)))
	if commonDivisor == 0 {
		return false // Не должно произойти, если a != b
	}

	normDQ := dQ / commonDivisor
	normDR := dR / commonDivisor
	normDS := dS / commonDivisor

	// Проверяем, совпадает ли нормализованный вектор с одним из 6 базовых направлений
	// Условие Q + R + S = 0 для кубических координат означает,
	// что нам достаточно проверить только два компонента вектора.
	// Если dQ + dR + dS = 0, то dS = -dQ - dR.
	// Так что проверка третьего компонента (normDS) избыточна, но оставим для ясности.

	// Шесть направлений в кубических координатах
	isDirection := (normDQ == 1 && normDR == 0 && normDS == -1) ||
		(normDQ == -1 && normDR == 0 && normDS == 1) ||
		(normDQ == 0 && normDR == 1 && normDS == -1) ||
		(normDQ == 0 && normDR == -1 && normDS == 1) ||
		(normDQ == 1 && normDR == -1 && normDS == 0) ||
		(normDQ == -1 && normDR == 1 && normDS == 0)

	return isDirection
}

// Вспомогательные функции
func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func gcd(a, b int) int {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}

func darkenColor(c color.RGBA) color.RGBA {
	return color.RGBA{
		R: uint8(float64(c.R) * 0.5),
		G: uint8(float64(c.G) * 0.5),
		B: uint8(float64(c.B) * 0.5),
		A: c.A,
	}
}

func (g *Game) PlaceTower(hex hexmap.Hex) bool {
	// Проверяем, что мы в фазе строительства и не превышен лимит башен
	if g.ECS.GameState != component.BuildState || g.towersBuilt >= config.MaxTowersInBuildPhase {
		return false
	}

	// Проверяем, можно ли разместить башню на этой клетке
	tile, exists := g.HexMap.Tiles[hex]
	if !exists || !tile.Passable || !tile.CanPlaceTower {
		return false
	}

	// Проверяем, что клетка не занята другой башней
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

	// Проверяем, не блокирует ли башня путь к чекпоинтам или выходу
	originalPassable := tile.Passable
	g.HexMap.Tiles[hex] = hexmap.Tile{Passable: false, CanPlaceTower: tile.CanPlaceTower}
	checkpoints := g.HexMap.Checkpoints
	current := g.HexMap.Entry
	for _, cp := range checkpoints {
		path := hexmap.AStar(current, cp, g.HexMap)
		if path == nil {
			g.HexMap.Tiles[hex] = hexmap.Tile{Passable: originalPassable, CanPlaceTower: tile.CanPlaceTower}
			//log.Println("Путь до чекпоинта", i+1, "заблокирован!")
			return false
		}
		current = cp
	}
	pathToExit := hexmap.AStar(current, g.HexMap.Exit, g.HexMap)
	g.HexMap.Tiles[hex] = hexmap.Tile{Passable: originalPassable, CanPlaceTower: tile.CanPlaceTower}
	if pathToExit == nil {
		//log.Println("Путь до выхода заблокирован!")
		return false
	}

	// Создаём новую сущность для башни
	id := g.ECS.NewEntity()
	px, py := hex.ToPixel(config.HexSize)
	px += float64(config.ScreenWidth) / 2
	py += float64(config.ScreenHeight) / 2
	g.ECS.Positions[id] = &component.Position{X: px, Y: py}

	// Новая логика выбора типа башни
	var towerType int
	if g.towersBuilt == 0 {
		towerType = rand.Intn(4) // Первая башня — атакующая
	} else if g.towersBuilt == 1 {
		towerType = config.TowerTypeMiner // Вторая — добытчик
	} else {
		towerType = -1 // Остальные — стенки
	}

	// Создаём башню, изначально неактивную — активация через updateTowerActivations
	g.ECS.Towers[id] = &component.Tower{
		Type:     towerType,
		Range:    config.TowerRange,
		Hex:      hex,
		IsActive: false, // Изначально неактивна
	}

	// Добавляем Combat только для атакующих башен (типы 0-3)
	if towerType >= 0 && towerType < config.TowerTypeMiner {
		g.ECS.Combats[id] = &component.Combat{
			FireRate:     config.TowerFireRate[towerType],
			FireCooldown: 0,
			Range:        config.TowerRange,
		}
		//log.Println("Башня", id, "создана с Combat, тип:", towerType, "на руде:", g.isOnOre(hex))
	} else {
		//log.Println("Башня", id, "без Combat, тип:", towerType)
	}

	// Устанавливаем цвет башни
	var color color.RGBA
	if towerType >= 0 && towerType < len(config.TowerColors)-1 {
		color = config.TowerColors[towerType]
	} else {
		color = config.TowerColors[len(config.TowerColors)-1] // Серый для камней
	}

	g.ECS.Renderables[id] = &component.Renderable{
		Color:     color,
		Radius:    float32(config.HexSize * config.TowerRadiusFactor),
		HasStroke: true,
	}

	// Обновляем карту, увеличиваем счётчик башен
	g.HexMap.Tiles[hex] = hexmap.Tile{Passable: false, CanPlaceTower: tile.CanPlaceTower}
	g.towersBuilt++

	// Обновляем активацию всех башен после размещения
	g.updateTowerActivations()

	// Отправляем событие о размещении башни
	g.EventDispatcher.Dispatch(event.Event{Type: event.TowerPlaced, Data: hex})

	// Переключаемся на фазу волны, если достигнут лимит башен
	if g.towersBuilt >= config.MaxTowersInBuildPhase {
		g.StateSystem.SwitchToWaveState()
	}

	return true
}

// hasActiveTowerBetween проверяет, есть ли активная башня между двумя гексами на одной линии
func (g *Game) hasActiveTowerBetween(hexA, hexB hexmap.Hex, allTowers map[hexmap.Hex]types.EntityID, potentiallyActive map[types.EntityID]bool) bool {
	// Получаем все гексы на линии между A и B
	line := hexA.LineTo(hexB)

	// Проверяем каждый гекс между начальным и конечным (исключая их самих)
	for i := 1; i < len(line)-1; i++ {
		hex := line[i]
		if towerID, exists := allTowers[hex]; exists {
			// Если на этом гексе есть потенциально активная башня, блокируем соединение
			if potentiallyActive[towerID] {
				return true
			}
		}
	}
	return false
}

// Метод для удаления линий у неактивных башен
// Обновляем метод removeInactiveLines
func (g *Game) removeInactiveLines(allTowers map[hexmap.Hex]types.EntityID) {
	linesToRemove := make([]types.EntityID, 0)

	for lineID, line := range g.ECS.LineRenders {
		tower1, exists1 := g.ECS.Towers[line.Tower1ID]
		tower2, exists2 := g.ECS.Towers[line.Tower2ID]

		// Удаляем линию если:
		// - Одна из башен не существует
		// - Одна из башен является стеной (тип -1)
		// - Одна из башен неактивна
		if !exists1 || !exists2 ||
			tower1.Type == -1 || tower2.Type == -1 ||
			!tower1.IsActive || !tower2.IsActive {
			linesToRemove = append(linesToRemove, lineID)
		}
	}

	// Удаляем линии
	for _, lineID := range linesToRemove {
		delete(g.ECS.LineRenders, lineID)
	}
}

func (g *Game) RemoveTower(hex hexmap.Hex) bool {
	if g.ECS.GameState != component.BuildState {
		return false
	}

	var towerIDToRemove types.EntityID = 0
	for id, tower := range g.ECS.Towers {
		if tower.Hex == hex {
			towerIDToRemove = id
			break
		}
	}

	if towerIDToRemove != 0 {
		// Удаляем башню из ECS
		delete(g.ECS.Positions, towerIDToRemove)
		delete(g.ECS.Towers, towerIDToRemove)
		delete(g.ECS.Combats, towerIDToRemove)
		delete(g.ECS.Renderables, towerIDToRemove)

		// Удаляем линии, связанные с этой башней
		for id, line := range g.ECS.LineRenders {
			if line.Tower1ID == towerIDToRemove || line.Tower2ID == towerIDToRemove {
				delete(g.ECS.LineRenders, id)
			}
		}

		if tile, exists := g.HexMap.Tiles[hex]; exists {
			tile.Passable = true
			g.HexMap.Tiles[hex] = tile
		}

		// Обновляем активацию всех башен после удаления
		g.updateTowerActivations()

		g.EventDispatcher.Dispatch(event.Event{Type: event.TowerRemoved, Data: hex})
		return true
	}

	return false
}

func (g *Game) ClearEnemies() {
	for id := range g.ECS.Enemies {
		delete(g.ECS.Positions, id)
		delete(g.ECS.Velocities, id)
		delete(g.ECS.Paths, id)
		delete(g.ECS.Healths, id)
		delete(g.ECS.Renderables, id)
		delete(g.ECS.Enemies, id) // Удаляем компонент Enemy
	}
}

func (g *Game) ClearProjectiles() {
	for id := range g.ECS.Projectiles {
		delete(g.ECS.Positions, id)
		delete(g.ECS.Velocities, id)
		delete(g.ECS.Renderables, id)
		delete(g.ECS.Projectiles, id)
		// Если у снарядов есть другие компоненты, добавь их удаление сюда
	}
}

func (g *Game) HandleIndicatorClick() {
	if g.ECS.GameState == component.BuildState {
		g.StateSystem.SwitchToWaveState()
	} else {
		g.StateSystem.SwitchToBuildState()
	}
}

func (g *Game) HandleSpeedClick() {
	g.SpeedButton.ToggleState()
	switch g.SpeedButton.CurrentState {
	case 0:
		g.SpeedMultiplier = 1.0
	case 1:
		g.SpeedMultiplier = 2.0
	case 2:
		g.SpeedMultiplier = 4.0
	}
}

func (g *Game) HandlePauseClick() {
	g.PauseButton.TogglePause()
}

func (g *Game) GetTowerHexes() []hexmap.Hex {
	var towerHexes []hexmap.Hex
	for _, tower := range g.ECS.Towers {
		towerHexes = append(towerHexes, tower.Hex)
	}
	return towerHexes
}

func (g *Game) SetTowersBuilt(count int) {
	g.towersBuilt = count
}

func (g *Game) GetTowersBuilt() int {
	return g.towersBuilt
}

func (g *Game) GetGameTime() float64 {
	return g.gameTime
}

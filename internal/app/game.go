// internal/app/game.go
package app

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/event"
	"go-tower-defense/internal/system"
	"go-tower-defense/internal/types"
	"go-tower-defense/internal/ui"
	"go-tower-defense/internal/utils"
	"go-tower-defense/pkg/hexmap"
	"log"
	"math"
	"math/rand"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// LineDragDebugInfo holds information for on-screen debugging.
type LineDragDebugInfo struct {
	ClickedHex    hexmap.Hex
	DirectionName string
	NeighborHex   hexmap.Hex
	FoundNeighbor bool
}

// Game holds the main game state and logic.
type Game struct {
	HexMap                    *hexmap.HexMap
	Wave                      int
	BaseHealth                int
	ECS                       *entity.ECS
	MovementSystem            *system.MovementSystem
	RenderSystem              *system.RenderSystemRL // Изменено
	WaveSystem                *system.WaveSystem
	CombatSystem              *system.CombatSystem
	ProjectileSystem          *system.ProjectileSystem
	StateSystem               *system.StateSystem
	OreSystem                 *system.OreSystem
	AuraSystem                *system.AuraSystem
	StatusEffectSystem        *system.StatusEffectSystem
	EnvironmentalDamageSystem *system.EnvironmentalDamageSystem
	VisualEffectSystem        *system.VisualEffectSystem
	CraftingSystem            *system.CraftingSystem
	PlayerSystem              *system.PlayerSystem
	AreaAttackSystem          *system.AreaAttackSystem
	VolcanoSystem             *system.VolcanoSystem
	BeaconSystem              *system.BeaconSystem
	EventDispatcher           *event.Dispatcher
	Font                      rl.Font // Изменено
	Rng                       *utils.PRNGService
	towersBuilt               int
	SpeedButton               *ui.SpeedButtonRL // Изменено
	SpeedMultiplier           float64
	PauseButton               *ui.PauseButtonRL // Изменено
	DebugTowerID              string
	DebugInfo                 *LineDragDebugInfo

	// Game state
	gameTime               float64
	isPaused               bool
	gameSpeed              float64
	currentWave            *component.Wave
	isDragging             bool
	sourceTowerID          types.EntityID
	hiddenLineID           types.EntityID
	highlightedTower       types.EntityID
	manuallySelectedTowers []types.EntityID

	// Line dragging state
	isLineDragging       bool
	dragSourceTowerID    types.EntityID
	dragOriginalParentID types.EntityID
	PlayerID             types.EntityID // ID сущности игрока
}

// NewGame initializes a new game instance.
func NewGame(hexMap *hexmap.HexMap, font rl.Font) *Game {
	if hexMap == nil {
		panic("hexMap cannot be nil")
	}

	ecs := entity.NewECS()
	eventDispatcher := event.NewDispatcher()
	g := &Game{
		HexMap:          hexMap,
		Wave:            1,
		BaseHealth:      config.BaseHealth,
		ECS:             ecs,
		MovementSystem:  system.NewMovementSystem(ecs),
		WaveSystem:      system.NewWaveSystem(ecs, hexMap, eventDispatcher),
		OreSystem:       system.NewOreSystem(ecs, eventDispatcher),
		EventDispatcher: eventDispatcher,
		Font:            font,
		Rng:             utils.NewPRNGService(0),
		towersBuilt:     0,
		gameTime:        0.0,
		DebugTowerID:    "TOWER_LIGHTHOUSE",
	}
	g.RenderSystem = system.NewRenderSystemRL(ecs, font)
	g.CombatSystem = system.NewCombatSystem(ecs, g.FindPowerSourcesForTower, g.FindPathToPowerSource)
	g.ProjectileSystem = system.NewProjectileSystem(ecs, eventDispatcher, g.CombatSystem)
	g.StateSystem = system.NewStateSystem(ecs, g, eventDispatcher)
	g.AuraSystem = system.NewAuraSystem(ecs)
	g.StatusEffectSystem = system.NewStatusEffectSystem(ecs)
	g.EnvironmentalDamageSystem = system.NewEnvironmentalDamageSystem(ecs)
	g.VisualEffectSystem = system.NewVisualEffectSystem(ecs)
	g.CraftingSystem = system.NewCraftingSystem(ecs)
	g.PlayerSystem = system.NewPlayerSystem(ecs)
	g.AreaAttackSystem = system.NewAreaAttackSystem(ecs)
	g.VolcanoSystem = system.NewVolcanoSystem(ecs, g.FindPowerSourcesForTower)
	g.BeaconSystem = system.NewBeaconSystem(ecs, g.FindPowerSourcesForTower)
	g.generateOre()
	g.initUI()

	listener := &GameEventListener{game: g}
	eventDispatcher.Subscribe(event.OreDepleted, listener)
	eventDispatcher.Subscribe(event.WaveEnded, listener)
	eventDispatcher.Subscribe(event.CombineTowersRequest, listener)
	eventDispatcher.Subscribe(event.ToggleTowerSelectionForSaveRequest, listener)

	eventDispatcher.Subscribe(event.TowerPlaced, g.CraftingSystem)
	eventDispatcher.Subscribe(event.TowerRemoved, g.CraftingSystem)

	eventDispatcher.Subscribe(event.EnemyKilled, g.PlayerSystem)
	eventDispatcher.Subscribe(event.EnemyKilled, g.ProjectileSystem)

	g.placeInitialStones()
	g.createPlayerEntity()

	return g
}

// CombineTowers выполняет логику объединения башен.
func (g *Game) CombineTowers(clickedTowerID types.EntityID) {
	combinable, ok := g.ECS.Combinables[clickedTowerID]
	if !ok || len(combinable.PossibleCrafts) == 0 {
		return
	}

	craftToPerform := combinable.PossibleCrafts[0]
	recipe := craftToPerform.Recipe
	combination := craftToPerform.Combination

	outputDef := defs.TowerDefs[recipe.OutputID]
	if tower, ok := g.ECS.Towers[clickedTowerID]; ok {
		tower.DefID = recipe.OutputID
		tower.CraftingLevel = outputDef.CraftingLevel

		if outputDef.Combat != nil {
			var combat *component.Combat
			var combatExists bool
			if combat, combatExists = g.ECS.Combats[clickedTowerID]; combatExists {
				combat.FireRate = outputDef.Combat.FireRate
				combat.Range = outputDef.Combat.Range
				combat.ShotCost = outputDef.Combat.ShotCost
			} else {
				combat = &component.Combat{
					FireRate: outputDef.Combat.FireRate,
					Range:    outputDef.Combat.Range,
					ShotCost: outputDef.Combat.ShotCost,
				}
			}

			if outputDef.Combat.Attack != nil {
				combat.Attack = *outputDef.Combat.Attack
			}
			if !combatExists {
				g.ECS.Combats[clickedTowerID] = combat
			}
		} else {
			delete(g.ECS.Combats, clickedTowerID)
		}

		if renderable, ok := g.ECS.Renderables[clickedTowerID]; ok {
			renderable.Color = outputDef.Visuals.Color
			renderable.Radius = float32(config.HexSize * outputDef.Visuals.RadiusFactor)
		}
	}

	wallDef := defs.TowerDefs["TOWER_WALL"]
	for _, id := range combination {
		if id == clickedTowerID {
			continue
		}
		if tower, ok := g.ECS.Towers[id]; ok {
			delete(g.ECS.Combats, id)
			delete(g.ECS.Auras, id)
			tower.DefID = "TOWER_WALL"
			if renderable, ok := g.ECS.Renderables[id]; ok {
				renderable.Color = wallDef.Visuals.Color
				renderable.Radius = float32(config.HexSize * wallDef.Visuals.RadiusFactor)
			}
		}
	}

	g.CraftingSystem.RecalculateCombinations()
	g.AuraSystem.RecalculateAuras()
	g.rebuildEnergyNetwork()
}

// FindPathToPowerSource находит кратчайший путь от атакующей башни до ближайшего
// источника энергии (башни-добытчика на активной руде).
func (g *Game) FindPathToPowerSource(startNode types.EntityID) []types.EntityID {
	if _, exists := g.ECS.Towers[startNode]; !exists {
		return nil
	}

	adj := g.buildAdjacencyList()
	queue := []types.EntityID{startNode}
	visited := map[types.EntityID]bool{startNode: true}
	parent := make(map[types.EntityID]types.EntityID)

	var pathEnd types.EntityID

	head := 0
	for head < len(queue) {
		currentID := queue[head]
		head++

		tower := g.ECS.Towers[currentID]
		towerDef, ok := defs.TowerDefs[tower.DefID]
		if !ok {
			continue
		}
		if towerDef.Type == defs.TowerTypeMiner && g.isOnOre(tower.Hex) {
			pathEnd = currentID
			break
		}

		if neighbors, ok := adj[currentID]; ok {
			for _, neighborID := range neighbors {
				if !visited[neighborID] {
					visited[neighborID] = true
					parent[neighborID] = currentID
					queue = append(queue, neighborID)
				}
			}
		}
	}

	if pathEnd == 0 {
		return nil
	}

	path := []types.EntityID{}
	for curr := pathEnd; curr != 0; curr = parent[curr] {
		path = append(path, curr)
	}

	for i, j := 0, len(path)-1; i < j; i, j = i+1, j-1 {
		path[i], path[j] = path[j], path[i]
	}

	return path
}

// GameEventListener обрабатывает события, важные для основного игрового цикла.
type GameEventListener struct {
	game *Game
}

// OnEvent реализует интерфейс event.Listener.
func (l *GameEventListener) OnEvent(e event.Event) {
	switch e.Type {
	case event.OreDepleted:
		poweredSet := l.game.findPoweredTowers()
		for id, tower := range l.game.ECS.Towers {
			_, isPowered := poweredSet[id]
			tower.IsActive = isPowered
		}
		l.game.cleanupOrphanedLines()
		l.game.updateAllTowerAppearances()
	case event.WaveEnded:
		l.game.StateSystem.SwitchToBuildState()
	case event.CombineTowersRequest:
		if towerID, ok := e.Data.(types.EntityID); ok {
			l.game.CombineTowers(towerID)
		}
	case event.ToggleTowerSelectionForSaveRequest:
		if towerID, ok := e.Data.(types.EntityID); ok {
			l.game.ToggleTowerSelectionForSave(towerID)
		}
	}
}

// placeInitialStones places stones around checkpoints at the start of the game.
func (g *Game) placeInitialStones() {
	center := hexmap.Hex{Q: 0, R: 0}
	for _, checkpoint := range g.HexMap.Checkpoints {
		dirIn := center.Subtract(checkpoint).Direction()
		for i := 1; i <= 2; i++ {
			hexToPlace := checkpoint.Add(dirIn.Scale(i))
			if g.canPlaceWall(hexToPlace) {
				g.createPermanentWall(hexToPlace)
			}
		}

		dirOut := checkpoint.Subtract(center).Direction()
		for i := 1; ; i++ {
			hexToPlace := checkpoint.Add(dirOut.Scale(i))
			if g.canPlaceWall(hexToPlace) {
				g.createPermanentWall(hexToPlace)
			} else {
				break
			}
		}
	}
}

// Update progresses the game state by one frame.
func (g *Game) Update(deltaTime float64) {
	dt := deltaTime * g.SpeedMultiplier
	g.gameTime += dt
	g.ECS.GameTime = g.gameTime

	g.RenderSystem.Update(dt)
	g.VisualEffectSystem.Update(dt)

	if g.ECS.GameState.Phase == component.WaveState {
		g.StatusEffectSystem.Update(dt)
		g.VolcanoSystem.Update(dt)
		g.BeaconSystem.Update(dt)
		g.AreaAttackSystem.Update(dt)
		g.CombatSystem.Update(dt)
		g.ProjectileSystem.Update(dt)
		g.WaveSystem.Update(dt, g.ECS.Wave)
		g.MovementSystem.Update(dt)
		g.EnvironmentalDamageSystem.Update(dt)
		g.cleanupDestroyedEntities()
	}
	g.OreSystem.Update()
}

// StartWave begins the enemy wave.
func (g *Game) StartWave() {
	g.ECS.Wave = g.WaveSystem.StartWave(g.Wave)
	g.WaveSystem.ResetActiveEnemies()
	g.Wave++
}

// --- Private Helper Functions ---

func (g *Game) initUI() {
	// Рассчитываем X-координаты кнопок, между которыми нужно вставить нашу
	pauseButtonX := float32(config.ScreenWidth - config.IndicatorOffsetX - 90)
	indicatorX := float32(config.ScreenWidth - config.IndicatorOffsetX)
	
	// Находим среднюю точку для симметричного расположения и добавляем небольшое смещение вправо
	speedButtonX := (pauseButtonX+indicatorX)/2 + 2

	g.SpeedButton = ui.NewSpeedButtonRL(
		speedButtonX, // Новая, вычисленная координата X
		float32(config.SpeedButtonY),
		float32(config.SpeedButtonSize),
	)
	g.SpeedMultiplier = 1.0

	g.PauseButton = ui.NewPauseButtonRL(
		float32(config.ScreenWidth-config.IndicatorOffsetX-90),
		float32(config.IndicatorOffsetX),
		float32(config.IndicatorRadius),
	)
}

func (g *Game) cleanupDestroyedEntities() {
	for id := range g.ECS.Enemies {
		path, hasPath := g.ECS.Paths[id]
		reachedEnd := hasPath && path.CurrentIndex >= len(path.Hexes)

		health, hasHealth := g.ECS.Healths[id]
		noHealth := hasHealth && health.Value <= 0

		if noHealth {
			g.EventDispatcher.Dispatch(event.Event{Type: event.EnemyKilled, Data: id})
		}

		if reachedEnd || noHealth {
			delete(g.ECS.Positions, id)
			delete(g.ECS.Velocities, id)
			delete(g.ECS.Paths, id)
			delete(g.ECS.Healths, id)
			delete(g.ECS.Renderables, id)
			delete(g.ECS.Enemies, id)
			g.EventDispatcher.Dispatch(event.Event{Type: event.EnemyRemovedFromGame, Data: id})
		}
	}
}

// --- Public Accessors & Mutators ---

func (g *Game) ClearEnemies() {
	for id := range g.ECS.Enemies {
		delete(g.ECS.Positions, id)
		delete(g.ECS.Velocities, id)
		delete(g.ECS.Paths, id)
		delete(g.ECS.Healths, id)
		delete(g.ECS.Renderables, id)
		delete(g.ECS.Enemies, id)
	}
}

func (g *Game) ClearProjectiles() {
	for id := range g.ECS.Projectiles {
		delete(g.ECS.Positions, id)
		delete(g.ECS.Velocities, id)
		delete(g.ECS.Renderables, id)
		delete(g.ECS.Projectiles, id)
	}
}

func (g *Game) HandleIndicatorClick() {
	if g.ECS.GameState.Phase == component.BuildState {
		g.StateSystem.SwitchToWaveState()
		g.ClearAllSelections()
	} else {
		g.StateSystem.SwitchToBuildState()
	}
}

func (g *Game) HandleSpeedClick() {
	g.SpeedButton.ToggleState()
	g.SpeedMultiplier = math.Pow(2, float64(g.SpeedButton.CurrentState))
}

func (g *Game) HandlePauseClick() {
	g.isPaused = !g.isPaused
	g.PauseButton.SetPaused(g.isPaused)
}

// IsPaused возвращает текущее состояние паузы.
func (g *Game) IsPaused() bool {
	return g.isPaused
}

// GetTowerHexesByType возвращает гексы, сгруппированные по типу башни.
func (g *Game) GetTowerHexesByType() ([]hexmap.Hex, []hexmap.Hex, []hexmap.Hex) {
	var wallHexes, typeAHexes, typeBHexes []hexmap.Hex

	for _, tower := range g.ECS.Towers {
		towerDef, ok := defs.TowerDefs[tower.DefID]
		if !ok {
			continue
		}
		isTypeA := towerDef.Type != defs.TowerTypeWall && towerDef.Type != defs.TowerTypeMiner
		isTypeB := towerDef.Type == defs.TowerTypeMiner

		if towerDef.Type == defs.TowerTypeWall {
			wallHexes = append(wallHexes, tower.Hex)
		} else if isTypeA {
			typeAHexes = append(typeAHexes, tower.Hex)
		} else if isTypeB {
			typeBHexes = append(typeBHexes, tower.Hex)
		}
	}
	return wallHexes, typeAHexes, typeBHexes
}

// GetAllTowerHexes возвращает все гексы с башнями одним списком.
func (g *Game) GetAllTowerHexes() []hexmap.Hex {
	var allHexes []hexmap.Hex
	for _, tower := range g.ECS.Towers {
		allHexes = append(allHexes, tower.Hex)
	}
	return allHexes
}

// GetTowerAtHex возвращает башню на указанном гексе, если она существует.
func (g *Game) GetTowerAtHex(hex hexmap.Hex) (*component.Tower, bool) {
	for _, tower := range g.ECS.Towers {
		if tower.Hex == hex {
			return tower, true
		}
	}
	return nil, false
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

// ToggleTowerSelectionForSave инвертирует состояние IsSelected для башни.
func (g *Game) ToggleTowerSelectionForSave(id types.EntityID) {
	if tower, ok := g.ECS.Towers[id]; ok {
		tower.IsSelected = !tower.IsSelected
	}
}

// SetHighlightedTower устанавливает башню, которая должна быть подсвечена для UI.
func (g *Game) SetHighlightedTower(id types.EntityID) {
	if g.highlightedTower != 0 {
		if tower, ok := g.ECS.Towers[g.highlightedTower]; ok {
			tower.IsHighlighted = false
		}
	}

	g.highlightedTower = id
	if id != 0 {
		if tower, ok := g.ECS.Towers[id]; ok {
			tower.IsHighlighted = true
		}
	}
}

func (g *Game) GetOreHexes() map[hexmap.Hex]float64 {
	oreHexes := make(map[hexmap.Hex]float64)
	for _, ore := range g.ECS.Ores {
		hex := utils.ScreenToHex(ore.Position.X, ore.Position.Y)
		oreHexes[hex] = ore.Power
	}
	return oreHexes
}

// --- Функции для режима перетаскивания линий ---

func (g *Game) ClearAllSelections() {
	g.SetHighlightedTower(0)

	if len(g.manuallySelectedTowers) > 0 {
		for _, towerID := range g.manuallySelectedTowers {
			if tower, ok := g.ECS.Towers[towerID]; ok {
				tower.IsManuallySelected = false
			}
		}
		g.manuallySelectedTowers = []types.EntityID{}
	}

	g.CraftingSystem.RecalculateCombinations()
}

func (g *Game) IsInLineDragMode() bool {
	return g.isLineDragging
}

func (g *Game) ClearManualSelection() {
	if len(g.manuallySelectedTowers) == 0 {
		return
	}
	for _, towerID := range g.manuallySelectedTowers {
		if tower, ok := g.ECS.Towers[towerID]; ok {
			tower.IsManuallySelected = false
		}
	}
	g.manuallySelectedTowers = []types.EntityID{}
	g.CraftingSystem.RecalculateCombinations()
}

func (g *Game) HandleShiftClick(hex hexmap.Hex, isLeftClick, isRightClick bool) {
	clickedTowerID, clickedOnTower := g.getTowerAt(hex)
	if !clickedOnTower {
		return
	}

	if isLeftClick {
		foundIndex := -1
		for i, id := range g.manuallySelectedTowers {
			if id == clickedTowerID {
				foundIndex = i
				break
			}
		}

		if foundIndex != -1 {
			g.manuallySelectedTowers = append(g.manuallySelectedTowers[:foundIndex], g.manuallySelectedTowers[foundIndex+1:]...)
			g.manuallySelectedTowers = append(g.manuallySelectedTowers, clickedTowerID)
		} else {
			g.manuallySelectedTowers = append(g.manuallySelectedTowers, clickedTowerID)
			if tower, ok := g.ECS.Towers[clickedTowerID]; ok {
				tower.IsManuallySelected = true
			}
		}
	} else if isRightClick {
		foundIndex := -1
		for i, id := range g.manuallySelectedTowers {
			if id == clickedTowerID {
				foundIndex = i
				break
			}
		}
		if foundIndex != -1 {
			if tower, ok := g.ECS.Towers[clickedTowerID]; ok {
				tower.IsManuallySelected = false
			}
			g.manuallySelectedTowers = append(g.manuallySelectedTowers[:foundIndex], g.manuallySelectedTowers[foundIndex+1:]...)
		}
	}
	g.CraftingSystem.RecalculateCombinations()
	log.Printf("Manual selection updated. Count: %d, IDs: %v", len(g.manuallySelectedTowers), g.manuallySelectedTowers)
}

func (g *Game) ToggleLineDragMode() {
	g.isLineDragging = !g.isLineDragging
	if !g.isLineDragging {
		g.CancelLineDrag()
	}
}

func (g *Game) HandleLineDragClick(hex hexmap.Hex, hitPoint rl.Vector3) {
	if g.dragSourceTowerID == 0 {
		g.startLineDrag(hex, hitPoint)
		return
	}
	g.finishLineDrag(hex)
}

func (g *Game) finishLineDrag(targetHex hexmap.Hex) {
	defer g.CancelLineDrag()

	targetID, ok := g.getTowerAt(targetHex)
	if !ok {
		return
	}

	if targetID == g.dragSourceTowerID || targetID == g.dragOriginalParentID {
		return
	}

	if g.isValidNewConnection(g.dragSourceTowerID, targetID, g.dragOriginalParentID) {
		g.reconnectTower(g.dragSourceTowerID, targetID, g.dragOriginalParentID)
	}
}

func (g *Game) isValidNewConnection(sourceID, targetID, originalParentID types.EntityID) bool {
	sourceTower := g.ECS.Towers[sourceID]
	targetTower := g.ECS.Towers[targetID]

	if !g.isValidConnection(sourceTower, targetTower) {
		return false
	}

	adj := g.buildAdjacencyList()
	adj[sourceID] = removeElement(adj[sourceID], originalParentID)
	adj[originalParentID] = removeElement(adj[originalParentID], sourceID)

	queue := []types.EntityID{targetID}
	visited := map[types.EntityID]bool{targetID: true}
	head := 0
	for head < len(queue) {
		current := queue[head]
		head++

		if current == sourceID {
			return false
		}

		for _, neighbor := range adj[current] {
			if !visited[neighbor] {
				visited[neighbor] = true
				queue = append(queue, neighbor)
			}
		}
	}

	adj[sourceID] = append(adj[sourceID], targetID)
	adj[targetID] = append(adj[targetID], sourceID)

	poweredSet := g.findPoweredTowersWithAdj(adj)
	_, isPowered := poweredSet[sourceID]
	return isPowered
}

func (g *Game) findPoweredTowersWithAdj(adj map[types.EntityID][]types.EntityID) map[types.EntityID]struct{} {
	poweredSet := make(map[types.EntityID]struct{})
	queue := []types.EntityID{}

	for id, tower := range g.ECS.Towers {
		towerDef, ok := defs.TowerDefs[tower.DefID]
		if !ok {
			continue
		}
		if towerDef.Type == defs.TowerTypeMiner && g.isOnOre(tower.Hex) {
			queue = append(queue, id)
			poweredSet[id] = struct{}{}
		}
	}

	head := 0
	for head < len(queue) {
		currentID := queue[head]
		head++

		if neighbors, ok := adj[currentID]; ok {
			for _, neighborID := range neighbors {
				if _, visited := poweredSet[neighborID]; !visited {
					poweredSet[neighborID] = struct{}{}
					queue = append(queue, neighborID)
				}
			}
		}
	}

	return poweredSet
}

func (g *Game) reconnectTower(sourceID, targetID, originalParentID types.EntityID) {
	if g.hiddenLineID != 0 {
		delete(g.ECS.LineRenders, g.hiddenLineID)
	}

	sourceTower := g.ECS.Towers[sourceID]
	targetTower := g.ECS.Towers[targetID]
	sourceDef := defs.TowerDefs[sourceTower.DefID]
	targetDef := defs.TowerDefs[targetTower.DefID]
	g.createLine(energyEdge{
		Tower1ID: sourceID,
		Tower2ID: targetID,
		Type1:    sourceDef.Type,
		Type2:    targetDef.Type,
		Distance: float64(sourceTower.Hex.Distance(targetTower.Hex)),
	})

	g.cleanupOrphanedLines()
	g.updateAllTowerAppearances()
}

func removeElement(slice []types.EntityID, element types.EntityID) []types.EntityID {
	result := []types.EntityID{}
	for _, item := range slice {
		if item != element {
			result = append(result, item)
		}
	}
	return result
}

func (g *Game) startLineDrag(hex hexmap.Hex, hitPoint rl.Vector3) {
	g.DebugInfo = nil

	sourceID, ok := g.getTowerAt(hex)
	if !ok {
		return
	}

	tower := g.ECS.Towers[sourceID]
	towerDef := defs.TowerDefs[tower.DefID]
	// Запрещаем перетаскивать линии от корневых майнеров (которые стоят на руде)
	isRootMiner := towerDef.Type == defs.TowerTypeMiner && g.isOnOre(tower.Hex)
	if isRootMiner {
		return
	}

	adj := g.buildAdjacencyList()
	connections, ok := adj[sourceID]
	if !ok || len(connections) == 0 {
		return
	}

	// Получаем 3D позицию исходной башни
	sourcePos3D := g.hexToWorld(tower.Hex)

	// Вычисляем угол клика на плоскости XZ
	clickAngle := math.Atan2(float64(hitPoint.Z-sourcePos3D.Z), float64(hitPoint.X-sourcePos3D.X))

	var bestMatchID types.EntityID
	minAngleDiff := math.Pi

	for _, neighborID := range connections {
		neighborTower, ok := g.ECS.Towers[neighborID]
		if !ok {
			continue
		}
		// Получаем 3D позицию соседней башни
		neighborPos3D := g.hexToWorld(neighborTower.Hex)

		// Вычисляем угол до соседа на плоскости XZ
		lineAngle := math.Atan2(float64(neighborPos3D.Z-sourcePos3D.Z), float64(neighborPos3D.X-sourcePos3D.X))
		angleDiff := math.Abs(clickAngle - lineAngle)
		if angleDiff > math.Pi {
			angleDiff = 2*math.Pi - angleDiff
		}

		if angleDiff < minAngleDiff {
			minAngleDiff = angleDiff
			bestMatchID = neighborID
		}
	}

	// Порог для определения "попадания" в линию
	if bestMatchID != 0 && minAngleDiff < math.Pi/3.5 {
		targetID := bestMatchID
		lineID, isConnected := g.getLineBetweenTowers(sourceID, targetID)
		if !isConnected {
			return
		}

		// ИСПРАВЛЕНО: Меняем местами источник и исходную точку
		g.dragSourceTowerID = targetID      // Источник - это сосед, от которого идет линия
		g.dragOriginalParentID = sourceID // А исходная точка - та, на которую кликнули
		g.hiddenLineID = lineID
	}
}

// hexToWorld - вспомогательная функция для преобразования гекса в мировые координаты
func (g *Game) hexToWorld(h hexmap.Hex) rl.Vector3 {
	x, y := h.ToPixel(float64(config.HexSize))
	return rl.NewVector3(float32(x*config.CoordScale), 0, float32(y*config.CoordScale))
}

func (g *Game) getLineBetweenTowers(tower1ID, tower2ID types.EntityID) (types.EntityID, bool) {
	for id, line := range g.ECS.LineRenders {
		if (line.Tower1ID == tower1ID && line.Tower2ID == tower2ID) ||
			(line.Tower1ID == tower2ID && line.Tower2ID == tower1ID) {
			return id, true
		}
	}
	return 0, false
}

func (g *Game) getTowerAt(hex hexmap.Hex) (types.EntityID, bool) {
	for id, tower := range g.ECS.Towers {
		if tower.Hex == hex {
			return id, true
		}
	}
	return 0, false
}

func (g *Game) GetDragSourceTowerID() types.EntityID {
	return g.dragSourceTowerID
}

func (g *Game) GetHiddenLineID() types.EntityID {
	return g.hiddenLineID
}

func (g *Game) GetDebugInfo() *LineDragDebugInfo {
	return g.DebugInfo
}

func (g *Game) CancelLineDrag() {
	g.isLineDragging = false
	g.dragSourceTowerID = 0
	g.dragOriginalParentID = 0
	g.hiddenLineID = 0
	g.DebugInfo = nil
}

func (g *Game) FinalizeTowerSelection() {
	towersToConvertToWalls := []hexmap.Hex{}
	idsToRemove := []types.EntityID{}

	for id, tower := range g.ECS.Towers {
		if !tower.IsTemporary {
			continue
		}

		if tower.IsSelected {
			tower.IsTemporary = false
		} else {
			idsToRemove = append(idsToRemove, id)
			towersToConvertToWalls = append(towersToConvertToWalls, tower.Hex)
		}
	}

	for _, id := range idsToRemove {
		g.deleteTowerEntity(id)
	}

	for _, hex := range towersToConvertToWalls {
		g.createPermanentWall(hex)
	}

	g.towersBuilt = 0
	g.ClearAllSelections()
	g.rebuildEnergyNetwork()
	g.AuraSystem.RecalculateAuras()
	g.CraftingSystem.RecalculateCombinations()
}

func (g *Game) CreateDebugTower(hex hexmap.Hex, towerDefID string) {
	if !g.canPlaceWall(hex) {
		return
	}

	if towerDefID == "RANDOM_ATTACK" {
		attackerIDs := []string{"TA", "TE", "TO", "DE", "NI", "NU", "PO", "PA", "PE"}
		towerDefID = attackerIDs[rand.Intn(len(attackerIDs))]
	}

	id := g.createTowerEntity(hex, towerDefID)
	if id == 0 {
		return
	}

	tower := g.ECS.Towers[id]
	tower.IsTemporary = false
	tower.IsSelected = false

	tile := g.HexMap.Tiles[hex]
	g.HexMap.Tiles[hex] = hexmap.Tile{Passable: false, CanPlaceTower: tile.CanPlaceTower}

	g.addTowerToEnergyNetwork(id)
	g.AuraSystem.RecalculateAuras()
	g.EventDispatcher.Dispatch(event.Event{Type: event.TowerPlaced, Data: hex})
}

func (g *Game) createPlayerEntity() {
	g.PlayerID = g.ECS.NewEntity()
	initialLevel := 1
	g.ECS.PlayerState[g.PlayerID] = &component.PlayerStateComponent{
		Level:         initialLevel,
		CurrentXP:     0,
		XPToNextLevel: config.CalculateXPForNextLevel(initialLevel),
	}
}
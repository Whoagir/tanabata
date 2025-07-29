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
	"io/ioutil"
	"log"
	"math"

	"golang.org/x/image/font"
	"golang.org/x/image/font/opentype"
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
	RenderSystem              *system.RenderSystem
	WaveSystem                *system.WaveSystem
	CombatSystem              *system.CombatSystem
	ProjectileSystem          *system.ProjectileSystem
	StateSystem               *system.StateSystem
	OreSystem                 *system.OreSystem
	AuraSystem                *system.AuraSystem
	StatusEffectSystem        *system.StatusEffectSystem
	EnvironmentalDamageSystem *system.EnvironmentalDamageSystem
	VisualEffectSystem        *system.VisualEffectSystem // Новая система
	CraftingSystem            *system.CraftingSystem     // Система крафта
	EventDispatcher           *event.Dispatcher
	FontFace                  font.Face
	towersBuilt               int // Счетчик для текущей фазы строительства
	SpeedButton               *ui.SpeedButton
	SpeedMultiplier           float64
	PauseButton               *ui.PauseButton
	gameTime                  float64
	DebugTowerType            int

	// Состояние для ручного выбора крафта
	manualCraftSelection []types.EntityID

	// Состояние для ручного выбора крафта
	ManualCraftSelection []types.EntityID

	// Состояние для перетаскивания линий
	isLineDragging       bool
	dragSourceTowerID    types.EntityID
	dragOriginalParentID types.EntityID
	hiddenLineID         types.EntityID // ID линии, скрытой на время перетаскивания
	DebugInfo            *LineDragDebugInfo
}

// NewGame initializes a new game instance.
func NewGame(hexMap *hexmap.HexMap) *Game {
	if hexMap == nil {
		panic("hexMap cannot be nil")
	}

	fontData, err := ioutil.ReadFile("assets/fonts/arial.ttf")
	if err != nil {
		log.Fatal(err)
	}
	tt, err := opentype.Parse(fontData)
	if err != nil {
		log.Fatal(err)
	}
	const fontSize = 11
	face, err := opentype.NewFace(tt, &opentype.FaceOptions{
		Size:    fontSize,
		DPI:     72,
		Hinting: font.HintingFull,
	})
	if err != nil {
		log.Fatal(err)
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
		FontFace:        face,
		towersBuilt:     0,
		gameTime:        0.0,
		DebugTowerType:  config.TowerTypeNone,
	}
	g.RenderSystem = system.NewRenderSystem(ecs, tt)
	g.CombatSystem = system.NewCombatSystem(ecs, g.FindPowerSourcesForTower, g.FindPathToPowerSource)
	g.ProjectileSystem = system.NewProjectileSystem(ecs, eventDispatcher, g.CombatSystem) // Передаем CombatSystem
	g.StateSystem = system.NewStateSystem(ecs, g, eventDispatcher)
	g.AuraSystem = system.NewAuraSystem(ecs)
	g.StatusEffectSystem = system.NewStatusEffectSystem(ecs)
	g.EnvironmentalDamageSystem = system.NewEnvironmentalDamageSystem(ecs)
	g.VisualEffectSystem = system.NewVisualEffectSystem(ecs)   // Инициализация
	g.CraftingSystem = system.NewCraftingSystem(ecs, g.HexMap) // Инициализация системы крафта
	g.generateOre()
	g.initUI()

	// Создаем слушателя и подписываем его на события
	listener := &GameEventListener{game: g}
	eventDispatcher.Subscribe(event.OreDepleted, listener)
	eventDispatcher.Subscribe(event.WaveEnded, listener)

	// Подписываем систему крафта на события
	eventDispatcher.Subscribe(event.TowerPlaced, g.CraftingSystem)
	eventDispatcher.Subscribe(event.TowerRemoved, g.CraftingSystem)
	eventDispatcher.Subscribe(event.CombineTowersRequest, listener)

	g.placeInitialStones()

	return g
}

// CombineTowers выполняет логику объединения башен.
func (g *Game) CombineTowers(clickedTowerID types.EntityID) {
	combinable, ok := g.ECS.Combinables[clickedTowerID]
	if !ok || len(combinable.PossibleCrafts) == 0 {
		return // У башни нет доступных крафтов
	}

	// ВРЕМЕННАЯ ЗАГЛУШКА: выполняем первый доступный крафт.
	craftToPerform := combinable.PossibleCrafts[0]
	recipe := craftToPerform.Recipe
	combination := craftToPerform.Combination

	// 1. Превращаем целевую (кликнутую) башню в результирующую башню
	outputDef := defs.TowerLibrary[recipe.OutputID]
	if tower, ok := g.ECS.Towers[clickedTowerID]; ok {
		tower.DefID = recipe.OutputID
		tower.Type = g.mapTowerIDToNumericType(recipe.OutputID)

		// Обновляем или создаем боевой компонент
		if outputDef.Combat != nil {
			if combat, ok := g.ECS.Combats[clickedTowerID]; ok {
				combat.FireRate = outputDef.Combat.FireRate
				combat.Range = outputDef.Combat.Range
				combat.ShotCost = outputDef.Combat.ShotCost
				if outputDef.Combat.Attack != nil {
					combat.Attack = *outputDef.Combat.Attack
				}
			} else {
				g.ECS.Combats[clickedTowerID] = &component.Combat{
					FireRate: outputDef.Combat.FireRate,
					Range:    outputDef.Combat.Range,
					ShotCost: outputDef.Combat.ShotCost,
					Attack:   *outputDef.Combat.Attack,
				}
			}
		} else {
			// Если у новой башни нет боевых характеристик, удаляем компонент
			delete(g.ECS.Combats, clickedTowerID)
		}

		// Обновляем визуальный компонент
		if renderable, ok := g.ECS.Renderables[clickedTowerID]; ok {
			renderable.Color = outputDef.Visuals.Color
			renderable.Radius = float32(config.HexSize * outputDef.Visuals.RadiusFactor)
		}
	}

	// 2. Превращаем остальные башни из комбинации в стены
	wallDef := defs.TowerLibrary["TOWER_WALL"]
	for _, id := range combination {
		if id == clickedTowerID {
			continue // Пропускаем саму целевую башню
		}
		if tower, ok := g.ECS.Towers[id]; ok {
			// Удаляем ненужные компоненты
			delete(g.ECS.Combats, id)
			delete(g.ECS.Auras, id)
			// Прев��ащаем в стену
			tower.DefID = "TOWER_WALL"
			tower.Type = config.TowerTypeWall
			if renderable, ok := g.ECS.Renderables[id]; ok {
				renderable.Color = wallDef.Visuals.Color
				renderable.Radius = float32(config.HexSize * wallDef.Visuals.RadiusFactor)
			}
		}
	}

	// 3. Пересчитываем состояние игры, так как состав башен кардинально изменился
	g.CraftingSystem.RecalculateCombinations()
	g.AuraSystem.RecalculateAuras()
	g.rebuildEnergyNetwork()
}

// FindPathToPowerSource находит кратчайший путь от атакующей башни до ближайшего
// источника энергии (башни-добытчика на активной руде).
// Возвращает срез ID башен, составляющих путь.
func (g *Game) FindPathToPowerSource(startNode types.EntityID) []types.EntityID {
	if _, exists := g.ECS.Towers[startNode]; !exists {
		return nil
	}

	adj := g.buildAdjacencyList()
	queue := []types.EntityID{startNode}
	visited := map[types.EntityID]bool{startNode: true}
	parent := make(map[types.EntityID]types.EntityID)

	var pathEnd types.EntityID

	// BFS для поиска ближайшего источника
	head := 0
	for head < len(queue) {
		currentID := queue[head]
		head++

		tower := g.ECS.Towers[currentID]
		if tower.Type == config.TowerTypeMiner && g.isOnOre(tower.Hex) {
			pathEnd = currentID
			break // Найден ближайший источник, выходим
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

	// Если источник не найден, возвращаем nil
	if pathEnd == 0 {
		return nil
	}

	// Восстанавливаем путь от источника до атакующей башни
	path := []types.EntityID{}
	for curr := pathEnd; curr != 0; curr = parent[curr] {
		path = append(path, curr)
	}

	// Разворачиваем путь, чтобы он шел от атакующей башни к источнику
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
		// log.Printf("[Log] Game: Received OreDepleted event for ore %d. Re-evaluating power grid.\n", e.Data.(types.EntityID))

		// 1. Определить новый набор запитанных башен от оставшихся источников руды.
		poweredSet := l.game.findPoweredTowers()

		// 2. Обновить статус IsActive для всех башен.
		for id, tower := range l.game.ECS.Towers {
			if _, isPowered := poweredSet[id]; isPowered {
				tower.IsActive = true
			} else {
				tower.IsActive = false
			}
		}

		// 3. Удалить линии, которые теперь подключены к неактивным башням.
		l.game.cleanupOrphanedLines()

		// 4. Обновить визуальное представление всех башен (цвет).
		l.game.updateAllTowerAppearances()
	case event.WaveEnded:
		l.game.StateSystem.SwitchToBuildState()
	case event.CombineTowersRequest:
		if towerID, ok := e.Data.(types.EntityID); ok {
			l.game.CombineTowers(towerID)
		}
	}
}

// placeInitialStones places stones around checkpoints at the start of the game.
func (g *Game) placeInitialStones() {
	center := hexmap.Hex{Q: 0, R: 0}
	for _, checkpoint := range g.HexMap.Checkpoints {
		// --- Place stones towards the center ---
		dirIn := center.Subtract(checkpoint).Direction()
		for i := 1; i <= 2; i++ {
			hexToPlace := checkpoint.Add(dirIn.Scale(i))
			if g.canPlaceWall(hexToPlace) {
				g.createPermanentWall(hexToPlace)
			}
		}

		// --- Place stones towards the edge ---
		dirOut := checkpoint.Subtract(center).Direction()
		for i := 1; ; i++ {
			hexToPlace := checkpoint.Add(dirOut.Scale(i))
			if g.canPlaceWall(hexToPlace) {
				g.createPermanentWall(hexToPlace)
			} else {
				// Stop if we hit the edge of the map, an invalid tile, or a path blockage
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
	g.VisualEffectSystem.Update(dt) // Обновление новой системы

	if g.ECS.GameState.Phase == component.WaveState {
		g.StatusEffectSystem.Update(dt)
		g.CombatSystem.Update(dt)
		g.ProjectileSystem.Update(dt)
		g.WaveSystem.Update(dt, g.ECS.Wave)
		g.MovementSystem.Update(dt)
		g.EnvironmentalDamageSystem.Update(dt)
		g.cleanupDestroyedEntities()
	}
	// OreSystem должен обновляться ПОСЛЕ всех систем, которые могут изменить
	// состояние руды (CombatSystem) или состояние игры (WaveSystem).
	// Это гарантирует, что удаление руды и перестройка сети произойдут
	// на основе самых актуальных данных за этот кадр.
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
}

func (g *Game) cleanupDestroyedEntities() {
	for id := range g.ECS.Enemies { // Итерируем только по врагам
		// Условие 1: Враг дошел до конца пути
		path, hasPath := g.ECS.Paths[id]
		reachedEnd := hasPath && path.CurrentIndex >= len(path.Hexes)

		// Условие 2: У врага закончилось здоровье
		health, hasHealth := g.ECS.Healths[id]
		noHealth := hasHealth && health.Value <= 0

		if reachedEnd || noHealth {
			// Удаляем все компоненты сущности
			delete(g.ECS.Positions, id)
			delete(g.ECS.Velocities, id)
			delete(g.ECS.Paths, id)
			delete(g.ECS.Healths, id)
			delete(g.ECS.Renderables, id)
			delete(g.ECS.Enemies, id) // Удаляем из списка врагов
			g.EventDispatcher.Dispatch(event.Event{Type: event.EnemyDestroyed, Data: id})
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

// GetTowerHexesByType возвращает гексы, сгруппированные по типу башни.
func (g *Game) GetTowerHexesByType() ([]hexmap.Hex, []hexmap.Hex, []hexmap.Hex) {
	var wallHexes, typeAHexes, typeBHexes []hexmap.Hex

	for _, tower := range g.ECS.Towers {
		// Башни типа A - все, кроме стен и добытчиков
		isTypeA := tower.Type != config.TowerTypeWall && tower.Type != config.TowerTypeMiner
		// Башни типа B - только добытчики
		isTypeB := tower.Type == config.TowerTypeMiner

		if tower.Type == config.TowerTypeWall {
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

func (g *Game) SetTowersBuilt(count int) {
	g.towersBuilt = count
}

func (g *Game) GetTowersBuilt() int {
	return g.towersBuilt
}

func (g *Game) GetGameTime() float64 {
	return g.gameTime
}

func (g *Game) GetOreHexes() map[hexmap.Hex]float64 {
	oreHexes := make(map[hexmap.Hex]float64)
	for _, ore := range g.ECS.Ores {
		// Используем новую утилиту для корректного преобразования
		hex := utils.ScreenToHex(ore.Position.X, ore.Position.Y)
		oreHexes[hex] = ore.Power
	}
	return oreHexes
}

// --- Функции для режима перетаскивания линий ---

// IsInLineDragMode возвращает true, если игра в режиме перетаскивания линий.
func (g *Game) IsInLineDragMode() bool {
	return g.isLineDragging
}

// ToggleLineDragMode переключает режим перетаскивания линий.
func (g *Game) ToggleLineDragMode() {
	g.isLineDragging = !g.isLineDragging

	// Если выключаем режим, сбрасываем все
	if !g.isLineDragging {
		g.CancelLineDrag() // Используем уже существующую логику сброса
	}
}

// HandleLineDragClick обрабатывает клик в режиме перетаскивания.
func (g *Game) HandleLineDragClick(hex hexmap.Hex, x, y int) {
	// Если мы еще не начали тащить линию
	if g.dragSourceTowerID == 0 {
		g.startLineDrag(hex, x, y)
		return
	}

	// Если мы уже тащим линию и кликнули на цель
	g.finishLineDrag(hex)
}

// finishLineDrag завершает процесс перетаскивания линии на целевой гекс.
func (g *Game) finishLineDrag(targetHex hexmap.Hex) {
	defer g.CancelLineDrag() // В любом случае выходим из режима перетаскивания

	targetID, ok := g.getTowerAt(targetHex)
	if !ok {
		return // Цели нет
	}

	if targetID == g.dragSourceTowerID || targetID == g.dragOriginalParentID {
		return // Нельзя подключиться к самому себе или к своему бывшему родителю
	}

	if g.isValidNewConnection(g.dragSourceTowerID, targetID, g.dragOriginalParentID) {
		g.reconnectTower(g.dragSourceTowerID, targetID, g.dragOriginalParentID)
	}
}

// isValidNewConnection проверяет, можно ли создать новую связь.
func (g *Game) isValidNewConnection(sourceID, targetID, originalParentID types.EntityID) bool {
	sourceTower := g.ECS.Towers[sourceID]
	targetTower := g.ECS.Towers[targetID]

	// 1. Проверка на расстояние и тип
	if !g.isValidConnection(sourceTower, targetTower) {
		return false
	}

	// --- Создаем временный граф, отсоединив перетаскиваемую башню ---
	adj := g.buildAdjacencyList()
	adj[sourceID] = removeElement(adj[sourceID], originalParentID)
	adj[originalParentID] = removeElement(adj[originalParentID], sourceID)

	// 2. Проверка на циклы: можно ли из новой цели достичь источника ДО создания новой связи?
	queue := []types.EntityID{targetID}
	visited := map[types.EntityID]bool{targetID: true}
	head := 0
	for head < len(queue) {
		current := queue[head]
		head++

		if current == sourceID {
			return false // Цикл найден!
		}

		for _, neighbor := range adj[current] {
			if !visited[neighbor] {
				visited[neighbor] = true
				queue = append(queue, neighbor)
			}
		}
	}

	// 3. Проверка на "выключение" графа: добавляем новую связь и проверяем питание
	adj[sourceID] = append(adj[sourceID], targetID)
	adj[targetID] = append(adj[targetID], sourceID)

	poweredSet := g.findPoweredTowersWithAdj(adj)
	if _, isPowered := poweredSet[sourceID]; !isPowered {
		return false // Башня теряет питание, подключение невалидно
	}

	return true
}

// findPoweredTowersWithAdj находит все запитанные башни, используя предоставленный список смежности.
func (g *Game) findPoweredTowersWithAdj(adj map[types.EntityID][]types.EntityID) map[types.EntityID]struct{} {
	poweredSet := make(map[types.EntityID]struct{})
	queue := []types.EntityID{}

	// Начинаем с корневых башен (добытчики на руде)
	for id, tower := range g.ECS.Towers {
		if tower.Type == config.TowerTypeMiner && g.isOnOre(tower.Hex) {
			queue = append(queue, id)
			poweredSet[id] = struct{}{}
		}
	}

	// BFS для поиска всех достижимых (запитанных) башен
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

// reconnectTower выполняет фактическое переподключение башни.
func (g *Game) reconnectTower(sourceID, targetID, originalParentID types.EntityID) {
	// 1. Удалить старую (скрытую) линию
	if g.hiddenLineID != 0 {
		delete(g.ECS.LineRenders, g.hiddenLineID)
	}

	// 2. Создать новую линию
	sourceTower := g.ECS.Towers[sourceID]
	targetTower := g.ECS.Towers[targetID]
	g.createLine(energyEdge{
		Tower1ID: sourceID,
		Tower2ID: targetID,
		Type1:    sourceTower.Type,
		Type2:    targetTower.Type,
		Distance: float64(sourceTower.Hex.Distance(targetTower.Hex)),
	})

	// 3. Обновить состояние (на всякий случай)
	g.cleanupOrphanedLines()
	g.updateAllTowerAppearances()
}

// removeElement удаляет элемент из среза.
func removeElement(slice []types.EntityID, element types.EntityID) []types.EntityID {
	result := []types.EntityID{}
	for _, item := range slice {
		if item != element {
			result = append(result, item)
		}
	}
	return result
}

// startLineDrag начинает процесс перетаскивания линии от башни на указанном гексе.
func (g *Game) startLineDrag(hex hexmap.Hex, x, y int) {
	g.DebugInfo = nil // Сбрасываем отладку при каждом клике

	sourceID, ok := g.getTowerAt(hex)
	if !ok {
		return // На гексе нет башни
	}

	// Нельзя перетаскивать от корневых добытчиков
	tower := g.ECS.Towers[sourceID]
	isRootMiner := tower.Type == config.TowerTypeMiner && g.isOnOre(tower.Hex)
	if isRootMiner {
		return
	}

	// Получаем все существующие соединения для этой башни
	adj := g.buildAdjacencyList()
	connections, ok := adj[sourceID]
	if !ok || len(connections) == 0 {
		return // Нет линий для перетаскивания
	}

	// Находим позицию центра исходной башни
	sourcePos, ok := g.ECS.Positions[sourceID]
	if !ok {
		return // У башни нет позиции (не должно случиться)
	}

	// Вычисляем угол клика относительно центра башни
	clickAngle := math.Atan2(float64(y)-sourcePos.Y, float64(x)-sourcePos.X)

	var bestMatchID types.EntityID
	minAngleDiff := math.Pi // Максимально возможная разница в углах

	// Ищем линию, угол которой наиболее близок к углу клика
	for _, neighborID := range connections {
		neighborPos, ok := g.ECS.Positions[neighborID]
		if !ok {
			continue
		}

		// Угол от исходной башни до соседа
		lineAngle := math.Atan2(neighborPos.Y-sourcePos.Y, neighborPos.X-sourcePos.X)

		// Вычисляем абсолютную разницу углов, учитывая "переход" через 2*Pi
		angleDiff := math.Abs(clickAngle - lineAngle)
		if angleDiff > math.Pi {
			angleDiff = 2*math.Pi - angleDiff
		}

		if angleDiff < minAngleDiff {
			minAngleDiff = angleDiff
			bestMatchID = neighborID
		}
	}

	// Проверяем, что клик был достаточно близок к направлению одной из линий
	// (Pi / 3.5 ~ 51.4 градуса, чуть меньше 60-градусного сектора для надежности)
	if bestMatchID != 0 && minAngleDiff < math.Pi/3.5 {
		targetID := bestMatchID
		lineID, isConnected := g.getLineBetweenTowers(sourceID, targetID)
		if !isConnected {
			return // Не должно произойти, но на всякий случай
		}

		// Начинаем перетаскивание
		g.dragSourceTowerID = sourceID
		g.dragOriginalParentID = targetID
		g.hiddenLineID = lineID
	}
}

// getLineBetweenTowers ищет линию, соединяющую две башни, и возвращает ее ID.
func (g *Game) getLineBetweenTowers(tower1ID, tower2ID types.EntityID) (types.EntityID, bool) {
	for id, line := range g.ECS.LineRenders {
		if (line.Tower1ID == tower1ID && line.Tower2ID == tower2ID) ||
			(line.Tower1ID == tower2ID && line.Tower2ID == tower1ID) {
			return id, true
		}
	}
	return 0, false
}

// getTowerAt возвращает ID башни на указанном гексе.
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
	g.hiddenLineID = 0 // "Показываем" линию обратно
	g.DebugInfo = nil
}

// AddToManualSelection добавляет башню в список ручного выбора для крафта.
func (g *Game) AddToManualSelection(id types.EntityID) {
	g.ManualCraftSelection = append(g.ManualCraftSelection, id)
	log.Printf("Added tower %d to manual selection. Current selection: %v", id, g.ManualCraftSelection)
}

// FinalizeTowerSelection обрабатывает окончание фазы выбора башен.
func (g *Game) FinalizeTowerSelection() {
	towersToConvertToWalls := []hexmap.Hex{}
	idsToRemove := []types.EntityID{}

	// Сначала собираем информацию, не изменяя срез во время итерации
	for id, tower := range g.ECS.Towers {
		if !tower.IsTemporary {
			continue
		}

		if tower.IsSelected {
			// Башня выбрана, делаем ее постоянной
			tower.IsTemporary = false
		} else {
			// Башня не выбрана, помечаем ее для удаления и запоминаем ее местоположение
			idsToRemove = append(idsToRemove, id)
			towersToConvertToWalls = append(towersToConvertToWalls, tower.Hex)
		}
	}

	// Удаляем все помеченные башни
	for _, id := range idsToRemove {
		g.deleteTowerEntity(id)
	}

	// Теперь создаем стены на месте удаленных башен
	for _, hex := range towersToConvertToWalls {
		g.createPermanentWall(hex)
	}

	// Сбрасываем счетчик построенных башен для следующей фазы
	g.towersBuilt = 0

	// Полностью пересчитываем состояние всех систем, зависящих от набора башен
	g.rebuildEnergyNetwork()
	g.AuraSystem.RecalculateAuras()
	g.CraftingSystem.RecalculateCombinations()
}

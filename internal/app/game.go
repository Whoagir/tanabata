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
	"io/ioutil"
	"log"

	"golang.org/x/image/font"
	"golang.org/x/image/font/opentype"
)

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
	EnvironmentalDamageSystem *system.EnvironmentalDamageSystem
	VisualEffectSystem        *system.VisualEffectSystem // Новая система
	EventDispatcher           *event.Dispatcher
	FontFace                  font.Face
	towersBuilt               int
	SpeedButton               *ui.SpeedButton
	SpeedMultiplier           float64
	PauseButton               *ui.PauseButton
	gameTime                  float64
	DebugTowerType            int
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
		Size:	fontSize,
		DPI:	72,
		Hinting: font.HintingFull,
	})
	if err != nil {
		log.Fatal(err)
	}

	ecs := entity.NewECS()
	eventDispatcher := event.NewDispatcher()
	g := &Game{
		HexMap:			hexMap,
		Wave:			1,
		BaseHealth:		config.BaseHealth,
		ECS:			ecs,
		MovementSystem:	system.NewMovementSystem(ecs),
		WaveSystem:		system.NewWaveSystem(ecs, hexMap, eventDispatcher),
		OreSystem:		system.NewOreSystem(ecs, eventDispatcher),
		EventDispatcher:	eventDispatcher,
		FontFace:		face,
		towersBuilt:	0,
		gameTime:		0.0,
		DebugTowerType:	config.TowerTypeNone,
	}
	g.RenderSystem = system.NewRenderSystem(ecs, g.FontFace)
	g.CombatSystem = system.NewCombatSystem(ecs, g.FindPowerSourcesForTower)
	g.ProjectileSystem = system.NewProjectileSystem(ecs, eventDispatcher, g.CombatSystem)
	g.StateSystem = system.NewStateSystem(ecs, g, eventDispatcher)
	g.EnvironmentalDamageSystem = system.NewEnvironmentalDamageSystem(ecs)
	g.VisualEffectSystem = system.NewVisualEffectSystem(ecs) // Инициализация
	g.generateOre()
	g.initUI()

	// Создаем слушателя и подписываем его на события
	listener := &GameEventListener{game: g}
	eventDispatcher.Subscribe(event.OreDepleted, listener)

	g.placeInitialStones()

	return g
}

// GameEventListener обрабатывает события, важные для основного игрового цикла.
type GameEventListener struct {
	game *Game
}

// OnEvent реализует интерфейс event.Listener.
func (l *GameEventListener) OnEvent(e event.Event) {
	if e.Type == event.OreDepleted {
		log.Printf("[Log] Game: Received OreDepleted event for ore %d. Rebuilding network.\n", e.Data.(types.EntityID))
		// Когда руда истощается, необходимо перестроить всю энергосеть,
		// ч��обы деактивировать башни, потерявшие источник питания.
		l.game.rebuildEnergyNetwork()
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

	g.VisualEffectSystem.Update(dt) // Обновление новой системы

	if g.ECS.GameState == component.WaveState {
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
		hex := hexmap.PixelToHex(ore.Position.X, ore.Position.Y, config.HexSize)
		oreHexes[hex] = ore.Power
	}
	return oreHexes
}

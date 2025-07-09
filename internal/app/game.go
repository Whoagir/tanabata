// internal/app/game.go
package app

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/event"
	"go-tower-defense/internal/system"
	"go-tower-defense/internal/ui"
	"go-tower-defense/pkg/hexmap"
	"image/color"
	"io/ioutil"
	"log"
	"fmt"

	"golang.org/x/image/font"
	"golang.org/x/image/font/opentype"
)

// Game holds the main game state and logic.
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
	OreSystem        *system.OreSystem
	EventDispatcher  *event.Dispatcher
	FontFace         font.Face // <-- Добавлено
	towersBuilt      int
	SpeedButton      *ui.SpeedButton
	SpeedMultiplier  float64
	PauseButton      *ui.PauseButton
	gameTime         float64
}

// NewGame initializes a new game instance.
func NewGame(hexMap *hexmap.HexMap) *Game {
	if hexMap == nil {
		panic("hexMap cannot be nil")
	}

	// Загрузка шрифта
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
		HexMap:           hexMap,
		Wave:             1,
		BaseHealth:       config.BaseHealth,
		ECS:              ecs,
		MovementSystem:   system.NewMovementSystem(ecs),
		WaveSystem:       system.NewWaveSystem(ecs, hexMap, eventDispatcher),
		ProjectileSystem: system.NewProjectileSystem(ecs, eventDispatcher),
		OreSystem:        system.NewOreSystem(ecs),
		EventDispatcher:  eventDispatcher,
		FontFace:         face, // <-- Добавлено
		towersBuilt:      0,
		gameTime:         0.0,
	}
	g.RenderSystem = system.NewRenderSystem(ecs, g.FontFace) // <-- Изменено
	g.CombatSystem = system.NewCombatSystem(ecs, g.FindPowerSourcesForTower)
	g.StateSystem = system.NewStateSystem(ecs, g, eventDispatcher)
	g.createOreEntities()
	g.initUI()
	return g
}

// Update progresses the game state by one frame.
func (g *Game) Update(deltaTime float64) {
	dt := deltaTime * g.SpeedMultiplier
	g.gameTime += dt
	g.ECS.GameTime = g.gameTime

	g.OreSystem.Update() // <-- Добавлено

	if g.ECS.GameState == component.WaveState {
		g.CombatSystem.Update(dt)
		g.ProjectileSystem.Update(dt)
		g.WaveSystem.Update(dt, g.ECS.Wave)
		g.MovementSystem.Update(dt)
		g.cleanupDestroyedEntities()
	}
}

// StartWave begins the enemy wave.
func (g *Game) StartWave() {
	g.ECS.Wave = g.WaveSystem.StartWave(g.Wave)
	g.WaveSystem.ResetActiveEnemies()
	g.Wave++
}

// --- Private Helper Functions ---

func (g *Game) createOreEntities() {
	for hex, power := range g.HexMap.EnergyVeins {
		id := g.ECS.NewEntity()
		px, py := hex.ToPixel(config.HexSize)
		px += float64(config.ScreenWidth) / 2
		py += float64(config.ScreenHeight) / 2
		g.ECS.Positions[id] = &component.Position{X: px, Y: py}
		g.ECS.Ores[id] = &component.Ore{
			Power:          power,
			MaxReserve:     power * 100, // База для расчета процентов
			CurrentReserve: power * 100,
			Position:       component.Position{X: px, Y: py},
			Radius:         float32(config.HexSize*0.2 + power*config.HexSize),
			Color:          color.RGBA{0, 0, 255, 128},
			PulseRate:      2.0,
		}
		g.ECS.Texts[id] = &component.Text{
			Value:    fmt.Sprintf("%.0f%%", power*100),
			Position: component.Position{X: px, Y: py},
			Color:    color.RGBA{R: 50, G: 50, B: 50, A: 255},
			IsUI:     true,
		}
	}
}

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

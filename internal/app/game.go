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
	"log"
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
	g.gameTime += dt // Накапливаем игровое время
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

func (g *Game) PlaceTower(hex hexmap.Hex) bool {
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

	originalPassable := tile.Passable
	g.HexMap.Tiles[hex] = hexmap.Tile{Passable: false, CanPlaceTower: tile.CanPlaceTower}
	checkpoints := g.HexMap.Checkpoints
	current := g.HexMap.Entry
	for i, cp := range checkpoints {
		path := hexmap.AStar(current, cp, g.HexMap)
		if path == nil {
			g.HexMap.Tiles[hex] = hexmap.Tile{Passable: originalPassable, CanPlaceTower: tile.CanPlaceTower}
			log.Println("Путь до чекпоинта", i+1, "заблокирован!")
			return false
		}
		current = cp
	}
	pathToExit := hexmap.AStar(current, g.HexMap.Exit, g.HexMap)
	g.HexMap.Tiles[hex] = hexmap.Tile{Passable: originalPassable, CanPlaceTower: tile.CanPlaceTower}
	if pathToExit == nil {
		log.Println("Путь до выхода заблокирован!")
		return false
	}

	id := g.ECS.NewEntity()
	px, py := hex.ToPixel(config.HexSize)
	px += float64(config.ScreenWidth) / 2
	py += float64(config.ScreenHeight) / 2
	g.ECS.Positions[id] = &component.Position{X: px, Y: py}

	towerType := rand.Intn(4)
	isActive := g.towersBuilt == 0
	g.ECS.Towers[id] = &component.Tower{
		Type:     towerType,
		Range:    config.TowerRange,
		Hex:      hex,
		IsActive: isActive,
	}

	if isActive {
		g.ECS.Combats[id] = &component.Combat{
			FireRate:     config.TowerFireRate[towerType],
			FireCooldown: 0,
			Range:        config.TowerRange,
		}
	}

	color := config.TowerColors[towerType]
	if !isActive {
		color = config.TowerColors[4]
	}
	g.ECS.Renderables[id] = &component.Renderable{
		Color:     color,
		Radius:    float32(config.HexSize * config.TowerRadiusFactor),
		HasStroke: true,
	}

	g.HexMap.Tiles[hex] = hexmap.Tile{Passable: false, CanPlaceTower: tile.CanPlaceTower}
	g.towersBuilt++

	g.EventDispatcher.Dispatch(event.Event{Type: event.TowerPlaced, Data: hex})

	if g.towersBuilt >= config.MaxTowersInBuildPhase {
		g.StateSystem.SwitchToWaveState()
	}

	return true
}

func (g *Game) RemoveTower(hex hexmap.Hex) bool {
	if g.ECS.GameState != component.BuildState {
		return false
	}

	for id, tower := range g.ECS.Towers {
		if tower.Hex == hex {
			delete(g.ECS.Positions, id)
			delete(g.ECS.Towers, id)
			delete(g.ECS.Combats, id)
			delete(g.ECS.Renderables, id)

			if tile, exists := g.HexMap.Tiles[hex]; exists {
				tile.Passable = true
				g.HexMap.Tiles[hex] = tile
			}

			g.EventDispatcher.Dispatch(event.Event{Type: event.TowerRemoved, Data: hex})
			return true
		}
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

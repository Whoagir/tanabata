// internal/system/wave.go
package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/event"
	"go-tower-defense/pkg/hexmap"
	"log"
)

type WaveSystem struct {
	ecs             *entity.ECS
	hexMap          *hexmap.HexMap
	eventDispatcher *event.Dispatcher
	activeEnemies   int
}

func NewWaveSystem(ecs *entity.ECS, hexMap *hexmap.HexMap, eventDispatcher *event.Dispatcher) *WaveSystem {
	ws := &WaveSystem{
		ecs:             ecs,
		hexMap:          hexMap,
		eventDispatcher: eventDispatcher,
		activeEnemies:   0,
	}
	eventDispatcher.Subscribe(event.EnemyDestroyed, ws)
	return ws
}

func (s *WaveSystem) Update(deltaTime float64, wave *component.Wave) {
	if wave == nil {
		// log.Println("Wave is nil!")
		return
	}
	// log.Println("Updating wave, EnemiesToSpawn:", wave.EnemiesToSpawn, "ActiveEnemies:", s.activeEnemies)
	if wave.EnemiesToSpawn > 0 {
		wave.SpawnTimer += deltaTime
		if wave.SpawnTimer >= wave.SpawnInterval {
			s.spawnEnemy(wave)
			wave.EnemiesToSpawn--
			wave.SpawnTimer = 0

			newInterval := config.InitialSpawnInterval - config.SpawnIntervalDecrement*wave.Number
			if newInterval < config.MinSpawnInterval {
				newInterval = config.MinSpawnInterval
			}
			wave.SpawnInterval = float64(newInterval) / 1000.0
		}
	} else if wave.EnemiesToSpawn == 0 && s.activeEnemies == 0 {
		s.eventDispatcher.Dispatch(event.Event{Type: event.WaveEnded})
		// log.Println("WaveEnded event dispatched") // Лог отправки события
	}
	// log.Println("EnemiesToSpawn:", wave.EnemiesToSpawn, "ActiveEnemies:", s.activeEnemies) // Лог состояния
}

func (s *WaveSystem) ResetActiveEnemies() {
	s.activeEnemies = 0
}

func (s *WaveSystem) spawnEnemy(wave *component.Wave) {
	id := s.ecs.NewEntity()
	x, y := s.hexMap.Entry.ToPixel(config.HexSize)
	s.ecs.Positions[id] = &component.Position{X: x + float64(config.ScreenWidth)/2, Y: y + float64(config.ScreenHeight)/2}
	s.ecs.Velocities[id] = &component.Velocity{Speed: config.EnemySpeed}
	s.ecs.Paths[id] = &component.Path{Hexes: wave.CurrentPath, CurrentIndex: 0}
	s.ecs.Healths[id] = &component.Health{Value: config.EnemyHealth}
	s.ecs.Renderables[id] = &component.Renderable{Color: config.EnemyColor, Radius: float32(config.EnemyRadius), HasStroke: false}
	s.ecs.Enemies[id] = &component.Enemy{OreDamageCooldown: 0, LineDamageCooldown: 0}
	s.activeEnemies++
}

func (s *WaveSystem) StartWave(waveNumber int) *component.Wave {
	enemiesToSpawn := config.EnemiesPerWave + (waveNumber-1)*config.EnemiesIncrementPerWave
	fullPath := []hexmap.Hex{}

	if len(s.hexMap.Checkpoints) == 0 {
		path := hexmap.AStar(s.hexMap.Entry, s.hexMap.Exit, s.hexMap)
		if path == nil {
			log.Println("Не удалось найти путь от входа до выхода при старте волны!")
			return nil
		}
		fullPath = path
	} else {
		current := s.hexMap.Entry
		for i, cp := range s.hexMap.Checkpoints {
			pathSegment := hexmap.AStar(current, cp, s.hexMap)
			if pathSegment == nil {
				log.Println("Не удалось найти путь до чекпоинта", i+1, "при старте волны!")
				return nil
			}
			if len(fullPath) == 0 {
				fullPath = pathSegment
			} else {
				fullPath = append(fullPath, pathSegment[1:]...)
			}
			current = cp
		}
		pathToExit := hexmap.AStar(current, s.hexMap.Exit, s.hexMap)
		if pathToExit == nil {
			log.Println("Не удалось найти путь до выхода при старте волны!")
			return nil
		}
		fullPath = append(fullPath, pathToExit[1:]...)
	}

	return &component.Wave{
		Number:         waveNumber,
		EnemiesToSpawn: enemiesToSpawn,
		SpawnTimer:     0,
		SpawnInterval:  float64(config.InitialSpawnInterval) / 1000.0,
		CurrentPath:    fullPath,
	}
}

func (s *WaveSystem) OnEvent(e event.Event) {
	if e.Type == event.EnemyDestroyed {
		s.activeEnemies--
	}
}

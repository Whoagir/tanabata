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
	eventDispatcher.Subscribe(event.EnemyDestroyed, ws) // Подписываемся на событие уничтожения врага
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

	pathToCheckpoint1 := hexmap.AStar(s.hexMap.Entry, s.hexMap.Checkpoint1, s.hexMap)
	pathToCheckpoint2 := hexmap.AStar(s.hexMap.Checkpoint1, s.hexMap.Checkpoint2, s.hexMap)
	pathToExit := hexmap.AStar(s.hexMap.Checkpoint2, s.hexMap.Exit, s.hexMap)
	if pathToCheckpoint1 == nil || pathToCheckpoint2 == nil || pathToExit == nil {
		log.Println("Не удалось найти путь через чекпоинты!")
		return
	}
	fullPath := append(pathToCheckpoint1, pathToCheckpoint2[1:]...)
	fullPath = append(fullPath, pathToExit[1:]...)

	s.ecs.Paths[id] = &component.Path{Hexes: fullPath, CurrentIndex: 0}
	s.ecs.Healths[id] = &component.Health{Value: config.EnemyHealth}
	s.ecs.Renderables[id] = &component.Renderable{Color: config.EnemyColor, Radius: float32(config.EnemyRadius), HasStroke: false}
	s.activeEnemies++
}

func (s *WaveSystem) StartWave(waveNumber int) *component.Wave {
	enemiesToSpawn := config.EnemiesPerWave + (waveNumber-1)*config.EnemiesIncrementPerWave
	pathToCheckpoint1 := hexmap.AStar(s.hexMap.Entry, s.hexMap.Checkpoint1, s.hexMap)
	pathToCheckpoint2 := hexmap.AStar(s.hexMap.Checkpoint1, s.hexMap.Checkpoint2, s.hexMap)
	pathToExit := hexmap.AStar(s.hexMap.Checkpoint2, s.hexMap.Exit, s.hexMap)
	if pathToCheckpoint1 == nil || pathToCheckpoint2 == nil || pathToExit == nil {
		log.Println("Не удалось найти путь через чекпоинты при старте волны!")
		return nil
	}
	fullPath := append(pathToCheckpoint1, pathToCheckpoint2[1:]...)
	fullPath = append(fullPath, pathToExit[1:]...)
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
		s.activeEnemies-- // Уменьшаем счётчик активных врагов
	}
}

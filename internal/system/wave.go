// internal/system/wave.go
package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/event"
	"go-tower-defense/pkg/hexmap"
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
	s.ecs.Paths[id] = &component.Path{Hexes: wave.CurrentPath, CurrentIndex: 0}
	s.ecs.Healths[id] = &component.Health{Value: config.EnemyHealth}
	s.ecs.Renderables[id] = &component.Renderable{Color: config.EnemyColor, Radius: float32(config.EnemyRadius), HasStroke: false}
	s.activeEnemies++ // Увеличиваем счётчик активных врагов
}

func (s *WaveSystem) StartWave(waveNumber int) *component.Wave {
	enemiesToSpawn := config.EnemiesPerWave + (waveNumber-1)*config.EnemiesIncrementPerWave
	currentPath := hexmap.AStar(s.hexMap.Entry, s.hexMap.Exit, s.hexMap)
	return &component.Wave{
		Number:         waveNumber,
		EnemiesToSpawn: enemiesToSpawn,
		SpawnTimer:     0,
		SpawnInterval:  float64(config.InitialSpawnInterval) / 1000.0, // Начальный интервал в секундах
		CurrentPath:    currentPath,
	}
}

func (s *WaveSystem) OnEvent(e event.Event) {
	if e.Type == event.EnemyDestroyed {
		s.activeEnemies-- // Уменьшаем счётчик активных врагов
	}
}

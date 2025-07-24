// internal/system/wave.go
package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/event"
	"go-tower-defense/internal/utils"
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
		return
	}
	if wave.EnemiesToSpawn > 0 {
		wave.SpawnTimer += deltaTime
		if wave.SpawnTimer >= wave.SpawnInterval {
			s.spawnEnemy(wave)
			wave.EnemiesToSpawn--
			wave.SpawnTimer = 0
		}
	} else if wave.EnemiesToSpawn == 0 && s.activeEnemies == 0 {
		s.eventDispatcher.Dispatch(event.Event{Type: event.WaveEnded})
	}
}

func (s *WaveSystem) ResetActiveEnemies() {
	s.activeEnemies = 0
}

func (s *WaveSystem) spawnEnemy(wave *component.Wave) {
	def, ok := defs.EnemyLibrary[wave.EnemyID]
	if !ok {
		log.Printf("Error: Enemy definition not found for ID: %s", wave.EnemyID)
		return
	}

	id := s.ecs.NewEntity()
	x, y := utils.HexToScreen(s.hexMap.Entry)
	s.ecs.Positions[id] = &component.Position{X: x, Y: y}
	s.ecs.Velocities[id] = &component.Velocity{Speed: def.Speed}
	s.ecs.Paths[id] = &component.Path{Hexes: wave.CurrentPath, CurrentIndex: 0}
	s.ecs.Healths[id] = &component.Health{Value: def.Health}
	s.ecs.Renderables[id] = &component.Renderable{
		Color:     def.Visuals.Color,
		Radius:    float32(config.HexSize * def.Visuals.RadiusFactor),
		HasStroke: def.Visuals.StrokeWidth > 0,
	}
	s.ecs.Enemies[id] = &component.Enemy{
		DefID:              wave.EnemyID,
		OreDamageCooldown:  0,
		LineDamageCooldown: 0,
		PhysicalArmor:      def.PhysicalArmor,
		MagicalArmor:       def.MagicalArmor,
	}
	s.activeEnemies++
}

func (s *WaveSystem) StartWave(waveNumber int) *component.Wave {
	waveDef, ok := defs.WavePatterns[waveNumber]
	if !ok {
		// Логика для волн после 10-й: повторяем с 6-й по 10-ю
		repeatingWaveNumber := ((waveNumber - 6) % 5) + 6
		waveDef, ok = defs.WavePatterns[repeatingWaveNumber]
		if !ok {
			log.Printf("Критическая ошибка: не найдено определение для повторяющейся волны %d", repeatingWaveNumber)
			// В качестве запасного варианта, используем первую волну
			waveDef = defs.WavePatterns[1]
		}
	}

	fullPath := s.calculatePath()
	if fullPath == nil {
		log.Println("Не удалось рассчитать путь для волны!")
		return nil
	}

	return &component.Wave{
		Number:         waveNumber,
		EnemiesToSpawn: waveDef.Count,
		SpawnTimer:     0,
		SpawnInterval:  waveDef.SpawnInterval.Seconds(),
		CurrentPath:    fullPath,
		EnemyID:        waveDef.EnemyID,
	}
}

func (s *WaveSystem) calculatePath() []hexmap.Hex {
	fullPath := []hexmap.Hex{}
	if len(s.hexMap.Checkpoints) == 0 {
		path := hexmap.AStar(s.hexMap.Entry, s.hexMap.Exit, s.hexMap)
		if path == nil {
			log.Println("Не удалось найти путь от входа до выхода!")
			return nil
		}
		return path
	}

	current := s.hexMap.Entry
	for i, cp := range s.hexMap.Checkpoints {
		pathSegment := hexmap.AStar(current, cp, s.hexMap)
		if pathSegment == nil {
			log.Printf("Не удалось найти путь до чекпоинта %d!", i+1)
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
		log.Println("Не удалось найти путь от последнего чекпоинта до выхода!")
		return nil
	}
	fullPath = append(fullPath, pathToExit[1:]...)
	return fullPath
}

func (s *WaveSystem) OnEvent(e event.Event) {
	if e.Type == event.EnemyDestroyed {
		s.activeEnemies--
	}
}

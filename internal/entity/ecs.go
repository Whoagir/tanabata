// internal/entity/ecs.go
package entity

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/types"
)

type ECS struct {
	GameTime    float64
	NextID      types.EntityID
	Positions   map[types.EntityID]*component.Position
	Velocities  map[types.EntityID]*component.Velocity
	Paths       map[types.EntityID]*component.Path
	Healths     map[types.EntityID]*component.Health
	Renderables map[types.EntityID]*component.Renderable
	Towers      map[types.EntityID]*component.Tower
	Projectiles map[types.EntityID]*component.Projectile
	Combats     map[types.EntityID]*component.Combat
	Ores        map[types.EntityID]*component.Ore
	Enemies     map[types.EntityID]*component.Enemy // Новое поле для врагов
	LineRenders map[types.EntityID]*component.LineRender
	Wave        *component.Wave
	GameState   component.GameState
}

func NewECS() *ECS {
	return &ECS{
		NextID:      1,
		Positions:   make(map[types.EntityID]*component.Position),
		Velocities:  make(map[types.EntityID]*component.Velocity),
		Paths:       make(map[types.EntityID]*component.Path),
		Healths:     make(map[types.EntityID]*component.Health),
		Renderables: make(map[types.EntityID]*component.Renderable),
		Towers:      make(map[types.EntityID]*component.Tower),
		Projectiles: make(map[types.EntityID]*component.Projectile),
		Combats:     make(map[types.EntityID]*component.Combat),
		Ores:        make(map[types.EntityID]*component.Ore),
		Enemies:     make(map[types.EntityID]*component.Enemy), // Инициализация нового поля
		LineRenders: make(map[types.EntityID]*component.LineRender),
		Wave:        nil,
		GameState:   component.BuildState,
	}
}

func (ecs *ECS) NewEntity() types.EntityID {
	id := ecs.NextID
	ecs.NextID++
	return id
}

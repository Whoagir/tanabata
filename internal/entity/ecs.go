// internal/entity/ecs.go
package entity

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/types"
)

type ECS struct {
	GameTime      float64
	NextID        types.EntityID
	Positions     map[types.EntityID]*component.Position
	Velocities    map[types.EntityID]*component.Velocity
	Paths         map[types.EntityID]*component.Path
	Healths       map[types.EntityID]*component.Health
	Renderables   map[types.EntityID]*component.Renderable
	Towers        map[types.EntityID]*component.Tower
	Projectiles   map[types.EntityID]*component.Projectile
	Combats       map[types.EntityID]*component.Combat
	Ores          map[types.EntityID]*component.Ore
	Enemies       map[types.EntityID]*component.Enemy
	LineRenders   map[types.EntityID]*component.LineRender
	Texts         map[types.EntityID]*component.Text
	DamageFlashes map[types.EntityID]*component.DamageFlashComponent
	AoeEffects    map[types.EntityID]*component.AoeEffectComponent
	Auras         map[types.EntityID]*component.Aura
	AuraEffects   map[types.EntityID]*component.AuraEffect
	SlowEffects   map[types.EntityID]*component.SlowEffect
	PoisonEffects map[types.EntityID]*component.PoisonEffect
	Lasers                 map[types.EntityID]*component.Laser
	Combinables            map[types.EntityID]*component.Combinable
	ManualSelectionMarkers map[types.EntityID]*component.ManualSelectionMarker
	PlayerState            map[types.EntityID]*component.PlayerStateComponent // <<< Новый компонент
	Wave                   *component.Wave
	GameState              *component.GameState
}

func NewECS() *ECS {
	return &ECS{
		NextID:                 1,
		Positions:              make(map[types.EntityID]*component.Position),
		Velocities:             make(map[types.EntityID]*component.Velocity),
		Paths:                  make(map[types.EntityID]*component.Path),
		Healths:                make(map[types.EntityID]*component.Health),
		Renderables:            make(map[types.EntityID]*component.Renderable),
		Towers:                 make(map[types.EntityID]*component.Tower),
		Projectiles:            make(map[types.EntityID]*component.Projectile),
		Combats:                make(map[types.EntityID]*component.Combat),
		Ores:                   make(map[types.EntityID]*component.Ore),
		Enemies:                make(map[types.EntityID]*component.Enemy),
		LineRenders:            make(map[types.EntityID]*component.LineRender),
		Texts:                  make(map[types.EntityID]*component.Text),
		DamageFlashes:          make(map[types.EntityID]*component.DamageFlashComponent),
		AoeEffects:             make(map[types.EntityID]*component.AoeEffectComponent),
		Auras:                  make(map[types.EntityID]*component.Aura),
		AuraEffects:            make(map[types.EntityID]*component.AuraEffect),
		SlowEffects:            make(map[types.EntityID]*component.SlowEffect),
		PoisonEffects:          make(map[types.EntityID]*component.PoisonEffect),
		Lasers:                 make(map[types.EntityID]*component.Laser),
		Combinables:            make(map[types.EntityID]*component.Combinable),
		ManualSelectionMarkers: make(map[types.EntityID]*component.ManualSelectionMarker),
		PlayerState:            make(map[types.EntityID]*component.PlayerStateComponent), // <<< Инициализация
		Wave:                   nil,
		GameState: &component.GameState{
			Phase:        component.BuildState,
			TowersToKeep: 2, // 1 miner + 1 attacker
		},
	}
}

func (ecs *ECS) NewEntity() types.EntityID {
	id := ecs.NextID
	ecs.NextID++
	return id
}

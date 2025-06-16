// system/render.go
package system

import (
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/vector"
)

// RenderSystem рисует сущности
type RenderSystem struct {
	ecs *entity.ECS
}

func NewRenderSystem(ecs *entity.ECS) *RenderSystem {
	return &RenderSystem{ecs: ecs}
}

func (s *RenderSystem) Draw(screen *ebiten.Image) {
	for id, render := range s.ecs.Renderables {
		if pos, hasPos := s.ecs.Positions[id]; hasPos {
			if render.HasStroke {
				// Рисуем обводку (чуть больший радиус)
				strokeRadius := render.Radius + 2 // Толщина обводки 2 пикселя
				vector.DrawFilledCircle(screen, float32(pos.X), float32(pos.Y), strokeRadius, config.TowerStrokeColor, true)
			}
			// Рисуем сам круг сущности
			vector.DrawFilledCircle(screen, float32(pos.X), float32(pos.Y), render.Radius, render.Color, true)
		}
	}
}

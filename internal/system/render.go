// internal/system/render.go
package system

import (
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"math"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/text"
	"github.com/hajimehoshi/ebiten/v2/vector"
	"golang.org/x/image/font"
)

// RenderSystem рисует сущности
type RenderSystem struct {
	ecs      *entity.ECS
	fontFace font.Face
}

func NewRenderSystem(ecs *entity.ECS, fontFace font.Face) *RenderSystem {
	return &RenderSystem{ecs: ecs, fontFace: fontFace}
}

func (s *RenderSystem) Draw(screen *ebiten.Image, gameTime float64) {
	// Сначала отрисовка руды с пульсацией
	for id, ore := range s.ecs.Ores {
		if pos, hasPos := s.ecs.Positions[id]; hasPos {
			pulseRadius := ore.Radius * float32(1+0.1*math.Sin(gameTime*ore.PulseRate*math.Pi/5))
			pulseAlpha := uint8(128 + 64*math.Sin(gameTime*ore.PulseRate*math.Pi/5))
			oreColor := ore.Color
			oreColor.A = pulseAlpha
			vector.DrawFilledCircle(screen, float32(pos.X), float32(pos.Y), pulseRadius, oreColor, true)
		}
	}

	// Затем отрисовка сущностей с Renderable
	for id, render := range s.ecs.Renderables {
		if pos, hasPos := s.ecs.Positions[id]; hasPos {
			if render.HasStroke {
				strokeRadius := render.Radius + 2
				vector.DrawFilledCircle(screen, float32(pos.X), float32(pos.Y), strokeRadius, config.TowerStrokeColor, true)
			}
			vector.DrawFilledCircle(screen, float32(pos.X), float32(pos.Y), render.Radius, render.Color, true)
		}
	}

	// Отрисовка линий
	for _, line := range s.ecs.LineRenders {
		vector.StrokeLine(screen, float32(line.StartX), float32(line.StartY), float32(line.EndX), float32(line.EndY), 2.0, line.Color, true)
	}

	// Отрисовка текста поверх всего
	for _, txt := range s.ecs.Texts {
		if txt.IsUI {
			bounds := text.BoundString(s.fontFace, txt.Value)
			x := int(txt.Position.X) - bounds.Min.X - bounds.Dx()/2
			y := int(txt.Position.Y) - bounds.Min.Y - bounds.Dy()/2
			text.Draw(screen, txt.Value, s.fontFace, x, y, txt.Color)
		}
	}
}

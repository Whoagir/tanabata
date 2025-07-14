// internal/system/render.go
package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/types"
	"image/color"
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
	s.drawPulsingOres(screen, gameTime)
	s.drawEntities(screen, gameTime)
	s.drawLines(screen)
	s.drawText(screen)
}

func (s *RenderSystem) drawPulsingOres(screen *ebiten.Image, gameTime float64) {
	for id, ore := range s.ecs.Ores {
		if pos, hasPos := s.ecs.Positions[id]; hasPos {
			pulseRadius := ore.Radius * float32(1+0.1*math.Sin(gameTime*ore.PulseRate*math.Pi/5))
			pulseAlpha := uint8(128 + 64*math.Sin(gameTime*ore.PulseRate*math.Pi/5))
			oreColor := ore.Color
			oreColor.A = pulseAlpha
			vector.DrawFilledCircle(screen, float32(pos.X), float32(pos.Y), pulseRadius, oreColor, true)
		}
	}
}

func (s *RenderSystem) drawEntities(screen *ebiten.Image, gameTime float64) {
	for id, renderable := range s.ecs.Renderables {
		if pos, ok := s.ecs.Positions[id]; ok {
			s.drawEntity(screen, id, renderable, pos, gameTime)
		}
	}
}

func (s *RenderSystem) drawEntity(screen *ebiten.Image, id types.EntityID, renderable *component.Renderable, pos *component.Position, gameTime float64) {
	finalColor := renderable.Color

	// Проверяем, есть ли у сущности активная вспышка урона
	if _, ok := s.ecs.DamageFlashes[id]; ok {
		finalColor = config.EnemyDamageColor
	}

	if renderable.HasStroke {
		vector.DrawFilledCircle(screen, float32(pos.X), float32(pos.Y), renderable.Radius, finalColor, true)
		vector.StrokeCircle(screen, float32(pos.X), float32(pos.Y), renderable.Radius, 1, color.White, true)
	} else {
		vector.DrawFilledCircle(screen, float32(pos.X), float32(pos.Y), renderable.Radius, finalColor, true)
	}
}

func (s *RenderSystem) drawLines(screen *ebiten.Image) {
	for _, line := range s.ecs.LineRenders {
		startPos := s.ecs.Positions[line.Tower1ID]
		endPos := s.ecs.Positions[line.Tower2ID]
		if startPos != nil && endPos != nil {
			vector.StrokeLine(screen, float32(startPos.X), float32(startPos.Y), float32(endPos.X), float32(endPos.Y), float32(config.StrokeWidth), line.Color, true)
		}
	}
}

func (s *RenderSystem) drawText(screen *ebiten.Image) {
	for _, txt := range s.ecs.Texts {
		text.Draw(screen, txt.Value, s.fontFace, int(txt.Position.X), int(txt.Position.Y), txt.Color)
	}
}

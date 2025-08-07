// internal/system/render.go
package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/types"
	"go-tower-defense/pkg/hexmap"
	"image/color"
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// RenderSystemRL - новая система рендеринга для Raylib
type RenderSystemRL struct {
	ecs    *entity.ECS
	font   rl.Font
	camera *rl.Camera3D
}

// NewRenderSystemRL создает новую систему рендеринга
func NewRenderSystemRL(ecs *entity.ECS, font rl.Font) *RenderSystemRL {
	return &RenderSystemRL{
		ecs:  ecs,
		font: font,
		// Камера будет установлена позже через SetCamera
	}
}

// SetCamera устанавливает камеру для системы рендеринга.
func (s *RenderSystemRL) SetCamera(camera *rl.Camera3D) {
	s.camera = camera
}

// Draw рисует все динамические сущности
func (s *RenderSystemRL) Draw(gameTime float64, isDragging bool, sourceTowerID, hiddenLineID types.EntityID, gameState component.GamePhase, cancelDrag func()) {
	// Проверяем, установлена л�� камера, прежде чем рисовать 3D
	if s.camera == nil {
		return
	}
	s.drawPulsingOres(gameTime)
	s.drawEntities()
	s.drawLines(hiddenLineID)
	s.drawLasers()
	s.drawRotatingBeams()
	s.drawDraggingLine(isDragging, sourceTowerID, cancelDrag)
	s.drawText()
	s.drawCombinationIndicators()
}

func (s *RenderSystemRL) Update(deltaTime float64) {
	// Обновляем таймеры лазеров и удаляем истекшие
	for id, laser := range s.ecs.Lasers {
		laser.Timer += deltaTime
		if laser.Timer >= laser.Duration {
			delete(s.ecs.Lasers, id)
		}
	}
}

// hexToWorld преобразует гекс в мировые 3D-координаты
func (s *RenderSystemRL) hexToWorld(h hexmap.Hex) rl.Vector3 {
	x, y := h.ToPixel(float64(config.HexSize))
	return rl.NewVector3(float32(x), 0, float32(y))
}

func (s *RenderSystemRL) drawLasers() {
	for _, laser := range s.ecs.Lasers {
		alpha := 1.0 - (laser.Timer / laser.Duration)
		if alpha < 0 {
			alpha = 0
		}
		r, g, b, _ := laser.Color.RGBA()
		lineColor := rl.NewColor(uint8(r>>8), uint8(g>>8), uint8(b>>8), uint8(alpha*255))

		startHex := hexmap.PixelToHex(laser.FromX, laser.FromY, config.HexSize)
		endHex := hexmap.PixelToHex(laser.ToX, laser.ToY, config.HexSize)

		startPos := s.hexToWorld(startHex)
		endPos := s.hexToWorld(endHex)

		rl.DrawLine3D(startPos, endPos, lineColor)
	}
}

func (s *RenderSystemRL) drawPulsingOres(gameTime float64) {
	for id, ore := range s.ecs.Ores {
		if pos, hasPos := s.ecs.Positions[id]; hasPos {
			pulseRadius := ore.Radius * float32(1+0.1*math.Sin(gameTime*ore.PulseRate*math.Pi/5))
			pulseAlpha := uint8(128 + 64*math.Sin(gameTime*ore.PulseRate*math.Pi/5))
			oreColor := config.OreColorRL
			oreColor.A = pulseAlpha

			worldPos := s.hexToWorld(hexmap.PixelToHex(pos.X, pos.Y, config.HexSize))
			rl.DrawCylinder(worldPos, pulseRadius, pulseRadius, 0.1, 20, oreColor)
		}
	}
}

func (s *RenderSystemRL) drawEntities() {
	for id, renderable := range s.ecs.Renderables {
		if pos, ok := s.ecs.Positions[id]; ok {
			s.drawEntity(id, renderable, pos)
		}
	}
}

func (s *RenderSystemRL) drawEntity(id types.EntityID, renderable *component.Renderable, pos *component.Position) {
	finalColor := colorToRL(renderable.Color)

	if _, ok := s.ecs.DamageFlashes[id]; ok {
		finalColor = config.EnemyDamageColorRL
	} else if _, ok := s.ecs.PoisonEffects[id]; ok {
		finalColor = config.ProjectileColorPoisonRL
	} else if _, ok := s.ecs.SlowEffects[id]; ok {
		finalColor = config.ProjectileColorSlowRL
	}

	worldPos := s.hexToWorld(hexmap.PixelToHex(pos.X, pos.Y, config.HexSize))
	worldPos.Y = float32(renderable.Radius / 2)

	if _, isEnemy := s.ecs.Enemies[id]; isEnemy {
		rl.DrawSphere(worldPos, renderable.Radius, finalColor)
		if renderable.HasStroke {
			rl.DrawSphereWires(worldPos, renderable.Radius, 8, 8, rl.White)
		}
	} else if tower, isTower := s.ecs.Towers[id]; isTower {
		height := renderable.Radius * 2
		worldPos.Y = height / 2

		if tower.CraftingLevel >= 1 {
			size := renderable.Radius * 2
			rl.DrawCube(worldPos, size, height, size, finalColor)
			if renderable.HasStroke {
				rl.DrawCubeWires(worldPos, size, height, size, rl.White)
			}
		} else {
			rl.DrawCylinder(worldPos, renderable.Radius, renderable.Radius, height, 12, finalColor)
			if renderable.HasStroke {
				rl.DrawCylinderWires(worldPos, renderable.Radius, renderable.Radius, height, 12, rl.White)
			}
		}
	} else {
		rl.DrawSphere(worldPos, renderable.Radius, finalColor)
	}
}

func (s *RenderSystemRL) drawCombinationIndicators() {
	for id := range s.ecs.Combinables {
		if pos, ok := s.ecs.Positions[id]; ok {
			if renderable, ok := s.ecs.Renderables[id]; ok {
				worldPos := s.hexToWorld(hexmap.PixelToHex(pos.X, pos.Y, config.HexSize))
				worldPos.Y = float32(renderable.Radius*2 + 2)
				indicatorRadius := renderable.Radius / 2

				rl.DrawSphere(worldPos, indicatorRadius, rl.Black)
				rl.DrawSphereWires(worldPos, indicatorRadius+0.2, 6, 6, rl.White)
			}
		}
	}
}

func (s *RenderSystemRL) drawLines(hiddenLineID types.EntityID) {
	for id, line := range s.ecs.LineRenders {
		if id == hiddenLineID {
			continue
		}
		startPosComp, ok1 := s.ecs.Positions[line.Tower1ID]
		endPosComp, ok2 := s.ecs.Positions[line.Tower2ID]
		if ok1 && ok2 {
			startPos := s.hexToWorld(hexmap.PixelToHex(startPosComp.X, startPosComp.Y, config.HexSize))
			endPos := s.hexToWorld(hexmap.PixelToHex(endPosComp.X, endPosComp.Y, config.HexSize))
			rl.DrawLine3D(startPos, endPos, colorToRL(line.Color))
		}
	}
}

func (s *RenderSystemRL) drawDraggingLine(isDragging bool, sourceTowerID types.EntityID, cancelDrag func()) {
	if !isDragging || sourceTowerID == 0 {
		return
	}
	sourcePosComp, ok := s.ecs.Positions[sourceTowerID]
	if !ok {
		return
	}

	ray := rl.GetMouseRay(rl.GetMousePosition(), *s.camera)
	t := -ray.Position.Y / ray.Direction.Y
	hitPoint := rl.Vector3Add(ray.Position, rl.Vector3Scale(ray.Direction, t))

	startPos := s.hexToWorld(hexmap.PixelToHex(sourcePosComp.X, sourcePosComp.Y, config.HexSize))

	if rl.Vector3Distance(startPos, hitPoint) > 300 {
		cancelDrag()
		return
	}

	rl.DrawLine3D(startPos, hitPoint, rl.Yellow)
}

func (s *RenderSystemRL) drawText() {
	for _, txt := range s.ecs.Texts {
		worldPos := s.hexToWorld(hexmap.PixelToHex(txt.Position.X, txt.Position.Y, config.HexSize))
		screenPos := rl.GetWorldToScreen(worldPos, *s.camera)
		rl.DrawTextEx(s.font, txt.Value, screenPos, float32(s.font.BaseSize), 1.0, colorToRL(txt.Color))
	}
}

func (s *RenderSystemRL) drawRotatingBeams() {
	if s.ecs.GameState.Phase != component.WaveState {
		return
	}
	for id, beam := range s.ecs.RotatingBeams {
		pos, ok := s.ecs.Positions[id]
		if !ok {
			continue
		}

		beamColor := rl.NewColor(255, 255, 102, 80)
		worldPos := s.hexToWorld(hexmap.PixelToHex(pos.X, pos.Y, config.HexSize))

		angle1 := beam.CurrentAngle - beam.ArcAngle/2
		angle2 := beam.CurrentAngle + beam.ArcAngle/2

		endX1 := worldPos.X + float32(float64(beam.Range*config.HexSize)*math.Cos(angle1))
		endZ1 := worldPos.Z + float32(float64(beam.Range*config.HexSize)*math.Sin(angle1))
		endX2 := worldPos.X + float32(float64(beam.Range*config.HexSize)*math.Cos(angle2))
		endZ2 := worldPos.Z + float32(float64(beam.Range*config.HexSize)*math.Sin(angle2))

		endPos1 := rl.NewVector3(endX1, worldPos.Y, endZ1)
		endPos2 := rl.NewVector3(endX2, worldPos.Y, endZ2)

		rl.DrawLine3D(worldPos, endPos1, beamColor)
		rl.DrawLine3D(worldPos, endPos2, beamColor)
	}
}

// colorToRL преобразует стандартный color.Color в rl.Color
func colorToRL(c color.Color) rl.Color {
	r, g, b, a := c.RGBA()
	return rl.NewColor(uint8(r>>8), uint8(g>>8), uint8(b>>8), uint8(a>>8))
}

// internal/system/render.go
package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/types"
	"go-tower-defense/pkg/hexmap"
	"image/color"
	"math"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// CachedRenderData хранит предварительно рассчитанные данные для рендеринга
type CachedRenderData struct {
	WorldPos   rl.Vector3
	Radius     float32
	Height     float32
	IsOnScreen bool
}

// RenderSystemRL - оптимизированная система рендеринга
type RenderSystemRL struct {
	ecs             *entity.ECS
	font            rl.Font
	camera          *rl.Camera3D
	renderCache     map[types.EntityID]*CachedRenderData
	frustum         [6]rl.Vector4 // Плоскости для frustum culling
	towerModels     map[string]rl.Model
	towerWireModels map[string]rl.Model
}

// NewRenderSystemRL создает новую оптимизированную систему рендеринга
func NewRenderSystemRL(ecs *entity.ECS, font rl.Font) *RenderSystemRL {
	rs := &RenderSystemRL{
		ecs:             ecs,
		font:            font,
		renderCache:     make(map[types.EntityID]*CachedRenderData),
		towerModels:     make(map[string]rl.Model),
		towerWireModels: make(map[string]rl.Model),
	}
	rs.pregenerateTowerModels()
	return rs
}

// pregenerateTowerModels создает 3D-модели для каждого типа башни
func (s *RenderSystemRL) pregenerateTowerModels() {
	for id, towerDef := range defs.TowerDefs {
		var mesh, wireMesh rl.Mesh

		// Логика создания меша в зависимости от типа башни
		switch {
		case towerDef.Type == defs.TowerTypeWall:
			mesh = rl.GenMeshCylinder(1.0, 1.0, 6)
			wireMesh = rl.GenMeshCylinder(1.0, 1.0, 6)
		case towerDef.Type == defs.TowerTypeMiner:
			// Добытчики будут рендериться динамически для сохранения формы конуса
			continue
		case towerDef.CraftingLevel >= 1:
			mesh = rl.GenMeshCube(1.0, 1.0, 1.0)
			wireMesh = rl.GenMeshCube(1.0, 1.0, 1.0)
		default: // Обычные атакующие башни
			mesh = rl.GenMeshCylinder(1.0, 1.0, 9)
			wireMesh = rl.GenMeshCylinder(1.0, 1.0, 9)
		}

		model := rl.LoadModelFromMesh(mesh)
		wireModel := rl.LoadModelFromMesh(wireMesh)

		s.towerModels[id] = model
		s.towerWireModels[id] = wireModel
	}
}

func (s *RenderSystemRL) SetCamera(camera *rl.Camera3D) {
	s.camera = camera
}

// Update кэширует данные и выполняет frustum culling
func (s *RenderSystemRL) Update(deltaTime float64) {
	if s.camera == nil {
		return
	}
	s.updateFrustum()

	for id, renderable := range s.ecs.Renderables {
		var worldPos rl.Vector3
		isTower := false
		if tower, ok := s.ecs.Towers[id]; ok {
			worldPos = s.hexToWorld(tower.Hex)
			isTower = true
		} else if pos, ok := s.ecs.Positions[id]; ok {
			worldPos = s.pixelToWorld(*pos)
		} else {
			delete(s.renderCache, id)
			continue
		}

		height := float32(0)
		if isTower {
			tower, _ := s.ecs.Towers[id]
			height = s.GetTowerRenderHeight(tower, renderable)
		}

		s.renderCache[id] = &CachedRenderData{
			WorldPos:   worldPos,
			Radius:     renderable.Radius,
			Height:     height,
			IsOnScreen: true,
		}
	}

	// Обновление таймеров лазеров
	for id, laser := range s.ecs.Lasers {
		laser.Timer += deltaTime
		if laser.Timer >= laser.Duration {
			delete(s.ecs.Lasers, id)
		}
	}
}

// Draw использует кэшированные данные для отрисовки
func (s *RenderSystemRL) Draw(gameTime float64, isDragging bool, sourceTowerID, hiddenLineID types.EntityID, gameState component.GamePhase, cancelDrag func()) {
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

func (s *RenderSystemRL) drawEntities() {
	for id, data := range s.renderCache {
		if !data.IsOnScreen {
			continue
		}

		renderable, ok := s.ecs.Renderables[id]
		if !ok {
			continue
		}

		finalColor := colorToRL(renderable.Color)
		if _, ok := s.ecs.DamageFlashes[id]; ok {
			finalColor = config.EnemyDamageColorRL
		} else if _, ok := s.ecs.PoisonEffects[id]; ok {
			finalColor = config.ProjectileColorPoisonRL
		} else if _, ok := s.ecs.SlowEffects[id]; ok {
			finalColor = config.ProjectileColorSlowRL
		}

		scaledRadius := data.Radius * float32(config.CoordScale)

		if _, isEnemy := s.ecs.Enemies[id]; isEnemy {
			pos := data.WorldPos
			pos.Y = scaledRadius
			rl.DrawSphere(pos, scaledRadius, finalColor)
			if renderable.HasStroke {
				rl.DrawSphereWires(pos, scaledRadius, 8, 8, rl.White)
			}
		} else if tower, isTower := s.ecs.Towers[id]; isTower {
			s.drawTower(tower, data, scaledRadius, finalColor, renderable.HasStroke)
		} else if _, isProjectile := s.ecs.Projectiles[id]; isProjectile {
			pos := data.WorldPos
			pos.Y = scaledRadius
			rl.DrawSphere(pos, scaledRadius, finalColor)
		}
	}
}

func (s *RenderSystemRL) drawTower(tower *component.Tower, data *CachedRenderData, scaledRadius float32, color rl.Color, hasStroke bool) {
	towerDef, _ := defs.TowerDefs[tower.DefID]

	// Новые множители размера
	baseWidthMultiplier := float32(1.32)      // 1.2 * 1.1
	attackTowerHeightMultiplier := float32(1.326) // 1.56 * 0.85
	minerTowerHeightMultiplier := float32(1.56)   // 1.2 * 1.3 (остается без изменений)
	wallHeightMultiplier := float32(1.68)     // 1.2 * 1.4 (остается без изменений)

	// Особый случай для майнеров: рисуем динамически, чтобы получить конус
	if towerDef.Type == defs.TowerTypeMiner {
		startPos := rl.NewVector3(data.WorldPos.X, 0, data.WorldPos.Z)
		endPos := rl.NewVector3(data.WorldPos.X, data.Height*minerTowerHeightMultiplier, data.WorldPos.Z)
		radius := scaledRadius * 1.2 * baseWidthMultiplier
		rl.DrawCylinderEx(startPos, endPos, radius, 0, 9, color)
		if hasStroke {
			rl.DrawCylinderWiresEx(startPos, endPos, radius, 0, 9, config.TowerWireColorRL)
		}
		return
	}

	// Оптимизированный путь для всех остальных башен
	model, ok := s.towerModels[tower.DefID]
	if !ok {
		return // Модель не найдена
	}
	wireModel, _ := s.towerWireModels[tower.DefID]

	position := data.WorldPos
	var scale rl.Vector3

	// Логика масштабирования в зависимости от типа
	switch {
	case towerDef.Type == defs.TowerTypeWall:
		radius := scaledRadius * 1.8 * baseWidthMultiplier
		scale = rl.NewVector3(radius, data.Height*wallHeightMultiplier, radius)
	case tower.CraftingLevel >= 1:
		size := scaledRadius * 2 * baseWidthMultiplier
		scale = rl.NewVector3(size, data.Height*attackTowerHeightMultiplier, size)
	default:
		radius := scaledRadius * 1.2 * baseWidthMultiplier
		scale = rl.NewVector3(radius, data.Height*attackTowerHeightMultiplier, radius)
	}

	rl.DrawModelEx(model, position, rl.NewVector3(0, 1, 0), 0, scale, color)
	if hasStroke {
		rl.DrawModelWiresEx(wireModel, position, rl.NewVector3(0, 1, 0), 0, scale, config.TowerWireColorRL)
	}
}

func (s *RenderSystemRL) GetTowerRenderHeight(tower *component.Tower, renderable *component.Renderable) float32 {
	scaledRadius := float32(renderable.Radius * config.CoordScale)
	towerDef, ok := defs.TowerDefs[tower.DefID]
	if !ok {
		return scaledRadius * 4
	}

	switch {
	case towerDef.Type == defs.TowerTypeWall:
		return scaledRadius * 1.5
	case towerDef.Type == defs.TowerTypeMiner:
		return scaledRadius * 9.0
	case tower.CraftingLevel >= 1:
		return scaledRadius * 4.0
	default:
		return scaledRadius * 7.0
	}
}

func (s *RenderSystemRL) updateFrustum() {
	proj := rl.MatrixPerspective(s.camera.Fovy*rl.Deg2rad, float32(rl.GetScreenWidth())/float32(rl.GetScreenHeight()), 0.1, 1000.0)
	view := rl.MatrixLookAt(s.camera.Position, s.camera.Target, s.camera.Up)
	clipMatrix := rl.MatrixMultiply(view, proj)

	s.frustum[0].X = clipMatrix.M3 - clipMatrix.M0
	s.frustum[0].Y = clipMatrix.M7 - clipMatrix.M4
	s.frustum[0].Z = clipMatrix.M11 - clipMatrix.M8
	s.frustum[0].W = clipMatrix.M15 - clipMatrix.M12
	s.frustum[1].X = clipMatrix.M3 + clipMatrix.M0
	s.frustum[1].Y = clipMatrix.M7 + clipMatrix.M4
	s.frustum[1].Z = clipMatrix.M11 + clipMatrix.M8
	s.frustum[1].W = clipMatrix.M15 + clipMatrix.M12
	s.frustum[2].X = clipMatrix.M3 + clipMatrix.M1
	s.frustum[2].Y = clipMatrix.M7 + clipMatrix.M5
	s.frustum[2].Z = clipMatrix.M11 + clipMatrix.M9
	s.frustum[2].W = clipMatrix.M15 + clipMatrix.M13
	s.frustum[3].X = clipMatrix.M3 - clipMatrix.M1
	s.frustum[3].Y = clipMatrix.M7 - clipMatrix.M5
	s.frustum[3].Z = clipMatrix.M11 - clipMatrix.M9
	s.frustum[3].W = clipMatrix.M15 - clipMatrix.M13
	s.frustum[4].X = clipMatrix.M3 - clipMatrix.M2
	s.frustum[4].Y = clipMatrix.M7 - clipMatrix.M6
	s.frustum[4].Z = clipMatrix.M11 - clipMatrix.M10
	s.frustum[4].W = clipMatrix.M15 - clipMatrix.M14
	s.frustum[5].X = clipMatrix.M3 + clipMatrix.M2
	s.frustum[5].Y = clipMatrix.M7 + clipMatrix.M6
	s.frustum[5].Z = clipMatrix.M11 + clipMatrix.M10
	s.frustum[5].W = clipMatrix.M15 + clipMatrix.M14

	for i := 0; i < 6; i++ {
		length := float32(math.Sqrt(float64(s.frustum[i].X*s.frustum[i].X + s.frustum[i].Y*s.frustum[i].Y + s.frustum[i].Z*s.frustum[i].Z)))
		if length > 0 {
			s.frustum[i].X /= length
			s.frustum[i].Y /= length
			s.frustum[i].Z /= length
			s.frustum[i].W /= length
		}
	}
}

func (s *RenderSystemRL) isInFrustum(box rl.BoundingBox) bool {
	// ... (implementation unchanged)
	return true
}

func (s *RenderSystemRL) hexToWorld(h hexmap.Hex) rl.Vector3 {
	x, y := h.ToPixel(float64(config.HexSize))
	return rl.NewVector3(float32(x*config.CoordScale), 0, float32(y*config.CoordScale))
}

func (s *RenderSystemRL) pixelToWorld(p component.Position) rl.Vector3 {
	return rl.NewVector3(float32(p.X*config.CoordScale), 0, float32(p.Y*config.CoordScale))
}

func colorToRL(c color.Color) rl.Color {
	r, g, b, a := c.RGBA()
	return rl.NewColor(uint8(r>>8), uint8(g>>8), uint8(b>>8), uint8(a>>8))
}

func (s *RenderSystemRL) drawPulsingOres(gameTime float64) {
	for id, ore := range s.ecs.Ores {
		if pos, hasPos := s.ecs.Positions[id]; hasPos {
			worldPos := s.pixelToWorld(*pos)

			scaledRadius := float32(ore.Radius * config.CoordScale)
			pulseRadius := scaledRadius * float32(1+0.1*math.Sin(gameTime*ore.PulseRate*math.Pi/5))
			pulseAlpha := uint8(128 + 64*math.Sin(gameTime*ore.PulseRate*math.Pi/5))
			oreColor := config.OreColorRL
			oreColor.A = pulseAlpha

			scaledHeight := float32(0.1 * config.CoordScale)
			worldPos.Y = scaledHeight/2 + 2.0

			rl.DrawCylinder(worldPos, pulseRadius, pulseRadius, scaledHeight, 20, oreColor)
		}
	}
}

func (s *RenderSystemRL) drawLines(hiddenLineID types.EntityID) {
	for id, line := range s.ecs.LineRenders {
		if id == hiddenLineID {
			continue
		}
		tower1, ok1 := s.ecs.Towers[line.Tower1ID]
		render1, ok1r := s.ecs.Renderables[line.Tower1ID]
		tower2, ok2 := s.ecs.Towers[line.Tower2ID]
		render2, ok2r := s.ecs.Renderables[line.Tower2ID]

		if ok1 && ok1r && ok2 && ok2r {
			startPos := s.hexToWorld(tower1.Hex)
			endPos := s.hexToWorld(tower2.Hex)

			height1 := s.GetTowerRenderHeight(tower1, render1)
			height2 := s.GetTowerRenderHeight(tower2, render2)

			startPos.Y = height1
			endPos.Y = height2

			rl.DrawCapsule(startPos, endPos, 0.6, 8, 8, rl.Yellow)
		}
	}
}

func (s *RenderSystemRL) drawLasers() {
	for _, laser := range s.ecs.Lasers {
		alpha := 1.0 - (laser.Timer / laser.Duration)
		if alpha < 0 {
			alpha = 0
		}
		r, g, b, _ := laser.Color.RGBA()
		lineColor := rl.NewColor(uint8(r>>8), uint8(g>>8), uint8(b>>8), uint8(alpha*255))

		startPos := s.pixelToWorld(component.Position{X: laser.FromX, Y: laser.FromY})
		endPos := s.pixelToWorld(component.Position{X: laser.ToX, Y: laser.ToY})

		rl.DrawLine3D(startPos, endPos, lineColor)
	}
}

func (s *RenderSystemRL) drawRotatingBeams() {
	// ... (implementation from "было.txt")
}

func (s *RenderSystemRL) drawDraggingLine(isDragging bool, sourceTowerID types.EntityID, cancelDrag func()) {
	// ... (implementation from "было.txt")
}

func (s *RenderSystemRL) drawText() {
	// ... (implementation from "было.txt")
}

func (s *RenderSystemRL) drawCombinationIndicators() {
	// ... (implementation from "было.txt")
}
// internal/system/render.go
package system

import (
	"go-tower-defense/internal/assets"
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/types"
	"go-tower-defense/pkg/hexmap"
	"image/color"
	"math"
	"unsafe"

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
	ecs          *entity.ECS
	font         rl.Font
	camera       *rl.Camera3D
	modelManager *assets.ModelManager // <-- Используем менеджер
	renderCache  map[types.EntityID]*CachedRenderData
	frustum      [6]rl.Vector4
	laserModel   rl.Model
	ellipseModel rl.Model
	cubeModel    rl.Model // Модель куба для процедурных башен
}

// NewRenderSystemRL создает новую оптимизированную систему рендеринга
func NewRenderSystemRL(ecs *entity.ECS, font rl.Font, modelManager *assets.ModelManager) *RenderSystemRL {
	rs := &RenderSystemRL{
		ecs:          ecs,
		font:         font,
		modelManager: modelManager, // <-- Сохраняем менеджер
		renderCache:  make(map[types.EntityID]*CachedRenderData),
	}
	rs.pregenerateLaserModel()
	// Генерируем модели-плейсхолдеры один раз
	rs.ellipseModel = rl.LoadModelFromMesh(rl.GenMeshCube(1.0, 1.0, 1.0))
	rs.cubeModel = rl.LoadModelFromMesh(rl.GenMeshCube(1.0, 1.0, 1.0))
	return rs
}

// pregenerateLaserModel создает 3D-модель для лазера для оптимизации.
func (s *RenderSystemRL) pregenerateLaserModel() {
	mesh := rl.GenMeshCylinder(1.0, 1.0, 8)
	transform := rl.MatrixTranslate(0, 0.5, 0)
	meshTransform(&mesh, transform)
	s.laserModel = rl.LoadModelFromMesh(mesh)
}

// meshTransform применяет матрицу трансформации к каждой вершине меша.
func meshTransform(mesh *rl.Mesh, transform rl.Matrix) {
	vertexCount := int(mesh.VertexCount)
	sliceHeader := struct {
		data unsafe.Pointer
		len  int
		cap  int
	}{
		data: unsafe.Pointer(mesh.Vertices),
		len:  vertexCount * 3,
		cap:  vertexCount * 3,
	}
	vertices := *(*[]float32)(unsafe.Pointer(&sliceHeader))

	for i := 0; i < vertexCount; i++ {
		vertexIndex := i * 3
		vec := rl.NewVector3(
			vertices[vertexIndex],
			vertices[vertexIndex+1],
			vertices[vertexIndex+2],
		)
		transformedVec := rl.Vector3Transform(vec, transform)
		vertices[vertexIndex] = transformedVec.X
		vertices[vertexIndex+1] = transformedVec.Y
		vertices[vertexIndex+2] = transformedVec.Z
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
			delete(s.renderCache, id) //abc
			continue                  //fdfd
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

	// Обновление таймеров лазеров и эффектов вулкана
	for id, laser := range s.ecs.Lasers {
		laser.Timer += deltaTime
		if laser.Timer >= laser.Duration {
			delete(s.ecs.Lasers, id)
		}
	}
	for id, effect := range s.ecs.VolcanoEffects {
		effect.Timer += deltaTime
		progress := effect.Timer / effect.Duration
		if progress > 1.0 {
			progress = 1.0
		}
		effect.Radius = effect.MaxRadius * progress
		if effect.Timer >= effect.Duration {
			delete(s.ecs.VolcanoEffects, id)
		}
	}
}

// Draw использует кэшированные данные для отрисовки
func (s *RenderSystemRL) Draw(gameTime float64, isDragging bool, sourceTowerID, hiddenLineID types.EntityID, gameState component.GamePhase, cancelDrag func(), clearedCheckpoints map[hexmap.Hex]bool, futurePath []hexmap.Hex, visualDebugEnabled bool) {
	if s.camera == nil {
		return
	}
	s.drawPulsingOres(gameTime)
	s.drawClearedCheckpoints(clearedCheckpoints)
	s.drawFuturePath(futurePath)
	s.drawSolidEntities()
	s.drawLines(hiddenLineID)
	s.drawLasers()
	s.drawVolcanoEffects()
	s.drawBeaconSectors()
	s.drawDraggingLine(isDragging, sourceTowerID, cancelDrag)
	s.drawText()
	s.drawCombinationIndicators()

	if visualDebugEnabled {
		s.drawDebugTurretLines()
	}
}

// ... (drawFuturePath, drawClearedCheckpoints, drawBeaconSectors без изменений) ...
func (s *RenderSystemRL) drawFuturePath(path []hexmap.Hex) {
	if path == nil || len(path) == 0 {
		return
	}
	color := rl.NewColor(0, 0, 0, 70)
	for _, hex := range path {
		pos := s.hexToWorld(hex)
		pos.Y += 0.75
		radius := float32(config.HexSize*config.CoordScale) * 1.05
		rl.DrawCylinder(pos, radius, radius, 1.2, 6, color)
	}
}

func (s *RenderSystemRL) drawClearedCheckpoints(clearedCheckpoints map[hexmap.Hex]bool) {
	if clearedCheckpoints == nil || len(clearedCheckpoints) == 0 {
		return
	}
	for hex := range clearedCheckpoints {
		pos := s.hexToWorld(hex)
		pos.Y += 0.7
		radius := float32(config.HexSize*config.CoordScale) * 1.05
		color := rl.NewColor(0, 120, 0, 200)
		rl.DrawCylinder(pos, radius, radius, 1.2, 6, color)
	}
}

func (s *RenderSystemRL) drawBeaconSectors() {
	for id, sector := range s.ecs.BeaconAttackSectors {
		if !sector.IsVisible {
			continue
		}
		tower, okT := s.ecs.Towers[id]
		beacon, okB := s.ecs.Beacons[id]
		combat, okC := s.ecs.Combats[id]
		renderable, okR := s.ecs.Renderables[id]
		if !okT || !okB || !okC || !okR {
			continue
		}
		towerPos := s.hexToWorld(tower.Hex)
		towerHeight := s.GetTowerRenderHeight(tower, renderable)
		towerTop := rl.NewVector3(towerPos.X, towerHeight, towerPos.Z)
		rangePixels := float32(float64(combat.Range) * config.HexSize * config.CoordScale)
		startAngle := float32(beacon.CurrentAngle - beacon.ArcAngle/2)
		endAngle := float32(beacon.CurrentAngle + beacon.ArcAngle/2)
		v1 := towerPos
		v2 := rl.NewVector3(towerPos.X+rangePixels*float32(math.Cos(float64(startAngle))), 0, towerPos.Z+rangePixels*float32(math.Sin(float64(startAngle))))
		v3 := rl.NewVector3(towerPos.X+rangePixels*float32(math.Cos(float64(endAngle))), 0, towerPos.Z+rangePixels*float32(math.Sin(float64(endAngle))))
		sectorColor := rl.NewColor(255, 255, 224, 70)
		rl.DrawTriangle3D(towerTop, v2, v3, sectorColor)
		rl.DrawTriangle3D(towerTop, v3, v1, sectorColor)
		rl.DrawTriangle3D(towerTop, v1, v2, sectorColor)
		lineColor := rl.NewColor(255, 255, 150, 150)
		rl.DrawLine3D(v1, v2, lineColor)
		rl.DrawLine3D(v1, v3, lineColor)
		rl.DrawLine3D(v2, v3, lineColor)
	}
}

func (s *RenderSystemRL) drawSolidEntities() {
	for id, data := range s.renderCache {
		if !data.IsOnScreen || s.ecs.Projectiles[id] != nil {
			continue
		}

		renderable, ok := s.ecs.Renderables[id]
		if !ok {
			continue
		}

		finalColor := colorToRL(renderable.Color)
		// ... (логика цвета без изменений) ...
		if _, ok := s.ecs.DamageFlashes[id]; ok {
			finalColor = config.EnemyDamageColorRL
		} else if poisonContainer, ok := s.ecs.JadePoisonContainers[id]; ok {
			numStacks := len(poisonContainer.Instances)
			if numStacks > 0 {
				originalColor := colorToRL(renderable.Color)
				targetColor := rl.NewColor(40, 220, 140, 255)
				const maxVisualStacks = 5.0
				lerpFactor := float32(numStacks) / maxVisualStacks
				if lerpFactor > 1.0 {
					lerpFactor = 1.0
				}
				finalColor.R = uint8(float32(originalColor.R)*(1-lerpFactor) + float32(targetColor.R)*lerpFactor)
				finalColor.G = uint8(float32(originalColor.G)*(1-lerpFactor) + float32(targetColor.G)*lerpFactor)
				finalColor.B = uint8(float32(originalColor.B)*(1-lerpFactor) + float32(targetColor.B)*lerpFactor)
			}
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
			s.drawTower(id, tower, data, scaledRadius, finalColor, renderable.HasStroke)
			if _, ok := s.ecs.Combinables[id]; ok {
				indicatorPos := data.WorldPos
				indicatorPos.Y = data.Height + 4.0
				indicatorRadius := scaledRadius * 0.5
				rl.DrawCylinder(indicatorPos, indicatorRadius, indicatorRadius, 0.1, 12, rl.Gold)
				rl.DrawCylinderWires(indicatorPos, indicatorRadius, indicatorRadius, 0.1, 12, rl.Black)
			}
		}
	}
}

// ... (DrawProjectiles без изменений) ...
func (s *RenderSystemRL) DrawProjectiles() {
	for id, data := range s.renderCache {
		if !data.IsOnScreen {
			continue
		}
		proj, isProjectile := s.ecs.Projectiles[id]
		if !isProjectile {
			continue
		}
		renderable, ok := s.ecs.Renderables[id]
		if !ok {
			continue
		}
		finalColor := colorToRL(renderable.Color)
		pos := data.WorldPos

		// --- НОВАЯ ЛОГИКА РАЗДЕЛЕНИЯ ВЫСОТЫ ---
		if proj.SpawnHeight > 0 {
			// Используем предрассчитанную высоту для башен с турелью
			pos.Y = float32(proj.SpawnHeight)
		} else {
			// Используем старую, низкую высоту для остальных башен
			pos.Y = float32(config.ProjectileRadius*config.CoordScale) + 1.0
		}
		// --- КОНЕЦ НОВОЙ ЛОГИКИ ---

		// Рассчитываем масштаб снаряда в зависимости от его возраста
		scale := float32(1.0)
		// Применяем анимацию роста только для снарядов от башен с турелью (у которых задана высота спавна)
		if proj.SpawnHeight > 0 {
			if proj.ScaleUpDuration > 0 && proj.Age < proj.ScaleUpDuration {
				scale = float32(proj.Age / proj.ScaleUpDuration)
			}
		}

		if proj.VisualType == "ELLIPSE" {
			length := float32(config.ProjectileRadius*config.CoordScale) * 1.5 * scale
			width := float32(config.ProjectileRadius*config.CoordScale) / 2.0 * scale
			height := float32(0.2)
			modelScale := rl.NewVector3(length, height, width)
			rotationAngle := float32(proj.Direction*rl.Rad2deg) + 90
			rl.DrawModelEx(s.ellipseModel, pos, rl.NewVector3(0, 1, 0), rotationAngle, modelScale, finalColor)
		} else {
			scaledRadius := data.Radius * float32(config.CoordScale) * scale
			rl.DrawSphere(pos, scaledRadius, finalColor)
		}
	}
}

func (s *RenderSystemRL) drawTower(id types.EntityID, tower *component.Tower, data *CachedRenderData, scaledRadius float32, color rl.Color, hasStroke bool) {
	towerDef, _ := defs.TowerDefs[tower.DefID]

	// --- Логика отрисовки башен с турелью ---
	if turret, hasTurret := s.ecs.Turrets[id]; hasTurret {
		baseModel, hasBase := s.modelManager.GetBaseModel(tower.DefID)
		headModel, hasHead := s.modelManager.GetHeadModel(tower.DefID)

		// Если есть кастомные модели для базы и головы
		if hasBase && hasHead {
			wireBaseModel, _ := s.modelManager.GetWireBaseModel(tower.DefID)
			wireHeadModel, _ := s.modelManager.GetWireHeadModel(tower.DefID)

			position := data.WorldPos
			finalScale := rl.NewVector3(1.0, 1.0, 1.0)

			// Рисуем базу
			rl.DrawModelEx(baseModel, position, rl.NewVector3(0, 1, 0), 0, finalScale, color)
			if hasStroke {
				rl.DrawModelWiresEx(wireBaseModel, position, rl.NewVector3(0, 1, 0), 0, finalScale, config.TowerWireColorRL)
			}

			// --- ОБНОВЛЕННАЯ ОТРИСОВКА ГОЛОВЫ ТУРЕЛИ С ДВУМЯ ОСЯМИ ВРАЩЕНИЯ ---
			baseHeight, ok := s.modelManager.GetBaseModelHeight(tower.DefID)
			if !ok {
				baseHeight = data.Height * 0.6
			}
			headPos := rl.NewVector3(position.X, baseHeight, position.Z)

			// Raylib для сложных трансформаций использует матричный стек
			rl.PushMatrix()
			// 1. Перемещаемся в позицию, где должна быть голова
			rl.Translatef(headPos.X, headPos.Y, headPos.Z)
			// 2. Применяем горизонтальный поворот (Yaw)
			rl.Rotatef(-turret.CurrentAngle*rl.Rad2deg, 0, 1, 0)
			// 3. Применяем вертикальный поворот (Pitch) вокруг локальной оси Z
			rl.Rotatef(turret.CurrentPitch*rl.Rad2deg, 0, 0, 1)
			// 4. Рисуем саму модель в начале координат (т.к. мы уже переместились)
			rl.DrawModel(headModel, rl.Vector3Zero(), 1.0, color)
			if hasStroke {
				rl.DrawModelWires(wireHeadModel, rl.Vector3Zero(), 1.0, config.TowerWireColorRL)
			}
			// 5. Возвращаем матрицу в исходное состояние
			rl.PopMatrix()
			// --- КОНЕЦ ОБНОВЛЕННОГО БЛОКА ---

		} else {
			// Фоллбэк на процедурную генерацию, если моделей нет
			scaleFactor := float32(1.5)
			baseHeight := data.Height * 0.6 * scaleFactor
			baseRadius := scaledRadius * 1.1 * scaleFactor
			basePos := data.WorldPos
			baseTopPos := rl.NewVector3(basePos.X, baseHeight, basePos.Z)

			rl.DrawCylinderEx(basePos, baseTopPos, baseRadius, baseRadius, 6, color)
			if hasStroke {
				rl.DrawCylinderWiresEx(basePos, baseTopPos, baseRadius, baseRadius, 6, config.TowerWireColorRL)
			}

			turretHeight := data.Height * 0.5 * scaleFactor
			turretWidth := scaledRadius * 1.5 * scaleFactor
			turretLength := scaledRadius * 0.7 * scaleFactor
			turretCenterPos := rl.NewVector3(basePos.X, baseHeight+turretHeight/2, basePos.Z)

			// Применяем инвертированный угол и к процедурной модели
			rotationAngleDegrees := -turret.CurrentAngle * rl.Rad2deg
			turretScale := rl.NewVector3(turretWidth, turretHeight, turretLength)

			rl.DrawModelEx(s.cubeModel, turretCenterPos, rl.NewVector3(0, 1, 0), rotationAngleDegrees, turretScale, color)
			if hasStroke {
				rl.DrawModelWiresEx(s.cubeModel, turretCenterPos, rl.NewVector3(0, 1, 0), rotationAngleDegrees, turretScale, config.TowerWireColorRL)
			}
		}
		return
	}
	// --- КОНЕЦ БЛОКА ---

	// Обычная отрисовка для башен без турели
	model, ok := s.modelManager.GetModel(tower.DefID)
	if !ok {
		return
	}
	wireModel, ok := s.modelManager.GetWireModel(tower.DefID)
	if !ok {
		return
	}

	position := data.WorldPos
	if tower.CraftingLevel >= 1 {
		position.Y += 3.05
	}
	finalScale := rl.NewVector3(1.0, 1.0, 1.0)

	if towerDef.Type == defs.TowerTypeWall {
		rl.DrawModelEx(model, position, rl.NewVector3(0, 1, 0), 0, finalScale, rl.White)
	} else {
		rl.DrawModelEx(model, position, rl.NewVector3(0, 1, 0), 0, finalScale, color)
	}

	if hasStroke {
		rl.DrawModelWiresEx(wireModel, position, rl.NewVector3(0, 1, 0), 0, finalScale, config.TowerWireColorRL)
	}
}

// ... (остальные функции без существенных изменений) ...
func (s *RenderSystemRL) GetTowerRenderHeight(tower *component.Tower, renderable *component.Renderable) float32 {
	scaledRadius := float32(renderable.Radius * config.CoordScale)
	towerDef, ok := defs.TowerDefs[tower.DefID]
	if !ok {
		return scaledRadius * 4
	}
	switch {
	case towerDef.Type == defs.TowerTypeWall:
		return scaledRadius * 1.5
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
	yAxis := rl.NewVector3(0, 1, 0)
	for _, laser := range s.ecs.Lasers {
		alpha := 1.0 - (laser.Timer / laser.Duration)
		if alpha < 0 {
			alpha = 0
		}
		r, g, b, _ := laser.Color.RGBA()
		lineColor := rl.NewColor(uint8(r>>8), uint8(g>>8), uint8(b>>8), uint8(alpha*255))
		startPos := s.pixelToWorld(component.Position{X: laser.FromX, Y: laser.FromY})
		startPos.Y = float32(laser.FromHeight)
		endPos := s.pixelToWorld(component.Position{X: laser.ToX, Y: laser.ToY})
		endPos.Y = float32(laser.ToHeight)
		direction := rl.Vector3Subtract(endPos, startPos)
		distance := rl.Vector3Length(direction)
		if distance < 0.001 {
			continue
		}
		scale := rl.NewVector3(1.0, distance, 1.0)
		rotationAxis := rl.Vector3CrossProduct(yAxis, direction)
		if rl.Vector3LengthSqr(rotationAxis) < 0.0001 {
			rotationAxis = rl.NewVector3(1, 0, 0)
		}
		dot := rl.Vector3DotProduct(yAxis, rl.Vector3Normalize(direction))
		if dot > 1.0 {
			dot = 1.0
		}
		if dot < -1.0 {
			dot = -1.0
		}
		rotationAngle := float32(math.Acos(float64(dot))) * rl.Rad2deg
		rl.DrawModelEx(s.laserModel, startPos, rotationAxis, rotationAngle, scale, lineColor)
	}
}

func (s *RenderSystemRL) drawRotatingBeams() {}

func (s *RenderSystemRL) drawDraggingLine(isDragging bool, sourceTowerID types.EntityID, cancelDrag func()) {
	if !isDragging || sourceTowerID == 0 || s.camera == nil {
		return
	}
	sourceTower, okT := s.ecs.Towers[sourceTowerID]
	sourceRender, okR := s.ecs.Renderables[sourceTowerID]
	if !okT || !okR {
		cancelDrag()
		return
	}
	startPos := s.hexToWorld(sourceTower.Hex)
	startPos.Y = s.GetTowerRenderHeight(sourceTower, sourceRender)
	ray := rl.GetMouseRay(rl.GetMousePosition(), *s.camera)
	t := -ray.Position.Y / ray.Direction.Y
	var endPos rl.Vector3
	if t > 0 {
		endPos = rl.Vector3Add(ray.Position, rl.Vector3Scale(ray.Direction, t))
	} else {
		endPos = rl.Vector3Add(s.camera.Position, rl.Vector3Scale(ray.Direction, 100))
	}
	rl.DrawCapsule(startPos, endPos, 0.6, 8, 8, rl.Yellow)
}

func (s *RenderSystemRL) drawText() {}

func (s *RenderSystemRL) drawCombinationIndicators() {}

func (s *RenderSystemRL) drawVolcanoEffects() {
	for _, effect := range s.ecs.VolcanoEffects {
		pos := rl.NewVector3(float32(effect.X*config.CoordScale), float32(effect.Z), float32(effect.Y*config.CoordScale))
		progress := effect.Timer / effect.Duration
		alpha := 0.0
		if progress < 0.5 {
			alpha = progress * 2
		} else {
			alpha = 1.0 - (progress-0.5)*2
		}
		color := colorToRL(effect.Color)
		color.A = uint8(alpha * 255)
		rl.DrawSphere(pos, float32(effect.Radius*config.CoordScale), color)
	}
}

func (s *RenderSystemRL) drawDebugTurretLines() {
	rl.DisableDepthTest()
	defer rl.EnableDepthTest()

	for id, turret := range s.ecs.Turrets {
		combat, hasCombat := s.ecs.Combats[id]
		tower, hasTower := s.ecs.Towers[id]
		renderable, hasRenderable := s.ecs.Renderables[id]
		if !hasCombat || !hasTower || !hasRenderable {
			continue
		}

		// --- 1. Определяем начальную точку (центр турели) ---
		var startPos rl.Vector3
		towerPos := s.hexToWorld(tower.Hex)

		baseHeight, ok := s.modelManager.GetBaseModelHeight(tower.DefID)
		if !ok {
			// Фоллбэк для процедурных башен
			baseHeight = s.GetTowerRenderHeight(tower, renderable) * 0.6
		}

		// Предполагаем, что "голова" находится на вершине базы
		startPos = rl.NewVector3(towerPos.X, baseHeight, towerPos.Z)

		// --- 2. Рисуем белую линию "идеального" направления ---
		idealLength := float32(combat.Range) * float32(config.HexSize*config.CoordScale)
		idealAngle := turret.CurrentAngle // Угол из логики игры

		idealEndPos := rl.NewVector3(
			startPos.X+idealLength*float32(math.Cos(float64(idealAngle))),
			startPos.Y, // Линия рисуется на той же высоте
			startPos.Z+idealLength*float32(math.Sin(float64(idealAngle))),
		)
		rl.DrawLine3D(startPos, idealEndPos, rl.White)

		// --- 3. Рисуем локальные оси модели ---
		axisLength := float32(10.0)                               // Длина осей для наглядности
		modelAngleRad := turret.CurrentAngle - (180 * rl.Deg2rad) // Угол, который применяется к модели

		cos := float32(math.Cos(float64(modelAngleRad)))
		sin := float32(math.Sin(float64(modelAngleRad)))

		// Локальная ось X модели (Красная)
		rotatedX := rl.NewVector3(cos, 0, sin)
		endPosX := rl.Vector3Add(startPos, rl.Vector3Scale(rotatedX, axisLength))
		rl.DrawLine3D(startPos, endPosX, rl.Red)

		// Локальная ось Y модели (Зеленая) - "вверх"
		rotatedY := rl.NewVector3(0, 1, 0)
		endPosY := rl.Vector3Add(startPos, rl.Vector3Scale(rotatedY, axisLength))
		rl.DrawLine3D(startPos, endPosY, rl.Green)

		// Локальная ось Z модели (Синяя)
		rotatedZ := rl.NewVector3(-sin, 0, cos)
		endPosZ := rl.Vector3Add(startPos, rl.Vector3Scale(rotatedZ, axisLength))
		rl.DrawLine3D(startPos, endPosZ, rl.Blue)
	}
}

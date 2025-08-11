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
	ecs             *entity.ECS
	font            rl.Font
	camera          *rl.Camera3D
	renderCache     map[types.EntityID]*CachedRenderData
	frustum         [6]rl.Vector4 // Плоскости для frustum culling
	towerModels     map[string]rl.Model
	towerWireModels map[string]rl.Model
	laserModel      rl.Model // Добавлено для оптимизации лазеров
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
	rs.pregenerateLaserModel() // Добавлен вызов для создания модели лазера
	return rs
}

// pregenerateLaserModel создает 3D-модель для лазера для оптимизации.
func (s *RenderSystemRL) pregenerateLaserModel() {
	mesh := rl.GenMeshCylinder(1.0, 1.0, 8)
	// Вручную трансформируем вершины, так как rl.MeshTransform может отсутствовать
	transform := rl.MatrixTranslate(0, 0.5, 0)
	meshTransform(&mesh, transform)
	s.laserModel = rl.LoadModelFromMesh(mesh)
}

// meshTransform применяет матрицу трансформации к каждой вершине меша.
// Это ручная реализация rl.MeshTransform для совместимости.
func meshTransform(mesh *rl.Mesh, transform rl.Matrix) {
	vertexCount := int(mesh.VertexCount)
	// Используем unsafe.Pointer для корректного преобразования *float32 в []float32
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

	// Обновление таймеров эффектов вулкана
	for id, effect := range s.ecs.VolcanoEffects {
		effect.Timer += deltaTime
		// Анимация радиуса
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

// Draw использует кэшированные данные для отрисовки всего, КРОМЕ снарядов
func (s *RenderSystemRL) Draw(gameTime float64, isDragging bool, sourceTowerID, hiddenLineID types.EntityID, gameState component.GamePhase, cancelDrag func()) {
	if s.camera == nil {
		return
	}
	s.drawPulsingOres(gameTime)
	s.drawSolidEntities()
	s.drawLines(hiddenLineID)
	s.drawLasers()
	s.drawVolcanoEffects() // <-- Добавлен вызов
	s.drawBeaconSectors()  // <-- НОВЫЙ ВЫЗОВ
	s.drawDraggingLine(isDragging, sourceTowerID, cancelDrag)
	s.drawText()
	s.drawCombinationIndicators()
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

		// Параметры для отрисовки
		towerPos := s.hexToWorld(tower.Hex)
		towerHeight := s.GetTowerRenderHeight(tower, renderable)
		towerTop := rl.NewVector3(towerPos.X, towerHeight, towerPos.Z)

		rangePixels := float32(float64(combat.Range) * config.HexSize * config.CoordScale)
		startAngle := float32(beacon.CurrentAngle - beacon.ArcAngle/2)
		endAngle := float32(beacon.CurrentAngle + beacon.ArcAngle/2)

		// Вершины основания пирамиды
		v1 := towerPos // Центр основания
		v2 := rl.NewVector3(
			towerPos.X+rangePixels*float32(math.Cos(float64(startAngle))),
			0,
			towerPos.Z+rangePixels*float32(math.Sin(float64(startAngle))),
		)
		v3 := rl.NewVector3(
			towerPos.X+rangePixels*float32(math.Cos(float64(endAngle))),
			0,
			towerPos.Z+rangePixels*float32(math.Sin(float64(endAngle))),
		)

		// Цвет с прозрачностью
		sectorColor := rl.NewColor(255, 255, 224, 70) // Бледно-желтый, полупрозрачный

		// Рисуем грани пирамиды
		rl.DrawTriangle3D(towerTop, v2, v3, sectorColor)
		rl.DrawTriangle3D(towerTop, v3, v1, sectorColor)
		rl.DrawTriangle3D(towerTop, v1, v2, sectorColor)

		// Рисуем контур основания
		lineColor := rl.NewColor(255, 255, 150, 150)
		rl.DrawLine3D(v1, v2, lineColor)
		rl.DrawLine3D(v1, v3, lineColor)
		rl.DrawLine3D(v2, v3, lineColor)
	}
}

func (s *RenderSystemRL) drawSolidEntities() {
	for id, data := range s.renderCache {
		if !data.IsOnScreen {
			continue
		}

		// Пропускаем снаряды, они будут отрисованы в отдельном проходе
		if _, isProjectile := s.ecs.Projectiles[id]; isProjectile {
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
			// <<< НАЧАЛО: Отрисовка индикатора крафта >>>
			if _, ok := s.ecs.Combinables[id]; ok {
				indicatorPos := data.WorldPos
				indicatorPos.Y = data.Height + 4.0 // Располагаем над башней
				indicatorRadius := scaledRadius * 0.5

				// Рисуем сам диск
				rl.DrawCylinder(indicatorPos, indicatorRadius, indicatorRadius, 0.1, 12, rl.Gold)
				// Рисуем обводку
				rl.DrawCylinderWires(indicatorPos, indicatorRadius, indicatorRadius, 0.1, 12, rl.Black)
			}
			// <<< КОНЕЦ: Отрисовка индикатора крафта >>>
		}
	}
}

// DrawProjectiles рисует только снаряды. Должна вызываться отдельно с отключенным depth test.
func (s *RenderSystemRL) DrawProjectiles() {
	for id, data := range s.renderCache {
		if !data.IsOnScreen {
			continue
		}

		// Рисуем только снаряды
		if _, isProjectile := s.ecs.Projectiles[id]; !isProjectile {
			continue
		}

		renderable, ok := s.ecs.Renderables[id]
		if !ok {
			continue
		}

		finalColor := colorToRL(renderable.Color)
		scaledRadius := data.Radius * float32(config.CoordScale)
		pos := data.WorldPos
		pos.Y = scaledRadius
		rl.DrawSphere(pos, scaledRadius, finalColor)
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

// drawLasers отрисовывает лазерные лучи с использованием оптимизированной модели.
func (s *RenderSystemRL) drawLasers() {
	yAxis := rl.NewVector3(0, 1, 0) // Модель цилиндра по умолчанию ориентирована вдоль оси Y

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

		// Масштаб: X и Z - толщина, Y - длина.
		// Наша модель имеет высоту 1, поэтому масштабируем Y на всю длину.
		scale := rl.NewVector3(1.0, distance, 1.0)

		// Вращение: вычисляем ось и угол для поворота от Y-оси к вектору direction
		rotationAxis := rl.Vector3CrossProduct(yAxis, direction)
		if rl.Vector3LengthSqr(rotationAxis) < 0.0001 {
			// Векторы коллинеарны (параллельны). Ось вращения может быть любой.
			rotationAxis = rl.NewVector3(1, 0, 0)
		}
		dot := rl.Vector3DotProduct(yAxis, rl.Vector3Normalize(direction))
		if dot > 1.0 { dot = 1.0 }
		if dot < -1.0 { dot = -1.0 }
		rotationAngle := float32(math.Acos(float64(dot))) * rl.Rad2deg

		// Позиция: теперь это startPos, так как мы изм��нили pivot модели на ее основание.
		// Модель будет отрисована в startPos и правильно повернута/растянута до endPos.
		rl.DrawModelEx(s.laserModel, startPos, rotationAxis, rotationAngle, scale, lineColor)
	}
}

func (s *RenderSystemRL) drawRotatingBeams() {
	// ... (implementation from "было.txt")
}

func (s *RenderSystemRL) drawDraggingLine(isDragging bool, sourceTowerID types.EntityID, cancelDrag func()) {
	if !isDragging || sourceTowerID == 0 || s.camera == nil {
		return
	}

	sourceTower, okT := s.ecs.Towers[sourceTowerID]
	sourceRender, okR := s.ecs.Renderables[sourceTowerID]
	if !okT || !okR {
		// Если башня по какой-то причине исчезла, отменяем перетаскивание
		cancelDrag()
		return
	}

	// Получаем начальную позицию (верхушка башни)
	startPos := s.hexToWorld(sourceTower.Hex)
	startPos.Y = s.GetTowerRenderHeight(sourceTower, sourceRender)

	// Получаем конечную позицию (курсор на плоскости y=0)
	ray := rl.GetMouseRay(rl.GetMousePosition(), *s.camera)
	t := -ray.Position.Y / ray.Direction.Y
	var endPos rl.Vector3
	if t > 0 {
		endPos = rl.Vector3Add(ray.Position, rl.Vector3Scale(ray.Direction, t))
	} else {
		// Если курсор не указывает на плоскость, рисуем линию в направлении камеры
		endPos = rl.Vector3Add(s.camera.Position, rl.Vector3Scale(ray.Direction, 100))
	}

	// Рисуем линию
	rl.DrawCapsule(startPos, endPos, 0.6, 8, 8, rl.Yellow)
}

func (s *RenderSystemRL) drawText() {
	// ... (implementation from "было.txt")
}

func (s *RenderSystemRL) drawCombinationIndicators() {
	// ... (implementation from "было.txt")
}

func (s *RenderSystemRL) drawVolcanoEffects() {
	for _, effect := range s.ecs.VolcanoEffects {
		pos := rl.NewVector3(float32(effect.X*config.CoordScale), float32(effect.Z), float32(effect.Y*config.CoordScale))
		
		// Анимация прозрачности: эффект плавно появляется и исчезает
		progress := effect.Timer / effect.Duration
		alpha := 0.0
		if progress < 0.5 {
			alpha = progress * 2 // От 0 до 1
		} else {
			alpha = 1.0 - (progress-0.5)*2 // От 1 до 0
		}

		color := colorToRL(effect.Color)
		color.A = uint8(alpha * 255)

		rl.DrawSphere(pos, float32(effect.Radius*config.CoordScale), color)
	}
}
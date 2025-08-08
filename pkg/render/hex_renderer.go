package render

import (
	"go-tower-defense/internal/config"
	"go-tower-defense/pkg/hexmap"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// HexRenderer отвечает за отрисовку гексагональной карты.
// Он предварительно генерирует модели для каждого типа гексов для оптимизации.
type HexRenderer struct {
	passableModel   rl.Model
	checkpointModel rl.Model
	entryModel      rl.Model
	exitModel       rl.Model
	outlineModel    rl.Model
}

// NewHexRenderer создает новый экземпляр HexRenderer и генерирует модели карты.
func NewHexRenderer(hexMap *hexmap.HexMap) *HexRenderer {
	// Разделяем гексы по типам
	passableHexes := []hexmap.Hex{}
	checkpointHexes := make(map[hexmap.Hex]bool)
	for _, cp := range hexMap.Checkpoints {
		checkpointHexes[cp] = true
	}

	for hex := range hexMap.Tiles {
		if hex == hexMap.Entry || hex == hexMap.Exit || checkpointHexes[hex] {
			continue
		}
		passableHexes = append(passableHexes, hex)
	}

	// Параметры для генерации
	mapThickness := float32(0.5 * config.CoordScale)
	fillRadius := float32((config.HexSize - 1.5) * config.CoordScale)
	outlineRadius := float32(config.HexSize * config.CoordScale)

	// Создаем объединенные модели для каждого типа
	passableMesh := createCombinedMesh(passableHexes, fillRadius, mapThickness)
	checkpointMesh := createCombinedMesh(hexMap.Checkpoints, fillRadius, mapThickness)
	entryMesh := createCombinedMesh([]hexmap.Hex{hexMap.Entry}, fillRadius, mapThickness)
	exitMesh := createCombinedMesh([]hexmap.Hex{hexMap.Exit}, fillRadius, mapThickness)
	outlineMesh := createCombinedMesh(mapsToSlice(hexMap.Tiles), outlineRadius, mapThickness)

	return &HexRenderer{
		passableModel:   rl.LoadModelFromMesh(passableMesh),
		checkpointModel: rl.LoadModelFromMesh(checkpointMesh),
		entryModel:      rl.LoadModelFromMesh(entryMesh),
		exitModel:       rl.LoadModelFromMesh(exitMesh),
		outlineModel:    rl.LoadModelFromMesh(outlineMesh),
	}
}

// Draw рендерит всю карту, используя предварительно созданные модели.
func (r *HexRenderer) Draw() {
	// Позиция (0,0,0) и масштаб 1.0, так как все трансформации уже "запечены" в модели
	origin := rl.NewVector3(0, 0, 0)
	rl.DrawModel(r.passableModel, origin, 1.0, config.PassableColorRL)
	rl.DrawModel(r.checkpointModel, origin, 1.0, config.CheckpointColorRL)
	rl.DrawModel(r.entryModel, origin, 1.0, config.EntryColorRL)
	rl.DrawModel(r.exitModel, origin, 1.0, config.ExitColorRL)
	rl.DrawModelWires(r.outlineModel, origin, 1.0, config.StrokeColorRL)
}

// Cleanup выгружает модели из памяти.
func (r *HexRenderer) Cleanup() {
	rl.UnloadModel(r.passableModel)
	rl.UnloadModel(r.checkpointModel)
	rl.UnloadModel(r.entryModel)
	rl.UnloadModel(r.exitModel)
	rl.UnloadModel(r.outlineModel)
}

// createCombinedMesh создает один большой меш из множества гексов.
func createCombinedMesh(hexes []hexmap.Hex, radius, height float32) rl.Mesh {
	if len(hexes) == 0 {
		return rl.Mesh{} // Возвращаем пустой меш, если нет гексов
	}

	allMeshes := make([]*rl.Mesh, len(hexes))
	for i, h := range hexes {
		// Создаем меш для одного гекса
		hexMesh := rl.GenMeshCylinder(radius, height, 6)

		// Применяем поворот в 30 градусов, чтобы выровнять с сеткой
		rotation := rl.MatrixRotate(rl.NewVector3(0, 1, 0), 30*rl.Deg2rad)
		// Применяем смещение в мировые координаты
		translation := rl.MatrixTranslate(
			float32(h.ToPixel(float64(config.HexSize)).X*config.CoordScale),
			-height/2, // Смещаем карту вниз, чтобы поверхность была на Y=0
			float32(h.ToPixel(float64(config.HexSize)).Y*config.CoordScale),
		)
		transform := rl.MatrixMultiply(rotation, translation)

		// Трансформируем вершины меша
		rl.MeshTransform(hexMesh, transform)
		allMeshes[i] = &hexMesh
	}

	// Объединяем все меши в один
	return rl.MergeMeshes(allMeshes)
}

// hexToWorld преобразует координаты гекса в мировые 3D координаты.
func hexToWorld(h hexmap.Hex) rl.Vector3 {
	x, y := h.ToPixel(float64(config.HexSize))
	return rl.NewVector3(float32(x*config.CoordScale), 0, float32(y*config.CoordScale))
}

// mapsToSlice преобразует map[hexmap.Hex]struct{} в срез []hexmap.Hex
func mapsToSlice(m map[hexmap.Hex]struct{}) []hexmap.Hex {
	s := make([]hexmap.Hex, 0, len(m))
	for k := range m {
		s = append(s, k)
	}
	return s
}
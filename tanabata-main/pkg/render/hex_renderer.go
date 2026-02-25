package render

import (
	"go-tower-defense/internal/config"
	"go-tower-defense/pkg/hexmap"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// HexRenderer отвечает за отрисовку гексагональной карты.
// Он предварительно генерирует модели для заливки и контура гекса для оптимизации.
type HexRenderer struct {
	hexMap         *hexmap.HexMap
	hexFillModel   rl.Model
	hexOutlineModel rl.Model
	customColors   map[hexmap.Hex]rl.Color
}

// NewHexRenderer создает новый экземпляр HexRenderer и генерирует модели гексов.
func NewHexRenderer(hexMap *hexmap.HexMap, customColors map[hexmap.Hex]rl.Color) *HexRenderer {
	// Параметры для генерации
	mapThickness := float32(1.0)
	fillRadius := float32((config.HexSize - 1.5) * config.CoordScale)
	outlineRadius := float32(config.HexSize * config.CoordScale)

	// Создаем меши
	fillMesh := rl.GenMeshCylinder(fillRadius, mapThickness, 6)
	outlineMesh := rl.GenMeshCylinder(outlineRadius, mapThickness, 6)

	// Создаем модели из мешей
	fillModel := rl.LoadModelFromMesh(fillMesh)
	outlineModel := rl.LoadModelFromMesh(outlineMesh)

	return &HexRenderer{
		hexMap:         hexMap,
		hexFillModel:   fillModel,
		hexOutlineModel: outlineModel,
		customColors:   customColors,
	}
}

// Draw рендерит всю карту, используя предварительно созданные модели.
func (r *HexRenderer) Draw() {
	// Рисуем все гексы
	for hex := range r.hexMap.Tiles {
		var color rl.Color
		// Приоритет цветов: чекпоинты > вход/выход > руда > по умолчанию
		isCheckpoint := false
		for _, cp := range r.hexMap.Checkpoints {
			if hex == cp {
				isCheckpoint = true
				break
			}
		}

		if isCheckpoint {
			color = config.CheckpointColorRL
		} else if hex == r.hexMap.Entry {
			color = config.EntryColorRL
		} else if hex == r.hexMap.Exit {
			color = config.ExitColorRL
		} else if customColor, ok := r.customColors[hex]; ok {
			color = customColor
		} else {
			color = config.PassableColorRL // Цвет по умолчанию
		}
		r.drawHexModel(hex, color)
	}
}

// drawHexModel рисует один гекс, используя общие модели.
func (r *HexRenderer) drawHexModel(h hexmap.Hex, color rl.Color) {
	pos := hexToWorld(h)
	// Смещаем карту вниз, чтобы поверхность была на Y=0
	pos.Y -= float32(1.0) / 2

	rl.DrawModel(r.hexFillModel, pos, 1.0, color)
	rl.DrawModelWires(r.hexOutlineModel, pos, 1.0, config.StrokeColorRL)
}

// Cleanup выгружает модели из памяти.
func (r *HexRenderer) Cleanup() {
	rl.UnloadModel(r.hexFillModel)
	rl.UnloadModel(r.hexOutlineModel)
}

// hexToWorld преобразует координаты гекса в мировые 3D координаты.
func hexToWorld(h hexmap.Hex) rl.Vector3 {
	x, y := h.ToPixel(float64(config.HexSize))
	return rl.NewVector3(float32(x*config.CoordScale), 0, float32(y*config.CoordScale))
}

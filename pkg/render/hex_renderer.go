// pkg/render/hex_renderer.go
package render

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/system"
	"go-tower-defense/internal/types"
	"go-tower-defense/pkg/hexmap"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// HexRendererRL - новая версия рендерера для Raylib
type HexRendererRL struct {
	hexMap        *hexmap.HexMap
	hexSize       float32 // Используем float32 для Raylib
	font          rl.Font
	checkpointMap map[hexmap.Hex]int
	EnergyVeins   map[hexmap.Hex]float64
}

// NewHexRendererRL создает новый рендерер для Raylib
func NewHexRendererRL(hexMap *hexmap.HexMap, energyVeins map[hexmap.Hex]float64, hexSize float32, font rl.Font) *HexRendererRL {
	renderer := &HexRendererRL{
		hexMap:        hexMap,
		hexSize:       hexSize,
		font:          font,
		checkpointMap: make(map[hexmap.Hex]int),
		EnergyVeins:   energyVeins,
	}

	for i, cp := range hexMap.Checkpoints {
		renderer.checkpointMap[cp] = i + 1
	}

	return renderer
}

// Draw отрисовывает карту и динамические объекты
func (r *HexRendererRL) Draw(renderSystem *system.RenderSystemRL, gameTime float64, isDragging bool, sourceTowerID, hiddenLineID types.EntityID, gameState component.GamePhase, cancelDrag func()) {
	// Отрисовка гексов как 3D объектов
	for h, tile := range r.hexMap.Tiles {
		pos := r.HexToWorld(h)
		radius := r.hexSize * 0.95 // Небольшой зазор между гексами
		height := float32(1.0)     // Плоские призмы

		var baseColor rl.Color
		if _, isCheckpoint := r.checkpointMap[h]; isCheckpoint {
			baseColor = config.CheckpointColorRL
		} else if _, exists := r.EnergyVeins[h]; exists {
			baseColor = config.OreColorRL
		} else if !tile.Passable {
			baseColor = config.ImpassableColorRL
		} else {
			baseColor = config.PassableColorRL
		}

		// Рисуем "крышку" гекса
		rl.DrawCylinder(pos, radius, radius, height, 6, baseColor)
		// Рисуем контур
		rl.DrawCylinderWires(pos, radius, radius, height, 6, config.StrokeColorRL)
	}

	// Вызываем систему рендеринга для динамических объектов (башни, враги и т.д.)
	renderSystem.Draw(gameTime, isDragging, sourceTowerID, hiddenLineID, gameState, cancelDrag)
}

// HexToWorld преобразует координаты гекса в мировые 3D-координаты
func (r *HexRendererRL) HexToWorld(h hexmap.Hex) rl.Vector3 {
	// Используем ту же логику, что и в ebiten, но для 3D
	x, y := h.ToPixel(float64(r.hexSize))
	// Y в 3D - это Z в 2D
	return rl.NewVector3(float32(x), 0, float32(y))
}

// WorldToHex преобразует мировые 3D-координаты в гекс
func (r *HexRendererRL) WorldToHex(point rl.Vector3) hexmap.Hex {
	// Обратное преобразование, игнорируя Y
	return hexmap.PixelToHex(float64(point.X), float64(point.Z), float64(r.hexSize))
}

// Unload больше не требует выгрузки специфичных для рендерера ресурсов
func (r *HexRendererRL) Unload() {
	// Пусто, так как мы больше не создаем текстуры или модели в этом рендерере
}

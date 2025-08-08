package render

import (
	"go-tower-defense/internal/config"
	"go-tower-defense/pkg/hexmap"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// HexRenderer отвечает за отрисовку гексагональной карты
type HexRenderer struct {
	HexMap *hexmap.HexMap
}

// NewHexRenderer создает новый экземпляр HexRenderer
func NewHexRenderer(hexMap *hexmap.HexMap) *HexRenderer {
	return &HexRenderer{HexMap: hexMap}
}

// Draw рендерит всю карту
func (r *HexRenderer) Draw() {
	// Итерируемся по ключам карты (hexmap.Hex)
	for hex := range r.HexMap.Tiles {
		// Пропускаем вход и выход, чтобы нарисовать их отдельно
		if hex == r.HexMap.Entry || hex == r.HexMap.Exit {
			continue
		}
		r.drawHex(hex, config.PassableColorRL, config.StrokeColorRL)
	}

	// Рисуем чекпоинты
	for _, cp := range r.HexMap.Checkpoints {
		r.drawHex(cp, config.CheckpointColorRL, config.StrokeColorRL)
	}

	// Рисуем вход и выход специальными цветами
	r.drawHex(r.HexMap.Entry, config.EntryColorRL, config.StrokeColorRL)
	r.drawHex(r.HexMap.Exit, config.ExitColorRL, config.StrokeColorRL)
}

func (r *HexRenderer) drawHex(h hexmap.Hex, fillColor, lineColor rl.Color) {
	// Draw hex using a 3D cylinder
	hexCenter3D := hexToWorld(h)
	// Используем CoordScale для определения толщины карты
	mapThickness := float32(0.5 * config.CoordScale)
	hexCenter3D.Y -= mapThickness / 2 // Смещаем карту вниз, чтобы поверхность была на Y=0

	// ИСПРАВЛЕНО: Уменьшаем радиус заливки для создания зазора
	fillRadius := float32((config.HexSize - 1.5) * config.CoordScale)
	outlineRadius := float32(config.HexSize * config.CoordScale)

	rl.DrawCylinder(hexCenter3D, fillRadius, fillRadius, mapThickness, 6, fillColor)
	rl.DrawCylinderWires(hexCenter3D, outlineRadius, outlineRadius, mapThickness, 6, lineColor)
}

func hexToWorld(h hexmap.Hex) rl.Vector3 {
	x, y := h.ToPixel(float64(config.HexSize))
	return rl.NewVector3(float32(x*config.CoordScale), 0, float32(y*config.CoordScale))
}

func (r *HexRenderer) drawLine(start, end hexmap.Hex, lineColor rl.Color) {
	startPos := hexToWorld(start)
	endPos := hexToWorld(end)
	rl.DrawLine3D(startPos, endPos, lineColor)
}

func (r *HexRenderer) Cleanup() {
	// Пока что нечего очищать
}

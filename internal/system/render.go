// internal/system/render.go
package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/types"
	"image/color"
	"log"
	"math"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/text"
	"github.com/hajimehoshi/ebiten/v2/vector"
	"golang.org/x/image/font"
	"golang.org/x/image/font/opentype"
)

// RenderSystem рисует сущности
type RenderSystem struct {
	ecs        *entity.ECS
	fontFace   font.Face
	uiFontFace font.Face
}

func NewRenderSystem(ecs *entity.ECS, tt *opentype.Font) *RenderSystem {
	fontFace, err := opentype.NewFace(tt, &opentype.FaceOptions{
		Size:    11,
		DPI:     72,
		Hinting: font.HintingFull,
	})
	if err != nil {
		log.Fatalf("failed to create font face: %v", err)
	}

	uiFontFace, err := opentype.NewFace(tt, &opentype.FaceOptions{
		Size:    24, // Larger font size for UI
		DPI:     72,
		Hinting: font.HintingFull,
	})
	if err != nil {
		log.Fatalf("failed to create UI font face: %v", err)
	}

	return &RenderSystem{ecs: ecs, fontFace: fontFace, uiFontFace: uiFontFace}
}

func (s *RenderSystem) Draw(screen *ebiten.Image, gameTime float64, isDragging bool, sourceTowerID, hiddenLineID types.EntityID, gameState component.GamePhase, cancelDrag func()) {
	s.drawPulsingOres(screen, gameTime)
	s.drawEntities(screen, gameTime)
	s.drawLines(screen, hiddenLineID) // Передаем ID скрытой линии
	s.drawLasers(screen)
	s.drawDraggingLine(screen, isDragging, sourceTowerID, cancelDrag)
	s.drawText(screen)
	s.drawCombinationIndicators(screen) // Рисуем индикаторы последними

	// Рисуем UI для режима перетаскивания
	if gameState == component.BuildState {
		s.drawDragModeIndicator(screen, isDragging)
	}
}

func (s *RenderSystem) Update(deltaTime float64) {
	// Обновляем таймеры лазеров и удаляем истекшие
	for id, laser := range s.ecs.Lasers {
		laser.Timer += deltaTime
		if laser.Timer >= laser.Duration {
			delete(s.ecs.Lasers, id)
			delete(s.ecs.Renderables, id) // Также удаляем Renderable компонент
		}
	}
}

func (s *RenderSystem) drawLasers(screen *ebiten.Image) {
	for _, laser := range s.ecs.Lasers {
		// Вычисляем альфа-канал для эффекта затухания
		alpha := 1.0 - (laser.Timer / laser.Duration)
		if alpha < 0 {
			alpha = 0
		}
		// Преобразуем цвет в RGBA, чтобы можно было изменить альфа
		r, g, b, _ := laser.Color.RGBA()
		lineColor := color.RGBA{
			R: uint8(r >> 8),
			G: uint8(g >> 8),
			B: uint8(b >> 8),
			A: uint8(alpha * 255),
		}
		vector.StrokeLine(screen, float32(laser.FromX), float32(laser.FromY), float32(laser.ToX), float32(laser.ToY), 2, lineColor, true)
	}
}

func (s *RenderSystem) drawDragModeIndicator(screen *ebiten.Image, isDragging bool) {
	const (
		char = "U"
		x    = 25
		y    = 45
	)
	var mainColor color.Color
	outlineColor := color.White

	if isDragging {
		mainColor = config.WaveStateColor // Red when active
	} else {
		mainColor = config.BuildStateColor // Blue when inactive
	}

	// 1. Draw outline for the text
	outlineOffsets := []struct{ dx, dy int }{
		{-2, -2}, {0, -2}, {2, -2},
		{-2, 0}, {2, 0},
		{-2, 2}, {0, 2}, {2, 2},
	}
	for _, offset := range outlineOffsets {
		text.Draw(screen, char, s.uiFontFace, x+offset.dx, y+offset.dy, outlineColor)
	}

	// 2. Draw main text (bold)
	boldOffsets := []struct{ dx, dy int }{
		{-1, -1}, {0, -1}, {1, -1},
		{-1, 0}, {0, 0}, {1, 0},
		{-1, 1}, {0, 1}, {1, 1},
	}
	for _, offset := range boldOffsets {
		text.Draw(screen, char, s.uiFontFace, x+offset.dx, y+offset.dy, mainColor)
	}

	if !isDragging {
		// 3. Draw a horizontal line through the "U"
		bounds := text.BoundString(s.uiFontFace, char)
		lineY := float32(y + (bounds.Min.Y+bounds.Max.Y)/2)
		startX := float32(x + bounds.Min.X - 5)
		endX := float32(x + bounds.Max.X + 5)

		// Draw outline for the line
		vector.StrokeLine(screen, startX, lineY, endX, lineY, 6, outlineColor, true)
		// Draw main line
		vector.StrokeLine(screen, startX, lineY, endX, lineY, 4, mainColor, true)
	}
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

func (s *RenderSystem) drawEntity(screen *ebiten.Image, id types.EntityID, renderable *component.Renderable, pos *component.Position, gameTime float64) { //+
	finalColor := renderable.Color //+

	// Приоритет 1: Урон (красный) //-
	if _, ok := s.ecs.DamageFlashes[id]; ok { //+
		finalColor = config.EnemyDamageColor //+
	} else if _, ok := s.ecs.PoisonEffects[id]; ok { // Приоритет 2: Отравление (зеленый)
		finalColor = config.ProjectileColorPoison
	} else if _, ok := s.ecs.SlowEffects[id]; ok { // Приоритет 3: Замедление (белый)
		finalColor = config.ProjectileColorSlow //+
	} //+

	// Проверяем, является ли сущность башней "Сильвер"
	if tower, isTower := s.ecs.Towers[id]; isTower && tower.DefID == "TOWER_SILVER" {
		// Рисуем квадрат
		size := renderable.Radius * 2 // Используем радиус для определения размера
		halfSize := size / 2
		vector.DrawFilledRect(screen, float32(pos.X)-halfSize, float32(pos.Y)-halfSize, size, size, finalColor, true)
		if renderable.HasStroke {
			vector.StrokeRect(screen, float32(pos.X)-halfSize, float32(pos.Y)-halfSize, size, size, 1, color.White, true)
		}
	} else {
		// Рисуем круг ��ля всех остальных сущностей
		if renderable.HasStroke { //+
			vector.DrawFilledCircle(screen, float32(pos.X), float32(pos.Y), renderable.Radius, finalColor, true) //+
			vector.StrokeCircle(screen, float32(pos.X), float32(pos.Y), renderable.Radius, 1, color.White, true)  //+
		} else { //+
			vector.DrawFilledCircle(screen, float32(pos.X), float32(pos.Y), renderable.Radius, finalColor, true) //+
		} //+
	}
} //+

func (s *RenderSystem) drawCombinationIndicators(screen *ebiten.Image) {
	// Итерируем по всем башням, у которых есть компонент Combinable.
	// Это гарантирует, что каждая башня, готовая к крафту, получит индикатор.
	for id := range s.ecs.Combinables {
		if pos, ok := s.ecs.Positions[id]; ok {
			if renderable, ok := s.ecs.Renderables[id]; ok {
				indicatorRadius := renderable.Radius / 2
				indicatorColor := color.RGBA{R: 0, G: 0, B: 0, A: 255}       // Черный цвет
				outlineColor := color.RGBA{R: 255, G: 255, B: 255, A: 255} // Белый цвет

				// Рисуем сначала обводку, потом сам круг
				vector.DrawFilledCircle(screen, float32(pos.X), float32(pos.Y), indicatorRadius+1, outlineColor, true)
				vector.DrawFilledCircle(screen, float32(pos.X), float32(pos.Y), indicatorRadius, indicatorColor, true)
			}
		}
	}
}

func (s *RenderSystem) drawLines(screen *ebiten.Image, hiddenLineID types.EntityID) {
	for id, line := range s.ecs.LineRenders {
		// Не рисуем линию, если она скрыта
		if id == hiddenLineID {
			continue
		}
		startPos := s.ecs.Positions[line.Tower1ID]
		endPos := s.ecs.Positions[line.Tower2ID]
		if startPos != nil && endPos != nil {
			vector.StrokeLine(screen, float32(startPos.X), float32(startPos.Y), float32(endPos.X), float32(endPos.Y), float32(config.StrokeWidth), line.Color, true)
		}
	}
}

func (s *RenderSystem) drawDraggingLine(screen *ebiten.Image, isDragging bool, sourceTowerID types.EntityID, cancelDrag func()) {
	if !isDragging || sourceTowerID == 0 {
		return
	}

	sourcePos, ok := s.ecs.Positions[sourceTowerID]
	if !ok {
		return
	}

	mx, my := ebiten.CursorPosition()

	// Проверка на разрыв связи
	dx := float64(mx) - sourcePos.X
	dy := float64(my) - sourcePos.Y
	if math.Sqrt(dx*dx+dy*dy) > 300 {
		cancelDrag()
		return
	}

	// Рисуем пунктирную линию до курсора
	vector.StrokeLine(screen, float32(sourcePos.X), float32(sourcePos.Y), float32(mx), float32(my), 2, color.RGBA{255, 255, 0, 255}, true)
}

func (s *RenderSystem) drawText(screen *ebiten.Image) {
	for _, txt := range s.ecs.Texts {
		text.Draw(screen, txt.Value, s.fontFace, int(txt.Position.X), int(txt.Position.Y), txt.Color)
	}
}

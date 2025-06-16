package render

import (
	"fmt"
	"image/color"
	"log"
	"math"

	"go-tower-defense/internal/config"
	"go-tower-defense/internal/system"
	"go-tower-defense/pkg/hexmap"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/text"
	"github.com/hajimehoshi/ebiten/v2/vector"

	"io/ioutil"

	"golang.org/x/image/font"
	"golang.org/x/image/font/opentype"
)

type HexRenderer struct {
	hexMap       *hexmap.HexMap
	hexSize      float64
	screenWidth  int
	screenHeight int
	fillImg      *ebiten.Image
	strokeImg    *ebiten.Image
	sortedHexes  []hexmap.Hex
	fillVs       []ebiten.Vertex
	fillIs       []uint16
	strokeVs     []ebiten.Vertex
	strokeIs     []uint16
	fontFace     font.Face
	mapImage     *ebiten.Image // Поле для предрендеренной карты
}

func NewHexRenderer(hexMap *hexmap.HexMap, hexSize float64, screenWidth, screenHeight int) *HexRenderer {
	fillImg := ebiten.NewImage(1, 1)
	fillImg.Fill(color.White)

	strokeImg := ebiten.NewImage(1, 1)
	strokeImg.Fill(color.White)

	var hexes []hexmap.Hex
	for hex := range hexMap.Tiles {
		hexes = append(hexes, hex)
	}

	// Загрузка TTF-шрифта
	fontData, err := ioutil.ReadFile("assets/fonts/arial.ttf")
	if err != nil {
		log.Fatal(err)
	}
	tt, err := opentype.Parse(fontData)
	if err != nil {
		log.Fatal(err)
	}
	const fontSize = 10
	face, err := opentype.NewFace(tt, &opentype.FaceOptions{
		Size:    fontSize,
		DPI:     72,
		Hinting: font.HintingFull,
	})
	if err != nil {
		log.Fatal(err)
	}

	renderer := &HexRenderer{
		hexMap:       hexMap,
		hexSize:      hexSize,
		screenWidth:  screenWidth,
		screenHeight: screenHeight,
		fillImg:      fillImg,
		strokeImg:    strokeImg,
		sortedHexes:  hexes,
		fillVs:       make([]ebiten.Vertex, 0, 18),
		fillIs:       make([]uint16, 0, 18),
		strokeVs:     make([]ebiten.Vertex, 0, 36),
		strokeIs:     make([]uint16, 0, 36),
		fontFace:     face,
		mapImage:     ebiten.NewImage(screenWidth, screenHeight), // Создаём изображение размером с экран
	}

	// Отрисовываем карту один раз при инициализации
	renderer.RenderMapImage()

	return renderer
}

// RenderMapImage создаёт предрендеренное изображение задника
func (r *HexRenderer) RenderMapImage() {
	// Очищаем изображение перед отрисовкой
	r.mapImage.Clear()

	// Рисуем заполнение всех гексов
	for _, hex := range r.sortedHexes {
		r.drawHexFill(r.mapImage, hex)
	}

	// Рисуем обводку всех гексов (без учёта башен, они динамические)
	for _, hex := range r.sortedHexes {
		r.drawHexOutline(r.mapImage, hex, nil) // nil, так как башни отрисовываются позже
	}
}

func (r *HexRenderer) Draw(screen *ebiten.Image, towerHexes []hexmap.Hex, renderSystem *system.RenderSystem) {
	// Рисуем предрендеренную карту одним вызовом
	screen.DrawImage(r.mapImage, nil)

	// Создаём map для быстрого доступа к гексам с башнями
	towerHexSet := make(map[hexmap.Hex]struct{})
	for _, hex := range towerHexes {
		towerHexSet[hex] = struct{}{}
	}

	// Рисуем обводку только для гексов с башнями
	for _, hex := range towerHexes {
		r.drawHexOutline(screen, hex, towerHexSet)
	}

	// Рисуем динамические сущности (башни, враги и т.д.)
	renderSystem.Draw(screen)
}

func (r *HexRenderer) drawHexFill(target *ebiten.Image, hex hexmap.Hex) {
	x, y := hex.ToPixel(r.hexSize)
	x += float64(r.screenWidth) / 2
	y += float64(r.screenHeight) / 2

	path := vector.Path{}
	for i := 0; i < 6; i++ {
		angle := math.Pi/3*float64(i) + math.Pi/6
		px := x + r.hexSize*math.Cos(angle)
		py := y + r.hexSize*math.Sin(angle)
		if i == 0 {
			path.MoveTo(float32(px), float32(py))
		} else {
			path.LineTo(float32(px), float32(py))
		}
	}
	path.Close()

	tile := r.hexMap.Tiles[hex]
	var fillColor color.RGBA
	if hex == r.hexMap.Entry {
		fillColor = config.EntryColor
	} else if hex == r.hexMap.Exit {
		fillColor = config.ExitColor
	} else if tile.Passable {
		fillColor = config.PassableColor
	} else {
		fillColor = config.ImpassableColor
	}

	r.fillVs, r.fillIs = path.AppendVerticesAndIndicesForFilling(r.fillVs[:0], r.fillIs[:0])
	for i := range r.fillVs {
		r.fillVs[i].ColorR = float32(fillColor.R) / 255
		r.fillVs[i].ColorG = float32(fillColor.G) / 255
		r.fillVs[i].ColorB = float32(fillColor.B) / 255
		r.fillVs[i].ColorA = float32(fillColor.A) / 255
	}
	target.DrawTriangles(r.fillVs, r.fillIs, r.fillImg, &ebiten.DrawTrianglesOptions{
		AntiAlias: true,
	})

	label := fmt.Sprintf("%d,%d", hex.Q, hex.R)
	var textColor color.RGBA
	if (fillColor.R+fillColor.G+fillColor.B)/3 > 128 {
		textColor = config.TextDarkColor
	} else {
		textColor = config.TextLightColor
	}
	textWidth := text.BoundString(r.fontFace, label).Max.X - text.BoundString(r.fontFace, label).Min.X
	textHeight := text.BoundString(r.fontFace, label).Max.Y - text.BoundString(r.fontFace, label).Min.Y
	text.Draw(target, label, r.fontFace, int(x)-textWidth/2, int(y)+textHeight/2, textColor)
}

func (r *HexRenderer) drawHexOutline(target *ebiten.Image, hex hexmap.Hex, towerHexSet map[hexmap.Hex]struct{}) {
	x, y := hex.ToPixel(r.hexSize)
	x += float64(r.screenWidth) / 2
	y += float64(r.screenHeight) / 2

	path := vector.Path{}
	for i := 0; i < 6; i++ {
		angle := math.Pi/3*float64(i) + math.Pi/6
		px := x + r.hexSize*math.Cos(angle)
		py := y + r.hexSize*math.Sin(angle)
		if i == 0 {
			path.MoveTo(float32(px), float32(py))
		} else {
			path.LineTo(float32(px), float32(py))
		}
	}
	path.Close()

	tile := r.hexMap.Tiles[hex]
	var fillColor color.RGBA
	if tile.Passable {
		fillColor = config.PassableColor
	} else {
		fillColor = config.ImpassableColor
	}

	r.strokeVs, r.strokeIs = path.AppendVerticesAndIndicesForStroke(r.strokeVs[:0], r.strokeIs[:0], &vector.StrokeOptions{
		Width: float32(config.StrokeWidth),
	})

	var strokeColor color.RGBA
	if towerHexSet != nil {
		if _, hasTower := towerHexSet[hex]; hasTower {
			strokeColor = color.RGBA{R: 255, G: 100, B: 100, A: 255} // Красноватый для башен
		} else {
			strokeColor = color.RGBA{
				R: uint8(min(255, int(fillColor.R)+40)),
				G: uint8(min(255, int(fillColor.G)+40)),
				B: uint8(min(255, int(fillColor.B)+40)),
				A: 255,
			}
		}
	} else {
		strokeColor = color.RGBA{
			R: uint8(min(255, int(fillColor.R)+40)),
			G: uint8(min(255, int(fillColor.G)+40)),
			B: uint8(min(255, int(fillColor.B)+40)),
			A: 255,
		}
	}

	for i := range r.strokeVs {
		r.strokeVs[i].ColorR = float32(strokeColor.R) / 255
		r.strokeVs[i].ColorG = float32(strokeColor.G) / 255
		r.strokeVs[i].ColorB = float32(strokeColor.B) / 255
		r.strokeVs[i].ColorA = float32(strokeColor.A) / 255
	}
	target.DrawTriangles(r.strokeVs, r.strokeIs, r.strokeImg, &ebiten.DrawTrianglesOptions{
		AntiAlias: true,
	})
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// pkg/render/hex_renderer.go
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
	hexMap             *hexmap.HexMap
	hexSize            float64
	screenWidth        int
	screenHeight       int
	fillImg            *ebiten.Image
	strokeImg          *ebiten.Image
	sortedHexes        []hexmap.Hex
	fillVs             []ebiten.Vertex
	fillIs             []uint16
	strokeVs           []ebiten.Vertex
	strokeIs           []uint16
	fontFace           font.Face // Шрифт для координат (10 пунктов)
	checkpointFontFace font.Face // Шрифт для номеров чекпоинтов (12 пунктов)
	percentFontFace    font.Face // Шрифт для процентов (8 пунктов)
	mapImage           *ebiten.Image
	checkpointMap      map[hexmap.Hex]int
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

	const checkpointFontSize = 12
	checkpointFace, err := opentype.NewFace(tt, &opentype.FaceOptions{
		Size:    checkpointFontSize,
		DPI:     72,
		Hinting: font.HintingFull,
	})
	if err != nil {
		log.Fatal(err)
	}

	const percentFontSize = 11
	percentFace, err := opentype.NewFace(tt, &opentype.FaceOptions{
		Size:    percentFontSize,
		DPI:     72,
		Hinting: font.HintingFull,
	})
	if err != nil {
		log.Fatal(err)
	}

	renderer := &HexRenderer{
		hexMap:             hexMap,
		hexSize:            hexSize,
		screenWidth:        screenWidth,
		screenHeight:       screenHeight,
		fillImg:            fillImg,
		strokeImg:          strokeImg,
		sortedHexes:        hexes,
		fillVs:             make([]ebiten.Vertex, 0, 18),
		fillIs:             make([]uint16, 0, 18),
		strokeVs:           make([]ebiten.Vertex, 0, 36),
		strokeIs:           make([]uint16, 0, 36),
		fontFace:           face,
		checkpointFontFace: checkpointFace,
		percentFontFace:    percentFace,
		mapImage:           ebiten.NewImage(screenWidth, screenHeight),
		checkpointMap:      make(map[hexmap.Hex]int),
	}

	for i, cp := range hexMap.Checkpoints {
		renderer.checkpointMap[cp] = i + 1
	}

	renderer.RenderMapImage()

	return renderer
}

func (r *HexRenderer) RenderMapImage() {
	r.mapImage.Clear()

	for _, hex := range r.sortedHexes {
		r.drawHexFill(r.mapImage, hex)
	}

	for _, hex := range r.sortedHexes {
		r.drawHexOutline(r.mapImage, hex, nil)
	}
}

func (r *HexRenderer) Draw(screen *ebiten.Image, towerHexes []hexmap.Hex, renderSystem *system.RenderSystem, gameTime float64) {
	screen.DrawImage(r.mapImage, nil)

	towerHexSet := make(map[hexmap.Hex]struct{})
	for _, hex := range towerHexes {
		towerHexSet[hex] = struct{}{}
	}

	for _, hex := range towerHexes {
		r.drawHexOutline(screen, hex, towerHexSet)
	}

	renderSystem.Draw(screen, gameTime)
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
	var coordsTextColor color.RGBA
	var checkpointNumTextColor = color.RGBA{255, 255, 0, 255}

	isCurrentHexCheckpoint := false
	if _, isCheckpoint := r.checkpointMap[hex]; isCheckpoint {
		isCurrentHexCheckpoint = true
	}

	if hex == r.hexMap.Entry {
		fillColor = config.EntryColor
		coordsTextColor = config.TextDarkColor
	} else if hex == r.hexMap.Exit {
		fillColor = config.ExitColor
		coordsTextColor = config.TextDarkColor
	} else if isCurrentHexCheckpoint {
		fillColor = color.RGBA{
			R: config.PassableColor.R / 2,
			G: config.PassableColor.G / 2,
			B: config.PassableColor.B / 2,
			A: config.PassableColor.A,
		}
		coordsTextColor = color.RGBA{
			R: config.TextLightColor.R / 2,
			G: config.TextLightColor.G / 2,
			B: config.TextLightColor.B / 2,
			A: config.TextLightColor.A,
		}
	} else if tile.Passable {
		fillColor = config.PassableColor
		if (fillColor.R+fillColor.G+fillColor.B)/3 > 128 {
			coordsTextColor = config.TextDarkColor
		} else {
			coordsTextColor = config.TextLightColor
		}
	} else {
		fillColor = config.ImpassableColor
		if (fillColor.R+fillColor.G+fillColor.B)/3 > 128 {
			coordsTextColor = config.TextDarkColor
		} else {
			coordsTextColor = config.TextLightColor
		}
	}

	// Отрисовка основного гекса
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

	// Подсветка для гекса с рудой
	if _, exists := r.hexMap.EnergyVeins[hex]; exists {
		highlightColor := color.RGBA{
			R: uint8(min(255, int(fillColor.R)+60)),
			G: uint8(min(255, int(fillColor.G)+60)),
			B: uint8(min(255, int(fillColor.B)+60)),
			A: 100, // Полупрозрачная подсветка
		}
		for i := range r.fillVs {
			r.fillVs[i].ColorR = float32(highlightColor.R) / 255
			r.fillVs[i].ColorG = float32(highlightColor.G) / 255
			r.fillVs[i].ColorB = float32(highlightColor.B) / 255
			r.fillVs[i].ColorA = float32(highlightColor.A) / 255
		}
		target.DrawTriangles(r.fillVs, r.fillIs, r.fillImg, &ebiten.DrawTrianglesOptions{
			AntiAlias: true,
		})
	}

	// Отрисовка текста координат
	label := fmt.Sprintf("%d,%d", hex.Q, hex.R)
	textWidth := text.BoundString(r.fontFace, label).Max.X - text.BoundString(r.fontFace, label).Min.X
	textHeight := text.BoundString(r.fontFace, label).Max.Y - text.BoundString(r.fontFace, label).Min.Y
	text.Draw(target, label, r.fontFace, int(x)-textWidth/2, int(y)+textHeight/2, coordsTextColor)

	// Отрисовка номера чекпоинта
	if num, isCheckpoint := r.checkpointMap[hex]; isCheckpoint {
		checkpointText := fmt.Sprintf("%d", num)
		checkpointTextWidth := text.BoundString(r.checkpointFontFace, checkpointText).Max.X - text.BoundString(r.checkpointFontFace, checkpointText).Min.X
		checkpointTextHeight := text.BoundString(r.checkpointFontFace, checkpointText).Max.Y - text.BoundString(r.checkpointFontFace, checkpointText).Min.Y
		text.Draw(target, checkpointText, r.checkpointFontFace, int(x)-checkpointTextWidth/2, int(y)+checkpointTextHeight/2, checkpointNumTextColor)
	}

	// Отрисовка процентов
	if power, exists := r.hexMap.EnergyVeins[hex]; exists {
		percentText := fmt.Sprintf("%.0f%%", power*100)
		percentTextWidth := text.BoundString(r.percentFontFace, percentText).Max.X - text.BoundString(r.percentFontFace, percentText).Min.X
		percentTextHeight := text.BoundString(r.percentFontFace, percentText).Max.Y - text.BoundString(r.percentFontFace, percentText).Min.Y
		text.Draw(target, percentText, r.percentFontFace, int(x)-percentTextWidth/2, int(y)+percentTextHeight/2+5, color.RGBA{50, 50, 50, 255}) // Тёмный текст, сдвинут выше
	}
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
			strokeColor = color.RGBA{R: 255, G: 100, B: 100, A: 255}
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

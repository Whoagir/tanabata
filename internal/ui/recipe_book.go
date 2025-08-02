// internal/ui/recipe_book.go
package ui

import (
	"go-tower-defense/internal/defs"
	"image/color"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/text"
	"github.com/hajimehoshi/ebiten/v2/vector"
	"golang.org/x/image/font"
)

// RecipeBook отображает окно с рецептами крафта.
type RecipeBook struct {
	IsVisible bool
	X, Y      float32
	Width     float32
	Height    float32
	fontFace  font.Face
	recipes   []defs.Recipe
}

// NewRecipeBook создает новую книгу рецептов.
func NewRecipeBook(x, y, width, height float32, fontFace font.Face, recipes []defs.Recipe) *RecipeBook {
	return &RecipeBook{
		IsVisible: false,
		X:         x,
		Y:         y,
		Width:     width,
		Height:    height,
		fontFace:  fontFace,
		recipes:   recipes,
	}
}

// Toggle переключает видимость книги рецептов.
func (rb *RecipeBook) Toggle() {
	rb.IsVisible = !rb.IsVisible
}

// Draw отрисовывает книгу рецептов, если она видима.
func (rb *RecipeBook) Draw(screen *ebiten.Image, availableTowers map[string]int) {
	if !rb.IsVisible {
		return
	}

	// --- Цвета ---
	whiteColor := color.RGBA{255, 255, 255, 255}
	grayColor := color.RGBA{100, 100, 100, 255}
	
	// --- Фон и рамка ---
	bgColor := color.RGBA{R: 20, G: 20, B: 30, A: 230}
	vector.DrawFilledRect(screen, rb.X, rb.Y, rb.Width, rb.Height, bgColor, false)
	borderColor := color.RGBA{R: 70, G: 100, B: 120, A: 255}
	vector.StrokeRect(screen, rb.X, rb.Y, rb.Width, rb.Height, 2, borderColor, false)

	// --- Заголовок ---
	title := "Книга Рецептов"
	titleBounds := text.BoundString(rb.fontFace, title)
	titleX := rb.X + (rb.Width-float32(titleBounds.Dx()))/2
	titleY := rb.Y + 30
	text.Draw(screen, title, rb.fontFace, int(titleX), int(titleY), whiteColor)

	// --- Отрисовка рецептов ---
	lineHeight := float32(rb.fontFace.Metrics().Height.Ceil())
	startY := titleY + lineHeight*2
	
	spaceWidth := text.BoundString(rb.fontFace, " ").Dx()

	for i, recipe := range rb.recipes {
		// --- Этап 1: Подготовка данных ---
		requiredTowers := make(map[string]int)
		for _, input := range recipe.Inputs {
			requiredTowers[input.ID]++
		}

		isCraftable := true
		tempAvailable := make(map[string]int)
		for k, v := range availableTowers {
			tempAvailable[k] = v
		}

		for towerID, count := range requiredTowers {
			if tempAvailable[towerID] < count {
				isCraftable = false
				break
			}
			tempAvailable[towerID] -= count
		}
		
		_, isOutputPresent := availableTowers[recipe.OutputID]

		// --- Этап 2 и 3: Покомпонентная отрисовка ---
		currentX := rb.X + 20
		currentY := startY + float32(i)*lineHeight*1.5

		// Отрисовка ингредиентов
		for j, input := range recipe.Inputs {
			ingredientColor := grayColor
			if availableTowers[input.ID] > 0 {
				ingredientColor = whiteColor
			}
			text.Draw(screen, input.ID, rb.fontFace, int(currentX), int(currentY), ingredientColor)
			currentX += float32(text.BoundString(rb.fontFace, input.ID).Dx() + spaceWidth)

			if j < len(recipe.Inputs)-1 {
				plusColor := grayColor
				if isCraftable {
					plusColor = whiteColor
				}
				text.Draw(screen, "+", rb.fontFace, int(currentX), int(currentY), plusColor)
				currentX += float32(text.BoundString(rb.fontFace, "+").Dx() + spaceWidth)
			}
		}

		// Отрисовка знака равенства
		equalColor := grayColor
		if isCraftable {
			equalColor = whiteColor
		}
		text.Draw(screen, "=", rb.fontFace, int(currentX), int(currentY), equalColor)
		currentX += float32(text.BoundString(rb.fontFace, "=").Dx() + spaceWidth)

		// Отрисовка результата
		outputColor := grayColor
		if isOutputPresent {
			outputColor = whiteColor
		}
		text.Draw(screen, recipe.OutputID, rb.fontFace, int(currentX), int(currentY), outputColor)
	}
}

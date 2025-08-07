// internal/ui/recipe_book.go
package ui

import (
	"fmt"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"strings"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// RecipeBookRL - версия книги рецептов для Raylib
type RecipeBookRL struct {
	IsVisible     bool
	X, Y          float32
	Width, Height float32
	recipes       []*defs.Recipe
	font          rl.Font
	scrollOffset  float32
}

// NewRecipeBookRL создает новую книгу рецептов
func NewRecipeBookRL(x, y, width, height float32, recipes []*defs.Recipe, font rl.Font) *RecipeBookRL {
	return &RecipeBookRL{
		IsVisible: false,
		X:         x,
		Y:         y,
		Width:     width,
		Height:    height,
		recipes:   recipes,
		font:      font,
	}
}

// Toggle переключает видимость книги
func (rb *RecipeBookRL) Toggle() {
	rb.IsVisible = !rb.IsVisible
}

// Update обрабатывает ввод для прокрутки
func (rb *RecipeBookRL) Update() {
	if !rb.IsVisible {
		return
	}
	// Прокрутка колесиком мыши
	wheel := rl.GetMouseWheelMove()
	rb.scrollOffset += wheel * 20 // Умножитель для скорости прокрутки

	// Ограничение прокрутки
	maxScroll := float32(len(rb.recipes))*config.RecipeEntryHeightRL - rb.Height + config.RecipePaddingRL*2
	if maxScroll < 0 {
		maxScroll = 0
	}
	if rb.scrollOffset > 0 {
		rb.scrollOffset = 0
	}
	if rb.scrollOffset < -maxScroll {
		rb.scrollOffset = -maxScroll
	}
}

// Draw отрисовывает книгу рецептов
func (rb *RecipeBookRL) Draw(availableTowers map[string]int) {
	if !rb.IsVisible {
		return
	}

	// Фон
	rl.DrawRectangle(int32(rb.X), int32(rb.Y), int32(rb.Width), int32(rb.Height), config.RecipeBookBackgroundColorRL)
	// Обводка
	rl.DrawRectangleLines(int32(rb.X), int32(rb.Y), int32(rb.Width), int32(rb.Height), config.RecipeBookBorderColorRL)

	// Заголовок
	title := "Recipes"
	titleWidth := rl.MeasureTextEx(rb.font, title, config.RecipeTitleFontSizeRL, 1.0).X
	rl.DrawTextEx(rb.font, title, rl.NewVector2(rb.X+(rb.Width-titleWidth)/2, rb.Y+config.RecipePaddingRL), config.RecipeTitleFontSizeRL, 1.0, config.RecipeTitleColorRL)

	// Устанавливаем область отсечения, чтобы рецепты не выходили за пределы панели
	rl.BeginScissorMode(int32(rb.X), int32(rb.Y+config.RecipeHeaderHeightRL), int32(rb.Width), int32(rb.Height-config.RecipeHeaderHeightRL))
	defer rl.EndScissorMode()

	currentY := rb.Y + config.RecipeHeaderHeightRL + rb.scrollOffset

	for _, recipe := range rb.recipes {
		var inputs []string
		canCraft := true
		for _, input := range recipe.Inputs {
			towerDef, ok := defs.TowerDefs[input.ID]
			if !ok {
				continue
			}
			count, has := availableTowers[input.ID]
			if !has || count < 1 {
				canCraft = false
			}
			inputs = append(inputs, towerDef.Name)
		}

		outputDef, ok := defs.TowerDefs[recipe.OutputID]
		if !ok {
			continue
		}

		inputText := strings.Join(inputs, " + ")
		fullText := fmt.Sprintf("%s -> %s", inputText, outputDef.Name)

		textColor := config.RecipeDefaultColorRL
		if canCraft {
			textColor = config.RecipeCanCraftColorRL
		}

		rl.DrawTextEx(rb.font, fullText, rl.NewVector2(rb.X+config.RecipePaddingRL, currentY), config.RecipeEntryFontSizeRL, 1.0, textColor)
		currentY += config.RecipeEntryHeightRL
	}
}
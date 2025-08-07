// internal/state/menu_state.go
package state

import (
	"go-tower-defense/internal/defs"

	rl "github.com/gen2brain/raylib-go/raylib"
)

type MenuState struct {
	stateMachine  *StateMachine
	recipeLibrary *defs.CraftingRecipeLibrary
}

func NewMenuState(sm *StateMachine, recipes *defs.CraftingRecipeLibrary) *MenuState {
	return &MenuState{
		stateMachine:  sm,
		recipeLibrary: recipes,
	}
}

func (s *MenuState) Enter() {}

func (s *MenuState) Update(deltaTime float64) {
	if rl.IsKeyPressed(rl.KeyEnter) {
		s.stateMachine.SetState(NewGameState(s.stateMachine, s.recipeLibrary, nil))
	}
}

func (s *MenuState) Draw() {
	rl.ClearBackground(rl.Black)
	title := "Go Tower Defense"
	titleFontSize := 40
	titleWidth := rl.MeasureText(title, int32(titleFontSize))
	rl.DrawText(title, (int32(rl.GetScreenWidth())-titleWidth)/2, int32(rl.GetScreenHeight()/2-80), int32(titleFontSize), rl.White)

	instructions := "Press ENTER to Start"
	instrFontSize := 20
	instrWidth := rl.MeasureText(instructions, int32(instrFontSize))
	rl.DrawText(instructions, (int32(rl.GetScreenWidth())-instrWidth)/2, int32(rl.GetScreenHeight()/2), int32(instrFontSize), rl.Gray)
}

func (s *MenuState) Exit() {}
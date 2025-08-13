// internal/state/menu_state.go
package state

import (
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/ui"
	"os"

	rl "github.com/gen2brain/raylib-go/raylib"
)

type MenuState struct {
	sm          *StateMachine
	font        rl.Font
	startButton *ui.Button
	exitButton  *ui.Button
}

func NewMenuState(sm *StateMachine, font rl.Font) *MenuState {
	btnWidth := float32(220)
	btnHeight := float32(50)
	spacing := float32(20)
	startX := (float32(rl.GetScreenWidth()) - btnWidth) / 2
	startY := float32(rl.GetScreenHeight()/2) - btnHeight

	startButton := ui.NewButton(
		rl.NewRectangle(startX, startY, btnWidth, btnHeight),
		"Начать игру",
		font,
	)

	exitButton := ui.NewButton(
		rl.NewRectangle(startX, startY+btnHeight+spacing, btnWidth, btnHeight),
		"Выход",
		font,
	)

	return &MenuState{
		sm:          sm,
		font:        font,
		startButton: startButton,
		exitButton:  exitButton,
	}
}

func (s *MenuState) Enter() {}

func (s *MenuState) Update(deltaTime float64) {
	mousePos := rl.GetMousePosition()

	if s.startButton.IsClicked(mousePos) {
		camera := rl.NewCamera3D(
			rl.NewVector3(0.0, 80.0, 100.0),
			rl.NewVector3(0.0, 0.0, 0.0),
			rl.NewVector3(0.0, 1.0, 0.0),
			45.0,
			rl.CameraPerspective,
		)

		towerDefPtrs := make(map[string]*defs.TowerDefinition)
		for id, def := range defs.TowerDefs {
			d := def
			towerDefPtrs[id] = &d
		}

		newState := NewGameState(s.sm, defs.RecipeLibrary, towerDefPtrs, &camera)
		newState.SetCamera(&camera)
		s.sm.SetState(newState)
	}

	if s.exitButton.IsClicked(mousePos) {
		os.Exit(0)
	}
}

func (s *MenuState) Draw() {
	rl.ClearBackground(rl.Black)
	title := "Go Tower Defense"
	titleFontSize := int32(60)
	titleWidth := rl.MeasureTextEx(s.font, title, float32(titleFontSize), 1).X
	rl.DrawTextEx(s.font, title, rl.NewVector2((float32(rl.GetScreenWidth())-titleWidth)/2, float32(rl.GetScreenHeight()/2-150)), float32(titleFontSize), 1, rl.White)

	mousePos := rl.GetMousePosition()
	s.startButton.Draw(mousePos)
	s.exitButton.Draw(mousePos)
}

func (s *MenuState) Exit() {}

func (s *MenuState) GetGame() GameInterface            { return nil }
func (s *MenuState) GetFont() rl.Font                  { return s.font }
func (s *MenuState) Cleanup()                          {}
func (s *MenuState) SetCamera(camera *rl.Camera3D)     {}
// internal/state/pause_state.go
package state

import (
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/ui"

	rl "github.com/gen2brain/raylib-go/raylib"
)

var _ State = (*PauseState)(nil)

type PauseState struct {
	stateMachine  *StateMachine
	previousState State
	font          rl.Font
	pauseButton   *ui.PauseButtonRL // Ссылка на основную кнопку паузы

	// Кнопки меню
	continueButton *ui.MenuButton
	restartButton  *ui.MenuButton
	mainMenuButton *ui.MenuButton
}

func NewPauseState(sm *StateMachine, prevState State, font rl.Font, pauseButton *ui.PauseButtonRL) *PauseState {
	s := &PauseState{
		stateMachine:  sm,
		previousState: prevState,
		font:          font,
		pauseButton:   pauseButton,
	}

	// Инициализация кнопок меню
	btnWidth := float32(250)
	btnHeight := float32(50)
	spacing := float32(20)
	startX := (float32(config.ScreenWidth) - btnWidth) / 2
	startY := (float32(config.ScreenHeight) - (btnHeight*3 + spacing*2)) / 2

	s.continueButton = ui.NewMenuButton(
		rl.NewRectangle(startX, startY, btnWidth, btnHeight),
		"Продолжить",
		font,
	)
	s.restartButton = ui.NewMenuButton(
		rl.NewRectangle(startX, startY+btnHeight+spacing, btnWidth, btnHeight),
		"Начать заново",
		font,
	)
	s.mainMenuButton = ui.NewMenuButton(
		rl.NewRectangle(startX, startY+(btnHeight+spacing)*2, btnWidth, btnHeight),
		"Главное меню",
		font,
	)

	return s
}

func (s *PauseState) Enter() {}

func (s *PauseState) Update(deltaTime float64) {
	// Разблокируем игру по нажатию клавиш или кнопок
	unpauseKeyPressed := rl.IsKeyPressed(rl.KeyP) || rl.IsKeyPressed(rl.KeyEscape) || rl.IsKeyPressed(rl.KeyF9)
	unpauseClicked := s.continueButton.IsClicked(rl.GetMousePosition()) && rl.IsMouseButtonPressed(rl.MouseLeftButton)
	pauseButtonCliced := s.pauseButton.IsClicked(rl.GetMousePosition()) && rl.IsMouseButtonPressed(rl.MouseLeftButton)

	if unpauseKeyPressed || unpauseClicked || pauseButtonCliced {
		s.stateMachine.SetState(s.previousState)
		return
	}

	// Обработка клика по кнопке "Начать заново"
	if s.restartButton.IsClicked(rl.GetMousePosition()) && rl.IsMouseButtonPressed(rl.MouseLeftButton) {
		if gs, ok := s.previousState.(*GameState); ok {
			// Создаем карту указателей для передачи в системы
			towerDefPtrs := make(map[string]*defs.TowerDefinition)
			for id, def := range defs.TowerDefs {
				d := def
				towerDefPtrs[id] = &d
			}
			// Пересоздаем состояние игры
			newState := NewGameState(s.stateMachine, defs.RecipeLibrary, towerDefPtrs, gs.camera)
			newState.SetCamera(gs.camera)
			s.stateMachine.SetState(newState)
		}
	}

	// Обработка клика по кнопке "Главное меню"
	if s.mainMenuButton.IsClicked(rl.GetMousePosition()) && rl.IsMouseButtonPressed(rl.MouseLeftButton) {
		// Предполагается, что у вас есть состояние NewMenuState
		// Если его нет, эту строку нужно будет адаптировать
		s.stateMachine.SetState(NewMenuState(s.stateMachine, s.font))
	}
}

func (s *PauseState) Draw() {
	if s.previousState != nil {
		s.previousState.Draw()
	}
}

func (s *PauseState) DrawUI() {
	// Рисуем UI предыдущего состояния, чтобы все элементы были на месте
	if uiDrawable, ok := s.previousState.(interface{ DrawUI() }); ok {
		uiDrawable.DrawUI()
	}

	// Затемняющий фон
	rl.DrawRectangle(0, 0, int32(config.ScreenWidth), int32(config.ScreenHeight), rl.NewColor(0, 0, 0, 180))

	// Перерисовываем кнопку паузы поверх фона, но в состоянии "воспроизведение"
	s.pauseButton.Draw(true)

	// Рисуем кнопки меню
	s.continueButton.Draw()
	s.restartButton.Draw()
	s.mainMenuButton.Draw()
}

func (s *PauseState) Exit() {}

// --- Методы-заглушки для соответствия интерфейсу State ---
func (s *PauseState) GetGame() GameInterface {
	if gs, ok := s.previousState.(GameInterface); ok {
		return gs
	}
	return nil
}

func (s *PauseState) GetFont() rl.Font {
	return s.font
}

func (s *PauseState) Cleanup() {}

func (s *PauseState) SetCamera(camera *rl.Camera3D) {}
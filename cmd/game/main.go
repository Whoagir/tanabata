// cmd/game/main.go
package main

import (
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/state"
	"log"
	"math/rand"
	"net/http"
	_ "net/http/pprof"
	"time"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// Vector3Lerp выполняет линейную интерполяцию между двумя векторами
func Vector3Lerp(v1, v2 rl.Vector3, t float32) rl.Vector3 {
	return rl.Vector3Add(v1, rl.Vector3Scale(rl.Vector3Subtract(v2, v1), t))
}

const startFromGame = true // true — начинать с игры, false — с меню

func main() {
	go func() {
		log.Println(http.ListenAndServe("localhost:6060", nil))
	}()

	// --- Инициализация Raylib ---
	rl.InitWindow(config.ScreenWidth, config.ScreenHeight, "Go Tower Defense")
	rl.SetTargetFPS(60)
	rl.EnableBackfaceCulling() // Включаем отсечение задних граней
	defer rl.CloseWindow()

	// --- Загрузка определений ---
	if err := defs.LoadAll("assets/data/"); err != nil {
		log.Fatalf("Failed to load definitions: %v", err)
	}

	// --- Инициализация игры ---
	rand.Seed(time.Now().UnixNano())
	sm := state.NewStateMachine()
	if startFromGame {
		sm.SetState(state.NewGameState(sm, defs.RecipeLibrary, nil))
	} else {
		log.Println("Menu state is not implemented for Raylib yet. Starting game directly.")
		sm.SetState(state.NewGameState(sm, defs.RecipeLibrary, nil))
	}

	// --- Настройка 3D камеры (как в map_viewer) ---
	camera := rl.Camera3D{}
	camera.Up = rl.NewVector3(0, 1, 0)
	camera.Projection = rl.CameraPerspective
	// Устанавливаем Fovy из конфига для консистентности
	camera.Fovy = config.CameraFovyDefault

	// Позиции и цели для интерполяции
	isoPos := rl.NewVector3(144, 200, 144)
	topDownPos := rl.NewVector3(0, 425, 0.1)
	isoTarget := rl.NewVector3(0, 0, 0)
	topDownTarget := rl.NewVector3(0, 0, 0)
	cameraAngleT := float32(0.5)

	// Передаем камеру в GameState
	if gs, ok := sm.Current().(*state.GameState); ok {
		gs.SetCamera(&camera)
	}

	lastUpdateTime := time.Now()
	rotationSpeed := float32(0.02)

	// --- Главный цикл игры ---
	for !rl.WindowShouldClose() {
		// --- Обновление логики ---
		now := time.Now()
		deltaTime := now.Sub(lastUpdateTime).Seconds()
		if deltaTime > config.MaxDeltaTime {
			deltaTime = config.MaxDeltaTime
		}
		lastUpdateTime = now

		// --- Управление камерой и обновление состояния (только если не на паузе) ---
		if _, isPaused := sm.Current().(*state.PauseState); !isPaused {
			// --- Управление камерой (как в map_viewer) ---
			if rl.IsKeyDown(rl.KeyQ) {
				isoPos = rl.Vector3RotateByAxisAngle(isoPos, camera.Up, -rotationSpeed)
			}
			if rl.IsKeyDown(rl.KeyE) {
				isoPos = rl.Vector3RotateByAxisAngle(isoPos, camera.Up, rotationSpeed)
			}

			wheel := rl.GetMouseWheelMove()
			if wheel != 0 {
				cameraAngleT += wheel * 0.05
				if cameraAngleT > 0.99 {
					cameraAngleT = 0.99
				} else if cameraAngleT < 0.0 {
					cameraAngleT = 0.0
				}
			}

			camera.Position = Vector3Lerp(isoPos, topDownPos, cameraAngleT)
			camera.Target = Vector3Lerp(isoTarget, topDownTarget, cameraAngleT)
			// УБРАНО: camera.Fovy = isoFovy + (topDownFovy-isoFovy)*cameraAngleT
			// Эта строка конфликтовала с логикой зума в GameState.
			// Теперь Fovy управляется только в GameState.
		}

		// Обновляем состояние всегда, чтобы PauseState мог обработать выход из паузы
		sm.Update(deltaTime)

		// --- Отрисовка ---
		rl.BeginDrawing()
		rl.ClearBackground(config.BackgroundColorRL)

		// 3D Сцена
		rl.BeginMode3D(camera)
		sm.Draw()
		rl.EndMode3D()

		// 2D UI (поверх 3D)
		if uiDrawable, ok := sm.Current().(interface{ DrawUI() }); ok {
			uiDrawable.DrawUI()
		}
		rl.DrawFPS(10, 10)

		rl.EndDrawing()
	}

	// --- Очистка перед выходом ---
	if cleanable, ok := sm.Current().(interface{ Cleanup() }); ok {
		cleanable.Cleanup()
	}
}

// cmd/game/main.go
package main

import (
	"flag"
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

func main() {
	// --- Флаг для режима разработки ---
	devMode := flag.Bool("dev", false, "Start directly in the game state for development")
	flag.Parse()

	go func() {
		log.Println(http.ListenAndServe("localhost:6060", nil))
	}()

	// --- Инициализация Raylib ---
	rl.InitWindow(config.ScreenWidth, config.ScreenHeight, "Go Tower Defense")
	rl.SetTargetFPS(60)
	rl.EnableBackfaceCulling()
	defer rl.CloseWindow()

	// --- Загрузка определений ---
	if err := defs.LoadAll("assets/data/"); err != nil {
		log.Fatalf("Failed to load definitions: %v", err)
	}

	// --- Загрузка шрифта для меню ---
	var fontChars []rune
	for i := 32; i <= 127; i++ {
		fontChars = append(fontChars, rune(i))
	}
	for i := 0x0400; i <= 0x04FF; i++ {
		fontChars = append(fontChars, rune(i))
	}
	fontChars = append(fontChars, '₽', '«', '»', '(', ')', '.', ',')
	font := rl.LoadFontEx("assets/fonts/arial.ttf", 64, fontChars, int32(len(fontChars)))
	defer rl.UnloadFont(font) // Очищаем шрифт при выходе

	// --- Инициализация игры ---
	rand.Seed(time.Now().UnixNano())
	sm := state.NewStateMachine()

	// --- Настройка 3D камеры ---
	camera := rl.Camera3D{}
	camera.Up = rl.NewVector3(0, 1, 0)
	camera.Projection = rl.CameraPerspective
	camera.Fovy = config.CameraFovyDefault

	// --- Выбор начального состояния ---
	if *devMode {
		log.Println("--- DEV MODE: Starting game directly ---")
		towerDefPtrs := make(map[string]*defs.TowerDefinition)
		for id, def := range defs.TowerDefs {
			d := def
			towerDefPtrs[id] = &d
		}
		gs := state.NewGameState(sm, defs.RecipeLibrary, towerDefPtrs, &camera)
		gs.SetCamera(&camera)
		sm.SetState(gs)
	} else {
		sm.SetState(state.NewMenuState(sm, font))
	}

	// Позиции и цели для интерполяции
	isoPos := rl.NewVector3(144, 200, 144)
	topDownPos := rl.NewVector3(0, 425, 0.1)
	isoTarget := rl.NewVector3(0, 0, 0)
	topDownTarget := rl.NewVector3(0, 0, 0)
	cameraAngleT := float32(0.5)

	lastUpdateTime := time.Now()
	rotationSpeed := float32(0.02)

	// --- Главный цикл игры ---
	for !rl.WindowShouldClose() {
		now := time.Now()
		deltaTime := now.Sub(lastUpdateTime).Seconds()
		if deltaTime > config.MaxDeltaTime {
			deltaTime = config.MaxDeltaTime
		}
		lastUpdateTime = now

		// --- Управление камерой (только если мы в игровом состоянии) ---
		if _, isGame := sm.Current().(*state.GameState); isGame {
			if _, isPaused := sm.Current().(*state.PauseState); !isPaused {
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
			}
		}

		sm.Update(deltaTime)

		// --- Отрисовка ---
		rl.BeginDrawing()
		rl.ClearBackground(config.BackgroundColorRL)

		// --- Отрисовка ---
		if gs, isGame := sm.Current().(*state.GameState); isGame {
			// 3D-режим только для основного игрового состояния
			gs.SetCamera(&camera) // <--- ВОТ ИСПРАВЛЕНИЕ
			rl.BeginMode3D(camera)
			sm.Draw()
			rl.EndMode3D()
		} else {
			// Для 2D-состояний, как меню, рисуем напрямую
			sm.Draw()
		}

		// 2D UI (поверх всего)
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
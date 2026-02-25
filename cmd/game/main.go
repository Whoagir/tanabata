// cmd/game/main.go
package main

import (
	"flag"
	"fmt"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/state"
	"log"
	"math/rand"
	"net/http"
	_ "net/http/pprof"
	"os"
	"path/filepath"
	"time"
	"unsafe"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// Vector3Lerp выполняет линейную интерполяцию между двумя векторами
func Vector3Lerp(v1, v2 rl.Vector3, t float32) rl.Vector3 {
	return rl.Vector3Add(v1, rl.Vector3Scale(rl.Vector3Subtract(v2, v1), t))
}

// exportMeshToObj экспортирует данный меш в файл формата .obj
func exportMeshToObj(mesh rl.Mesh, filePath string) error {
	file, err := os.Create(filePath)
	if err != nil {
		return fmt.Errorf("could not create file: %w", err)
	}
	defer file.Close()

	vertexCount := int(mesh.VertexCount)

	// --- Вершины ---
	verticesHeader := struct {
		data unsafe.Pointer
		len  int
		cap  int
	}{unsafe.Pointer(mesh.Vertices), vertexCount * 3, vertexCount * 3}
	vertices := *(*[]float32)(unsafe.Pointer(&verticesHeader))

	// --- Нормали ---
	normalsHeader := struct {
		data unsafe.Pointer
		len  int
		cap  int
	}{unsafe.Pointer(mesh.Normals), vertexCount * 3, vertexCount * 3}
	normals := *(*[]float32)(unsafe.Pointer(&normalsHeader))

	// --- Текстурные координаты ---
	texCoordsHeader := struct {
		data unsafe.Pointer
		len  int
		cap  int
	}{unsafe.Pointer(mesh.Texcoords), vertexCount * 2, vertexCount * 2}
	texcoords := *(*[]float32)(unsafe.Pointer(&texCoordsHeader))

	// Запись вершин
	for i := 0; i < len(vertices); i += 3 {
		_, err := fmt.Fprintf(file, "v %f %f %f\n", vertices[i], vertices[i+1], vertices[i+2])
		if err != nil {
			return err
		}
	}

	// Запись текстурных координат
	for i := 0; i < len(texcoords); i += 2 {
		_, err := fmt.Fprintf(file, "vt %f %f\n", texcoords[i], texcoords[i+1])
		if err != nil {
			return err
		}
	}

	// Запись нормалей
	for i := 0; i < len(normals); i += 3 {
		_, err := fmt.Fprintf(file, "vn %f %f %f\n", normals[i], normals[i+1], normals[i+2])
		if err != nil {
			return err
		}
	}

	// Запись граней
	if mesh.Indices != nil {
		// Продвинутый метод: используем индексы, если они есть
		triangleCount := int(mesh.TriangleCount)
		indicesHeader := struct {
			data unsafe.Pointer
			len  int
			cap  int
		}{unsafe.Pointer(mesh.Indices), triangleCount * 3, triangleCount * 3}
		indices := *(*[]uint16)(unsafe.Pointer(&indicesHeader))

		for i := 0; i < len(indices); i += 3 {
			// OBJ формат использует 1-based индексацию, поэтому добавляем 1
			i1 := indices[i] + 1
			i2 := indices[i+1] + 1
			i3 := indices[i+2] + 1
			_, err := fmt.Fprintf(file, "f %d/%d/%d %d/%d/%d %d/%d/%d\n", i1, i1, i1, i2, i2, i2, i3, i3, i3)
			if err != nil {
				return err
			}
		}
	} else {
		// Базовый метод: для мешей без индексов (менее надежно)
		for i := 1; i <= vertexCount; i += 3 {
			_, err := fmt.Fprintf(file, "f %d/%d/%d %d/%d/%d %d/%d/%d\n", i, i, i, i+1, i+1, i+1, i+2, i+2, i+2)
			if err != nil {
				return err
			}
		}
	}

	log.Printf("Successfully exported mesh to %s", filePath)
	return nil
}

// exportAllTowerModels генерирует и сохраняет .obj файлы для всех башен.
func exportAllTowerModels() {
	log.Println("Exporting all tower models...")

	// Сначала нужно загрузить определения, чтобы знать, какие башни существуют
	if err := defs.LoadAll("assets/data/"); err != nil {
		log.Fatalf("Failed to load definitions for export: %v", err)
	}

	for id, towerDef := range defs.TowerDefs {
		var mesh rl.Mesh

		// Пропускаем типы, для которых не нужна статическая модель
		if towerDef.Type == defs.TowerTypeMiner {
			continue
		}

		// Логика генерации меша с финальными размерами
		switch {
		case towerDef.Type == defs.TowerTypeWall:
			// Стены
			mesh = rl.GenMeshCylinder(4.59, 5.7, 6)
		case towerDef.CraftingLevel >= 1:
			// Улучшенные башни
			mesh = rl.GenMeshCube(6.1, 6.1, 6.1)
		default: // Обычные атакующие башни
			// Базовые башни
			mesh = rl.GenMeshCylinder(2.45, 13.87, 9)
		}

		filePath := filepath.Join("assets", "models", fmt.Sprintf("%s.obj", id))

		if err := exportMeshToObj(mesh, filePath); err != nil {
			log.Printf("ERROR: Failed to export model for %s: %v", id, err)
		}

		rl.UnloadMesh(&mesh) // Очищаем меш после экспорта
	}

	log.Println("All tower models exported.")
}

func main() {
	// --- Флаги командной строки ---
	devMode := flag.Bool("dev", false, "Start directly in the game state for development")
	exportModels := flag.Bool("export-models", false, "Export game models to .obj files and exit")
	flag.Parse()

	// --- Инициализация Raylib ---
	rl.InitWindow(config.ScreenWidth, config.ScreenHeight, "Go Tower Defense")
	defer rl.CloseWindow()

	// --- Обработка флага экспорта ---
	if *exportModels {
		exportAllTowerModels()
		return // Завершаем программу после экспорта
	}

	go func() {
		log.Println(http.ListenAndServe("localhost:6060", nil))
	}()

	rl.SetTargetFPS(60)
	rl.EnableBackfaceCulling()

	// --- Загрузка определений ---
	if err := defs.LoadAll("assets/data/"); err != nil {
		log.Fatalf("Failed to load definitions: %v", err)
	}

	// --- Загрузка шрифта ---
	var fontChars []rune
	for i := 32; i <= 127; i++ {
		fontChars = append(fontChars, rune(i))
	}
	for i := 0x0400; i <= 0x04FF; i++ {
		fontChars = append(fontChars, rune(i))
	}
	fontChars = append(fontChars, '₽', '«', '»', '(', ')', '.', ',')
	font := rl.LoadFontEx("assets/fonts/arial.ttf", 64, fontChars, int32(len(fontChars)))
	defer rl.UnloadFont(font)

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
		log.Println("---" + "DEV MODE: Starting game directly" + "---")
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

		// --- Управление камерой ---
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

		if gs, isGame := sm.Current().(*state.GameState); isGame {
			gs.SetCamera(&camera)
			rl.BeginMode3D(camera)
			sm.Draw()
			rl.EndMode3D()
		} else {
			sm.Draw()
		}

		if uiDrawable, ok := sm.Current().(interface{ DrawUI() }); ok {
			uiDrawable.DrawUI()
		}
		rl.DrawFPS(10, 10)

		rl.EndDrawing()
	}

	if cleanable, ok := sm.Current().(interface{ Cleanup() }); ok {
		cleanable.Cleanup()
	}
}

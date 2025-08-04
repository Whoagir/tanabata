package main

import (
	"go-tower-defense/pkg/hexmap"
	"math"
	"math/rand"
	"time"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// Vector3Lerp выполняет линейную интерполяцию между двумя векторами
func Vector3Lerp(v1, v2 rl.Vector3, t float32) rl.Vector3 {
	return rl.Vector3Add(v1, rl.Vector3Scale(rl.Vector3Subtract(v2, v1), t))
}

// ColorLerp выполняет линейную интерполяцию между двумя цветами
func ColorLerp(c1, c2 rl.Color, t float32) rl.Color {
	return rl.NewColor(
		uint8(float32(c1.R)*(1-t)+float32(c2.R)*t),
		uint8(float32(c1.G)*(1-t)+float32(c2.G)*t),
		uint8(float32(c1.B)*(1-t)+float32(c2.B)*t),
		uint8(float32(c1.A)*(1-t)+float32(c2.A)*t),
	)
}

// hexFromWorldPoint преобразует мировые координаты в гексагональные
func hexFromWorldPoint(point rl.Vector3, hexSize, scale float32) hexmap.Hex {
	x := point.X / scale
	z := point.Z / scale
	q := (2.0 / 3.0 * x) / hexSize
	r := (-1.0/3.0*x + float32(math.Sqrt(3))/3.0*z) / hexSize
	return hexmap.Hex{Q: int(round(q)), R: int(round(r))}
}

func round(f float32) float32 {
	return float32(math.Floor(float64(f) + 0.5))
}

func main() {
	// --- Инициализация ---
	const screenWidth = 1280
	const screenHeight = 720
	backgroundColor := rl.NewColor(10, 10, 20, 255)

	rl.InitWindow(screenWidth, screenHeight, "Raylib Map Viewer | Q/E - Rotate, Mouse Wheel - Change Angle")
	rl.SetTargetFPS(60)

	// --- Настройка 3D камеры ---
	camera := rl.Camera3D{}
	camera.Up = rl.NewVector3(0, 1, 0)
	camera.Projection = rl.CameraPerspective

	// Позиции, цели и углы обзора для интерполяции
	isoPos := rl.NewVector3(80, 180, 180)
	topDownPos := rl.NewVector3(0, 400, 0.1)
	isoTarget := rl.NewVector3(0, 0, 0)
	topDownTarget := rl.NewVector3(0, 0, 0)
	isoFovy := float32(55.0)
	topDownFovy := float32(35.0)
	cameraAngleT := float32(0.5)

	// --- Генерация карты ---
	rand.Seed(time.Now().UnixNano())
	gameMap := hexmap.NewHexMap()
	const coordScale = 0.5
	const hexSizeRender = 10.0

	// Создаем мапу для быстрой проверки чекпоинтов
	checkpointsMap := make(map[hexmap.Hex]struct{})
	for _, cp := range gameMap.Checkpoints {
		checkpointsMap[cp] = struct{}{}
	}

	// --- Главный цикл ---
	for !rl.WindowShouldClose() {
		// --- Обновление (логика) ---

		// Вращение
		if rl.IsKeyDown(rl.KeyQ) {
			isoPos = rl.Vector3RotateByAxisAngle(isoPos, camera.Up, -0.02)
		}
		if rl.IsKeyDown(rl.KeyE) {
			isoPos = rl.Vector3RotateByAxisAngle(isoPos, camera.Up, 0.02)
		}

		// Изменение угла
		wheel := rl.GetMouseWheelMove()
		if wheel != 0 {
			cameraAngleT += wheel * 0.05
			if cameraAngleT > 0.99 {
				cameraAngleT = 0.99
			} else if cameraAngleT < 0.0 {
				cameraAngleT = 0.0
			}
		}

		// Обновляем камеру
		camera.Position = Vector3Lerp(isoPos, topDownPos, cameraAngleT)
		camera.Target = Vector3Lerp(isoTarget, topDownTarget, cameraAngleT)
		camera.Fovy = isoFovy + (topDownFovy-isoFovy)*cameraAngleT

		// --- Оптимизация: Определение видимых гексов ---
		visibleHexes := make(map[hexmap.Hex]struct{})
		for x := -50; x <= screenWidth+50; x += 100 {
			for y := -50; y <= screenHeight+50; y += 100 {
				ray := rl.GetMouseRay(rl.NewVector2(float32(x), float32(y)), camera)
				t := -ray.Position.Y / ray.Direction.Y
				if t > 0 {
					hitPoint := rl.Vector3Add(ray.Position, rl.Vector3Scale(ray.Direction, t))
					h := hexFromWorldPoint(hitPoint, hexSizeRender, coordScale)
					for _, neighbor := range h.Neighbors(gameMap) {
						visibleHexes[neighbor] = struct{}{}
					}
					visibleHexes[h] = struct{}{}
				}
			}
		}

		// --- Отрисовка ---
		rl.BeginDrawing()
		rl.ClearBackground(backgroundColor)

		rl.BeginMode3D(camera)

		// Отрисовка гексов
		for h, tile := range gameMap.Tiles {
			pixelX, pixelY := h.ToPixel(hexSizeRender)

			var baseColor rl.Color
			if h == gameMap.Entry {
				baseColor = rl.SkyBlue
			} else if h == gameMap.Exit {
				baseColor = rl.Red
			} else if _, isCheckpoint := checkpointsMap[h]; isCheckpoint {
				baseColor = rl.Gold
			} else if !tile.Passable {
				baseColor = rl.Gray
			} else {
				baseColor = rl.NewColor(100, 140, 110, 255)
			}

			x := float32(pixelX) * coordScale
			z := float32(pixelY) * coordScale
			radius := float32(hexSizeRender * 0.5)
			hexPos := rl.NewVector3(x, 0, z)

			// --- Эффект тумана ---
			distance := rl.Vector3Distance(camera.Position, hexPos)
			fogStart := float32(150.0)
			fogEnd := float32(350.0)
			fogFactor := (distance - fogStart) / (fogEnd - fogStart)
			if fogFactor < 0 {
				fogFactor = 0
			}
			if fogFactor > 1 {
				fogFactor = 1
			}
			
			finalColor := ColorLerp(baseColor, backgroundColor, fogFactor)
			finalColumnColor := ColorLerp(rl.DarkGray, backgroundColor, fogFactor)


			// Рисуем крышку всегда
			capHeight := float32(2.0)
			capBottomPos := rl.NewVector3(x, -1.0, z)
			rl.DrawCylinder(capBottomPos, radius, radius, capHeight, 6, finalColor)
			rl.DrawCylinderWires(capBottomPos, radius, radius, capHeight, 6, rl.DarkGray)

			// Рисуем колонну только если гекс видим
			if _, ok := visibleHexes[h]; ok {
				columnHeight := float32(1000.0)
				columnBottomPos := rl.NewVector3(x, -1001.0, z)
				rl.DrawCylinder(columnBottomPos, radius, radius, columnHeight, 6, finalColumnColor)
			}
		}

		rl.EndMode3D()

		// --- UI ---
		rl.DrawText("Use Q/E to rotate and Mouse Wheel to change angle", 10, 10, 20, rl.White)
		rl.DrawFPS(10, 40)

		rl.EndDrawing()
	}

	rl.CloseWindow()
}

// internal/app/ore_generation.go
package app

import (
	"fmt"
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/pkg/hexmap"
	"image/color"
	"math"
	"math/rand"
)

func findFarthestHex(candidates []hexmap.Hex, existingCenters []hexmap.Hex) hexmap.Hex {
	var bestHex hexmap.Hex
	maxTotalDist := -1.0

	for _, candidate := range candidates {
		totalDist := 0.0
		for _, center := range existingCenters {
			totalDist += float64(candidate.Distance(center))
		}

		if totalDist > maxTotalDist {
			maxTotalDist = totalDist
			bestHex = candidate
		}
	}
	return bestHex
}

type EnergyCircle struct {
	CenterX float64
	CenterY float64
	Radius  float64
	Power   float64
}

func (g *Game) generateOre() {
	// Все возможные гексы
	allHexes := make([]hexmap.Hex, 0, len(g.HexMap.Tiles))
	for hex := range g.HexMap.Tiles {
		allHexes = append(allHexes, hex)
	}

	// Центр карты
	centerHex := hexmap.Hex{Q: 0, R: 0}

	// --- Функции для проверки валидности центров жил ---
	isTooCloseToCritical := func(hex hexmap.Hex) bool {
		if hex == g.HexMap.Entry || hex == g.HexMap.Exit || g.isCheckpoint(hex) {
			return true
		}
		if g.HexMap.Entry.Distance(hex) < 2 || g.HexMap.Exit.Distance(hex) < 2 {
			return true
		}
		for _, cp := range g.HexMap.Checkpoints {
			if cp.Distance(hex) < 2 {
				return true
			}
		}
		return false
	}

	// --- Поиск трех центров для жил ---
	var centers []hexmap.Hex

	// Центр 1: В центре (дистанция < 3)
	for len(centers) < 1 {
		candidate := allHexes[rand.Intn(len(allHexes))]
		if !isTooCloseToCritical(candidate) && centerHex.Distance(candidate) < 3 {
			centers = append(centers, candidate)
		}
	}

	// Центр 2: Средний радиус (4-9), подальше от первого
	for len(centers) < 2 {
		candidate := allHexes[rand.Intn(len(allHexes))]
		distFromCenter := centerHex.Distance(candidate)
		if !isTooCloseToCritical(candidate) && distFromCenter >= 4 && distFromCenter <= 9 {
			if centers[0].Distance(candidate) > 6 { // Убедимся, что он не слишком близко к первому
				centers = append(centers, candidate)
			}
		}
	}

	// Центр 3: Далеко (дистанция >= 10), подальше от первых двух (надежн��й метод)
	var centerCandidates3 []hexmap.Hex
	for _, hex := range allHexes {
		if !isTooCloseToCritical(hex) && centerHex.Distance(hex) >= 10 {
			centerCandidates3 = append(centerCandidates3, hex)
		}
	}

	// Если кандидатов на краю не нашлось, это маловероятно, но лучше иметь запасной вариант
	if len(centerCandidates3) > 0 {
		center3 := findFarthestHex(centerCandidates3, centers)
		centers = append(centers, center3)
	} else {
		// В крайнем случае, если на расстоянии 10+ ничего нет, ищем на 8+
		for _, hex := range allHexes {
			if !isTooCloseToCritical(hex) && centerHex.Distance(hex) >= 8 {
				centerCandidates3 = append(centerCandidates3, hex)
			}
		}
		if len(centerCandidates3) > 0 {
			center3 := findFarthestHex(centerCandidates3, centers)
			centers = append(centers, center3)
		}
	}

	// --- Генерация жил ---
	// Убедимся, что у нас есть 3 центра перед тем, как продолжить
	if len(centers) < 3 {
		// Если по какой-то причине третий центр не был найден, дублируем второй,
		// чтобы избежать пани��и, но смещаем его.
		if len(centers) == 2 {
			shiftedCenter := centers[1].Add(hexmap.Hex{Q: 1, R: 1})
			centers = append(centers, shiftedCenter)
		} else {
			// Этого никогда не должно произойти, но на всякий случай
			return
		}
	}

	veinAreas := make([][]hexmap.Hex, 3)
	for i, center := range centers {
		if i == 0 {
			// Новая детерминированная логика для центральной жилы
			centralVein := []hexmap.Hex{center}
			neighbors := g.HexMap.GetNeighbors(center)

			// Перемешиваем соседей для случайности
			rand.Shuffle(len(neighbors), func(i, j int) {
				neighbors[i], neighbors[j] = neighbors[j], neighbors[i]
			})

			// Добавляем первых 3 валидных соседа, чтобы получить ровно 4 гекса
			for _, neighbor := range neighbors {
				if len(centralVein) >= 4 {
					break
				}
				// Дополнительно проверяем, что сосед не является критической точкой
				if !isTooCloseToCritical(neighbor) {
					centralVein = append(centralVein, neighbor)
				}
			}
			veinAreas[i] = centralVein
		} else {
			// Старая, рабочая логика для остальных жил
			veinAreas[i] = g.HexMap.GetHexesInRange(center, 2)
		}
	}

	energyVeins := make(map[hexmap.Hex]float64)

	// --- Динамическая генерация мощности жил ---
	// 1. Генерируем общую мощность для карты
	totalMapPower := 240.0 + rand.Float64()*30 // от 240 до 270

	// 2. Определяем доли для жил со случайным разбросом
	// Центральная жила (самая слабая)
	centralShare := (0.18 + rand.Float64()*0.04) * (2.5 / 1.5) // 18% - 22%, УМНОЖЕНО НА 2.5 и разделено на 1.5
	// Средняя жила
	midShare := 0.27 + rand.Float64()*0.06 // 27% - 33%
	// Дальняя жила (самая сильная) получает остаток, чтобы сумма была 100%
	farShare := 1.0 - centralShare - midShare

	// 3. Распределяем общую мощность по долям
	totalPowers := []float64{
		totalMapPower * centralShare, // Центральная
		totalMapPower * midShare,     // Средняя
		totalMapPower * farShare,     // Дальняя
	}

	// Распределение энергии по жилам
	for i, area := range veinAreas {
		if len(area) == 0 {
			continue
		}

		totalVeinPower := totalPowers[i]

		if i == 0 { // Специальная, детерминированная логика для центральной жилы
			// Расп��еделяем общую мощность жилы (totalVeinPower) между 4 гексами
			remainingPower := totalVeinPower
			for j := 0; j < len(area)-1; j++ {
				hex := area[j]
				// Берем случайную долю от оставшейся мощности, но с ограничением,
				// чтобы не забрать всё сразу и оставить что-то остальным.
				avgPower := remainingPower / float64(len(area)-j)
				fluctuation := avgPower * 0.4 // Колебание в пределах 40%
				power := avgPower + (rand.Float64()*2-1)*fluctuation
				
				if power > remainingPower {
					power = remainingPower
				}
				if power < 0 {
					power = 0
				}

				energyVeins[hex] = power / 100.0 // Конвертируем из процентов
				remainingPower -= power
			}
			// Последний гекс забирает всё оставшееся
			if len(area) > 0 {
				energyVeins[area[len(area)-1]] = remainingPower / 100.0
			}

		} else { // Старая, случайная логика для остальных жил
			circles := generateEnergyCircles(area, totalVeinPower, config.HexSize)
			// Привязка энергии к гексам ч��рез круги
			for _, circle := range circles {
				hexesInCircle := g.getHexesInCircle(circle.CenterX, circle.CenterY, circle.Radius)
				for _, hex := range hexesInCircle {
					if g.isCheckpoint(hex) {
						continue
					}
					if _, exists := energyVeins[hex]; !exists {
						energyVeins[hex] = 0
					}
					energyVeins[hex] += circle.Power
				}
			}
		}
	}

	for hex, power := range energyVeins {
		id := g.ECS.NewEntity()
		px, py := hex.ToPixel(float64(config.HexSize)) // ИСПРАВЛЕНО
		g.ECS.Positions[id] = &component.Position{X: px, Y: py}
		g.ECS.Ores[id] = &component.Ore{
			Power:          power,
			MaxReserve:     power * 100, // База для расчета процентов
			CurrentReserve: power * 100,
			Position:       component.Position{X: px, Y: py},
			Radius:         float32(config.HexSize*0.2 + power*config.HexSize),
			Color:          color.RGBA{0, 0, 255, 128},
			PulseRate:      2.0,
		}
		g.ECS.Texts[id] = &component.Text{
			Value:    fmt.Sprintf("%.0f%%", power*100),
			Position: component.Position{X: px, Y: py},
			Color:    color.RGBA{R: 50, G: 50, B: 50, A: 255},
			IsUI:     true,
		}
	}
}

func generateEnergyCircles(area []hexmap.Hex, totalPower float64, hexSize float64) []EnergyCircle {
	var circles []EnergyCircle
	remainingPower := totalPower

	for remainingPower > 0 {
		hex := area[rand.Intn(len(area))]
		cx, cy := hex.ToPixel(float64(hexSize)) // ИСПРАВЛЕНО
		// Add random jitter within the hex
		cx += (rand.Float64()*2 - 1) * hexSize / 2
		cy += (rand.Float64()*2 - 1) * hexSize / 2

		// Ограничиваем энергию до 5-20% для большего количества кружков
		power := float64((rand.Intn(4) + 1) * 5) // 5, 10, 15, 20%
		if power > remainingPower {
			power = remainingPower
		}
		remainingPower -= power

		// Увеличиваем радиус в 2 раза (было 0.1, стало 0.2)
		radius := hexSize * 0.2 * (power / 5.0)

		circles = append(circles, EnergyCircle{
			CenterX: cx,
			CenterY: cy,
			Radius:  radius,
			Power:   power / 100.0,
		})
	}

	return circles
}

func (g *Game) getHexesInCircle(cx, cy, radius float64) []hexmap.Hex {
	var hexes []hexmap.Hex
	for hex := range g.HexMap.Tiles {
		hx, hy := hex.ToPixel(float64(config.HexSize)) // ИСПРАВЛЕНО
		dx := hx - cx
		dy := hy - cy
		if math.Sqrt(dx*dx+dy*dy) < radius+config.HexSize {
			hexes = append(hexes, hex)
		}
	}
	return hexes
}

func (g *Game) getBorderHexes(borderRadius int) map[hexmap.Hex]struct{} {
	border := make(map[hexmap.Hex]struct{})
	for hex := range g.HexMap.Tiles {
		if hex.Q <= -g.HexMap.Radius+borderRadius || hex.Q >= g.HexMap.Radius-borderRadius ||
			hex.R <= -g.HexMap.Radius+borderRadius || hex.R >= g.HexMap.Radius-borderRadius ||
			hex.Q+hex.R <= -g.HexMap.Radius+borderRadius || hex.Q+hex.R >= g.HexMap.Radius-borderRadius {
			border[hex] = struct{}{}
		}
	}
	return border
}

func (g *Game) isCheckpoint(hex hexmap.Hex) bool {
	for _, cp := range g.HexMap.Checkpoints {
		if cp == hex {
			return true
		}
	}
	return false
}
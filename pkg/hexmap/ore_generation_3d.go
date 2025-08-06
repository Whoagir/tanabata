// pkg/hexmap/ore_generation_3d.go
package hexmap

import (
	"math"
	"math/rand"
)

// findFarthestHex3D находит самый удаленный гекс из кандидатов от существующих центров.
// Эта версия изолирована и не зависит от игрового состояния.
func findFarthestHex3D(candidates []Hex, existingCenters []Hex) Hex {
	var bestHex Hex
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

// isTooCloseToCritical3D проверяет, не находится ли гекс слишком близко к важным точкам карты.
func isTooCloseToCritical3D(hex Hex, gameMap *HexMap) bool {
	if hex == gameMap.Entry || hex == gameMap.Exit {
		return true
	}
	if gameMap.Entry.Distance(hex) < 2 || gameMap.Exit.Distance(hex) < 2 {
		return true
	}
	for _, cp := range gameMap.Checkpoints {
		if cp == hex || cp.Distance(hex) < 2 {
			return true
		}
	}
	return false
}

// GenerateOre3D генерирует руду для 3D-визуализатора.
// Возвращает карту, где ключ - это гекс, а значение - мощность руды.
// Эта функция является адаптированной версией GenerateOre из основной игры,
// но без зависимостей от ECS и состояния игры.
func GenerateOre3D(gameMap *HexMap) map[Hex]float64 {
	allHexes := make([]Hex, 0, len(gameMap.Tiles))
	for hex := range gameMap.Tiles {
		allHexes = append(allHexes, hex)
	}

	centerHex := Hex{Q: 0, R: 0}
	var centers []Hex

	// --- Поиск трех центров для жил ---
	// Центр 1: В центре (дистанция < 3)
	for len(centers) < 1 {
		candidate := allHexes[rand.Intn(len(allHexes))]
		if !isTooCloseToCritical3D(candidate, gameMap) && centerHex.Distance(candidate) < 3 {
			centers = append(centers, candidate)
		}
	}

	// Центр 2: Средний радиус (4-9), подальше от первого
	for len(centers) < 2 {
		candidate := allHexes[rand.Intn(len(allHexes))]
		distFromCenter := centerHex.Distance(candidate)
		if !isTooCloseToCritical3D(candidate, gameMap) && distFromCenter >= 4 && distFromCenter <= 9 {
			if centers[0].Distance(candidate) > 6 {
				centers = append(centers, candidate)
			}
		}
	}

	// Центр 3: Далеко (дистанция >= 10)
	var centerCandidates3 []Hex
	for _, hex := range allHexes {
		if !isTooCloseToCritical3D(hex, gameMap) && centerHex.Distance(hex) >= 10 {
			centerCandidates3 = append(centerCandidates3, hex)
		}
	}
	if len(centerCandidates3) > 0 {
		center3 := findFarthestHex3D(centerCandidates3, centers)
		centers = append(centers, center3)
	} else { // Запасной вариант
		for _, hex := range allHexes {
			if !isTooCloseToCritical3D(hex, gameMap) && centerHex.Distance(hex) >= 8 {
				centerCandidates3 = append(centerCandidates3, hex)
			}
		}
		if len(centerCandidates3) > 0 {
			centers = append(centers, findFarthestHex3D(centerCandidates3, centers))
		}
	}

	if len(centers) < 3 {
		return make(map[Hex]float64) // Не удалось найти центры, возвращаем пустую карту
	}

	// --- Генерация жил ---
	veinAreas := make([][]Hex, 3)
	for i, center := range centers {
		if i == 0 { // Центральная ж��ла
			centralVein := []Hex{center}
			neighbors := gameMap.GetNeighbors(center)
			rand.Shuffle(len(neighbors), func(i, j int) { neighbors[i], neighbors[j] = neighbors[j], neighbors[i] })
			for _, neighbor := range neighbors {
				if len(centralVein) >= 4 {
					break
				}
				if !isTooCloseToCritical3D(neighbor, gameMap) {
					centralVein = append(centralVein, neighbor)
				}
			}
			veinAreas[i] = centralVein
		} else { // Остальные жилы
			veinAreas[i] = gameMap.GetHexesInRange(center, 2)
		}
	}

	energyVeins := make(map[Hex]float64)
	totalMapPower := 240.0 + rand.Float64()*30
	centralShare := (0.18 + rand.Float64()*0.04) * (2.5 / 1.5)
	midShare := 0.27 + rand.Float64()*0.06
	farShare := 1.0 - centralShare - midShare
	totalPowers := []float64{totalMapPower * centralShare, totalMapPower * midShare, totalMapPower * farShare}

	for i, area := range veinAreas {
		if len(area) == 0 {
			continue
		}
		totalVeinPower := totalPowers[i]
		if i == 0 { // Центральная жила
			remainingPower := totalVeinPower
			for j := 0; j < len(area)-1; j++ {
				hex := area[j]
				avgPower := remainingPower / float64(len(area)-j)
				fluctuation := avgPower * 0.4
				power := avgPower + (rand.Float64()*2-1)*fluctuation
				if power > remainingPower { power = remainingPower }
				if power < 0 { power = 0 }
				energyVeins[hex] = power / 100.0
				remainingPower -= power
			}
			if len(area) > 0 {
				energyVeins[area[len(area)-1]] = remainingPower / 100.0
			}
		} else { // Остальные жилы (упрощенная логика без кругов)
			powerPerHex := totalVeinPower / float64(len(area))
			for _, hex := range area {
				if !isTooCloseToCritical3D(hex, gameMap) {
					fluctuation := powerPerHex * 0.5
					finalPower := powerPerHex + (rand.Float64()*2-1)*fluctuation
					if _, exists := energyVeins[hex]; !exists {
						energyVeins[hex] = 0
					}
					energyVeins[hex] += finalPower / 100.0
				}
			}
		}
	}

	// Очистка от нулевых значений и гексов на критических точках
	finalEnergyVeins := make(map[Hex]float64)
	for hex, power := range energyVeins {
		if power > 0.01 && !isTooCloseToCritical3D(hex, gameMap) {
			finalEnergyVeins[hex] = math.Max(0, power)
		}
	}

	return finalEnergyVeins
}

// internal/system/ore.go
package system

import (
	"fmt"
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"go-tower-defense/pkg/hexmap"
	"image/color"
	"math"
	"math/rand"
	"time"
)

// EnergyCircle defines a circular area of energy.
type EnergyCircle struct {
	CenterX float64
	CenterY float64
	Radius  float64
	Power   float64
}

// OreSystem manages the state of ore veins, like visual depletion.
type OreSystem struct {
	ecs           *entity.ECS
	EnergyVeins   map[hexmap.Hex]float64
	EnergyCircles []EnergyCircle
}

// NewOreSystem creates a new OreSystem.
func NewOreSystem(ecs *entity.ECS) *OreSystem {
	return &OreSystem{
		ecs:           ecs,
		EnergyVeins:   make(map[hexmap.Hex]float64),
		EnergyCircles: nil,
	}
}

// Update is called every frame to update the state of ore components.
func (s *OreSystem) Update() {
	for id, ore := range s.ecs.Ores {
		if ore.MaxReserve > 0 {
			// The displayed percentage is now simply the current reserve.
			displayPercentage := ore.CurrentReserve

			// The radius shrinks as the reserve is depleted.
			// The variable part of the radius is scaled by the percentage of the remaining reserve.
			baseRadius := config.HexSize * 0.2
			variableRadius := ore.Power * config.HexSize
			reservePercentage := ore.CurrentReserve / ore.MaxReserve
			ore.Radius = float32(baseRadius + (variableRadius * reservePercentage))

			// Update or create text component
			textValue := fmt.Sprintf("%.0f%%", displayPercentage)
			textColor := color.RGBA{R: 50, G: 50, B: 50, A: 255}

			if textComp, exists := s.ecs.Texts[id]; exists {
				textComp.Value = textValue
			} else {
				// This part is a fallback, should be created in game.go
				s.ecs.Texts[id] = &component.Text{
					Value:    textValue,
					Position: ore.Position,
					Color:    textColor,
					IsUI:     true,
				}
			}
		}
	}
}

func (s *OreSystem) GenerateOres(hexMap *hexmap.HexMap) {
	rand.Seed(time.Now().UnixNano())

	// Все возможные гексы
	allHexes := make([]hexmap.Hex, 0, len(hexMap.Tiles))
	for hex := range hexMap.Tiles {
		allHexes = append(allHexes, hex)
	}

	// Получаем гексы на границе (в ��адиусе 3 от края)
	borderHexes := hexMap.GetBorderHexes(3)

	// Центр карты
	centerHex := hexmap.Hex{Q: 0, R: 0}

	// Проверка валидности центра жилы
	isValidCenter1 := func(hex hexmap.Hex) bool {
		if hex == hexMap.Entry || hex == hexMap.Exit || hexMap.IsCheckpoint(hex) {
			return false
		}
		if hexMap.Entry.Distance(hex) < 2 || hexMap.Exit.Distance(hex) < 2 {
			return false
		}
		for _, cp := range hexMap.Checkpoints {
			if cp.Distance(hex) < 1 {
				return false
			}
		}
		if _, isBorder := borderHexes[hex]; isBorder {
			return false
		}
		if centerHex.Distance(hex) < 3 {
			return true
		}
		return false
	}

	isValidCenter2 := func(hex hexmap.Hex) bool {
		if hex == hexMap.Entry || hex == hexMap.Exit || hexMap.IsCheckpoint(hex) {
			return false
		}
		if hexMap.Entry.Distance(hex) < 2 || hexMap.Exit.Distance(hex) < 2 {
			return false
		}
		for _, cp := range hexMap.Checkpoints {
			if cp.Distance(hex) < 1 {
				return false
			}
		}
		if _, isBorder := borderHexes[hex]; isBorder {
			return false
		}
		if centerHex.Distance(hex) < 3 {
			return false
		}
		return true
	}

	// Выбор двух центров
	var centers []hexmap.Hex
	for len(centers) < 1 {
		candidate := allHexes[rand.Intn(len(allHexes))]
		if isValidCenter1(candidate) {
			if len(centers) == 0 || centers[0].Distance(candidate) <= 6 {
				centers = append(centers, candidate)
			}
		}
	}
	for len(centers) < 2 {
		candidate := allHexes[rand.Intn(len(allHexes))]
		if isValidCenter2(candidate) {
			if len(centers) == 0 || centers[0].Distance(candidate) <= 10 {
				centers = append(centers, candidate)
			}
		}
	}

	// Генерация областей жил
	veinAreas := make([][]hexmap.Hex, 2)
	for i, center := range centers {
		veinAreas[i] = hexMap.GetHexesInRange(center, 2)
	}

	// Генерация кружков для каждой жилы
	for _, area := range veinAreas {
		totalPower := 100.0 + float64(rand.Intn(21)) // 100-120%
		circles := s.generateEnergyCircles(area, totalPower, config.HexSize)
		s.EnergyCircles = append(s.EnergyCircles, circles...)

		// Привязка энергии к гексам, исключая чекпоинты
		for _, circle := range circles {
			hexesInCircle := s.getHexesInCircle(hexMap, circle.CenterX, circle.CenterY, circle.Radius)
			for _, hex := range hexesInCircle {
				if hexMap.IsCheckpoint(hex) {
					continue // Пропускаем чекпоинты
				}
				if _, exists := s.EnergyVeins[hex]; !exists {
					s.EnergyVeins[hex] = 0
				}
				s.EnergyVeins[hex] += circle.Power
			}
		}
	}
}

func (s *OreSystem) generateEnergyCircles(area []hexmap.Hex, totalPower float64, hexSize float64) []EnergyCircle {
	var circles []EnergyCircle
	remainingPower := totalPower

	for remainingPower > 0 {
		hex := area[rand.Intn(len(area))]
		cx, cy := hex.ToPixel(hexSize)
		cx += float64(config.ScreenWidth)/2 + (rand.Float64()*2-1)*hexSize/2
		cy += float64(config.ScreenHeight)/2 + (rand.Float64()*2-1)*hexSize/2

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

func (s *OreSystem) getHexesInCircle(hexMap *hexmap.HexMap, cx, cy, radius float64) []hexmap.Hex {
	var hexes []hexmap.Hex
	for hex := range hexMap.Tiles {
		hx, hy := hex.ToPixel(config.HexSize)
		hx += float64(config.ScreenWidth) / 2
		hy += float64(config.ScreenHeight) / 2
		dx := hx - cx
		dy := hy - cy
		if math.Sqrt(dx*dx+dy*dy) < radius+config.HexSize {
			hexes = append(hexes, hex)
		}
	}
	return hexes
}

func (s *OreSystem) CreateEntities(ecs *entity.ECS) {
	for hex, power := range s.EnergyVeins {
		id := ecs.NewEntity()
		px, py := hex.ToPixel(config.HexSize)
		px += float64(config.ScreenWidth) / 2
		py += float64(config.ScreenHeight) / 2
		ecs.Positions[id] = &component.Position{X: px, Y: py}
		ecs.Ores[id] = &component.Ore{
			Power:          power,
			MaxReserve:     power * 100, // База для расчета процентов
			CurrentReserve: power * 100,
			Position:       component.Position{X: px, Y: py},
			Radius:         float32(config.HexSize*0.2 + power*config.HexSize),
			Color:          color.RGBA{0, 0, 255, 128},
			PulseRate:      2.0,
		}
		ecs.Texts[id] = &component.Text{
			Value:    fmt.Sprintf("%.0f%%", power*100),
			Position: component.Position{X: px, Y: py},
			Color:    color.RGBA{R: 50, G: 50, B: 50, A: 255},
			IsUI:     true,
		}
	}
}

// pkg/hexmap/map.go
package hexmap

import (
	"go-tower-defense/internal/config"
	"math"
	"math/rand"
	"time"
)

type Tile struct {
	Passable      bool
	CanPlaceTower bool
}

type HexMap struct {
	Tiles         map[Hex]Tile
	Radius        int
	Entry         Hex
	Exit          Hex
	Checkpoints   []Hex
	EnergyVeins   map[Hex]float64
	EnergyCircles []EnergyCircle
}

type EnergyCircle struct {
	CenterX float64
	CenterY float64
	Radius  float64
	Power   float64
}

func NewHexMap() *HexMap {
	tiles := make(map[Hex]Tile)
	radius := config.MapRadius

	// Генерация базовой карты
	for q := -radius; q <= radius; q++ {
		r1 := max(-radius, -q-radius)
		r2 := min(radius, -q+radius)
		for r := r1; r <= r2; r++ {
			tiles[Hex{q, r}] = Tile{Passable: true, CanPlaceTower: true}
		}
	}

	entry := Hex{Q: -(radius + 1), R: radius - radius/2 + 1}
	exit := Hex{Q: radius + 1, R: -(radius - radius/2 + 1)}
	tiles[entry] = Tile{Passable: true, CanPlaceTower: false}
	tiles[exit] = Tile{Passable: true, CanPlaceTower: false}

	hm := &HexMap{
		Tiles:         tiles,
		Radius:        radius,
		Entry:         entry,
		Exit:          exit,
		Checkpoints:   nil,
		EnergyVeins:   make(map[Hex]float64),
		EnergyCircles: nil,
	}

	// Генерация чекпоинтов
	D := hm.Radius - 3
	if D < 1 {
		hm.Checkpoints = []Hex{}
	} else {
		baseCheckpoints := []Hex{
			{Q: -D, R: D}, {Q: D, R: -D}, {Q: 0, R: -D},
			{Q: 0, R: D}, {Q: D, R: 0}, {Q: -D, R: 0},
		}
		k := rand.Intn(6)
		hm.Checkpoints = append(baseCheckpoints[k:], baseCheckpoints[:k]...)
	}

	// Генерация жил энергии
	hm.generateEnergyVeins()

	// Процедурная генерация и пост-обработка
	exclusion := hm.getExclusionZones(3)
	sections := hm.getBorderSections()
	for _, section := range sections {
		if hm.sectionIntersectsExclusion(section, exclusion) {
			continue
		}
		action := rand.Intn(10)
		if action < 3 {
			hm.addOuterSection(section)
		} else if action < 6 {
			hm.removeInnerSection(section)
		}
	}
	hm.processCorners(exclusion)
	hm.postProcessMap()

	return hm
}

func (hm *HexMap) generateEnergyVeins() {
	rand.Seed(time.Now().UnixNano())

	// Все возможные гексы
	allHexes := make([]Hex, 0, len(hm.Tiles))
	for hex := range hm.Tiles {
		allHexes = append(allHexes, hex)
	}

	// Получаем гексы на границе (в радиусе 3 от края)
	borderHexes := hm.getBorderHexes(3)

	// Центр карты
	centerHex := Hex{Q: 0, R: 0}

	// Проверка валидности центра жилы
	isValidCenter := func(hex Hex) bool {
		if hex == hm.Entry || hex == hm.Exit || hm.isCheckpoint(hex) {
			return false
		}
		if hm.Entry.Distance(hex) < 2 || hm.Exit.Distance(hex) < 2 {
			return false
		}
		for _, cp := range hm.Checkpoints {
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
	var centers []Hex
	for len(centers) < 2 {
		candidate := allHexes[rand.Intn(len(allHexes))]
		if isValidCenter(candidate) {
			if len(centers) == 0 || centers[0].Distance(candidate) >= 6 {
				centers = append(centers, candidate)
			}
		}
	}

	// Генерация областей жил
	veinAreas := make([][]Hex, 2)
	for i, center := range centers {
		veinAreas[i] = hm.GetHexesInRange(center, 2)
	}

	// Генерация кружков для каждой жилы
	for _, area := range veinAreas {
		totalPower := 100.0 + float64(rand.Intn(21)) // 100-120%
		circles := generateEnergyCircles(area, totalPower, config.HexSize)
		hm.EnergyCircles = append(hm.EnergyCircles, circles...)

		// Привязка энергии к гексам, исключая чекпоинты
		for _, circle := range circles {
			hexesInCircle := hm.getHexesInCircle(circle.CenterX, circle.CenterY, circle.Radius)
			for _, hex := range hexesInCircle {
				if hm.isCheckpoint(hex) {
					continue // Пропускаем чекпоинты
				}
				if _, exists := hm.EnergyVeins[hex]; !exists {
					hm.EnergyVeins[hex] = 0
				}
				hm.EnergyVeins[hex] += circle.Power
			}
		}
	}
}

func generateEnergyCircles(area []Hex, totalPower float64, hexSize float64) []EnergyCircle {
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

func (hm *HexMap) getHexesInCircle(cx, cy, radius float64) []Hex {
	var hexes []Hex
	for hex := range hm.Tiles {
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

func (hm *HexMap) getBorderHexes(borderRadius int) map[Hex]struct{} {
	border := make(map[Hex]struct{})
	for hex := range hm.Tiles {
		if hex.Q <= -hm.Radius+borderRadius || hex.Q >= hm.Radius-borderRadius ||
			hex.R <= -hm.Radius+borderRadius || hex.R >= hm.Radius-borderRadius ||
			hex.Q+hex.R <= -hm.Radius+borderRadius || hex.Q+hex.R >= hm.Radius-borderRadius {
			border[hex] = struct{}{}
		}
	}
	return border
}

// Остальные функции остаются без изменений
func (hm *HexMap) isCheckpoint(hex Hex) bool {
	for _, cp := range hm.Checkpoints {
		if cp == hex {
			return true
		}
	}
	return false
}

func (hm *HexMap) getExclusionZones(radius int) map[Hex]struct{} {
	exclusion := make(map[Hex]struct{})
	entryZone := hm.GetHexesInRange(hm.Entry, radius)
	exitZone := hm.GetHexesInRange(hm.Exit, radius)
	for _, hex := range entryZone {
		exclusion[hex] = struct{}{}
	}
	for _, hex := range exitZone {
		exclusion[hex] = struct{}{}
	}
	return exclusion
}

func (hm *HexMap) getBorderSections() [][]Hex {
	var sections [][]Hex
	radius := hm.Radius
	sides := []struct {
		coords func(int) Hex
		start  int
		end    int
	}{
		{func(r int) Hex { return Hex{radius, r} }, -radius, 0},
		{func(q int) Hex { return Hex{q, radius - q} }, 0, radius},
		{func(q int) Hex { return Hex{q, -radius} }, 0, radius},
		{func(r int) Hex { return Hex{-radius, r} }, 0, radius},
		{func(q int) Hex { return Hex{q, -radius - q} }, -radius, 0},
		{func(q int) Hex { return Hex{q, radius} }, -radius, 0},
	}

	for _, side := range sides {
		for i := side.start; i <= side.end-2; i += 3 {
			section := []Hex{
				side.coords(i),
				side.coords(i + 1),
				side.coords(i + 2),
			}
			valid := true
			for _, hex := range section {
				if !hm.Contains(hex) {
					valid = false
					break
				}
			}
			if valid {
				sections = append(sections, section)
			}
		}
	}
	return sections
}

func (hm *HexMap) sectionIntersectsExclusion(section []Hex, exclusion map[Hex]struct{}) bool {
	for _, hex := range section {
		if _, excluded := exclusion[hex]; excluded {
			return true
		}
	}
	return false
}

func (hm *HexMap) addOuterSection(section []Hex) {
	for _, hex := range section {
		neighbors := hex.AllPossibleNeighbors()
		for _, n := range neighbors {
			if !hm.Contains(n) {
				hm.Tiles[n] = Tile{Passable: true, CanPlaceTower: true}
			}
		}
	}
}

func (hm *HexMap) removeInnerSection(section []Hex) {
	for _, hex := range section {
		tile := hm.Tiles[hex]
		tile.Passable = false
		hm.Tiles[hex] = tile
	}
	path := AStar(hm.Entry, hm.Exit, hm)
	for _, hex := range section {
		tile := hm.Tiles[hex]
		tile.Passable = true
		hm.Tiles[hex] = tile
	}
	if path == nil {
		return
	}
	for _, hex := range section {
		delete(hm.Tiles, hex)
	}
}

func (hm *HexMap) processCorners(exclusion map[Hex]struct{}) {
	corners := []Hex{
		{hm.Radius, 0}, {0, hm.Radius}, {-hm.Radius, hm.Radius},
		{-hm.Radius, 0}, {0, -hm.Radius}, {hm.Radius, -hm.Radius},
	}

	for _, corner := range corners {
		if _, excluded := exclusion[corner]; excluded {
			continue
		}
		action := rand.Intn(10)
		if action < 3 {
			var additions []Hex
			switch corner {
			case Hex{hm.Radius, 0}:
				additions = []Hex{{hm.Radius + 1, 0}, {hm.Radius + 1, -1}, {hm.Radius, -1}}
			case Hex{0, hm.Radius}:
				additions = []Hex{{1, hm.Radius}, {0, hm.Radius + 1}, {-1, hm.Radius}}
			case Hex{-hm.Radius, hm.Radius}:
				additions = []Hex{{-hm.Radius, hm.Radius + 1}, {-hm.Radius - 1, hm.Radius}, {-hm.Radius - 1, hm.Radius + 1}}
			case Hex{-hm.Radius, 0}:
				additions = []Hex{{-hm.Radius - 1, 0}, {-hm.Radius - 1, 1}, {-hm.Radius, 1}}
			case Hex{0, -hm.Radius}:
				additions = []Hex{{1, -hm.Radius}, {0, -hm.Radius - 1}, {-1, -hm.Radius}}
			case Hex{hm.Radius, -hm.Radius}:
				additions = []Hex{{hm.Radius + 1, -hm.Radius}, {hm.Radius, -hm.Radius - 1}, {hm.Radius + 1, -hm.Radius - 1}}
			}
			for _, hex := range additions {
				if !hm.Contains(hex) {
					hm.Tiles[hex] = Tile{Passable: true, CanPlaceTower: true}
				}
			}
		} else if action < 6 {
			tile := hm.Tiles[corner]
			tile.Passable = false
			hm.Tiles[corner] = tile
			path := AStar(hm.Entry, hm.Exit, hm)
			tile = hm.Tiles[corner]
			tile.Passable = true
			hm.Tiles[corner] = tile
			if path != nil {
				delete(hm.Tiles, corner)
			}
		}
	}
}

func (hm *HexMap) postProcessMap() {
	extraRadius := 2
	for {
		changes := false
		potentialHexes := hm.getAllPotentialHexes(extraRadius)
		for _, hex := range potentialHexes {
			neighbors := hex.AllPossibleNeighbors()
			onMapNeighbors := 0
			for _, n := range neighbors {
				if hm.Contains(n) {
					onMapNeighbors++
				}
			}
			if !hm.Contains(hex) {
				if onMapNeighbors >= 4 {
					hm.Tiles[hex] = Tile{Passable: true, CanPlaceTower: true}
					changes = true
				}
			} else {
				if hex != hm.Entry && hex != hm.Exit && onMapNeighbors <= 2 {
					delete(hm.Tiles, hex)
					changes = true
				}
			}
		}
		if !changes {
			break
		}
	}
}

func (hm *HexMap) getAllPotentialHexes(extraRadius int) []Hex {
	radius := hm.Radius + extraRadius
	var hexes []Hex
	for q := -radius; q <= radius; q++ {
		r1 := max(-radius, -q-radius)
		r2 := min(radius, -q+radius)
		for r := r1; r <= r2; r++ {
			hexes = append(hexes, Hex{q, r})
		}
	}
	return hexes
}

func (hm *HexMap) IsPassable(hex Hex) bool {
	if tile, exists := hm.Tiles[hex]; exists {
		return tile.Passable
	}
	return false
}

func (hm *HexMap) SetPassable(hex Hex, passable bool) {
	if tile, exists := hm.Tiles[hex]; exists {
		tile.Passable = passable
		hm.Tiles[hex] = tile
	}
}

func (hm *HexMap) GetHexesInRange(center Hex, radius int) []Hex {
	var result []Hex
	for q := -radius; q <= radius; q++ {
		for r := max(-radius, -q-radius); r <= min(radius, -q+radius); r++ {
			s := -q - r
			if abs(q)+abs(r)+abs(s) <= radius*2 {
				hex := center.Add(Hex{Q: q, R: r})
				if hm.Contains(hex) {
					result = append(result, hex)
				}
			}
		}
	}
	return result
}

func (hm *HexMap) Contains(hex Hex) bool {
	_, exists := hm.Tiles[hex]
	return exists
}

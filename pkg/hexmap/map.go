// pkg/hexmap/map.go
package hexmap

import (
	"go-tower-defense/internal/config"
	"math/rand"
)

type Tile struct {
	Passable      bool
	CanPlaceTower bool
}

type HexMap struct {
	Tiles       map[Hex]Tile
	Radius      int
	Entry       Hex
	Exit        Hex
	Checkpoints []Hex
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
		Tiles:       tiles,
		Radius:      radius,
		Entry:       entry,
		Exit:        exit,
		Checkpoints: nil,
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
	// hm.generateEnergyVeins() // Этот вызов будет удален

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

func (hm *HexMap) GetBorderHexes(borderRadius int) map[Hex]struct{} {
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

// Остальные функции остаются ��ез изменений
func (hm *HexMap) IsCheckpoint(hex Hex) bool {
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

// GetNeighbors returns all valid, existing neighbors for a given hex.
func (hm *HexMap) GetNeighbors(h Hex) []Hex {
	return h.Neighbors(hm)
}

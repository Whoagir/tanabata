// pkg/hexmap/hex.go
package hexmap

import (
	"container/heap"
	"go-tower-defense/internal/config"
	"math"
	"math/rand"
)

// Hex представляет гекс в осевых координатах (Q, R)
type Hex struct {
	Q, R int
}

// Tile содержит свойства гекса на карте
type Tile struct {
	Passable      bool // Проходимость для врагов
	CanPlaceTower bool // Можно ли ставить башню
}

// HexMap хранит карту гексов и их свойств
type HexMap struct {
	Tiles       map[Hex]Tile // Карта гексов
	Radius      int          // Радиус карты (для шестиугольника)
	Entry       Hex          // Вход
	Exit        Hex          // Выход
	Checkpoint1 Hex          // Первый чекпоинт
	Checkpoint2 Hex          // Второй чекпоинт
}

// NewHexMap создает новую гексагональную карту с процедурно сгенерированными краями
func NewHexMap() *HexMap {
	tiles := make(map[Hex]Tile)
	radius := config.MapRadius

	// Генерация базовой шестиугольной карты
	for q := -radius; q <= radius; q++ {
		r1 := max(-radius, -q-radius)
		r2 := min(radius, -q+radius)
		for r := r1; r <= r2; r++ {
			tiles[Hex{q, r}] = Tile{Passable: true, CanPlaceTower: true}
		}
	}

	// Установка входа и выхода
	entry := Hex{Q: -(radius + 1), R: radius - radius/2 + 1}
	exit := Hex{Q: radius + 1, R: -(radius - radius/2 + 1)}
	tiles[entry] = Tile{Passable: true, CanPlaceTower: false}
	tiles[exit] = Tile{Passable: true, CanPlaceTower: false}

	hm := &HexMap{
		Tiles:       tiles,
		Radius:      radius,
		Entry:       entry,
		Exit:        exit,
		Checkpoint1: Hex{Q: -10, R: 10},
		Checkpoint2: Hex{Q: 10, R: -10},
	}

	// Получаем зоны исключения (радиус 3 от входа и выхода)
	exclusion := hm.getExclusionZones(3)

	// Определяем все секции по 3 гекса для каждой из 6 сторон
	sections := hm.getBorderSections()

	// Применяем процедурную генерацию
	for _, section := range sections {
		if hm.sectionIntersectsExclusion(section, exclusion) {
			continue
		}
		// Случайное действие: 30% — добавить, 30% — убрать, 40% — ничего
		action := rand.Intn(10)
		if action < 3 {
			hm.addOuterSection(section)
		} else if action < 6 {
			hm.removeInnerSection(section)
		}
	}

	// Обрабатываем углы отдельно
	hm.processCorners(exclusion)

	// Пост-обработка для устранения аномалий
	hm.postProcessMap()

	return hm
}

// getExclusionZones возвращает гексы в радиусе от входа и выхода
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

// getBorderSections возвращает секции по 3 гекса для каждой стороны шестиугольника
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

// sectionIntersectsExclusion проверяет, пересекается ли секция с зоной исключения
func (hm *HexMap) sectionIntersectsExclusion(section []Hex, exclusion map[Hex]struct{}) bool {
	for _, hex := range section {
		if _, excluded := exclusion[hex]; excluded {
			return true
		}
	}
	return false
}

// addOuterSection добавляет внешнюю группу из 3 гексов
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

// removeInnerSection убирает секцию, если это не нарушит связность
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

// processCorners обрабатывает угловые гексы с особыми правилами
func (hm *HexMap) processCorners(exclusion map[Hex]struct{}) {
	corners := []Hex{
		{hm.Radius, 0},
		{0, hm.Radius},
		{-hm.Radius, hm.Radius},
		{-hm.Radius, 0},
		{0, -hm.Radius},
		{hm.Radius, -hm.Radius},
	}

	for _, corner := range corners {
		if _, excluded := exclusion[corner]; excluded {
			continue
		}
		action := rand.Intn(10)
		if action < 3 { // 30% — добавить 3 гекса
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
		} else if action < 6 { // 30% — убрать угол
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

// postProcessMap устраняет аномалии: единичные клетки и дыры
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
				if onMapNeighbors >= 4 { // Заполняем дыры
					hm.Tiles[hex] = Tile{Passable: true, CanPlaceTower: true}
					changes = true
				}
			} else {
				// Удаляем единичные клетки, но не трогаем вход и выход
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

// getAllPotentialHexes возвращает все возможные гексы в расширенном радиусе
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

// AllPossibleNeighbors возвращает всех возможных соседей гекса
func (h Hex) AllPossibleNeighbors() []Hex {
	return []Hex{
		{h.Q + 1, h.R},
		{h.Q + 1, h.R - 1},
		{h.Q, h.R - 1},
		{h.Q - 1, h.R},
		{h.Q - 1, h.R + 1},
		{h.Q, h.R + 1},
	}
}

// Add возвращает сумму двух гексов
func (h Hex) Add(other Hex) Hex {
	return Hex{
		Q: h.Q + other.Q,
		R: h.R + other.R,
	}
}

// Subtract возвращает разность двух гексов
func (h Hex) Subtract(other Hex) Hex {
	return Hex{
		Q: h.Q - other.Q,
		R: h.R - other.R,
	}
}

// Distance вычисляет расстояние между гексами
func (h Hex) Distance(to Hex) int {
	dq := h.Q - to.Q
	dr := h.R - to.R
	return (abs(dq) + abs(dr) + abs(dq+dr)) / 2
}

// Neighbors возвращает существующих соседей гекса
func (h Hex) Neighbors(hm *HexMap) []Hex {
	allNeighbors := h.AllPossibleNeighbors()
	validNeighbors := make([]Hex, 0, 6)
	for _, n := range allNeighbors {
		if _, exists := hm.Tiles[n]; exists {
			validNeighbors = append(validNeighbors, n)
		}
	}
	return validNeighbors
}

// ToPixel конвертирует гекс в пиксельные координаты (pointy top ориентация)
func (h Hex) ToPixel(hexSize float64) (x, y float64) {
	x = hexSize * (Sqrt3*float64(h.Q) + (Sqrt3 / 2 * float64(h.R)))
	y = hexSize * (3.0 / 2.0 * float64(h.R))
	return
}

// PixelToHex конвертирует пиксельные координаты в гекс
func PixelToHex(x, y, hexSize float64) Hex {
	x -= float64(config.ScreenWidth) / 2
	y -= float64(config.ScreenHeight) / 2
	q := (Sqrt3/3*x - 1.0/3*y) / hexSize
	r := (2.0 / 3 * y) / hexSize
	return axialRound(q, r)
}

// IsPassable проверяет, проходим ли гекс
func (hm *HexMap) IsPassable(hex Hex) bool {
	if tile, exists := hm.Tiles[hex]; exists {
		return tile.Passable
	}
	return false
}

// SetPassable устанавливает проходимость гекса
func (hm *HexMap) SetPassable(hex Hex, passable bool) {
	if tile, exists := hm.Tiles[hex]; exists {
		tile.Passable = passable
		hm.Tiles[hex] = tile
	}
}

// GetHexesInRange возвращает все гексы в заданном радиусе от центра
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

// Contains проверяет, существует ли гекс на карте
func (hm *HexMap) Contains(hex Hex) bool {
	_, exists := hm.Tiles[hex]
	return exists
}

// Lerp выполняет линейную интерполяцию между двумя гексами
func (a Hex) Lerp(b Hex, t float64) Hex {
	return Hex{
		Q: int(float64(a.Q)*(1-t) + float64(b.Q)*t),
		R: int(float64(a.R)*(1-t) + float64(b.R)*t),
	}
}

// LineTo возвращает гексы на прямой между двумя точками
func (start Hex) LineTo(end Hex) []Hex {
	n := start.Distance(end)
	results := make([]Hex, 0, n+1)
	for i := 0; i <= n; i++ {
		t := 1.0 / float64(n) * float64(i)
		results = append(results, start.Lerp(end, t))
	}
	return results
}

// AStar находит кратчайший путь от start до goal
func AStar(start, goal Hex, hm *HexMap) []Hex {
	pq := &PriorityQueue{}
	heap.Init(pq)
	heap.Push(pq, &Node{Hex: start, Cost: 0, Parent: nil})
	cameFrom := make(map[Hex]*Node)
	costSoFar := make(map[Hex]int)
	costSoFar[start] = 0
	for pq.Len() > 0 {
		current := heap.Pop(pq).(*Node)
		if current.Hex == goal {
			return reconstructPath(current)
		}
		for _, neighbor := range current.Hex.Neighbors(hm) {
			if !hm.IsPassable(neighbor) {
				continue
			}
			newCost := costSoFar[current.Hex] + 1
			if _, exists := costSoFar[neighbor]; !exists || newCost < costSoFar[neighbor] {
				costSoFar[neighbor] = newCost
				priority := newCost + neighbor.Distance(goal)
				heap.Push(pq, &Node{Hex: neighbor, Cost: priority, Parent: current})
				cameFrom[neighbor] = current
			}
		}
	}
	return nil // Нет пути
}

// PriorityQueue для A*
type PriorityQueue []*Node

type Node struct {
	Hex    Hex
	Cost   int
	Parent *Node
}

func (pq PriorityQueue) Len() int           { return len(pq) }
func (pq PriorityQueue) Less(i, j int) bool { return pq[i].Cost < pq[j].Cost }
func (pq PriorityQueue) Swap(i, j int)      { pq[i], pq[j] = pq[j], pq[i] }
func (pq *PriorityQueue) Push(x interface{}) {
	*pq = append(*pq, x.(*Node))
}
func (pq *PriorityQueue) Pop() interface{} {
	old := *pq
	n := len(old)
	item := old[n-1]
	*pq = old[0 : n-1]
	return item
}

func reconstructPath(node *Node) []Hex {
	path := []Hex{}
	for node != nil {
		path = append([]Hex{node.Hex}, path...)
		node = node.Parent
	}
	return path
}

// Вспомогательные функции
func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// Внутренние функции для конвертации координат
func axialToCube(q, r float64) (x, y, z float64) {
	x = q
	z = r
	y = -x - z
	return
}

func cubeRound(x, y, z float64) (rx, ry, rz int) {
	xf := math.Round(x)
	yf := math.Round(y)
	zf := math.Round(z)
	xd := math.Abs(xf - x)
	yd := math.Abs(yf - y)
	zd := math.Abs(zf - z)
	if xd > yd && xd > zd {
		xf = -yf - zf
	} else if yd > zd {
		yf = -xf - zf
	} else {
		zf = -xf - yf
	}
	return int(xf), int(yf), int(zf)
}

func axialRound(q, r float64) Hex {
	x, y, z := axialToCube(q, r)
	cx, cy, cz := cubeRound(x, y, z)
	return cubeToAxial(cx, cy, cz)
}

func cubeToAxial(x, y, z int) Hex {
	return Hex{Q: x, R: z}
}

// Константа √3 для вычислений
const Sqrt3 = 1.7320508075688772935274463415059

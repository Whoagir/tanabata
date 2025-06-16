// pkg/hexmap/hex.go
package hexmap

import (
	"container/heap"
	"go-tower-defense/internal/config"
	"math"
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
	Tiles  map[Hex]Tile // Карта гексов
	Radius int          // Радиус карты (для шестиугольника)
	Entry  Hex          // Вход
	Exit   Hex          // Выход
}

// NewHexMap создает новую гексагональную карту заданного радиуса
func NewHexMap() *HexMap {
	tiles := make(map[Hex]Tile)
	radius := config.MapRadius

	// Генерация шестиугольной карты
	for q := -radius; q <= radius; q++ {
		r1 := max(-radius, -q-radius)
		r2 := min(radius, -q+radius)
		for r := r1; r <= r2; r++ {
			tiles[Hex{q, r}] = Tile{Passable: true, CanPlaceTower: true}
		}
	}

	// Установка входа и выхода
	entry := Hex{Q: -(radius + 1), R: radius - radius/2 + 1} // Для R=7: (-8, 5)
	exit := Hex{Q: radius + 1, R: -(radius - radius/2 + 1)}  // Для R=7: (8, -5)

	// Вход и выход проходимы, но нельзя ставить башни
	tiles[entry] = Tile{Passable: true, CanPlaceTower: false}
	tiles[exit] = Tile{Passable: true, CanPlaceTower: false}

	return &HexMap{
		Tiles:  tiles,
		Radius: radius,
		Entry:  entry,
		Exit:   exit,
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
	allNeighbors := []Hex{
		{h.Q + 1, h.R},     // Восток
		{h.Q + 1, h.R - 1}, // Северо-восток
		{h.Q, h.R - 1},     // Северо-запад
		{h.Q - 1, h.R},     // Запад
		{h.Q - 1, h.R + 1}, // Юго-запад
		{h.Q, h.R + 1},     // Юго-восток
	}
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

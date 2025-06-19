// pkg/hexmap/hex.go
package hexmap

import (
	"go-tower-defense/internal/config"
)

// Hex представляет гекс в осевых координатах (Q, R)
type Hex struct {
	Q, R int
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

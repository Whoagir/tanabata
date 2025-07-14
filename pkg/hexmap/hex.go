// pkg/hexmap/hex.go
package hexmap

import (
	"go-tower-defense/internal/config"
	"go-tower-defense/pkg/utils"
)

// Hex представляет гекс в осевых координатах (Q, R)
type Hex struct {
	Q, R int
}

// NeighborDirections defines the 6 possible directions from a hex, starting from East and going counter-clockwise.
// This order is crucial for angle-to-direction calculations.
var NeighborDirections = []Hex{
	{Q: 1, R: 0}, {Q: 0, R: -1}, {Q: -1, R: 0},
	{Q: -1, R: 1}, {Q: 0, R: 1}, {Q: 1, R: -1},
}

// ToPixel конвертирует гекс в пиксельные координаты (pointy top ориентация)
func (h Hex) ToPixel(hexSize float64) (x, y float64) {
	x = hexSize * (Sqrt3*float64(h.Q) + Sqrt3/2*float64(h.R))
	y = hexSize * (3.0 / 2.0 * float64(h.R))
	return
}

// PixelToHex конвертирует ��иксельные координаты в гекс
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
	return (utils.Abs(dq) + utils.Abs(dr) + utils.Abs(dq+dr)) / 2
}

// Lerp выполняет линейную интерполяцию между двумя гексами
func (a Hex) Lerp(b Hex, t float64) Hex {
	q := float64(a.Q)*(1-t) + float64(b.Q)*t
	r := float64(a.R)*(1-t) + float64(b.R)*t
	return axialRound(q, r)
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

// IsOnSameLine checks if two hexes are on the same straight line.
func (h Hex) IsOnSameLine(other Hex) bool {
	if h == other {
		return true
	}

	dQ := h.Q - other.Q
	dR := h.R - other.R
	dS := (-h.Q - h.R) - (-other.Q - other.R) // S = -Q - R

	if dQ == 0 && dR == 0 { // dS will also be 0
		return true
	}

	commonDivisor := utils.Gcd(utils.Abs(dQ), utils.Gcd(utils.Abs(dR), utils.Abs(dS)))
	if commonDivisor == 0 {
		return false
	}

	normDQ := dQ / commonDivisor
	normDR := dR / commonDivisor

	// Check if the normalized vector matches one of the 6 base directions.
	// In cubic coordinates, Q + R + S = 0.
	// We only need to check two components.
	isDirection := (utils.Abs(normDQ) == 1 && normDR == 0) ||
		(normDQ == 0 && utils.Abs(normDR) == 1) ||
		(utils.Abs(normDQ) == 1 && utils.Abs(normDR) == 1 && normDQ == -normDR)

	return isDirection
}

// Direction returns a normalized hex vector (length 1) pointing from the origin towards h.
func (h Hex) Direction() Hex {
	if h.Q == 0 && h.R == 0 {
		return h // No direction from origin to origin
	}
	// A proper way would be to convert to cube, divide by distance, and round.
	// This simplified version handles the 6 cardinal directions, which is enough for now.
	absQ, absR, absS := utils.Abs(h.Q), utils.Abs(h.R), utils.Abs(-h.Q-h.R)
	if absQ >= absR && absQ >= absS {
		return Hex{h.Q / absQ, h.R / absQ}
	}
	if absR >= absQ && absR >= absS {
		return Hex{h.Q / absR, h.R / absR}
	}
	return Hex{h.Q / absS, h.R / absS}
}

// Scale multiplies a hex vector by a scalar.
func (h Hex) Scale(factor int) Hex {
	return Hex{h.Q * factor, h.R * factor}
}

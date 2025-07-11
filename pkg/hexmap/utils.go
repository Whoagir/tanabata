// pkg/hexmap/utils.go
package hexmap

import "math"

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
// internal/utils/math.go
package utils

import "math"

// Lerp выполняет стандартную линейную интерполяцию
func Lerp(from, to float32, t float32) float32 {
	return from + (to-from)*t
}

// LerpAngle выполняет линейную интерполяцию между двумя углами с учётом кратчайшего пути
func LerpAngle(from, to float32, t float32) float32 {
	// Нормализуем углы в диапазон [-π, π]
	from = NormalizeAngle(from)
	to = NormalizeAngle(to)
	
	// Находим кратчайшую разницу
	diff := to - from
	if diff > math.Pi {
		diff -= 2 * math.Pi
	} else if diff < -math.Pi {
		diff += 2 * math.Pi
	}
	
	return NormalizeAngle(from + diff*t)
}

// NormalizeAngle нормализует угол в диапазон [-π, π]
func NormalizeAngle(angle float32) float32 {
	for angle > math.Pi {
		angle -= 2 * math.Pi
	}
	for angle < -math.Pi {
		angle += 2 * math.Pi
	}
	return angle
}
// internal/utils/prng.go
package utils

import (
	"go-tower-defense/internal/defs"
	"math/rand"
	"time"
)

// PRNGService — это обертка над стандартным генератором случайных чисел Go,
// которая позволяет использовать предсказуемый (seeded) рандом во всей игре.
type PRNGService struct {
	rng *rand.Rand
}

// NewPRNGService создает новый экземпляр сервиса с указанным сидом.
// Если сид равен 0, используется текущее время.
func NewPRNGService(seed int64) *PRNGService {
	if seed == 0 {
		seed = time.Now().UnixNano()
	}
	source := rand.NewSource(seed)
	return &PRNGService{
		rng: rand.New(source),
	}
}

// Intn возвращает случайное целое число в диапазоне [0, n).
func (s *PRNGService) Intn(n int) int {
	return s.rng.Intn(n)
}

// Float64 возвращает случайное число с плавающей точкой в диапазоне [0.0, 1.0).
func (s *PRNGService) Float64() float64 {
	return s.rng.Float64()
}

// ChooseWeighted выполняет взвешенный случайный выбор из таблицы выпадения.
// Он суммирует все веса, выбирает случайное число в этом диапазоне,
// а затем находит элемент, которому соответствует это число.
func (s *PRNGService) ChooseWeighted(entries []defs.LootEntry) string {
	if len(entries) == 0 {
		return "" // Возвращаем пустую строку, если таблица пуста
	}

	totalWeight := 0
	for _, entry := range entries {
		totalWeight += entry.Weight
	}

	if totalWeight <= 0 {
		// Если сумма весов некорректна, возвращаем первый элемент по умолчанию
		return entries[0].TowerID
	}

	r := s.Intn(totalWeight)
	upto := 0
	for _, entry := range entries {
		if upto+entry.Weight > r {
			return entry.TowerID
		}
		upto += entry.Weight
	}

	// Этот код не должен быть достижим, но на всякий случай
	return entries[len(entries)-1].TowerID
}

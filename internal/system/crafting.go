package system

import (
	"fmt"
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/event"
	"go-tower-defense/internal/types"
	"sort"
)

// CraftingSystem отвечает за обнаружение и выполнение рецептов крафта.
type CraftingSystem struct {
	ecs *entity.ECS
}

func NewCraftingSystem(ecs *entity.ECS) *CraftingSystem {
	return &CraftingSystem{
		ecs: ecs,
	}
}

// OnEvent обрабатывает события, на которые подписана система.
func (s *CraftingSystem) OnEvent(e event.Event) {
	switch e.Type {
	case event.TowerPlaced, event.TowerRemoved:
		s.RecalculateCombinations()
	}
}

// RecalculateCombinations находит все возможные комбинации для крафта по всей карте.
func (s *CraftingSystem) RecalculateCombinations() {
	// 1. Очищаем старые данные о крафте
	s.ecs.Combinables = make(map[types.EntityID]*component.Combinable)

	// 2. Группируем все существу��щие башни по их типу (ID) и уровню
	// Ключ карты - строка "ID-Уровень", например, "TA-1"
	towerBuckets := make(map[string][]types.EntityID)
	for id, tower := range s.ecs.Towers {
		if tower.DefID == "TOWER_WALL" {
			continue
		}
		key := fmt.Sprintf("%s-%d", tower.DefID, tower.Level)
		towerBuckets[key] = append(towerBuckets[key], id)
	}

	// 3. Итерируем по всем рецептам
	for i := range defs.RecipeLibrary {
		recipe := &defs.RecipeLibrary[i]

		// 4. Собираем требования для текущего рецепта
		// Ключ - "ID-Уровень", значение - количество
		needed := make(map[string]int)
		for _, input := range recipe.Inputs {
			key := fmt.Sprintf("%s-%d", input.ID, input.Level)
			needed[key]++
		}

		// 5. Проверяем, достаточно ли у нас башен для этого рецепта
		hasEnoughIngredients := true
		for key, count := range needed {
			if len(towerBuckets[key]) < count {
				hasEnoughIngredients = false
				break
			}
		}

		if !hasEnoughIngredients {
			continue // Переходим к следующему рецепту
		}

		// 6. Если ингредиентов достаточно, находим все возможные комбинации
		s.findAndMarkCombinations(recipe, needed, towerBuckets)
	}
}

// findAndMarkCombinations находит все уникальные наборы башен, которые соответствуют рецепту.
func (s *CraftingSystem) findAndMarkCombinations(recipe *defs.Recipe, needed map[string]int, buckets map[string][]types.EntityID) {
	// Собираем список ключей (типов ингредиентов), чтобы итерировать в предсказуемом порядке
	neededKeys := make([]string, 0, len(needed))
	for key := range needed {
		neededKeys = append(neededKeys, key)
	}
	sort.Strings(neededKeys)

	// Карта для отслеживания уже найденных комбинаций, чтобы избежать дубликатов
	foundCombinations := make(map[string]bool)

	// Рекурсивная функция для поиска
	var find func(keyIndex int, currentCombination []types.EntityID)
	find = func(keyIndex int, currentCombination []types.EntityID) {
		// Базовый случай: мы нашли ингредиенты для всех типов
		if keyIndex == len(neededKeys) {
			// Сортируем ID в комбинации, чтобы ключ был консистентным
			sort.Slice(currentCombination, func(i, j int) bool { return currentCombination[i] < currentCombination[j] })
			key := combinationKey(currentCombination)

			if !foundCombinations[key] {
				foundCombinations[key] = true
				// Найдена новая уникальная комбинация!
				// Добавляем компонент Combinable всем участникам.
				craftInfo := component.CraftInfo{
					Recipe:      recipe,
					Combination: currentCombination,
				}
				for _, id := range currentCombination {
					if s.ecs.Combinables[id] == nil {
						s.ecs.Combinables[id] = &component.Combinable{}
					}
					s.ecs.Combinables[id].PossibleCrafts = append(s.ecs.Combinables[id].PossibleCrafts, craftInfo)
				}
			}
			return
		}

		// Рекурсивный шаг:
		ingredientKey := neededKeys[keyIndex]
		requiredCount := needed[ingredientKey]
		availableTowers := buckets[ingredientKey]

		// Генерируем все комбинации из `requiredCount` башен из `availableTowers`
		var generateTowerCombinations func(startIdx int, combinationPart []types.EntityID)
		generateTowerCombinations = func(startIdx int, combinationPart []types.EntityID) {
			if len(combinationPart) == requiredCount {
				// Мы собрали нужное количество башен для этого типа.
				// Переходим к следующему типу ингредиентов.
				newCombination := append([]types.EntityID{}, currentCombination...)
				newCombination = append(newCombination, combinationPart...)
				find(keyIndex+1, newCombination)
				return
			}

			// Не выходим за пределы среза
			if startIdx >= len(availableTowers) {
				return
			}

			for i := startIdx; i < len(availableTowers); i++ {
				// Добавляем башню и рекурсивно ищем дальше
				newPart := append(combinationPart, availableTowers[i])
				generateTowerCombinations(i+1, newPart)
			}
		}

		generateTowerCombinations(0, []types.EntityID{})
	}

	find(0, []types.EntityID{})
}

// combinationKey создает уникальный строковый ключ для комбинации ID.
func combinationKey(ids []types.EntityID) string {
	b := make([]byte, 0, len(ids)*4)
	for _, id := range ids {
		b = append(b, byte(id), byte(id>>8), byte(id>>16), byte(id>>24))
	}
	return string(b)
}
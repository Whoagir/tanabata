package system

import (
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/entity"
	"go-tower-defense/internal/event"
	"go-tower-defense/internal/types"
	"go-tower-defense/pkg/hexmap"
	"sort"
)

// CraftingSystem отвечает за обнаружение и выполнение рецептов крафта.
type CraftingSystem struct {
	ecs          *entity.ECS
	hexMap       *hexmap.HexMap
	recipeIndex  map[string][]*defs.Recipe
	towerBuckets map[string][]types.EntityID
}

func NewCraftingSystem(ecs *entity.ECS, hexMap *hexmap.HexMap) *CraftingSystem {
	s := &CraftingSystem{
		ecs:         ecs,
		hexMap:      hexMap,
		recipeIndex: make(map[string][]*defs.Recipe),
	}
	s.buildRecipeIndex()
	return s
}

// buildRecipeIndex создает инвертированный индекс для быстрого поиска рецептов.
func (s *CraftingSystem) buildRecipeIndex() {
	for i := range defs.RecipeLibrary {
		recipe := &defs.RecipeLibrary[i]
		for _, inputID := range recipe.InputIDs {
			s.recipeIndex[inputID] = append(s.recipeIndex[inputID], recipe)
		}
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
	s.ecs.Combinables = make(map[types.EntityID]*component.Combinable)
	s.towerBuckets = make(map[string][]types.EntityID)

	for id, tower := range s.ecs.Towers {
		if tower.DefID != "TOWER_WALL" {
			s.towerBuckets[tower.DefID] = append(s.towerBuckets[tower.DefID], id)
		}
	}

	// Используем карту для отслеживания уже найденных комбинаций, чтобы избежать дубликатов.
	// Ключ - отсортированная строка ID башен.
	foundCombinations := make(map[string]bool)

	for towerID, tower := range s.ecs.Towers {
		if tower.DefID == "TOWER_WALL" {
			continue
		}

		// Находим все рецепты, в которых участвует эта башня
		possibleRecipes := s.recipeIndex[tower.DefID]
		for _, recipe := range possibleRecipes {
			s.findCombinationsForRecipe(towerID, recipe, foundCombinations)
		}
	}
}

// findCombinationsForRecipe рекурсивно ищет все уникальные комбинации для данного рецепта,
// начиная с определенной башни.
func (s *CraftingSystem) findCombinationsForRecipe(startTowerID types.EntityID, recipe *defs.Recipe, found map[string]bool) {
	// Создаем копию карты доступных башен, чтобы не изменять оригинал во время рекурсии
	tempBuckets := make(map[string][]types.EntityID)
	for k, v := range s.towerBuckets {
		tempBuckets[k] = append([]types.EntityID{}, v...)
	}

	// Собираем необходимые ингредиенты для рецепта, исключая стартовую башню
	needed := make(map[string]int)
	for _, id := range recipe.InputIDs {
		needed[id]++
	}
	startTowerDefID := s.ecs.Towers[startTowerID].DefID
	needed[startTowerDefID]--
	if needed[startTowerDefID] == 0 {
		delete(needed, startTowerDefID)
	}

	// Удаляем стартовую башню из временного пула
	tempBuckets[startTowerDefID] = removeOnce(tempBuckets[startTowerDefID], startTowerID)

	// Рекурсивная функция для поиска комбинаций
	var find func(neededNow map[string]int, currentCombination []types.EntityID)
	find = func(neededNow map[string]int, currentCombination []types.EntityID) {
		if len(neededNow) == 0 {
			// Комбинация найдена
			finalCombination := append(currentCombination, startTowerID)
			sort.Slice(finalCombination, func(i, j int) bool { return finalCombination[i] < finalCombination[j] })

			// Проверяем на дубликат
			key := combinationKey(finalCombination)
			if !found[key] {
				found[key] = true
				// Добавляем Combinable компонент всем участникам
				craftInfo := component.CraftInfo{
					Recipe:      recipe,
					Combination: finalCombination,
				}
				for _, id := range finalCombination {
					if s.ecs.Combinables[id] == nil {
						s.ecs.Combinables[id] = &component.Combinable{}
					}
					s.ecs.Combinables[id].PossibleCrafts = append(s.ecs.Combinables[id].PossibleCrafts, craftInfo)
				}
			}
			return
		}

		// Берем следующий необходимый тип
		var nextDefID string
		for id := range neededNow {
			nextDefID = id
			break
		}

		// Пробуем каждую доступную башню это��о типа
		availableTowers := tempBuckets[nextDefID]
		if len(availableTowers) < neededNow[nextDefID] {
			return // Недостаточно башен этого типа
		}

		// Генерируем все комбинации для текущего типа башен
		towerIndices := make([]int, neededNow[nextDefID])
		var generateTowerCombinations func(startIdx, depth int)
		generateTowerCombinations = func(startIdx, depth int) {
			if depth == len(towerIndices) {
				// Собрали нужное количество башен этого типа
				newCombination := append([]types.EntityID{}, currentCombination...)
				newTempBuckets := make(map[string][]types.EntityID)
				for k, v := range tempBuckets {
					newTempBuckets[k] = append([]types.EntityID{}, v...)
				}

				usedTowers := []types.EntityID{}
				for _, idx := range towerIndices {
					towerID := availableTowers[idx]
					newCombination = append(newCombination, towerID)
					usedTowers = append(usedTowers, towerID)
				}

				// Удаляем использованные башни из временного пула
				for _, usedID := range usedTowers {
					newTempBuckets[nextDefID] = removeOnce(newTempBuckets[nextDefID], usedID)
				}

				newNeeded := make(map[string]int)
				for k, v := range neededNow {
					newNeeded[k] = v
				}
				delete(newNeeded, nextDefID)

				find(newNeeded, newCombination)
				return
			}

			for i := startIdx; i < len(availableTowers); i++ {
				towerIndices[depth] = i
				generateTowerCombinations(i+1, depth+1)
			}
		}
		generateTowerCombinations(0, 0)
	}

	find(needed, []types.EntityID{})
}

// removeOnce удаляет первое вхождение элемента из среза.
func removeOnce(slice []types.EntityID, element types.EntityID) []types.EntityID {
	for i, v := range slice {
		if v == element {
			return append(slice[:i], slice[i+1:]...)
		}
	}
	return slice
}

// combinationKey создает уникальный строковый ключ для комбинации ID.
func combinationKey(ids []types.EntityID) string {
	b := make([]byte, 0, len(ids)*4)
	for _, id := range ids {
		b = append(b, byte(id), byte(id>>8), byte(id>>16), byte(id>>24))
	}
	return string(b)
}

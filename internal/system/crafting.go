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
	ecs    *entity.ECS
	hexMap *hexmap.HexMap
}

// OnEvent обрабатывает события, на которые подписана система.
func (s *CraftingSystem) OnEvent(e event.Event) {
	switch e.Type {
	case event.TowerPlaced, event.TowerRemoved:
		s.RecalculateCombinations()
	}
}

func NewCraftingSystem(ecs *entity.ECS, hexMap *hexmap.HexMap) *CraftingSystem {
	return &CraftingSystem{ecs: ecs, hexMap: hexMap}
}

// RecalculateCombinations находит возможные комбинации для крафта по всей карте.
func (s *CraftingSystem) RecalculateCombinations() {
	// 1. Очищаем все существующие Combinable компоненты.
	s.ecs.Combinables = make(map[types.EntityID]*component.Combinable)

	// 2. Собираем все существующие башни и группируем их по типам.
	towersByType := make(map[string][]types.EntityID)
	for id, tower := range s.ecs.Towers {
		if tower.Type != -1 { // Игнорируем стены
			typeID := mapNumericTypeToTowerID(tower.Type)
			if typeID != "" {
				towersByType[typeID] = append(towersByType[typeID], id)
			}
		}
	}

	// 3. Проверяем каждый рецепт.
	for _, recipe := range defs.RecipeLibrary {
		canCraft := true
		var combination []types.EntityID

		// Проверяем, хватает ли у нас башен для каждого инпута в рецепте.
		for _, inputTypeID := range recipe.Inputs {
			if towers, ok := towersByType[inputTypeID]; ok && len(towers) > 0 {
				// Башни такого типа есть. Берем первую и удаляем из списка, чтобы не использовать ее дважды.
				combination = append(combination, towers[0])
				towersByType[inputTypeID] = towers[1:]
			} else {
				// Не хватает башен для рецепта.
				canCraft = false
				break
			}
		}

		// 4. Если можем скрафтить, помеч��ем все участвующие башни.
		if canCraft {
			combinable := &component.Combinable{
				RecipeOutputID: recipe.Output,
				Combination:    combination,
			}
			for _, towerID := range combination {
				s.ecs.Combinables[towerID] = combinable
			}
		}
	}
}

// checkCombination проверяет, соответствует ли группа из 3х башен какому-либо рецепту.
func (s *CraftingSystem) checkCombination(towerIDs []types.EntityID) {
	if len(towerIDs) != 3 {
		return
	}

	// Собираем ID типов башен из комбинации
	var typeIDs []string
	for _, id := range towerIDs {
		tower, ok := s.ecs.Towers[id]
		if !ok {
			return // Невалидная башня
		}
		// Используем существующий маппер для получения строкового ID
		typeID := mapNumericTypeToTowerID(tower.Type)
		if typeID == "" {
			return
		}
		typeIDs = append(typeIDs, typeID)
	}

	// Сортируем для консистентного сравнения
	sort.Strings(typeIDs)

	// Проверяем по библиотеке рецептов
	for _, recipe := range defs.RecipeLibrary {
		if len(recipe.Inputs) != 3 {
			continue
		}
		// Копируе�� и сортируем инпуты рецепта для сравнения
		recipeInputs := make([]string, len(recipe.Inputs))
		copy(recipeInputs, recipe.Inputs)
		sort.Strings(recipeInputs)

		// Сравниваем отсортированные срезы
		if equalSlices(typeIDs, recipeInputs) {
			// Найдено совпадение! Добавляем Combinable компонент всем трем башням.
			combinable := &component.Combinable{
				RecipeOutputID: recipe.Output,
				Combination:    towerIDs,
			}
			for _, id := range towerIDs {
				s.ecs.Combinables[id] = combinable
			}
			// Прерываемся, чтобы не проверять другие рецепты для этой же комбинации
			return
		}
	}
}

// equalSlices проверяет, равны ли два строковых среза.
func equalSlices(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
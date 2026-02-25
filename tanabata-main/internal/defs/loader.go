// internal/defs/loader.go
package defs

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// LoadAll загружает все файлы определений из указанной директории.
func LoadAll(dataDir string) error {
	if err := LoadTowerDefinitions(filepath.Join(dataDir, "towers.json")); err != nil {
		return fmt.Errorf("failed to load tower definitions: %w", err)
	}
	if err := LoadEnemyDefinitions(filepath.Join(dataDir, "enemies.json")); err != nil {
		return fmt.Errorf("failed to load enemy definitions: %w", err)
	}
	if err := LoadRecipes(filepath.Join(dataDir, "recipes.json")); err != nil {
		return fmt.Errorf("failed to load recipes: %w", err)
	}
	if err := LoadLootTables(filepath.Join(dataDir, "loot_tables.json")); err != nil {
		return fmt.Errorf("failed to load loot tables: %w", err)
	}
	// Загрузка волн может быть добавлена сюда же, если потребуется
	// if err := LoadWaves(filepath.Join(dataDir, "waves.json")); err != nil {
	// 	return fmt.Errorf("failed to load waves: %w", err)
	// }
	return nil
}


// LoadTowerDefinitions загружает определения башен из JSON-файла.
func LoadTowerDefinitions(filename string) error {
	file, err := os.ReadFile(filename)
	if err != nil {
		return err
	}

	var towers []TowerDefinition
	if err := json.Unmarshal(file, &towers); err != nil {
		return err
	}

	TowerDefs = make(map[string]TowerDefinition)
	for _, tower := range towers {
		TowerDefs[tower.ID] = tower
	}
	return nil
}

// LoadEnemyDefinitions загружает определения врагов из JSON-файла.
func LoadEnemyDefinitions(filename string) error {
	file, err := os.ReadFile(filename)
	if err != nil {
		return err
	}

	var enemies []EnemyDefinition
	if err := json.Unmarshal(file, &enemies); err != nil {
		return err
	}

	EnemyDefs = make(map[string]EnemyDefinition)
	for _, enemy := range enemies {
		EnemyDefs[enemy.ID] = enemy
	}
	return nil
}

// LoadRecipes загружает рецепты крафта из JSON-файла.
func LoadRecipes(filename string) error {
	file, err := os.ReadFile(filename)
	if err != nil {
		return err
	}

	var recipes []*Recipe
	if err := json.Unmarshal(file, &recipes); err != nil {
		return err
	}

	RecipeLibrary = &CraftingRecipeLibrary{Recipes: recipes}
	return nil
}

// LoadLootTables загружает таблицы лута из JSON-файла.
func LoadLootTables(filename string) error {
	file, err := os.ReadFile(filename)
	if err != nil {
		return err
	}

	var tables []LootTable
	if err := json.Unmarshal(file, &tables); err != nil {
		return err
	}

	LootTablesByLevel = make(map[int]*LootTable)
	for i := range tables {
		table := &tables[i]
		table.prepare()
		LootTablesByLevel[table.PlayerLevel] = table
	}
	return nil
}
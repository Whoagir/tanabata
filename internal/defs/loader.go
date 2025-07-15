// internal/defs/loader.go
package defs

import (
	"encoding/json"
	"fmt"
	"os"
)

// TowerLibrary is a map to hold all tower definitions, keyed by their ID.
var TowerLibrary map[string]TowerDefinition

// EnemyLibrary is a map to hold all enemy definitions, keyed by their ID.
var EnemyLibrary map[string]EnemyDefinition

// LoadTowerDefinitions reads the tower configuration file and populates the TowerLibrary.
func LoadTowerDefinitions(path string) error {
	file, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("failed to read tower definitions file: %w", err)
	}

	var towerDefs []TowerDefinition
	if err := json.Unmarshal(file, &towerDefs); err != nil {
		return fmt.Errorf("failed to unmarshal tower definitions: %w", err)
	}

	TowerLibrary = make(map[string]TowerDefinition)
	for _, def := range towerDefs {
		TowerLibrary[def.ID] = def
	}

	fmt.Printf("Loaded %d tower definitions\n", len(TowerLibrary))
	return nil
}

// LoadEnemyDefinitions reads the enemy configuration file and populates the EnemyLibrary.
func LoadEnemyDefinitions(path string) error {
	file, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("failed to read enemy definitions file: %w", err)
	}

	var enemyDefs []EnemyDefinition
	if err := json.Unmarshal(file, &enemyDefs); err != nil {
		return fmt.Errorf("failed to unmarshal enemy definitions: %w", err)
	}

	EnemyLibrary = make(map[string]EnemyDefinition)
	for _, def := range enemyDefs {
		EnemyLibrary[def.ID] = def
	}

	fmt.Printf("Loaded %d enemy definitions\n", len(EnemyLibrary))
	return nil
}


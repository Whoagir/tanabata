// internal/defs/loot_tables.go
package defs

// LootEntry представляет одну запись в таблице выпадения.
// TowerID - это ID башни, а Weight - ее "вес" или относительный шанс выпадения.
type LootEntry struct {
	TowerID string `json:"tower_id"`
	Weight  int    `json:"weight"`
}

// LootTable определяет полный список возможных башен для выпадения
// на определенном уровне игрока.
type LootTable struct {
	PlayerLevel int         `json:"player_level"`
	Entries     []LootEntry `json:"entries"`
	totalWeight int
}

// prepare вычисляет общий вес всех записей в таблице.
// Это нужно для оптимизации процесса случайного выбора.
func (lt *LootTable) prepare() {
	lt.totalWeight = 0
	for _, entry := range lt.Entries {
		lt.totalWeight += entry.Weight
	}
}

// LootTablesByLevel is the library of all loot tables, mapped by player level.
var LootTablesByLevel map[int]*LootTable

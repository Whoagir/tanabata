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
}

// internal/event/types.go
package event

const (
	WaveEnded      EventType = "WaveEnded"      // Волна закончилась
	TowerPlaced    EventType = "TowerPlaced"    // Башня построена
	EnemyDestroyed EventType = "EnemyDestroyed" // Враг уничтожен
	TowerRemoved   EventType = "TowerRemoved"
	OreDepleted    EventType = "OreDepleted"    // Руда истощена
)

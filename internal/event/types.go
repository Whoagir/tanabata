// internal/event/types.go
package event

const (
	WaveEnded                        EventType = "WaveEnded"      // Волна закончилась
	TowerPlaced                      EventType = "TowerPlaced"    // Башня построена
	EnemyRemovedFromGame             EventType = "EnemyRemovedFromGame" // Враг удален из игры (очистка)
	EnemyKilled                      EventType = "EnemyKilled"    // Враг убит (для игровой логики)
	TowerRemoved                     EventType = "TowerRemoved"
	OreDepleted                      EventType = "OreDepleted" // Руда истощена
	OreConsumed                      EventType = "OreConsumed" // Руда потрачена (например, на выстрел)
	BuildPhaseStarted                EventType = "BuildPhaseStarted"
	WavePhaseStarted                 EventType = "WavePhaseStarted"
	CombineTowersRequest             EventType = "CombineTowersRequest" // Запрос на объединение башен
	ToggleTowerSelectionForSaveRequest EventType = "ToggleTowerSelectionForSaveRequest" // Запрос на изменение выбора башни для сохранения
)

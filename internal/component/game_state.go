package component

type GamePhase int

const (
	BuildState GamePhase = iota
	WaveState
	TowerSelectionState
)

// GameState — компонент для хранения состояния игры
type GameState struct {
	Phase        GamePhase
	TowersToKeep int
}

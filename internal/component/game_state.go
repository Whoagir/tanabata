package component

// GameState — компонент для хранения состояния игры
type GameState int

const (
	BuildState GameState = iota
	WaveState
)

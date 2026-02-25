// internal/system/game_context.go
package interfaces

type GameContext interface {
	ClearEnemies()
	ClearProjectiles()
	StartWave()
	SetTowersBuilt(count int)
	GetTowersBuilt() int
}

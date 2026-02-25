package interfaces

type Game interface {
	ClearEnemies()
	ClearProjectiles()
	StartWave()
	ClearAllSelections()
}

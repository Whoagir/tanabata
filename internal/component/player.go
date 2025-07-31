// internal/component/player.go
package component

// PlayerStateComponent хранит информацию, специфичную для игрока,
// такую как его текущий уровень и опыт.
type PlayerStateComponent struct {
	Level         int // Текущий уровень игрока
	CurrentXP     int // Текущее количество очков опыта
	XPToNextLevel int // Количество опыта, необходимое для следующего уровня
}

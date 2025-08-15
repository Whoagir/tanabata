package component

// Enemy представляет вражескую сущность.
type Enemy struct {
	DefID               string  // ID из enemies.json
	OreDamageCooldown   float64 // Таймер для получения урона от руды
	LineDamageCooldown  float64 // Таймер для получения урона от линий
	PhysicalArmor       int
	MagicalArmor        int
	Damage              int     // Урон, который нанесет враг
	LastCheckpointIndex int     // Индекс последнего пройденного чекпоинта
	ReachedEnd          bool    // Достиг ли враг конца пути
}
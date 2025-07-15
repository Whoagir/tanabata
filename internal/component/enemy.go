package component

// Enemy представляет вражескую сущность.
type Enemy struct {
	OreDamageCooldown  float64 // Таймер для получения урона от руды
	LineDamageCooldown float64 // Таймер для получения урона от линий
	PhysicalArmor      int
	MagicalArmor       int
}
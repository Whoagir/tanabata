package component

// Health — компонент здоровья
type Health struct {
	Value int
}

// Combat — компонент для башен, управляющий атакой
type Combat struct {
	FireRate     float64 // Скорострельность (выстрелов в секунду)
	FireCooldown float64 // Оставшееся время до следующего выстрела
	Range        int     // Радиус действия (в гексах)
}

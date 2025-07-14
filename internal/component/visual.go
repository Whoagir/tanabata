// internal/component/visual.go
package component

// DamageFlash указывает, что сущность должна быть отрисована цветом урона.
type DamageFlash struct {
	Timer    float64 // Сколько времени эффект уже активен
	Duration float64 // Общая продолжительность эффекта
}

// internal/component/volcano.go
package component

// VolcanoAura представляет собой компонент для башни "Вулкан",
// который управляет ее уникальной механикой урона по области.
type VolcanoAura struct {
	// TickTimer отсчитывает время до следующего срабатывания ауры урона.
	TickTimer float64
}

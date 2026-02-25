// internal/component/wave.go
package component

import "go-tower-defense/pkg/hexmap"

// Wave — компонент для волны врагов
type Wave struct {
	Number         int          // Номер волны
	EnemiesToSpawn int          // Сколько врагов осталось спавнить
	SpawnTimer     float64      // Таймер спавна
	SpawnInterval  float64      // Интервал между спавнами (в секундах)
	CurrentPath    []hexmap.Hex // Текущий путь для врагов
	EnemyID        string       // ID врага для этой волны
	DamagePerEnemy []int        // Урон для каждого врага в волне
}

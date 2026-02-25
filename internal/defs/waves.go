package defs

import "time"

// WaveDefinition описывает параметры для одной волны врагов.
type WaveDefinition struct {
	EnemyID       string          // Идентификатор врага из enemies.json
	Count         int             // Количество врагов в волне
	SpawnInterval time.Duration   // Интервал между появлением врагов
}

// WavePatterns определяет последовательность волн в игре.
// Ключ карты - это номер волны.
var WavePatterns = map[int]WaveDefinition{
	1:  {EnemyID: "ENEMY_NORMAL_WEAK", Count: 5, SpawnInterval: time.Millisecond * 800},
	2:  {EnemyID: "ENEMY_NORMAL_WEAK", Count: 7, SpawnInterval: time.Millisecond * 800},
	3:  {EnemyID: "ENEMY_NORMAL_WEAK", Count: 9, SpawnInterval: time.Millisecond * 800},
	4:  {EnemyID: "ENEMY_TOUGH", Count: 7, SpawnInterval: time.Second * 1},
	5:  {EnemyID: "ENEMY_NORMAL", Count: 10, SpawnInterval: time.Millisecond * 800},
	6:  {EnemyID: "ENEMY_MAGIC_RESIST", Count: 10, SpawnInterval: time.Millisecond * 750},
	7:  {EnemyID: "ENEMY_PHYSICAL_RESIST", Count: 10, SpawnInterval: time.Millisecond * 750},
	8:  {EnemyID: "ENEMY_FAST", Count: 15, SpawnInterval: time.Millisecond * 500},
	9:  {EnemyID: "ENEMY_NORMAL", Count: 20, SpawnInterval: time.Millisecond * 400},
	10: {EnemyID: "ENEMY_BOSS", Count: 1, SpawnInterval: time.Second * 1},
}

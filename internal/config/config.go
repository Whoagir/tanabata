// internal/config/config.go
package config

import "image/color"

const (
	ScreenWidth           = 1200
	ScreenHeight          = 900
	HexSize               = 19.0 // test
	MapRadius             = 13   // test
	BuildPhaseDuration    = 30.0
	BaseHealth            = 100
	EnemiesPerWave        = 5
	DamagePerEnemy        = 10
	ClickCooldown         = 300
	MaxTowersInBuildPhase = 5
	MaxDeltaTime          = 0.06
	ClickDebounceTime     = 100
	IndicatorOffsetX      = 30
	IndicatorRadius       = 10.0

	InitialSpawnInterval    = 500
	MinSpawnInterval        = 100
	SpawnIntervalDecrement  = 20
	EnemiesIncrementPerWave = 2

	EnemySpeed  = 80.0
	EnemyHealth = 100
	EnemyRadius = 10.0

	TowerRange        = 3
	TowerRadiusFactor = 0.3
	TowerStrokeWidth  = 2.0

	TextCharWidth = 7
	TextOffsetY   = 4

	ProjectileSpeed  = 200.0 // pixels per second
	ProjectileRadius = 5.0   // pixels

	SpeedButtonOffsetX = 80   // Отступ слева от края индикатора
	SpeedButtonY       = 30   // Позиция по Y
	SpeedButtonSize    = 18.0 // Размер кнопки (радиус или ширина, в зависимости от реализации ui.SpeedButton)

	EnergyTransferRadius = 3
	TowerShotCost        = 0.2 // Стоимость одного выстрела
)

const (
	TowerTypeRed = iota
	TowerTypeGreen
	TowerTypeBlue
	TowerTypePurple
	TowerTypeMiner // Новый тип для добытчика
	TowerTypeWall  = -1
)

var (
	BackgroundColor  = color.RGBA{20, 20, 30, 255}
	PassableColor    = color.RGBA{70, 100, 120, 220}
	ImpassableColor  = color.RGBA{150, 70, 70, 220}
	EntryColor       = color.RGBA{0, 255, 0, 255}
	ExitColor        = color.RGBA{255, 0, 0, 255}
	TextLightColor   = color.RGBA{240, 240, 240, 255}
	TextDarkColor    = color.RGBA{20, 20, 30, 255}
	BuildStateColor  = color.RGBA{70, 130, 180, 220}
	WaveStateColor   = color.RGBA{220, 60, 60, 220}
	IndicatorStroke  = color.RGBA{240, 240, 240, 255}
	BaseColor        = color.RGBA{50, 205, 50, 255}
	EnemyColor       = color.RGBA{0, 0, 0, 255}
	TowerStrokeColor = color.RGBA{255, 255, 255, 255}
	LineColor        = color.RGBA{255, 255, 0, 128}
	StrokeWidth      = 2.0
	TowerColors      = []color.RGBA{
		{255, 50, 50, 255},   // Red
		{50, 255, 50, 255},   // Green
		{50, 100, 255, 255},  // Blue
		{180, 50, 230, 255},  // Purple
		{255, 215, 0, 255},   // Gold (жёлтый) для добытчика
		{128, 128, 128, 255}, // Серый цвет для стен
	}
	SpeedButtonColors = []color.Color{
		color.RGBA{70, 130, 180, 220},  // Серый для скорости x1
		color.RGBA{220, 60, 60, 220},   // Оранжевый для скорости x2
		color.RGBA{194, 178, 128, 255}, // x4, песочно-жёлтый
	}
	TowerFireRate = []float64{1.0, 1.5, 2.0, 0.5} // Выстрелов в секунду для каждого типа
	TowerDamage   = []int{10, 15, 20, 5}          // Урон для каждого типа
)

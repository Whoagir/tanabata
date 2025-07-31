// internal/config/config.go
package config

import "image/color"

const (
	ScreenWidth           = 1200
	ScreenHeight          = 993
	MapCenterOffsetY      = -57 // Смещение центра карты вверх
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

	TowerRange        = 3
	TowerRadiusFactor = 0.3
	TowerStrokeWidth  = 2.0

	TextCharWidth = 7
	TextOffsetY   = 4

	ProjectileSpeed  = 200.0 // pixels per second
	ProjectileRadius = 5.0   // pixels

	SpeedButtonOffsetX = 80   // Отступ слева от края индикатора
	SpeedButtonY       = 30   // Позиция по Y
	SpeedButtonSize    = 18.0 // Размер кнопки (радиус или ��ирина, в зависимости от реализации ui.SpeedButton)

	EnergyTransferRadius     = 3
	OrePerHexMin             = 15
	OrePerHexMax             = 75
	OreDamagePerSecond       = 10.0 // Базовый урон от руды в секунду
	OreDamageTicksPerSecond  = 8.0  // Количество тиков урона в секунду
	LineDamagePerSecond      = 10.0 // Урон от линии в секунду
	LineDamageTicksPerSecond = 8.0  // Количество тиков урона от линии в секунду
	DamageFlashDuration      = 0.2  // Длительность "вспышки" урона в секундах
	OreDepletionThreshold    = 0.1  // Порог, при котором руда считается истощенной

	// Бонусы к урону от руды
	OreBonusLowThreshold  = 10.0 // Нижний порог запаса руды для макс бонуса
	OreBonusHighThreshold = 75.0 // Верхний порог запаса руды для мин бонуса
	OreBonusMaxMultiplier = 1.5  // Максимальный множитель урона
	OreBonusMinMultiplier = 0.5  // Минимальный множитель урона
	LineDegradationFactor = 0.6  // Коэффициент снижения урона за каждую башню типа А в цепи
)

var (
	BackgroundColor   = color.RGBA{20, 20, 30, 255}
	PassableColor     = color.RGBA{70, 100, 120, 220}
	ImpassableColor   = color.RGBA{150, 70, 70, 220}
	EntryColor        = color.RGBA{0, 255, 0, 255}
	ExitColor         = color.RGBA{255, 0, 0, 255}
	TextLightColor    = color.RGBA{240, 240, 240, 255}
	TextDarkColor     = color.RGBA{20, 20, 30, 255}
	BuildStateColor   = color.RGBA{70, 130, 180, 220}
	WaveStateColor    = color.RGBA{220, 60, 60, 220}
	SelectionStateColor = color.RGBA{255, 215, 0, 255} // Золотой/желтый для выбора
	IndicatorStroke   = color.RGBA{240, 240, 240, 255}
	BaseColor         = color.RGBA{50, 205, 50, 255}
	EnemyColor        = color.RGBA{0, 0, 0, 255}
	EnemyDamageColor  = color.RGBA{255, 0, 0, 255} // Цвет врага при получении урона
	TowerStrokeColor  = color.RGBA{255, 255, 255, 255}
	TowerAStrokeColor = color.RGBA{255, 80, 80, 255} // Ярко-красный для типа A
	TowerBStrokeColor = color.RGBA{255, 255, 0, 255} // Желтый для типа B
	LineColor         = color.RGBA{255, 195, 0, 150}   // Насыщенный золотой для сети
	StrokeWidth       = 2.0
	SpeedButtonColors = []color.Color{
		color.RGBA{70, 130, 180, 220},
		color.RGBA{220, 60, 60, 220},
		color.RGBA{194, 178, 128, 255},
	}
	// Новая палитра для снарядов
	ProjectileColorPhysical = color.RGBA{255, 100, 0, 255}   // Яркий оранжевый
	ProjectileColorMagical  = color.RGBA{220, 50, 220, 255}   // Яркий пурпурный
	ProjectileColorPure     = color.RGBA{180, 240, 255, 255} // Светло-голубой
	ProjectileColorSlow     = color.RGBA{173, 216, 230, 255} // Ледяной синий
	ProjectileColorPoison   = color.RGBA{124, 252, 0, 255}   // Ядовито-салатовый
	HighlightColor          = color.RGBA{135, 206, 250, 120} // Полупрозрачный светло-голубой для подсветки
)
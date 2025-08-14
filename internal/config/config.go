// internal/config/config.go
package config

import (
	"image/color"

	rl "github.com/gen2brain/raylib-go/raylib"
)

const (
	// ScreenWidth ширина экрана
	ScreenWidth = 1200
	// ScreenHeight высота экрана
	ScreenHeight = 993
	// HexSize размер гекса в пикселях
	HexSize = 20.0
	// CoordScale масштабирует мировые координаты для рендеринга
	CoordScale = 0.25
	// MaxDeltaTime максимальное время кадра для предотвращения спирали смерти
	MaxDeltaTime = 0.05
	GridWidth       = 40   // Из нового (новая константа)
	GridHeight      = 30   // Из нового (новая константа)
	TowerBuildLimit = 2    // Из нового (аналог MaxTowersInBuildPhase)
	MapRadius       = 15   // Из нового; в старом 13

	// Добавлено из старого
	BuildPhaseDuration      = 30.0
	BaseHealth              = 100
	EnemiesPerWave          = 5
	DamagePerEnemy          = 10
	ClickCooldown           = 300
	MaxTowersInBuildPhase   = 5 // Аналог TowerBuildLimit, но добавил для совместимости
	ClickDebounceTime       = 100
	IndicatorOffsetX        = 30
	IndicatorRadius         = 10.0
	InitialSpawnInterval    = 500
	MinSpawnInterval        = 100
	SpawnIntervalDecrement  = 20
	EnemiesIncrementPerWave = 2
	TowerRange              = 3
	TowerRadiusFactor       = 0.3
	TowerStrokeWidth        = 2.0
	SpeedButtonOffsetX      = 80
	SpeedButtonY            = 30
	SpeedButtonSize         = 18.0
	EnergyTransferRadius    = 3
	OrePerHexMin            = 15
	OrePerHexMax            = 75
	LineHeight              = 5.0 // Высота линии энергии

	// Новые константы для управления камерой
	CameraZoomStep    = 5.0 // Шаг приближения/отдаления
	CameraFovyDefault = 45.0 // Угол обзора по умолчанию
	CameraFovyMin     = 10.0  // Минимальный угол обзора (максимальный зум)
	CameraFovyMax     = 120.0 // Максимальный угол обзора (минимальный зум)

	// Новые константы для ортографической камеры
	CameraOrthoFovyDefault = 160.0 // Начальный "зум" для орто-режима
	CameraOrthoFovyMin     = 40.0  // Минимальный "зум"
	CameraOrthoFovyMax     = 240.0 // Максимальный "зум"
	CameraOrthoZoomStep    = 10.0  // Шаг "зума" для орто-режима

	UIBorderWidth = 2.0 // Ширина обводки для элементов UI
)

// Цвета для Ebiten (останутся для справки или если где-то еще используются)
var (
	BackgroundColor       = color.RGBA{R: 30, G: 30, B: 30, A: 255}
	GridColor             = color.RGBA{R: 50, G: 50, B: 50, A: 255}
	HighlightColor        = color.RGBA{R: 255, G: 255, B: 0, A: 100}
	TextLightColor        = color.White
	TextDarkColor         = color.Black
	InfoPanelBgColor      = color.RGBA{R: 40, G: 40, B: 40, A: 220}
	ButtonIdleColor       = color.RGBA{R: 70, G: 70, B: 70, A: 255}
	ButtonHoverColor      = color.RGBA{R: 100, G: 100, B: 100, A: 255}
	ButtonClickColor      = color.RGBA{R: 130, G: 130, B: 130, A: 255}
)

// --- Новые цвета и константы для Raylib ---
var (
	// Основная палитра UI (приглушенные цвета)
	UIColorBlue   = rl.NewColor(44, 85, 119, 255)   // Приглушенный синий
	UIColorRed    = rl.NewColor(169, 68, 66, 255)   // Приглушенный красный
	UIColorYellow = rl.NewColor(204, 146, 67, 255)  // Приглушенный желтый/оранжевый
	UIBorderColor = rl.NewColor(220, 220, 220, 220) // Слегка прозрачный белый

	// Цвета состояний из основной палитры
	BuildStateColor       = UIColorBlue
	WaveStateColor        = UIColorRed
	SelectionStateColor   = UIColorYellow
	PauseButtonPlayColor  = UIColorBlue
	PauseButtonPauseColor = UIColorRed
	UIndicatorActiveColor = UIColorRed
	UIndicatorInactiveColor = UIColorBlue

	// Цве��а для кнопки скорости
	SpeedButtonColorsRL = []rl.Color{
		UIColorBlue,
		UIColorRed,
		UIColorYellow,
	}

	// Остальные цвета UI
	InfoPanelBgColorRL          = rl.NewColor(40, 40, 40, 230)
	InfoPanelBorderColorRL      = rl.Gray
	WaveIndicatorColorRL        = rl.LightGray
	XpBarBackgroundColorRL      = rl.DarkGray
	XpBarForegroundColorRL      = rl.NewColor(77, 144, 77, 255) // Приглушенный зеленый
	XpBarBorderColorRL          = rl.Gray
	PlayerLevelTextColorRL      = rl.White
	PlayerXpTextColorRL         = rl.White
	RecipeBookBackgroundColorRL = rl.NewColor(20, 20, 30, 245)
	RecipeBookBorderColorRL     = rl.Gray
	RecipeTitleColorRL          = rl.NewColor(255, 215, 0, 220) // Слегка приглушенное золото
	RecipeDefaultColorRL        = rl.Gray
	RecipeCanCraftColorRL       = rl.LightGray
	CombineButtonColorRL        = UIColorBlue
	SelectButtonColorRL         = rl.NewColor(77, 144, 77, 255)
	SelectButtonActiveColorRL   = UIColorYellow
	UIndicatorStrikethroughColorRL = rl.NewColor(255, 255, 255, 150)

	// Цвета для нового индикатора руды
	OreIndicatorFullColor     = rl.NewColor(70, 130, 180, 220) // Насыщенный синий
	OreIndicatorEmptyColor    = rl.NewColor(0, 0, 0, 0)       // Полностью прозрачный
	OreIndicatorWarningColor  = rl.NewColor(217, 83, 79, 220)  // Насыщенный красный
	OreIndicatorCriticalColor = rl.NewColor(240, 173, 78, 220) // Насыщенный желтый/оранжевый
	OreIndicatorDepletedColor = rl.NewColor(10, 10, 10, 220)   // Очень темный серый (почти черный)

	// --- Игровые цвета (НЕ ТРОГАТЬ) ---
	BackgroundColorRL           = rl.NewColor(30, 30, 30, 255)
	GridColorRL                 = rl.NewColor(50, 50, 50, 255)
	HighlightColorRL            = rl.NewColor(255, 255, 0, 100)
	TextLightColorRL            = rl.White
	TextDarkColorRL             = rl.Black
	CheckpointColorRL           = rl.NewColor(255, 215, 0, 255)
	OreHexBackgroundColorRL     = rl.NewColor(45, 45, 45, 255)
	StrokeColorRL               = rl.NewColor(100, 100, 100, 255)

	// Цвета снарядов
	ProjectileColorPhysicalRL = rl.NewColor(255, 100, 0, 255)
	ProjectileColorMagicalRL  = rl.NewColor(220, 50, 220, 255)
	ProjectileColorPureRL     = rl.NewColor(180, 240, 255, 255)
	ProjectileColorSlowRL     = rl.NewColor(173, 216, 230, 255)
	ProjectileColorPoisonRL   = rl.NewColor(124, 252, 0, 255)

	// Цвета сущностей
	OreColorRL         = rl.NewColor(70, 130, 180, 128)
	EnemyDamageColorRL = rl.White
	TowerWireColorRL   = rl.NewColor(80, 80, 80, 255)

	// Старые цвета (адаптированные)
	PassableColorRL       = rl.NewColor(70, 100, 120, 220)
	ImpassableColorRL     = rl.NewColor(150, 70, 70, 220)
	EntryColorRL          = rl.NewColor(0, 255, 0, 255)
	ExitColorRL           = rl.NewColor(255, 0, 0, 255)
	IndicatorStrokeRL     = rl.NewColor(240, 240, 240, 255)
	BaseColorRL           = rl.NewColor(50, 205, 50, 255)
	EnemyColorRL          = rl.NewColor(0, 0, 0, 255)
	TowerStrokeColorRL    = rl.NewColor(255, 255, 255, 255)
	TowerAStrokeColorRL   = rl.NewColor(255, 80, 80, 255)
	TowerBStrokeColorRL   = rl.NewColor(255, 255, 0, 255)
	LineColorRL           = rl.NewColor(255, 195, 0, 150)
)

const (
	MapCenterOffsetY = -50 // Из нового; в старом -57

	// Боевые параметры (из нового + добавлено из старого)
	ProjectileSpeed       = 200.0  // Из нового; в старом 200.0
	ProjectileRadius      = 5.0    // Из нового и старого
	OreBonusLowThreshold  = 100.0  // Из нового; в старом 10.0
	OreBonusHighThreshold = 1000.0 // Из нового; в старом 75.0
	OreBonusMaxMultiplier = 1.5    // Из нового и старого
	OreBonusMinMultiplier = 0.75   // Из нового; в старом 0.5
	LineDegradationFactor = 0.9    // Из нового; в старом 0.6

	// Шрифты (из нового)
	TitleFontSizeRL         = 40
	RegularFontSizeRL       = 20
	WaveIndicatorFontSizeRL = 24
	PlayerLevelFontSizeRL   = 18
	PlayerXpFontSizeRL      = 16
	RecipeTitleFontSizeRL   = 22
	RecipeEntryFontSizeRL   = 18
	RecipeHeaderHeightRL    = 40
	RecipeEntryHeightRL     = 25
	RecipePaddingRL         = 10

	// Параметры урона от окружения (из нового + добавлено/обновлено из старого)
	OreDamagePerSecond       = 5.0  // Из нового; в старом 10.0
	OreDamageTicksPerSecond  = 2.0  // Из нового; в старом 8.0
	LineDamagePerSecond      = 10.0 // Из нового и старого
	LineDamageTicksPerSecond = 5.0  // Из нового; в старом 8.0

	// Параметры руды (из нового + добавлено из старого)
	OreDepletionThreshold = 0.1 // Из нового и старого

	// Параметры текста (из нового + добавлено из старого)
	TextCharWidth = 10.0 // Из нового; в старом 7
	TextOffsetY   = 5.0  // Из нового; в старом 4

	// Параметры игрока (из нового + добавлено из старого)
	XPPerKill = 10 // Из нового; в старом 7

	// Визуальные эффекты (из нового + добавлено из старого)
	DamageFlashDuration = 0.2 // Из нового и старого
)

// CalculateXPForNextLevel рассчитывает, сколько опыта нужно для достижения следующего уровня.
func CalculateXPForNextLevel(level int) int {
	// Формула из нового: 100 для первого уровня, +50 за каждый последующий
	// (Если нужно старую: return 75 + (level * 25))
	return 100 + (level-1)*50
}
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
)

// Цвета для Ebiten (останутся для справки или если где-то еще используются)
var (
	BackgroundColor       = color.RGBA{R: 30, G: 30, B: 30, A: 255}
	GridColor             = color.RGBA{R: 50, G: 50, B: 50, A: 255}
	BuildStateColor       = color.RGBA{R: 0, G: 255, B: 0, A: 255}
	WaveStateColor        = color.RGBA{R: 255, G: 0, B: 0, A: 255}
	SelectionStateColor   = color.RGBA{R: 255, G: 255, B: 0, A: 255}
	HighlightColor        = color.RGBA{R: 255, G: 255, B: 0, A: 100}
	TextLightColor        = color.White
	TextDarkColor         = color.Black
	InfoPanelBgColor      = color.RGBA{R: 40, G: 40, B: 40, A: 220}
	ButtonIdleColor       = color.RGBA{R: 70, G: 70, B: 70, A: 255}
	ButtonHoverColor      = color.RGBA{R: 100, G: 100, B: 100, A: 255}
	ButtonClickColor      = color.RGBA{R: 130, G: 130, B: 130, A: 255}
	SpeedButtonPlayColor  = color.RGBA{R: 0, G: 150, B: 255, A: 255}
	SpeedButtonFastColor  = color.RGBA{R: 255, G: 165, B: 0, A: 255}
	SpeedButtonSuperColor = color.RGBA{R: 255, G: 69, B: 0, A: 255}
	PauseButtonPlayColor  = color.RGBA{R: 0, G: 200, B: 0, A: 255}
	PauseButtonPauseColor = color.RGBA{R: 255, G: 200, B: 0, A: 255}
)

// --- Новые цвета и константы для Raylib ---
var (
	BackgroundColorRL           = rl.NewColor(30, 30, 30, 255)
	GridColorRL                 = rl.NewColor(50, 50, 50, 255)
	HighlightColorRL            = rl.NewColor(255, 255, 0, 100)
	TextLightColorRL            = rl.White
	TextDarkColorRL             = rl.Black
	InfoPanelBgColorRL          = rl.NewColor(40, 40, 40, 220)
	ButtonIdleColorRL           = rl.NewColor(70, 70, 70, 255)
	ButtonHoverColorRL          = rl.NewColor(100, 100, 100, 255)
	ButtonClickColorRL          = rl.NewColor(130, 130, 130, 255)
	SpeedButtonPlayColorRL      = rl.NewColor(0, 150, 255, 255)
	SpeedButtonFastColorRL      = rl.NewColor(255, 165, 0, 255)
	SpeedButtonSuperColorRL     = rl.NewColor(255, 69, 0, 255)
	PauseButtonPlayColorRL      = rl.NewColor(0, 200, 0, 255)
	PauseButtonPauseColorRL     = rl.NewColor(255, 200, 0, 255)
	WaveIndicatorColorRL        = rl.White
	XpBarBackgroundColorRL      = rl.DarkGray
	XpBarForegroundColorRL      = rl.Green
	XpBarBorderColorRL          = rl.LightGray
	PlayerLevelTextColorRL      = rl.White
	PlayerXpTextColorRL         = rl.White
	RecipeBookBackgroundColorRL = rl.NewColor(20, 20, 30, 240)
	RecipeBookBorderColorRL     = rl.LightGray
	RecipeTitleColorRL          = rl.Gold
	RecipeDefaultColorRL        = rl.Gray
	RecipeCanCraftColorRL       = rl.White
	InfoPanelBorderColorRL      = rl.LightGray
	CheckpointColorRL           = rl.NewColor(255, 215, 0, 255) // Золотой для чекпоинтов
	OreHexBackgroundColorRL     = rl.NewColor(45, 45, 45, 255)   // Темно-серый для фона гекса с рудой
	StrokeColorRL               = rl.NewColor(100, 100, 100, 255) // Цвет обводки гексов
	CombineButtonColorRL        = rl.NewColor(0, 121, 241, 255) // Синий
	SelectButtonColorRL         = rl.NewColor(40, 167, 69, 255) // Зеленый
	SelectButtonActiveColorRL   = rl.NewColor(255, 193, 7, 255) // Желтый

	// Цвета снарядов (из нового + добавлено из старого, если нужно)
	ProjectileColorPhysicalRL = rl.NewColor(255, 100, 0, 255)   // Яркий оранжевый
	ProjectileColorMagicalRL  = rl.NewColor(220, 50, 220, 255)  // Яркий пурпурный
	ProjectileColorPureRL     = rl.NewColor(180, 240, 255, 255) // Светло-голубой
	ProjectileColorSlowRL     = rl.NewColor(173, 216, 230, 255) // Ледяной синий
	ProjectileColorPoisonRL   = rl.NewColor(124, 252, 0, 255)   // Ядовито-салатовый

	// Цвета сущностей (из нового + добавлено из старого)
	OreColorRL         = rl.NewColor(70, 130, 180, 128) // Более темный синий для руды
	EnemyDamageColorRL = rl.White                        // Белый для вспышки урона
	TowerWireColorRL   = rl.NewColor(80, 80, 80, 255)    // Темно-серый для обводки башен

	// Добавлено из старого (адаптировано для Raylib)
	PassableColorRL       = rl.NewColor(70, 100, 120, 220)
	ImpassableColorRL     = rl.NewColor(150, 70, 70, 220)
	EntryColorRL          = rl.NewColor(0, 255, 0, 255)
	ExitColorRL           = rl.NewColor(255, 0, 0, 255)
	BuildStateColorRL     = rl.NewColor(70, 130, 180, 220) // Был в старом, добавил RL-версию
	WaveStateColorRL      = rl.NewColor(220, 60, 60, 220)  // Был в старом, добавил RL-версию
	SelectionStateColorRL = rl.NewColor(255, 215, 0, 255)  // Золотой/желтый для выбора
	IndicatorStrokeRL     = rl.NewColor(240, 240, 240, 255)
	BaseColorRL           = rl.NewColor(50, 205, 50, 255)
	EnemyColorRL          = rl.NewColor(0, 0, 0, 255)
	TowerStrokeColorRL    = rl.NewColor(255, 255, 255, 255)
	TowerAStrokeColorRL   = rl.NewColor(255, 80, 80, 255) // Ярко-красный для типа A
	TowerBStrokeColorRL   = rl.NewColor(255, 255, 0, 255) // Желтый для типа B
	LineColorRL           = rl.NewColor(255, 195, 0, 150) // Насыщенный золотой для сети
	StrokeWidth           = 2.0                           // Не цвет, но добавил как var из старого
	SpeedButtonColorsRL   = []rl.Color{                   // Массив из старого, адаптированный
		rl.NewColor(70, 130, 180, 220),
		rl.NewColor(220, 60, 60, 220),
		rl.NewColor(194, 178, 128, 255),
	}
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

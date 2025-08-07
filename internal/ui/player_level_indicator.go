// internal/ui/player_level_indicator.go
package ui

import (
	"fmt"
	"go-tower-defense/internal/config"

	rl "github.com/gen2brain/raylib-go/raylib"
)

const (
	XpBarWidth  float32 = 200
	XpBarHeight float32 = 20
)

// PlayerLevelIndicatorRL - версия индикатора уровня для Raylib
type PlayerLevelIndicatorRL struct {
	X, Y float32
	font rl.Font
}

// NewPlayerLevelIndicatorRL создает новый индикатор уровня
func NewPlayerLevelIndicatorRL(x, y float32, font rl.Font) *PlayerLevelIndicatorRL {
	return &PlayerLevelIndicatorRL{
		X:    x,
		Y:    y,
		font: font,
	}
}

// Draw отрисовывает индикатор уровня и опыта
func (i *PlayerLevelIndicatorRL) Draw(level, currentXP, xpToNextLevel int) {
	// Фон полосы опыта
	rl.DrawRectangle(int32(i.X), int32(i.Y), int32(XpBarWidth), int32(XpBarHeight), config.XpBarBackgroundColorRL)

	// Полоса текущего опыта
	progress := float32(0)
	if xpToNextLevel > 0 {
		progress = float32(currentXP) / float32(xpToNextLevel)
	}
	currentXpWidth := XpBarWidth * progress
	rl.DrawRectangle(int32(i.X), int32(i.Y), int32(currentXpWidth), int32(XpBarHeight), config.XpBarForegroundColorRL)

	// Обводка
	rl.DrawRectangleLines(int32(i.X), int32(i.Y), int32(XpBarWidth), int32(XpBarHeight), config.XpBarBorderColorRL)

	// Текст уровня
	levelText := fmt.Sprintf("Lvl: %d", level)
	levelTextPos := rl.NewVector2(i.X-50, i.Y+2)
	rl.DrawTextEx(i.font, levelText, levelTextPos, config.PlayerLevelFontSizeRL, 1.0, config.PlayerLevelTextColorRL)

	// Текст опыта
	xpText := fmt.Sprintf("%d / %d", currentXP, xpToNextLevel)
	xpTextSize := rl.MeasureTextEx(i.font, xpText, config.PlayerXpFontSizeRL, 1.0)
	xpTextPos := rl.NewVector2(i.X+(XpBarWidth-xpTextSize.X)/2, i.Y+(XpBarHeight-xpTextSize.Y)/2)
	rl.DrawTextEx(i.font, xpText, xpTextPos, config.PlayerXpFontSizeRL, 1.0, config.PlayerXpTextColorRL)
}
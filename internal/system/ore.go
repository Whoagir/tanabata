// internal/system/ore.go
package system

import (
	"fmt"
	"go-tower-defense/internal/component"
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/entity"
	"image/color"
)

// OreSystem manages the state of ore veins, like visual depletion.
type OreSystem struct {
	ecs *entity.ECS
}

// NewOreSystem creates a new OreSystem.
func NewOreSystem(ecs *entity.ECS) *OreSystem {
	return &OreSystem{ecs: ecs}
}

// Update is called every frame to update the state of ore components.
func (s *OreSystem) Update() {
	for id, ore := range s.ecs.Ores {
		if ore.MaxReserve > 0 {
			// The displayed percentage is now simply the current reserve.
			displayPercentage := ore.CurrentReserve

			// The radius shrinks as the reserve is depleted.
			// The variable part of the radius is scaled by the percentage of the remaining reserve.
			baseRadius := config.HexSize * 0.2
			variableRadius := ore.Power * config.HexSize
			reservePercentage := ore.CurrentReserve / ore.MaxReserve
			ore.Radius = float32(baseRadius + (variableRadius * reservePercentage))

			// Update or create text component
			textValue := fmt.Sprintf("%.0f%%", displayPercentage)
			textColor := color.RGBA{R: 50, G: 50, B: 50, A: 255}

			if textComp, exists := s.ecs.Texts[id]; exists {
				textComp.Value = textValue
			} else {
				// This part is a fallback, should be created in game.go
				s.ecs.Texts[id] = &component.Text{
					Value:    textValue,
					Position: ore.Position,
					Color:    textColor,
					IsUI:     true,
				}
			}
		}
	}
}

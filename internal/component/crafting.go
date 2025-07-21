package component

import (
	"go-tower-defense/internal/defs"
	"go-tower-defense/internal/types"
)

// CraftInfo содержит информацию о конкретном возможном крафте.
type CraftInfo struct {
	Recipe      *defs.Recipe
	Combination []types.EntityID
}

// Combinable указывает, что башня может участвовать в одном или нескольких крафтах.
type Combinable struct {
	PossibleCrafts []CraftInfo
}

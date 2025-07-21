package component

import "go-tower-defense/internal/types"

// Combinable указывает, что башня является частью действительного рецепта крафта.
type Combinable struct {
	// RecipeOutputID - это ID башни, которая получится в результате крафта.
	RecipeOutputID string
	// Combination - это список ID всех башен, участвующих в этом крафте.
	Combination []types.EntityID
}

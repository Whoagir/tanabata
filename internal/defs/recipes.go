package defs

// RecipeInput defines a single ingredient for a recipe, including its type and required level.
type RecipeInput struct {
	ID    string `json:"id"`
	Level int    `json:"level"`
}

// Recipe defines the inputs and output for crafting a tower.
// It's designed to be loaded from a JSON file.
type Recipe struct {
	Inputs   []RecipeInput `json:"inputs"`    // List of tower DefIDs and their levels required for the craft.
	OutputID string        `json:"output_id"` // Tower DefID of the resulting tower.
}

// CraftingRecipeLibrary holds all the crafting recipes.
type CraftingRecipeLibrary struct {
	Recipes []*Recipe
}

// RecipeLibrary is the global instance of the crafting recipe library.
var RecipeLibrary *CraftingRecipeLibrary

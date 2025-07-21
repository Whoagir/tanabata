package defs

// Recipe defines the inputs and output for crafting a tower.
type Recipe struct {
	Inputs []string // List of tower type IDs required for the craft.
	Output string   // Tower type ID of the resulting tower.
}

// RecipeLibrary holds all the crafting recipes in the game.
var RecipeLibrary []Recipe

func init() {
	// Initialize the recipe library.
	RecipeLibrary = []Recipe{
		{
			Inputs: []string{"TOWER_SLOW", "TOWER_PHYSICAL_ATTACK", "TOWER_PURE_ATTACK"},
			Output: "TOWER_SILVER",
		},
		// Future recipes can be added here.
	}
}
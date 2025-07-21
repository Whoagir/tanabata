package defs

// Recipe defines the inputs and output for crafting a tower.
// It's designed to be loaded from a JSON file.
type Recipe struct {
	InputIDs []string `json:"input_ids"` // List of tower DefIDs required for the craft.
	OutputID string   `json:"output_id"` // Tower DefID of the resulting tower.
}

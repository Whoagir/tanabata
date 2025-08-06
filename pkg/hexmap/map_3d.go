// pkg/hexmap/map_3d.go
package hexmap

// NewHexMap3D создает карту для 3D-визуализатора, включая генерацию руды.
// Она сначала создает базовую карту, а затем добавляет на нее руду,
// используя изолированную логику генерации.
func NewHexMap3D() (*HexMap, map[Hex]float64) {
	// 1. Создаем стандартную карту без руды.
	gameMap := NewHexMap()

	// 2. Генерируем руду, используя новую, изолированную функцию.
	oreData := GenerateOre3D(gameMap)

	// 3. Возвращаем и карту, и данные о руде.
	return gameMap, oreData
}

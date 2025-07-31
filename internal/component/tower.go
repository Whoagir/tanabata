// component/tower.go
package component

import "go-tower-defense/pkg/hexmap"

type Tower struct {
	DefID              string     // ID из towers.json
	CraftingLevel      int        // Уровень крафта (0 - базовая, 1 - крафт 1-го уровня и т.д.)
	Range              int        // Рад��ус действия
	Hex                hexmap.Hex // Гекс, на котором стоит башня
	IsActive           bool       // Активна ли башня (стреляет или просто стена)
	IsTemporary        bool       // Временная ли башня (для механики выбора)
	IsSelected         bool       // Выбрана ли башня для СОХРАНЕНИЯ после фазы выбора
	IsManuallySelected bool       // Выбрана ли башня вручную в группу (для крафта)
	IsHighlighted      bool       // Подсвечена ли башня в данный момент (для UI)
}

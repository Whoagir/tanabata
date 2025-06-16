// component/tower.go
package component

import "go-tower-defense/pkg/hexmap"

type Tower struct {
	Type     int        // Тип башни (0 - Red, 1 - Green, etc.)
	Range    int        // Радиус действия
	Hex      hexmap.Hex // Гекс, на котором стоит башня
	IsActive bool       // Активна ли башня (стреляет или просто стена)
}

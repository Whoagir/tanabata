// internal/component/turret.go
package component

import "go-tower-defense/internal/types"

// TurretComponent отвечает за вращение "головы" башни.
type TurretComponent struct {
	// CurrentAngle - текущий угол поворота в радианах.
	CurrentAngle float32
	// TargetAngle - угол, к которому стремится башня.
	TargetAngle float32
	// TurnSpeed - скорость поворота в радианах в секунду.
	TurnSpeed float32
	// TargetID - ID цели, на которую наведена турель.
	TargetID types.EntityID
}

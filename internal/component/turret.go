// internal/component/turret.go
package component

import "go-tower-defense/internal/types"

// TurretComponent отвечает за вращение "головы" башни.
type TurretComponent struct {
	// CurrentAngle - текущий угол поворота в радианах (вокруг оси Y, рыскание).
	CurrentAngle float32
	// TargetAngle - угол, к которому стремится башня (вокруг оси Y).
	TargetAngle float32
	// CurrentPitch - текущий вертикальный угол в радианах (вокруг локальной оси Z, тангаж).
	CurrentPitch float32
	// TargetPitch - целевой вертикальный угол.
	TargetPitch float32
	// TurnSpeed - скорость поворота в радианах в секунду.
	TurnSpeed float32
	// AcquisitionRange - радиус, в котором турель начинает отслеживать цели (больше радиуса атаки).
	AcquisitionRange float32
	// TargetID - ID цели, на которую наведена турель.
	TargetID types.EntityID
}

package component

// Beacon - компонент для башни "Маяк".
// Он управляет ее уникальной механикой вращения и атаки.
type Beacon struct {
	// CurrentAngle - текущий угол поворота сектора атаки в радианах.
	CurrentAngle float64
	// TickTimer - отсчитывает время до следующего срабатывания урона.
	TickTimer float64
	// RotationSpeed - скорость вращения в радианах в секунду.
	RotationSpeed float64
	// ArcAngle - ширина сектора атаки в радианах.
	ArcAngle float64
}

// BeaconAttackSector - компонент для визуализации сектора атаки маяка.
type BeaconAttackSector struct {
	IsVisible bool    // Определяет, должен ли сектор быть видимым.
	Angle     float64 // Текущий центральный угол сектора в радианах.
	Arc       float64 // Ширина дуги сектора в радианах.
	Range     float32 // Дальность сектора в игровых единицах.
}
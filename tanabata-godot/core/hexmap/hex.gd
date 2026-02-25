# hex.gd
# Гексагональная математика (осевые координаты)
# Перенесено из Go проекта (pkg/hexmap/hex.go)
# Референс: https://www.redblobgames.com/grids/hexagons/
class_name Hex

# ============================================================================
# СВОЙСТВА
# ============================================================================

var q: int  # Осевая координата Q
var r: int  # Осевая координата R

# Кубическая координата S (вычисляемая)
var s: int:
	get:
		return -q - r

# ============================================================================
# КОНСТРУКТОР
# ============================================================================

func _init(q_: int = 0, r_: int = 0):
	q = q_
	r = r_

# ============================================================================
# КООРДИНАТЫ
# ============================================================================

# Преобразование гекс-координат в пиксельные (2D)
# Pointy-top ориентация (острые вершины вверх/вниз)
func to_pixel(hex_size: float) -> Vector2:
	var x = hex_size * (sqrt(3) * q + sqrt(3)/2.0 * r)
	var y = hex_size * (3.0/2.0 * r)
	return Vector2(x, y)

# Статический метод: пиксельные координаты -> гекс
static func from_pixel(pixel: Vector2, hex_size: float) -> Hex:
	var q_float = (sqrt(3)/3.0 * pixel.x - 1.0/3.0 * pixel.y) / hex_size
	var r_float = (2.0/3.0 * pixel.y) / hex_size
	return hex_round(q_float, r_float)

# Округление дробных кубических координат до ближайшего гекса
static func hex_round(q_float: float, r_float: float) -> Hex:
	var s_float = -q_float - r_float
	
	var q_rounded = roundi(q_float)
	var r_rounded = roundi(r_float)
	var s_rounded = roundi(s_float)
	
	var q_diff = abs(q_rounded - q_float)
	var r_diff = abs(r_rounded - r_float)
	var s_diff = abs(s_rounded - s_float)
	
	if q_diff > r_diff and q_diff > s_diff:
		q_rounded = -r_rounded - s_rounded
	elif r_diff > s_diff:
		r_rounded = -q_rounded - s_rounded
	
	return Hex.new(q_rounded, r_rounded)

# ============================================================================
# РАССТОЯНИЕ
# ============================================================================

# Манхэттенское расстояние между гексами
func distance_to(other: Hex) -> int:
	return (abs(q - other.q) + abs(r - other.r) + abs(s - other.s)) / 2

# ============================================================================
# СОСЕДИ
# ============================================================================

# Направления для 6 соседей (pointy-top)
const DIRECTIONS = [
	Vector2i(1, 0),   # Восток
	Vector2i(1, -1),  # Северо-восток
	Vector2i(0, -1),  # Северо-запад
	Vector2i(-1, 0),  # Запад
	Vector2i(-1, 1),  # Юго-запад
	Vector2i(0, 1)    # Юго-восток
]

# Получить соседа в направлении
func neighbor(direction: int) -> Hex:
	var dir = DIRECTIONS[direction % 6]
	return Hex.new(q + dir.x, r + dir.y)

# Получить всех 6 соседей
func get_neighbors() -> Array[Hex]:
	var neighbors: Array[Hex] = []
	for i in range(6):
		neighbors.append(neighbor(i))
	return neighbors

# ============================================================================
# ДИАПАЗОН
# ============================================================================

# Получить все гексы в радиусе N от этого гекса
func get_hexes_in_range(radius: int) -> Array[Hex]:
	var results: Array[Hex] = []
	for q_offset in range(-radius, radius + 1):
		var r1 = max(-radius, -q_offset - radius)
		var r2 = min(radius, -q_offset + radius)
		for r_offset in range(r1, r2 + 1):
			results.append(Hex.new(q + q_offset, r + r_offset))
	return results

# Получить все гексы на определенном расстоянии (кольцо)
func get_ring(radius: int) -> Array[Hex]:
	var results: Array[Hex] = []
	if radius == 0:
		results.append(Hex.new(q, r))
		return results
	
	var hex = Hex.new(q, r)
	# Начинаем с направления 4 (юго-запад), сдвигаемся на radius
	for i in range(radius):
		hex = hex.neighbor(4)
	
	# Идем по периметру
	for direction in range(6):
		for step in range(radius):
			results.append(Hex.new(hex.q, hex.r))
			hex = hex.neighbor(direction)
	
	return results

# ============================================================================
# ЛИНИЯ
# ============================================================================

# Проверка: находятся ли гексы на одной прямой
func is_on_same_line(other: Hex) -> bool:
	if q == other.q:
		return true  # Вертикальная линия (по R)
	if r == other.r:
		return true  # Диагональная линия (по Q)
	if s == other.s:
		return true  # Диагональная линия (по S)
	return false

# Получить все гексы на линии от this до other
func line_to(other: Hex) -> Array[Hex]:
	var dist = distance_to(other)
	var results: Array[Hex] = []
	
	if dist == 0:
		results.append(Hex.new(q, r))
		return results
	
	for i in range(dist + 1):
		var t = float(i) / float(dist)
		var q_lerp = lerp(float(q), float(other.q), t)
		var r_lerp = lerp(float(r), float(other.r), t)
		results.append(hex_round(q_lerp, r_lerp))
	
	return results

# ============================================================================
# ОПЕРАТОРЫ И УТИЛИТЫ
# ============================================================================

# Сложение гексов
func add(other: Hex) -> Hex:
	return Hex.new(q + other.q, r + other.r)

# Вычитание гексов
func subtract(other: Hex) -> Hex:
	return Hex.new(q - other.q, r - other.r)

# Масштабирование (умножение на скаляр)
func scale(factor: int) -> Hex:
	return Hex.new(q * factor, r * factor)

# Направление (нормализация к единичному гексу)
func direction() -> Hex:
	var dist = distance_to(Hex.ZERO())
	if dist == 0:
		return Hex.ZERO()
	
	# Нормализуем к ближайшему направлению
	var dq = float(q) / float(dist)
	var dr = float(r) / float(dist)
	return hex_round(dq, dr)

# Сравнение (для использования в словарях)
func equals(other: Hex) -> bool:
	return q == other.q and r == other.r

# Хеш для словарей (используем встроенный hash)
func hash_value() -> int:
	return hash([q, r])

# Строковое представление
func _to_string() -> String:
	return "Hex(%d, %d)" % [q, r]

# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
# ============================================================================

# Создать массив гексов из координат
static func from_coords(coords: Array) -> Array[Hex]:
	var hexes: Array[Hex] = []
	for coord in coords:
		if coord is Vector2i:
			hexes.append(Hex.new(coord.x, coord.y))
		elif coord is Array and coord.size() == 2:
			hexes.append(Hex.new(coord[0], coord[1]))
	return hexes

# Создать ключ для словаря (строковый)
func to_key() -> String:
	return "%d,%d" % [q, r]

# Целочисленный ключ для высокопроизводительных Dictionary (pathfinding).
# Работает для координат в диапазоне [-999, 999].
func to_int_key() -> int:
	return (q + 1000) * 10000 + (r + 1000)

static func int_key_from_qr(q_: int, r_: int) -> int:
	return (q_ + 1000) * 10000 + (r_ + 1000)

# Создать гекс из ключа
static func from_key(key: String) -> Hex:
	var parts = key.split(",")
	if parts.size() != 2:
		push_error("Invalid hex key: " + key)
		return Hex.new(0, 0)
	return Hex.new(int(parts[0]), int(parts[1]))

# ============================================================================
# КОНСТАНТЫ
# ============================================================================

# Предопределенные гексы
static func ZERO() -> Hex:
	return Hex.new(0, 0)

static func INVALID() -> Hex:
	return Hex.new(999999, 999999)  # Невалидный гекс

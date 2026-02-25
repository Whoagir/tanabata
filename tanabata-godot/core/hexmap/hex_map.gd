# hex_map.gd
# Гексагональная карта с процедурной генерацией
# Перенесено из Go проекта (pkg/hexmap/map.go)
class_name HexMap

# ============================================================================
# ТАЙЛ
# ============================================================================

class Tile:
	var hex: Hex
	var passable: bool = true
	var can_place_tower: bool = true
	var has_tower: bool = false
	var tower_id: int = GameTypes.INVALID_ENTITY_ID
	
	func _init(hex_: Hex):
		hex = hex_
	
	func _to_string() -> String:
		return "Tile(%s, passable=%s)" % [hex, passable]

# ============================================================================
# СВОЙСТВА
# ============================================================================

var radius: int
var tiles: Dictionary = {}  # String (hex.to_key()) -> Tile

# Особые гексы
var entry: Hex
var exit: Hex
var checkpoints: Array[Hex] = []

# Seed для генерации (для воспроизводимости)
var generation_seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# ============================================================================
# КОНСТРУКТОР
# ============================================================================

func _init(radius_: int, seed_: int = 0):
	radius = radius_
	generation_seed = seed_ if seed_ != 0 else randi()
	rng.seed = generation_seed

# ============================================================================
# ДОСТУП К ТАЙЛАМ
# ============================================================================

# Получить тайл по гексу
func get_tile(hex: Hex) -> Tile:
	var key = hex.to_key()
	if key in tiles:
		return tiles[key]
	return null

# Установить тайл
func set_tile(hex: Hex, tile: Tile):
	tiles[hex.to_key()] = tile

# Есть ли тайл в этой позиции
func has_tile(hex: Hex) -> bool:
	return hex.to_key() in tiles

# Проходим ли тайл
func is_passable(hex: Hex) -> bool:
	var tile = get_tile(hex)
	return tile != null and tile.passable

# Быстрая проверка проходимости по q,r без создания Hex объекта (для A*)
func has_tile_qr(q: int, r: int) -> bool:
	return "%d,%d" % [q, r] in tiles

func is_passable_qr(q: int, r: int) -> bool:
	var key = "%d,%d" % [q, r]
	if not key in tiles:
		return false
	return tiles[key].passable

# Можно ли поставить башню
func can_place_tower(hex: Hex) -> bool:
	var tile = get_tile(hex)
	return tile != null and tile.can_place_tower and not tile.has_tower

# Получить все тайлы
func get_all_tiles() -> Array:
	return tiles.values()

# Получить все гексы
func get_all_hexes() -> Array[Hex]:
	var hexes: Array[Hex] = []
	for tile in tiles.values():
		hexes.append(tile.hex)
	return hexes

# ============================================================================
# ГЕНЕРАЦИЯ КАРТЫ
# ============================================================================

# Полная генерация карты. checkpoint_count: -1 = по умолчанию (6), 0 = без чекпоинтов (обучение «Основы»).
func generate(checkpoint_count: int = -1):
	
	# Шаг 1: Базовая гексагональная сетка
	_generate_base_grid()
	
	# Шаг 2: Установка Entry/Exit
	_set_entry_exit()
	
	# Шаг 3: Генерация чекпоинтов (0 для пустой карты обучения)
	_generate_checkpoints(checkpoint_count)
	
	# Шаг 4–6: для карты с чекпоинтами — модификация секций и углов
	if checkpoint_count != 0:
		_modify_sections()
		_process_corners()
		_post_process()
	
	# Шаг 7: Зоны исключения (уже учтены в шагах 4-5)
	

# Шаг 1: Базовая сетка
func _generate_base_grid():
	for q in range(-radius, radius + 1):
		var r1 = max(-radius, -q - radius)
		var r2 = min(radius, -q + radius)
		for r in range(r1, r2 + 1):
			var hex = Hex.new(q, r)
			var tile = Tile.new(hex)
			set_tile(hex, tile)

# Шаг 2: Entry/Exit
func _set_entry_exit():
	# Entry: левая сторона
	entry = Hex.new(-radius - 1, radius / 2)
	
	# Exit: правая сторона
	exit = Hex.new(radius + 1, -radius / 2)
	
	# Убеждаемся, что entry и exit НЕ в тайлах (они снаружи)
	# Но создаем тайлы для них, если нужны
	if not has_tile(entry):
		var entry_tile = Tile.new(entry)
		entry_tile.can_place_tower = false
		set_tile(entry, entry_tile)
	
	if not has_tile(exit):
		var exit_tile = Tile.new(exit)
		exit_tile.can_place_tower = false
		set_tile(exit, exit_tile)

# Шаг 3: Генерация чекпоинтов. count: -1 = 6 (по умолчанию), 0 = пустой массив.
func _generate_checkpoints(count: int = -1):
	checkpoints = []
	if count == 0:
		return
	var D = radius - 3
	if D < 1:
		return
	var n = 6
	if count > 0:
		n = mini(count, 6)
	
	# 6 базовых позиций (как в Go)
	var base_checkpoints = [
		Hex.new(-D, D),   # SW
		Hex.new(D, -D),   # NE
		Hex.new(0, -D),   # N
		Hex.new(0, D),    # S
		Hex.new(D, 0),    # SE
		Hex.new(-D, 0)    # NW
	]
	
	# Рандомная ротация (как в Go: k := rand.Intn(6))
	var k = rng.randi() % 6
	for i in range(n):
		var checkpoint_hex = base_checkpoints[(k + i) % 6]
		
		# Корректируем, если гекс не существует
		if not has_tile(checkpoint_hex):
			checkpoint_hex = _find_nearest_valid_hex(checkpoint_hex)
		
		checkpoints.append(checkpoint_hex)
		
		# Помечаем чекпоинт как особый
		var tile = get_tile(checkpoint_hex)
		if tile:
			tile.can_place_tower = false  # На чекпоинте нельзя строить

# Найти ближайший валидный гекс
func _find_nearest_valid_hex(target: Hex) -> Hex:
	for dist in range(1, 5):
		for hex in target.get_ring(dist):
			if has_tile(hex):
				return hex
	return Hex.ZERO()  # Fallback

# Шаг 4: Модификация секций (как в Go)
func _modify_sections():
	var exclusion = _get_exclusion_zones(3)
	var sections = _get_border_sections()
	
	for section in sections:
		if _section_intersects_exclusion(section, exclusion):
			continue
		
		var action = rng.randi() % 10
		if action < 3:
			_add_outer_section(section)
		elif action < 6:
			_remove_inner_section(section)

# Шаг 5: Обработка углов (как в Go)
func _process_corners():
	var exclusion = _get_exclusion_zones(3)
	var corners = [
		Hex.new(radius, 0), Hex.new(0, radius), Hex.new(-radius, radius),
		Hex.new(-radius, 0), Hex.new(0, -radius), Hex.new(radius, -radius)
	]
	
	for corner in corners:
		if exclusion.has(corner.to_key()):
			continue
		
		var action = rng.randi() % 10
		if action < 3:
			# Добавить угол
			var additions = _get_corner_additions(corner)
			for hex in additions:
				if not has_tile(hex):
					var tile = Tile.new(hex)
					set_tile(hex, tile)
		elif action < 6:
			# Удалить угол (если не блокирует путь)
			var tile = get_tile(corner)
			if tile:
				tile.passable = false
				set_tile(corner, tile)
				var path = Pathfinding.find_path(entry, exit, self)
				tile.passable = true
				set_tile(corner, tile)
				if path.size() > 0:
					tiles.erase(corner.to_key())

# Шаг 6: Постобработка (как в Go)
func _post_process():
	var extra_radius = 2
	var max_iterations = 20
	var iteration = 0
	
	while iteration < max_iterations:
		var changes = false
		var potential_hexes = _get_all_potential_hexes(extra_radius)
		
		for hex in potential_hexes:
			var neighbors = hex.get_neighbors()
			var on_map_neighbors = 0
			for n in neighbors:
				if has_tile(n):
					on_map_neighbors += 1
			
			if not has_tile(hex):
				# Гекс не на карте - добавить если >= 4 соседа
				if on_map_neighbors >= 4:
					var tile = Tile.new(hex)
					set_tile(hex, tile)
					changes = true
			else:
				# Гекс на карте - удалить если <= 2 соседа (кроме Entry/Exit)
				if hex.equals(entry) or hex.equals(exit):
					continue
				if on_map_neighbors <= 2:
					tiles.erase(hex.to_key())
					changes = true
		
		if not changes:
			break
		iteration += 1

# ============================================================================
# ЗОНЫ ИСКЛЮЧЕНИЯ
# ============================================================================

# Проверка: находится ли гекс в зоне исключения (радиус 3 от важных точек)
func is_in_exclusion_zone(hex: Hex) -> bool:
	if entry.distance_to(hex) <= 3:
		return true
	if exit.distance_to(hex) <= 3:
		return true
	for checkpoint in checkpoints:
		if checkpoint.distance_to(hex) <= 3:
			return true
	return false

# ============================================================================
# БАШНИ
# ============================================================================

# Разместить башню
func place_tower(hex: Hex, tower_id: int) -> bool:
	var tile = get_tile(hex)
	if tile and tile.can_place_tower and not tile.has_tower:
		tile.has_tower = true
		tile.tower_id = tower_id
		tile.passable = false  # Башня блокирует путь
		return true
	return false

# Удалить башню
func remove_tower(hex: Hex):
	var tile = get_tile(hex)
	if tile and tile.has_tower:
		tile.has_tower = false
		tile.tower_id = GameTypes.INVALID_ENTITY_ID
		tile.passable = true

# Получить ID башни на гексе
func get_tower_id(hex: Hex) -> int:
	var tile = get_tile(hex)
	if tile:
		return tile.tower_id
	return GameTypes.INVALID_ENTITY_ID

# ============================================================================
# ДЕБАГ
# ============================================================================

func print_info():
	print("=== HexMap Info ===")
	print("  Radius: %d" % radius)
	print("  Tiles: %d" % tiles.size())
	print("  Entry: %s" % entry)
	print("  Exit: %s" % exit)
	print("  Checkpoints: %d" % checkpoints.size())
	for i in range(checkpoints.size()):
		print("    %d: %s" % [i, checkpoints[i]])

# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ ГЕНЕРАЦИИ (из Go)
# ============================================================================

func get_hexes_in_range(center: Hex, dist: int) -> Array[Hex]:
	var result: Array[Hex] = []
	for q in range(-dist, dist + 1):
		var r1 = max(-dist, -q - dist)
		var r2 = min(dist, -q + dist)
		for r in range(r1, r2 + 1):
			var hex = Hex.new(center.q + q, center.r + r)
			if has_tile(hex):
				result.append(hex)
	return result

func _get_exclusion_zones(dist: int) -> Dictionary:
	var exclusion = {}
	var entry_zone = get_hexes_in_range(entry, dist)
	var exit_zone = get_hexes_in_range(exit, dist)
	for hex in entry_zone:
		exclusion[hex.to_key()] = true
	for hex in exit_zone:
		exclusion[hex.to_key()] = true
	return exclusion

func _get_border_sections() -> Array:
	var sections = []
	var sides = [
		{"coords": func(i): return Hex.new(radius, i), "start": -radius, "end": 0},
		{"coords": func(i): return Hex.new(i, radius - i), "start": 0, "end": radius},
		{"coords": func(i): return Hex.new(i, -radius), "start": 0, "end": radius},
		{"coords": func(i): return Hex.new(-radius, i), "start": 0, "end": radius},
		{"coords": func(i): return Hex.new(i, -radius - i), "start": -radius, "end": 0},
		{"coords": func(i): return Hex.new(i, radius), "start": -radius, "end": 0}
	]
	
	for side in sides:
		var start = side["start"]
		var end = side["end"]
		var coords_func = side["coords"]
		
		var i = start
		while i <= end - 2:
			var section = [
				coords_func.call(i),
				coords_func.call(i + 1),
				coords_func.call(i + 2)
			]
			var valid = true
			for hex in section:
				if not has_tile(hex):
					valid = false
					break
			if valid:
				sections.append(section)
			i += 3
	
	return sections

func _section_intersects_exclusion(section: Array, exclusion: Dictionary) -> bool:
	for hex in section:
		if exclusion.has(hex.to_key()):
			return true
	return false

func _add_outer_section(section: Array):
	for hex in section:
		var neighbors = hex.get_neighbors()
		for n in neighbors:
			if not has_tile(n):
				var tile = Tile.new(n)
				set_tile(n, tile)

func _remove_inner_section(section: Array):
	# Пробуем удалить, проверяем путь
	for hex in section:
		var tile = get_tile(hex)
		if tile:
			tile.passable = false
			set_tile(hex, tile)
	
	var path = Pathfinding.find_path(entry, exit, self)
	
	for hex in section:
		var tile = get_tile(hex)
		if tile:
			tile.passable = true
			set_tile(hex, tile)
	
	if path.size() == 0:
		return  # Путь заблокирован, не удаляем
	
	for hex in section:
		tiles.erase(hex.to_key())

func _get_corner_additions(corner: Hex) -> Array:
	var additions = []
	if corner.equals(Hex.new(radius, 0)):
		additions = [Hex.new(radius + 1, 0), Hex.new(radius + 1, -1), Hex.new(radius, -1)]
	elif corner.equals(Hex.new(0, radius)):
		additions = [Hex.new(1, radius), Hex.new(0, radius + 1), Hex.new(-1, radius)]
	elif corner.equals(Hex.new(-radius, radius)):
		additions = [Hex.new(-radius, radius + 1), Hex.new(-radius - 1, radius), Hex.new(-radius - 1, radius + 1)]
	elif corner.equals(Hex.new(-radius, 0)):
		additions = [Hex.new(-radius - 1, 0), Hex.new(-radius - 1, 1), Hex.new(-radius, 1)]
	elif corner.equals(Hex.new(0, -radius)):
		additions = [Hex.new(1, -radius), Hex.new(0, -radius - 1), Hex.new(-1, -radius)]
	elif corner.equals(Hex.new(radius, -radius)):
		additions = [Hex.new(radius + 1, -radius), Hex.new(radius, -radius - 1), Hex.new(radius + 1, -radius - 1)]
	return additions

func _get_all_potential_hexes(extra_radius: int) -> Array:
	var r = radius + extra_radius
	var hexes = []
	for q in range(-r, r + 1):
		var r1 = max(-r, -q - r)
		var r2 = min(r, -q + r)
		for rr in range(r1, r2 + 1):
			hexes.append(Hex.new(q, rr))
	return hexes

# ============================================================================
# НАЧАЛЬНЫЕ СТЕНЫ (из Go: placeInitialStones)
# ============================================================================

func get_initial_wall_hexes() -> Array[Hex]:
	"""Возвращает список гексов для начальных стен (как в Go)"""
	var result: Array[Hex] = []
	var center = Hex.ZERO()
	
	for checkpoint in checkpoints:
		# Направление К центру (от чекпоинта к центру)
		var dir_in = center.subtract(checkpoint).direction()
		for i in range(1, 3):  # i = 1, 2
			var hex_to_place = checkpoint.add(dir_in.scale(i))
			if _can_place_initial_wall(hex_to_place):
				result.append(hex_to_place)
		
		# Направление ОТ центра (от чекпоинта наружу)
		var dir_out = checkpoint.subtract(center).direction()
		var i = 1
		while true:
			var hex_to_place = checkpoint.add(dir_out.scale(i))
			if _can_place_initial_wall(hex_to_place):
				result.append(hex_to_place)
				i += 1
			else:
				break  # Достигли границы карты или неподходящий гекс
	
	return result

func _can_place_initial_wall(hex: Hex) -> bool:
	"""Проверка: можно ли поставить начальную стену на этом гексе"""
	# Должен существовать на карте
	if not has_tile(hex):
		return false
	
	var tile = get_tile(hex)
	# Должен быть проходим и можно ставить башни
	if not tile.passable or not tile.can_place_tower:
		return false
	
	# Не должен быть чекпоинтом, входом или выходом
	if hex.equals(entry) or hex.equals(exit):
		return false
	
	for cp in checkpoints:
		if hex.equals(cp):
			return false
	
	return true

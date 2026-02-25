# ore_generation_system.gd
# Генерация руды (копия логики из Go проекта)
class_name OreGenerationSystem

var ecs: ECSWorld
var hex_map: HexMap
var rng: RandomNumberGenerator
var ore_vein_hexes: Array[Array] = []  # массив жил (размер = vein_count)

func _init(ecs_: ECSWorld, hex_map_: HexMap, seed_: int):
	ecs = ecs_
	hex_map = hex_map_
	rng = RandomNumberGenerator.new()
	rng.seed = seed_

# Генерация руды. vein_count — количество жил (3 по умолчанию, для обучения можно 6).
func generate_ore(vein_count: int = 3):
	vein_count = clampi(vein_count, 1, 12)
	
	# Все гексы карты
	var all_hexes = hex_map.get_all_tiles()
	var center_hex = Hex.new(0, 0)
	
	# --- Поиск N центров для жил ---
	var centers: Array[Hex] = []
	
	# Центр 1: в центре (дистанция < 3)
	while centers.size() < 1:
		var candidate = all_hexes[rng.randi() % all_hexes.size()].hex
		if not _is_too_close_to_critical(candidate) and center_hex.distance_to(candidate) < 3:
			centers.append(candidate)
	
	# Центр 2: средний радиус (4-9), подальше от первого
	while centers.size() < 2 and vein_count >= 2:
		var candidate = all_hexes[rng.randi() % all_hexes.size()].hex
		var dist_from_center = center_hex.distance_to(candidate)
		if not _is_too_close_to_critical(candidate) and dist_from_center >= 4 and dist_from_center <= 9:
			if centers[0].distance_to(candidate) > 6:
				centers.append(candidate)
	
	# Центр 3: далеко (дистанция >= 10), подальше от первых двух
	if vein_count >= 3:
		var center_candidates_3: Array[Hex] = []
		for tile in all_hexes:
			var hex = tile.hex
			if not _is_too_close_to_critical(hex) and center_hex.distance_to(hex) >= 10:
				center_candidates_3.append(hex)
		if center_candidates_3.size() > 0:
			var center3 = _find_farthest_hex(center_candidates_3, centers)
			centers.append(center3)
		else:
			center_candidates_3.clear()
			for tile in all_hexes:
				var hex = tile.hex
				if not _is_too_close_to_critical(hex) and center_hex.distance_to(hex) >= 8:
					center_candidates_3.append(hex)
			if center_candidates_3.size() > 0:
				var center3 = _find_farthest_hex(center_candidates_3, centers)
				centers.append(center3)
	
	# Дополнительные центры (4, 5, 6, ...): максимизируем расстояние до уже выбранных
	var safe_hexes: Array[Hex] = []
	for tile in all_hexes:
		var hex = tile.hex
		if not _is_too_close_to_critical(hex):
			safe_hexes.append(hex)
	while centers.size() < vein_count and safe_hexes.size() > 0:
		var next_center = _find_farthest_hex(safe_hexes, centers)
		if next_center == null:
			break
		centers.append(next_center)
		# Убираем из кандидатов гексы слишком близко к новому центру, чтобы не класть две жилы вплотную
		var to_remove: Array[Hex] = []
		for h in safe_hexes:
			if h.distance_to(next_center) < 4:
				to_remove.append(h)
		for h in to_remove:
			safe_hexes.erase(h)
	
	# Добиваем до vein_count при необходимости (дублируем последний центр со сдвигом)
	while centers.size() < vein_count:
		var last = centers[centers.size() - 1]
		centers.append(last.add(Hex.new(1, 0)))
	
	# --- Генерация областей жил ---
	var vein_areas: Array[Array] = []
	for i in range(centers.size()):
		if i == 0:
			var central_vein: Array[Hex] = [centers[i]]
			var neighbors = centers[i].get_neighbors()
			neighbors.shuffle()
			for neighbor in neighbors:
				if central_vein.size() >= 4:
					break
				if not _is_too_close_to_critical(neighbor):
					central_vein.append(neighbor)
			vein_areas.append(central_vein)
		else:
			vein_areas.append(_get_hexes_in_range(centers[i], 2))
	
	# --- Генерация мощности жил (равные доли для простоты при N > 3) ---
	var total_map_power = 240.0 + rng.randf() * 30.0  # 240-270
	var total_powers: Array[float] = []
	var n = vein_areas.size()
	if n <= 3:
		var central_share = (0.18 + rng.randf() * 0.04) * (2.5 / 1.5) * 1.10
		var mid_share = 0.27 + rng.randf() * 0.06
		var far_share = 1.0 - central_share - mid_share
		total_powers = [
			total_map_power * central_share,
			total_map_power * mid_share,
			total_map_power * far_share
		]
	else:
		var share = 1.0 / float(n)
		for i in range(n):
			total_powers.append(total_map_power * share)
	
	# Распределение энергии по жилам
	var energy_veins: Dictionary = {}  # hex_key -> power
	
	for i in range(vein_areas.size()):
		var area = vein_areas[i]
		if area.size() == 0:
			continue
		var total_vein_power = total_powers[i] if i < total_powers.size() else (total_map_power / float(n))
		
		if i == 0:
			var remaining_power = total_vein_power
			for j in range(area.size() - 1):
				var hex = area[j]
				var avg_power = remaining_power / float(area.size() - j)
				var fluctuation = avg_power * 0.4
				var power = avg_power + (rng.randf() * 2.0 - 1.0) * fluctuation
				power = clamp(power, 0.0, remaining_power)
				energy_veins[hex.to_key()] = power / 100.0
				remaining_power -= power
			if area.size() > 0:
				energy_veins[area[area.size() - 1].to_key()] = remaining_power / 100.0
		else:
			var circles = _generate_energy_circles(area, total_vein_power)
			for circle in circles:
				var hexes_in_circle = _get_hexes_in_circle(circle["center_x"], circle["center_y"], circle["radius"])
				for hex in hexes_in_circle:
					if _is_checkpoint(hex):
						continue
					var hex_key = hex.to_key()
					if not energy_veins.has(hex_key):
						energy_veins[hex_key] = 0.0
					energy_veins[hex_key] += circle["power"]
	
	# Сохраняем гексы по жилам для индикатора расхода руды
	ore_vein_hexes.clear()
	for i in range(vein_areas.size()):
		ore_vein_hexes.append(vein_areas[i].duplicate())
	
	# --- Создание сущностей руды ---
	for hex_key in energy_veins.keys():
		var power = energy_veins[hex_key]
		var hex = Hex.from_key(hex_key)
		var pixel_pos = hex.to_pixel(Config.HEX_SIZE)
		
		var ore_id = ecs.create_entity()
		ecs.positions[ore_id] = pixel_pos
		ecs.add_component(ore_id, "ore", {
			"power": power,
			"max_reserve": power * 100.0,
			"current_reserve": power * 100.0,
			"hex": hex,
			"radius": Config.HEX_SIZE * 0.2 + power * Config.HEX_SIZE,
			"pulse_rate": 2.0,
			"is_highlighted": false
		})
		ecs.ore_hex_index[hex_key] = ore_id
	

# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ============================================================================

func _is_too_close_to_critical(hex: Hex) -> bool:
	if hex.equals(hex_map.entry) or hex.equals(hex_map.exit):
		return true
	if hex_map.entry.distance_to(hex) < 2 or hex_map.exit.distance_to(hex) < 2:
		return true
	for cp in hex_map.checkpoints:
		if cp.distance_to(hex) < 2:
			return true
	return false

func _is_checkpoint(hex: Hex) -> bool:
	for cp in hex_map.checkpoints:
		if cp.equals(hex):
			return true
	return false

func _find_farthest_hex(candidates: Array[Hex], existing_centers: Array[Hex]) -> Hex:
	var best_hex: Hex = null
	var max_total_dist = -1.0
	
	for candidate in candidates:
		var total_dist = 0.0
		for center in existing_centers:
			total_dist += candidate.distance_to(center)
		
		if total_dist > max_total_dist:
			max_total_dist = total_dist
			best_hex = candidate
	
	return best_hex

func _get_hexes_in_range(center: Hex, range: int) -> Array[Hex]:
	var result: Array[Hex] = []
	for tile in hex_map.get_all_tiles():
		var hex = tile.hex
		if center.distance_to(hex) <= range:
			result.append(hex)
	return result

func _generate_energy_circles(area: Array[Hex], total_power: float) -> Array:
	var circles = []
	var remaining_power = total_power
	
	while remaining_power > 0:
		var hex = area[rng.randi() % area.size()]
		var pixel = hex.to_pixel(Config.HEX_SIZE)
		var cx = pixel.x + (rng.randf() * 2.0 - 1.0) * Config.HEX_SIZE / 2.0
		var cy = pixel.y + (rng.randf() * 2.0 - 1.0) * Config.HEX_SIZE / 2.0
		
		# Мощность 5, 10, 15, 20%
		var power = float((rng.randi() % 4 + 1) * 5)
		if power > remaining_power:
			power = remaining_power
		remaining_power -= power
		
		var radius = Config.HEX_SIZE * 0.2 * (power / 5.0)
		
		circles.append({
			"center_x": cx,
			"center_y": cy,
			"radius": radius,
			"power": power / 100.0
		})
	
	return circles

func _get_hexes_in_circle(cx: float, cy: float, radius: float) -> Array[Hex]:
	var result: Array[Hex] = []
	for tile in hex_map.get_all_tiles():
		var hex = tile.hex
		var pixel = hex.to_pixel(Config.HEX_SIZE)
		var dx = pixel.x - cx
		var dy = pixel.y - cy
		if sqrt(dx * dx + dy * dy) < radius + Config.HEX_SIZE:
			result.append(hex)
	return result

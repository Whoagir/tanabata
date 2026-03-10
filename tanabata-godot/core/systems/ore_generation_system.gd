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
	
	# Центр 2 (средняя жила): средний радиус (4-9), подальше от первого; обязательно >= 6 гексов без чекпоинтов в радиусе 5 (иначе средняя жила не наберёт 6-8)
	var mid_center_attempts = 0
	while centers.size() < 2 and vein_count >= 2:
		mid_center_attempts += 1
		var candidate = all_hexes[rng.randi() % all_hexes.size()].hex
		var dist_from_center = center_hex.distance_to(candidate)
		if not _is_too_close_to_critical(candidate) and dist_from_center >= 4 and dist_from_center <= 9:
			if centers[0].distance_to(candidate) > 6:
				var valid_count = 0
				for h in _get_hexes_in_range(candidate, 5):
					if not _is_checkpoint(h):
						valid_count += 1
				var ok = valid_count >= 6
				if not ok and mid_center_attempts > 80:
					var valid_r6 = 0
					for h in _get_hexes_in_range(candidate, 6):
						if not _is_checkpoint(h):
							valid_r6 += 1
					ok = valid_r6 >= 6
				if ok:
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
	# Средняя жила (индекс 1): фиксируем число гексов 6–8 (как с долей мощности)
	const MID_VEIN_MIN_HEXES = 6
	const MID_VEIN_MAX_HEXES = 8
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
		elif i == 1:
			var mid_center = centers[i]
			# Средняя жила: строго 6–8 гексов. Крутим радиус пока не наберётся минимум 6 (без чекпоинтов)
			var mid_hexes_ok: Array[Hex] = []
			for radius in range(2, 16):
				mid_hexes_ok.clear()
				var raw = _get_hexes_in_range(mid_center, radius)
				for h in raw:
					if not _is_checkpoint(h):
						mid_hexes_ok.append(h)
				if mid_hexes_ok.size() >= MID_VEIN_MIN_HEXES:
					break
			mid_hexes_ok.sort_custom(func(a, b): return mid_center.distance_to(a) < mid_center.distance_to(b))
			var want_count = rng.randi_range(MID_VEIN_MIN_HEXES, MID_VEIN_MAX_HEXES)
			want_count = mini(want_count, mid_hexes_ok.size())
			var mid_vein: Array[Hex] = []
			for j in range(want_count):
				mid_vein.append(mid_hexes_ok[j])
			vein_areas.append(mid_vein)
		else:
			vein_areas.append(_get_hexes_in_range(centers[i], 2))
	
	# --- Генерация мощности жил (равные доли для простоты при N > 3) ---
	var total_map_power = 240.0 + rng.randf() * 30.0  # 240-270
	var total_powers: Array[float] = []
	var n = vein_areas.size()
	# Центральная жила: фиксированно 37%. Средняя: случайно 28–32%.
	const CENTRAL_VEIN_SHARE = 0.37
	const MID_VEIN_MIN_SHARE = 0.28
	const MID_VEIN_MAX_SHARE = 0.32
	if n <= 3:
		var central_share = CENTRAL_VEIN_SHARE
		var mid_share = clampf(0.27 + rng.randf() * 0.06, MID_VEIN_MIN_SHARE, MID_VEIN_MAX_SHARE)
		var far_share = 1.0 - central_share - mid_share
		# Средняя жила: в 2 раза больше руды (множитель 2.0); остаток total_map_power делим между центральной и крайней в прежнем соотношении
		var mid_power = total_map_power * mid_share * 2.0
		var rest = total_map_power - mid_power
		var denom = central_share * 1.10 + far_share * 1.50
		if denom > 0.0:
			total_powers = [
				rest * (central_share * 1.10 / denom),
				mid_power,
				rest * (far_share * 1.50 / denom)
			]
		else:
			total_powers = [rest * 0.5, mid_power, rest * 0.5]
	else:
		var share = 1.0 / float(n)
		for i in range(n):
			total_powers.append(total_map_power * share)
	# Центральная жила (индекс 0): свёрнутый множитель (было: +13%, +25%, ...; затем −10%, затем −6%)
	const CENTRAL_VEIN_POWER_MULT = 2.2320864  # 2.6384 * 0.9 * 0.94
	if total_powers.size() > 0:
		total_powers[0] *= CENTRAL_VEIN_POWER_MULT
	
	if total_powers.size() >= 3:
		# Крайняя жила: +60% руды (центральную и среднюю не трогаем)
		total_powers[2] *= 1.6
		# В логах: суммарная руда по жилам (в единицах reserve)
		print("[Ore] Центральная жила: %.0f, средняя: %.0f, крайняя: %.0f (суммарно руды)" % [total_powers[0], total_powers[1], total_powers[2]])
	
	# Распределение энергии по жилам; sector 0=центральный, 1=средний, 2=крайний (для аналитики лабиринта)
	var energy_veins: Dictionary = {}  # hex_key -> power
	var sector_by_hex: Dictionary = {}  # hex_key -> sector_index (0..2)
	
	for i in range(vein_areas.size()):
		var area = vein_areas[i]
		if area.size() == 0:
			continue
		var total_vein_power = total_powers[i] if i < total_powers.size() else (total_map_power / float(n))
		var sector_idx = mini(i, 2)  # 0, 1, 2 для первых трёх жил
		
		if i == 0:
			# Центральная жила: распределение по гексам вручную
			var remaining_power = total_vein_power
			for j in range(area.size() - 1):
				var hex = area[j]
				var hk = hex.to_key()
				var avg_power = remaining_power / float(area.size() - j)
				var fluctuation = avg_power * 0.4
				var power = avg_power + (rng.randf() * 2.0 - 1.0) * fluctuation
				power = clamp(power, 0.0, remaining_power)
				energy_veins[hk] = power / 100.0
				sector_by_hex[hk] = sector_idx
				remaining_power -= power
			if area.size() > 0:
				var hk = area[area.size() - 1].to_key()
				energy_veins[hk] = remaining_power / 100.0
				sector_by_hex[hk] = sector_idx
		elif i == 1:
			# Средняя жила: строго 6–8 гексов, руду даём каждому гексу напрямую; разброс между гексами не менее 50% (здесь 65%)
			var remaining_power = total_vein_power
			for j in range(area.size() - 1):
				var hex = area[j]
				var hk = hex.to_key()
				var avg_power = remaining_power / float(area.size() - j)
				var fluctuation = avg_power * 0.65
				var power = avg_power + (rng.randf() * 2.0 - 1.0) * fluctuation
				power = clamp(power, 0.0, remaining_power)
				energy_veins[hk] = power / 100.0
				sector_by_hex[hk] = sector_idx
				remaining_power -= power
			if area.size() > 0:
				var hk = area[area.size() - 1].to_key()
				energy_veins[hk] = remaining_power / 100.0
				sector_by_hex[hk] = sector_idx
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
						sector_by_hex[hex_key] = sector_idx
					energy_veins[hex_key] += circle["power"]
	
	# Точка руды на серединном перпендикуляре между центральной и средней жилой (равноудалена от обоих центров), на расстоянии 3 гекса от середины отрезка; 15–20 руды
	var extra_ore_hex: Hex = null
	if vein_count >= 2 and centers.size() >= 2:
		var c0 = centers[0]
		var c1 = centers[1]
		var mid_hex = Hex.hex_round((c0.q + c1.q) / 2.0, (c0.r + c1.r) / 2.0)
		var bisector_candidates: Array[Hex] = []
		for tile in all_hexes:
			var hex = tile.hex
			if hex.distance_to(c0) != hex.distance_to(c1):
				continue
			if hex.distance_to(mid_hex) != 3:
				continue
			if _is_too_close_to_critical(hex) or _is_checkpoint(hex):
				continue
			bisector_candidates.append(hex)
		if bisector_candidates.size() > 0:
			extra_ore_hex = bisector_candidates[rng.randi() % bisector_candidates.size()]
			var extra_amount = float(rng.randi_range(15, 20))
			var extra_key = extra_ore_hex.to_key()
			if energy_veins.has(extra_key):
				energy_veins[extra_key] += extra_amount / 100.0
			else:
				energy_veins[extra_key] = extra_amount / 100.0
				sector_by_hex[extra_key] = 0
	
	# Крайняя жила (сектор 2): лимит 60 на гекс, излишек перераспределяем по гексам с запасом < 60
	const FAR_VEIN_MAX_PER_HEX = 60.0
	var far_hexes: Array[String] = []
	for hk in sector_by_hex.keys():
		if sector_by_hex[hk] == 2:
			far_hexes.append(hk)
	if far_hexes.size() > 0:
		var capped_list: Array[Dictionary] = []
		var excess_total = 0.0
		for hk in far_hexes:
			var reserve = energy_veins[hk] * 100.0
			var capped = minf(reserve, FAR_VEIN_MAX_PER_HEX)
			excess_total += (reserve - capped)
			capped_list.append({"key": hk, "reserve": capped})
		capped_list.sort_custom(func(a, b): return a["reserve"] < b["reserve"])
		for entry in capped_list:
			if excess_total <= 0.0:
				break
			var room = FAR_VEIN_MAX_PER_HEX - entry["reserve"]
			var add = minf(excess_total, room)
			entry["reserve"] += add
			excess_total -= add
			energy_veins[entry["key"]] = entry["reserve"] / 100.0
	
	# Сохраняем гексы по жилам для индикатора расхода руды
	ore_vein_hexes.clear()
	for i in range(vein_areas.size()):
		ore_vein_hexes.append(vein_areas[i].duplicate())
	if extra_ore_hex != null:
		ore_vein_hexes.append([extra_ore_hex])
	
	# --- Создание сущностей руды ---
	for hex_key in energy_veins.keys():
		var power = energy_veins[hex_key]
		var hex = Hex.from_key(hex_key)
		var pixel_pos = hex.to_pixel(Config.HEX_SIZE)
		var sector = sector_by_hex.get(hex_key, 0)
		
		var ore_id = ecs.create_entity()
		ecs.positions[ore_id] = pixel_pos
		var reserve = power * 100.0
		if sector == 2:
			reserve *= 1.4
		ecs.add_component(ore_id, "ore", {
			"power": power,
			"max_reserve": reserve,
			"current_reserve": reserve,
			"hex": hex,
			"radius": Config.HEX_SIZE * 0.2 + power * Config.HEX_SIZE,
			"pulse_rate": 2.0,
			"is_highlighted": false,
			"sector": sector
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

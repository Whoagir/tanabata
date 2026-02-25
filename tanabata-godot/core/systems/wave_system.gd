# wave_system.gd
# Система волн и спавна врагов
class_name WaveSystem

var ecs: ECSWorld
var hex_map: HexMap

var current_wave_entity: int = GameTypes.INVALID_ENTITY_ID
# Плавное восстановление руды во время волны: накопление времени и учёт добавленного за волну
var _ore_restore_accumulator: float = 0.0
var _ore_restore_added_this_wave: Dictionary = {}  # ore_id -> float
# Кэш: ore_id -> restore_per_round (майнеры не меняются во время волны — считаем один раз за волну)
var _ore_restore_per_ore_cache: Dictionary = {}
# Кэш путей за волну: карта не меняется, так что ground/flying пути стабильны
var _cached_ground_path: Array = []
var _cached_flying_path: Array = []

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================================

func _init(ecs_: ECSWorld, hex_map_: HexMap):
	ecs = ecs_
	hex_map = hex_map_

# Для летающих: через центр только если отрезок (i -> i+1) длиннее, чем (i+1 -> i+2).
# Вход: если чекпоинт 1 входит в два самых удалённых от входа — летим вход->центр->1.
# Выход: если чекпоинт 6 входит в два самых удалённых от выхода — летим 6->центр->выход.
func _get_checkpoints_for_path(flying: bool) -> Array[Hex]:
	if not flying:
		return hex_map.checkpoints
	var center = Hex.ZERO()
	var cps = hex_map.checkpoints
	if cps.size() == 0:
		return cps
	var waypoints: Array[Hex] = []
	var entry = hex_map.entry
	var exit_hex = hex_map.exit
	var two_farthest_from_entry = _two_farthest_indices(cps, entry)
	var two_farthest_from_exit = _two_farthest_indices(cps, exit_hex)
	if 0 in two_farthest_from_entry:
		waypoints.append(center)
	waypoints.append(cps[0])
	for i in range(cps.size() - 1):
		var go_via_center = false
		if i + 2 < cps.size():
			var dist_current = cps[i].distance_to(cps[i + 1])
			var dist_next = cps[i + 1].distance_to(cps[i + 2])
			go_via_center = dist_current > dist_next
		if go_via_center:
			waypoints.append(center)
		waypoints.append(cps[i + 1])
	if cps.size() - 1 in two_farthest_from_exit:
		waypoints.append(center)
	return waypoints

func _two_farthest_indices(cps: Array, from_hex: Hex) -> Array:
	var dist_indices: Array = []
	for i in range(cps.size()):
		dist_indices.append({ "d": cps[i].distance_to(from_hex), "i": i })
	dist_indices.sort_custom(func(a, b): return a.d > b.d)
	var result: Array = []
	for j in range(min(2, dist_indices.size())):
		result.append(dist_indices[j].i)
	return result

# ============================================================================
# ОБНОВЛЕНИЕ
# ============================================================================

func update(delta: float):
	Profiler.start("wave_system")
	
	var current_phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	
	# Волны работают только в WAVE_STATE (не в BUILD и не в SELECTION)
	if current_phase != GameTypes.GamePhase.WAVE_STATE:
		Profiler.end("wave_system")
		return
	
	# Проверяем есть ли активная волна
	if current_wave_entity == GameTypes.INVALID_ENTITY_ID:
		# Начинаем новую волну
		start_wave()
		Profiler.end("wave_system")
		return
	
	if not ecs.has_component(current_wave_entity, "wave"):
		# Волна была, но сущность удалена - завершаем фазу
		_end_wave_phase()
		Profiler.end("wave_system")
		return
	
	var wave = ecs.waves[current_wave_entity]
	
	# Спавним врагов по таймеру
	wave["spawn_timer"] += delta
	
	if wave["spawn_timer"] >= wave["spawn_interval"] and wave["enemies_to_spawn"] > 0:
		_spawn_enemy(wave)
		wave["spawn_timer"] = 0.0
		wave["enemies_to_spawn"] -= 1
	
	# Проверяем завершение волны (все враги заспавнены и убиты/дошли)
	if wave["enemies_to_spawn"] == 0:
		var alive_enemies = _count_alive_enemies()
		if alive_enemies == 0:
			_end_wave_phase()
	
	# Плавное восстановление руды во время волны: каждые ORE_RESTORE_INTERVAL сек добавляем порцию
	_ore_restore_accumulator += delta
	while _ore_restore_accumulator >= Config.ORE_RESTORE_INTERVAL and GameManager.energy_network:
		_ore_restore_accumulator -= Config.ORE_RESTORE_INTERVAL
		# Кэш restore_per_round по жилам (один раз за волну — майнеры не меняются)
		if _ore_restore_per_ore_cache.is_empty():
			for ore_id in ecs.ores.keys():
				_ore_restore_per_ore_cache[ore_id] = GameManager.energy_network.get_ore_restore_per_round(ore_id)
		var portion = 1.0 / float(Config.ORE_RESTORE_TICKS_PER_WAVE)
		for ore_id in ecs.ores.keys():
			var ore = ecs.ores[ore_id]
			var cur = ore.get("current_reserve", 0.0)
			var max_r = ore.get("max_reserve", 0.0)
			if cur >= max_r:
				continue
			var add_per_round = _ore_restore_per_ore_cache.get(ore_id, 1.0)
			var add = add_per_round * portion
			add = minf(add, max_r - cur)
			if add > 0.0:
				ore["current_reserve"] = cur + add
				_ore_restore_added_this_wave[ore_id] = _ore_restore_added_this_wave.get(ore_id, 0.0) + add
	
	Profiler.end("wave_system")

# ============================================================================
# НАЧАЛО ВОЛНЫ
# ============================================================================

func start_wave():
	ecs.game_state["wave_skipped"] = false  # новая волна — не пропущена
	var current_wave_number = ecs.game_state.get("current_wave", 0) + 1
	ecs.game_state["current_wave"] = current_wave_number
	
	# Аналитика: только при старте волны — волна, лвл, XP, HP
	var player_level = 1
	var current_xp = 0
	var xp_to_next = 100
	var health = 100
	for player_id in ecs.player_states.keys():
		var player = ecs.player_states[player_id]
		player_level = player.get("level", 1)
		current_xp = player.get("current_xp", 0)
		xp_to_next = player.get("xp_to_next_level", 100)
		health = player.get("health", 100)
		break
	var total_xp = Config.get_total_xp(player_level, current_xp)
	print("Wave %d | Lv.%d | XP: %d (%d/%d) | HP: %d" % [current_wave_number, player_level, total_xp, current_xp, xp_to_next, health])
	
	# Сброс подсветки пройденных чекпоинтов (как в Go)
	ecs.game_state["cleared_checkpoints"] = {}
	# Статистика урона вышек за волну
	ecs.game_state["tower_damage_this_wave"] = {}
	# Сброс учёта восстановления руды за волну (для плавного восстановления)
	_ore_restore_added_this_wave.clear()
	_ore_restore_accumulator = 0.0
	_ore_restore_per_ore_cache.clear()
	
	# Получаем определение волны
	var wave_def = DataRepository.get_wave_def(current_wave_number)
	if wave_def.is_empty():
		push_error("[WaveSystem] No wave definition for wave %d" % current_wave_number)
		return
	# Размер волны (кол-во врагов) — для баланса вулкана и др.
	var enemy_count: int
	var enemy_def_id: String
	var spawn_order: Array = []  # для смешанных волн: очередь enemy_id
	if wave_def.has("enemies") and wave_def["enemies"] is Array:
		for e in wave_def["enemies"]:
			var eid = e.get("enemy_id", "")
			var c = int(e.get("count", 0))
			for i in range(c):
				spawn_order.append(eid)
		spawn_order.shuffle()
		enemy_count = spawn_order.size()
		if enemy_count == 0:
			push_error("[WaveSystem] Wave %d 'enemies' is empty" % current_wave_number)
			return
		# Путь для смешанной волны считаем по первому врагу (для общего числа; путь по факту — в _spawn_enemy)
		enemy_def_id = spawn_order[0]
	else:
		enemy_count = wave_def.get("count", 5)
		enemy_def_id = wave_def.get("enemy_id", "ENEMY_NORMAL_WEAK")
	
	ecs.game_state["current_wave_enemy_count"] = enemy_count
	var enemy_def = DataRepository.get_enemy_def(enemy_def_id)
	var flying = enemy_def.get("flying", false)
	
	# Кэшируем ground-путь (всегда нужен)
	var ground_cps = _get_checkpoints_for_path(false)
	_cached_ground_path = Pathfinding.find_path_through_checkpoints(
		hex_map.entry, ground_cps, hex_map.exit, hex_map, false
	)
	# Кэшируем flying-путь (считаем один раз, а не на каждого летающего врага)
	var flying_cps = _get_checkpoints_for_path(true)
	_cached_flying_path = Pathfinding.find_path_through_checkpoints(
		hex_map.entry, flying_cps, hex_map.exit, hex_map, true
	)
	
	var path = _cached_flying_path if flying else _cached_ground_path
	if path.is_empty():
		push_error("[WaveSystem] Cannot find path through checkpoints! Towers blocking?")
		return
	
	current_wave_entity = ecs.create_entity()
	var spawn_interval = wave_def.get("spawn_interval", 1.0)
	
	# Распределяем урон между врагами
	var damage_per_enemy = _distribute_damage(enemy_count)
	
	var wave_data = {
		"wave_number": current_wave_number,
		"enemy_def_id": enemy_def_id,
		"enemies_to_spawn": enemy_count,
		"spawn_interval": spawn_interval,
		"spawn_timer": 0.0,
		"current_path": path,
		"damage_per_enemy": damage_per_enemy
	}
	if spawn_order.size() > 0:
		wave_data["spawn_order"] = spawn_order
	
	ecs.add_component(current_wave_entity, "wave", wave_data)
	

# ============================================================================
# СПАВН ВРАГА
# ============================================================================

func _spawn_enemy(wave: Dictionary):
	var enemy_def_id: String
	var path: Array
	if wave.has("spawn_order") and wave["spawn_order"].size() > 0:
		enemy_def_id = wave["spawn_order"].pop_front()
		var enemy_def_for_path = DataRepository.get_enemy_def(enemy_def_id)
		var flying = enemy_def_for_path.get("flying", false)
		path = _cached_flying_path if flying else _cached_ground_path
	else:
		enemy_def_id = wave["enemy_def_id"]
		path = wave.get("current_path", [])
	
	var enemy_def = DataRepository.get_enemy_def(enemy_def_id)
	var wave_def = DataRepository.get_wave_def(wave.get("wave_number", 1))
	
	if enemy_def.is_empty():
		push_error("[WaveSystem] Enemy definition not found: %s" % enemy_def_id)
		return
	
	var diff = ecs.game_state.get("difficulty", GameTypes.Difficulty.MEDIUM)
	var diff_health = Config.get_difficulty_health_multiplier(diff)
	var diff_regen = Config.get_difficulty_regen_multiplier(diff)
	var diff_speed = Config.get_difficulty_speed_multiplier(diff)
	
	var base_health = wave_def.get("health_override", enemy_def.get("health", 100))
	if base_health <= 0:
		base_health = enemy_def.get("health", 100)
	var health_mult = wave_def.get("health_multiplier", 1.0)
	if wave_def.has("health_multiplier_flying") and wave_def.has("health_multiplier_ground"):
		health_mult = wave_def.get("health_multiplier_flying", 1.0) if enemy_def.get("flying", false) else wave_def.get("health_multiplier_ground", 1.0)
	base_health = int(base_health * health_mult * diff_health)
	# Обучение: враги слабее на 70% (30% от обычного HP)
	if ecs.game_state.get("is_tutorial", false):
		base_health = max(1, int(base_health * 0.3))
	var regen_per_sec = wave_def.get("regen", 0) * diff_regen
	
	var enemy_id = ecs.create_entity()
	var start_hex = hex_map.entry
	var start_pos = start_hex.to_pixel(Config.HEX_SIZE)
	
	ecs.positions[enemy_id] = start_pos
	
	var speed = enemy_def.get("speed", 80.0) * wave_def.get("speed_multiplier", 1.0) * diff_speed
	ecs.velocities[enemy_id] = Vector2.ZERO
	
	ecs.add_component(enemy_id, "health", {
		"current": base_health,
		"max": base_health
	})
	
	var abilities = _get_wave_abilities(wave).duplicate()
	if enemy_def_id == "ENEMY_HEALER":
		abilities.append("healer_aura")
	if enemy_def_id == "ENEMY_TANK":
		abilities.append("aggro")
	var phys_bonus = wave_def.get("physical_armor_bonus", 0) + Config.get_difficulty_physical_armor_bonus(diff)
	var mag_bonus = wave_def.get("magical_armor_bonus", 0) + Config.get_difficulty_magical_armor_bonus(diff)
	var enemy_data = {
		"def_id": enemy_def_id,
		"physical_armor": enemy_def.get("physical_armor", 0) + phys_bonus,
		"magical_armor": enemy_def.get("magical_armor", 0) + mag_bonus,
		"last_checkpoint_index": -1,
		"damage_to_player": wave["damage_per_enemy"].pop_front() if wave["damage_per_enemy"].size() > 0 else 10,
		"speed": speed,
		"is_highlighted": false,
		"flying": enemy_def.get("flying", false),
		"abilities": abilities,
		"regen": regen_per_sec,
		"evasion_chance": wave_def.get("evasion_chance", 0.0)
	}
	if abilities.has("rush"):
		enemy_data["rush_cooldown_left"] = 5.0
		enemy_data["rush_duration_left"] = 0.0
	if abilities.has("blink"):
		enemy_data["blink_cooldown_left"] = Config.BLINK_START_COOLDOWN
	if abilities.has("reflection"):
		enemy_data["reflection_stacks"] = 0
		enemy_data["reflection_cooldown_left"] = Config.REFLECTION_COOLDOWN
	if abilities.has("aggro"):
		enemy_data["aggro_duration_left"] = 0.0
		enemy_data["aggro_cooldown_left"] = Config.AGGRO_COOLDOWN
	ecs.add_component(enemy_id, "enemy", enemy_data)
	
	# Путь (для смешанной волны path уже посчитан выше, иначе из wave)
	ecs.add_component(enemy_id, "path", {
		"hexes": path.duplicate(),
		"current_index": 0
	})
	
	# Визуал (КАК БЫЛО!)
	if "visuals" in enemy_def:
		var vis = enemy_def["visuals"]
		var color_dict = vis.get("color", {"r": 128, "g": 128, "b": 128, "a": 255})
		ecs.add_component(enemy_id, "renderable", {
			"color": Color(color_dict["r"] / 255.0, color_dict["g"] / 255.0, color_dict["b"] / 255.0, color_dict["a"] / 255.0),
			"radius": Config.HEX_SIZE * vis.get("radius_factor", 0.5),
		"visible": true
	})

# ============================================================================
# ЗАВЕРШЕНИЕ ВОЛНЫ
# ============================================================================

func _end_wave_phase():
	# Итоги урона вышек в консоль (для баланса)
	if GameManager:
		GameManager.log_wave_damage_report()
	# Удаляем сущность волны
	if current_wave_entity != GameTypes.INVALID_ENTITY_ID:
		ecs.destroy_entity(current_wave_entity)
		current_wave_entity = GameTypes.INVALID_ENTITY_ID
	
	# Очищаем только снаряды (враги уже удалены в ProjectileSystem)
	for proj_id in ecs.projectiles.keys():
		ecs.destroy_entity(proj_id)
	
	# Возобновляемость руды: за волну ровно restore_per_round на жилу (часть уже добавлена плавно во время волны, остаток — сейчас)
	for ore_id in ecs.ores.keys():
		var ore = ecs.ores[ore_id]
		var cur = ore.get("current_reserve", 0.0)
		var max_r = ore.get("max_reserve", 0.0)
		if cur >= max_r:
			continue
		var add_per_round = 1.0
		if GameManager.energy_network:
			add_per_round = GameManager.energy_network.get_ore_restore_per_round(ore_id)
		var already_added = _ore_restore_added_this_wave.get(ore_id, 0.0)
		var remainder = maxf(0.0, add_per_round - already_added)
		remainder = minf(remainder, max_r - cur)
		if remainder > 0.0:
			ore["current_reserve"] = cur + remainder
	
	# Пересобираем энергосеть по обновлённым запасам руды — к началу фазы строительства сеть уже корректна
	if GameManager.energy_network:
		GameManager.energy_network.rebuild_energy_network()
	
	# Автоматически переключаем в фазу строительства
	ecs.game_state["phase"] = GameTypes.GamePhase.BUILD_STATE
	ecs.game_state["towers_built_this_phase"] = 0
	ecs.game_state["placements_made_this_phase"] = 0
	
	# Обучение: плашка второй фазы строительства (шаг 6) — при естественном завершении волны transition_to_build не вызывается
	if ecs.game_state.get("is_tutorial", false) and GameManager:
		var idx = ecs.game_state.get("tutorial_step_index", 0)
		var steps = GameManager.get_tutorial_steps()
		if steps.size() > 6 and (idx == 4 or idx == 5):
			ecs.game_state["tutorial_step_index"] = 6
			print("[Tutorial] >>> forced step -> 6 (second build phase, plaque 'Фаза СТРОИТЕЛЬСТВА...')")
	
	# Обучение: если достигнут лимит волн — уровень пройден
	var cw = ecs.game_state.get("current_wave", 0)
	var wave_max = ecs.game_state.get("tutorial_wave_max", 0)
	if ecs.game_state.get("is_tutorial", false) and wave_max > 0 and cw >= wave_max:
		var idx = ecs.game_state.get("tutorial_index", 0)
		GameManager.tutorial_level_completed.emit(idx)

# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ============================================================================

func _get_wave_abilities(wave: Dictionary) -> Array:
	"""Способности врагов на этой волне (из wave_def, например effect_immunity, disarm)"""
	var wave_def = DataRepository.get_wave_def(wave.get("wave_number", 1))
	return wave_def.get("abilities", [])

func _count_alive_enemies() -> int:
	var count = 0
	for enemy_id in ecs.enemies.keys():
		var health = ecs.healths.get(enemy_id)
		if health and health.get("current", 0) > 0:
			count += 1
	return count

func _distribute_damage(enemy_count: int) -> Array:
	var total_damage = Config.TOTAL_WAVE_DAMAGE
	var base_damage = int(total_damage / enemy_count)
	var remainder = total_damage % enemy_count
	
	var damages = []
	for i in range(enemy_count):
		damages.append(base_damage)
	
	# Распределяем остаток случайно
	for i in range(remainder):
		var index = randi() % enemy_count
		damages[index] += 1
	
	# Перемешиваем
	damages.shuffle()
	
	return damages

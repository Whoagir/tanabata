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
# За волну ровно ORE_RESTORE_TICKS_PER_WAVE тиков (фикс. сумма), не больше — длинные волны не дают лишней руды
var _ore_restore_ticks_this_wave: int = 0
var _ore_restore_wave_mult: float = 1.0  # коэффициент по номеру волны (Config.get_ore_restore_mult_for_wave)
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
		if ecs.game_state.get("alive_enemies_count", 0) == 0:
			_end_wave_phase()
	
	# Плавное восстановление руды: тик раз в ORE_RESTORE_INTERVAL сек; за волну ровно ORE_RESTORE_TICKS_PER_WAVE тиков (фикс. сумма на жилу)
	_ore_restore_accumulator += delta
	while _ore_restore_accumulator >= Config.ORE_RESTORE_INTERVAL and GameManager.energy_network:
		_ore_restore_accumulator -= Config.ORE_RESTORE_INTERVAL
		if _ore_restore_ticks_this_wave >= Config.ORE_RESTORE_TICKS_PER_WAVE:
			continue
		_ore_restore_ticks_this_wave += 1
		if _ore_restore_per_ore_cache.is_empty():
			for ore_id in ecs.ores.keys():
				_ore_restore_per_ore_cache[ore_id] = GameManager.energy_network.get_ore_restore_per_round(ore_id)
		var portion = 1.0 / float(Config.ORE_RESTORE_TICKS_PER_WAVE)
		var did_add_this_tick = false
		for ore_id in ecs.ores.keys():
			var ore = ecs.ores[ore_id]
			var cur = ore.get("current_reserve", 0.0)
			var max_r = ore.get("max_reserve", 0.0)
			if cur >= max_r:
				continue
			var add_per_round = _ore_restore_per_ore_cache.get(ore_id, 1.0)
			var add = add_per_round * portion * _ore_restore_wave_mult
			add = minf(add, max_r - cur)
			if add > 0.0:
				ore["current_reserve"] = cur + add
				_ore_restore_added_this_wave[ore_id] = _ore_restore_added_this_wave.get(ore_id, 0.0) + add
				did_add_this_tick = true
		# После восстановления руды пересобираем сеть, чтобы вышки снова включились
		if did_add_this_tick and GameManager.energy_network:
			GameManager.energy_network.rebuild_energy_network()
	
	Profiler.end("wave_system")

# ============================================================================
# НАЧАЛО ВОЛНЫ
# ============================================================================

func start_wave():
	ecs.game_state["wave_skipped"] = false  # новая волна — не пропущена
	var current_wave_number = ecs.game_state.get("current_wave", 0) + 1
	ecs.game_state["current_wave"] = current_wave_number
	GameManager.record_wave_snapshot()

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
	
	# Сброс подсветки пройденных чекпоинтов (как в Go)
	ecs.game_state["cleared_checkpoints"] = {}
	# Статистика урона вышек за волну
	ecs.game_state["tower_damage_this_wave"] = {}
	ecs.game_state["energy_line_damage_this_wave"] = 0
	# Сброс учёта восстановления руды за волну (для плавного восстановления)
	_ore_restore_added_this_wave.clear()
	_ore_restore_accumulator = 0.0
	_ore_restore_per_ore_cache.clear()
	_ore_restore_ticks_this_wave = 0
	_ore_restore_wave_mult = Config.get_ore_restore_mult_for_wave(current_wave_number)
	
	# Получаем определение волны (с учётом перемешивания по интервалам: контент из source_wave_number, масштаб HP по EHP)
	var wave_def = DataRepository.get_wave_def(current_wave_number)
	var health_scale: float = 1.0
	var source_wave_number: int = current_wave_number
	var shuffle_map = ecs.game_state.get("wave_shuffle_map", {})
	if shuffle_map.has(current_wave_number):
		var entry = shuffle_map[current_wave_number]
		source_wave_number = entry.get("source_wave_number", current_wave_number)
		health_scale = entry.get("health_scale", 1.0)
		wave_def = DataRepository.get_wave_def(source_wave_number)
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
		if wave_def.get("shuffle", true):
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
	
	# Система успеха: количество врагов в волне зависит от уровня успеха (стандарт = 10). Боссы не масштабируем.
	var is_boss_wave = _wave_has_boss(wave_def, enemy_def_id)
	var success_level = ecs.game_state.get("success_level", Config.SUCCESS_LEVEL_DEFAULT)
	var base_count = enemy_count
	if not is_boss_wave:
		enemy_count = maxi(1, int(base_count * float(success_level) / 10.0))
		if spawn_order.size() > 0:
			while spawn_order.size() < enemy_count:
				spawn_order.append(spawn_order[spawn_order.size() % base_count])
			if spawn_order.size() > enemy_count:
				spawn_order.resize(enemy_count)
	
	ecs.game_state["current_wave_enemy_count"] = enemy_count
	ecs.game_state["alive_enemies_count"] = 0  # увеличивается в _spawn_enemy, уменьшается в ecs.kill_enemy
	ecs.game_state["hud_refresh_requested"] = true  # HUD обновит волну/счётчики при следующем кадре
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
	
	var ground_path_len = _cached_ground_path.size()
	var enemy_summary = _format_wave_enemy_summary(wave_def, enemy_count, enemy_def_id, spawn_order, source_wave_number, ground_path_len)
	print("Wave %d | Lv.%d | XP: %d (%d/%d) | HP: %d | %s" % [current_wave_number, player_level, total_xp, current_xp, xp_to_next, health, enemy_summary])
	
	current_wave_entity = ecs.create_entity()
	var spawn_interval = wave_def.get("spawn_interval", 1.0)
	
	# Распределяем урон между врагами (total_wave_damage в определении волны переопределяет константу)
	var damage_per_enemy = _distribute_damage(enemy_count, wave_def)
	
	var wave_data = {
		"wave_number": current_wave_number,
		"enemy_def_id": enemy_def_id,
		"enemies_to_spawn": enemy_count,
		"spawn_interval": spawn_interval,
		"spawn_timer": 0.0,
		"current_path": path,
		"damage_per_enemy": damage_per_enemy,
		"health_scale": health_scale,
		"source_wave_number": source_wave_number
	}
	if spawn_order.size() > 0:
		wave_data["spawn_order"] = spawn_order
	# Волна 40 (Тройник): способности и evasion_chance у каждого босса свои, порядок спавна фиксированный
	if current_wave_number == 40 and wave_def.has("enemies"):
		var ability_sets: Array = []
		var evasion_sets: Array = []
		for e in wave_def["enemies"]:
			var c = int(e.get("count", 0))
			var ab = e.get("abilities", [])
			var ev = float(e.get("evasion_chance", 0.0))
			for _i in range(c):
				ability_sets.append(ab.duplicate())
				evasion_sets.append(ev)
		wave_data["ability_sets"] = ability_sets
		wave_data["evasion_chance_sets"] = evasion_sets
		wave_data["triplet_spawn_index"] = 0
		ecs.game_state["wave_40_triplet_ids"] = []
	
	ecs.add_component(current_wave_entity, "wave", wave_data)

	ecs.game_state["wave_game_time"] = 0.0
	var _wa_abilities: Array = wave_def.get("abilities", [])
	var _wa_enemy_def = DataRepository.get_enemy_def(enemy_def_id)
	var _wa_base_speed = _wa_enemy_def.get("speed", 80)
	var _wa_base_hp_raw = _wa_enemy_def.get("health", 100)
	var _wa_regen_base = Config.get_regen_base_for_wave(source_wave_number)
	ecs.game_state["wave_analytics"] = {
		"wave_number": current_wave_number,
		"spawned": enemy_count,
		"passed": 0,
		"total_hp": 0,
		"enemy_def_id": enemy_def_id,
		"enemy_abilities": ";".join(PackedStringArray(_wa_abilities)) if _wa_abilities.size() > 0 else "",
		"enemy_base_speed": _wa_base_speed,
		"enemy_base_hp": _wa_base_hp_raw,
		"enemy_regen_base": _wa_regen_base,
		"enemy_flying": 1 if _wa_enemy_def.get("flying", false) else 0,
		"success_level_before": ecs.game_state.get("success_level", Config.SUCCESS_LEVEL_DEFAULT),
		"player_hp_before": health,
		"source_wave": source_wave_number,
	}
	
	# Аналитика лабиринта: время старта (реал. и игр.), длина пути, руда по секторам до волны, массивы для прогресса врагов
	ecs.game_state["wave_start_time"] = Time.get_ticks_msec() / 1000.0
	ecs.game_state["wave_game_time"] = 0.0  # накапливается каждым кадром как scaled_delta
	ecs.game_state["wave_path_length"] = path.size()
	ecs.game_state["wave_ore_by_sector_start"] = GameManager.get_ore_totals_by_sector() if GameManager else {}
	ecs.game_state["wave_ore_spent_total"] = 0.0
	ecs.game_state["wave_ore_spent_by_sector"] = {0: 0.0, 1: 0.0, 2: 0.0}
	ecs.game_state["tower_ore_spent_this_wave"] = {}
	ecs.game_state["wave_enemy_checkpoints"] = []
	ecs.game_state["wave_enemy_path_indices"] = []
	ecs.game_state["wave_enemy_checkpoint_times"] = {}
	ecs.game_state["gold_spawned_this_wave"] = false

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
	var wave_def = DataRepository.get_wave_def(wave.get("source_wave_number", wave.get("wave_number", 1)))
	
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
	health_mult *= wave_def.get("health_multiplier_modifier", 1.0)
	base_health = int(base_health * health_mult * diff_health)
	var source_wn = wave.get("source_wave_number", wave.get("wave_number", 1))
	var code_mult = DataRepository.get_wave_health_code_multiplier(source_wn, ecs.game_state.get("is_tutorial", false))
	base_health = max(1, int(base_health * code_mult))
	if enemy_def.get("flying", false) and source_wn >= 11 and source_wn <= 15:
		base_health = max(1, int(base_health * DataRepository.get_flying_waves_11_15_hp_multiplier()))
	if source_wn >= 6 and source_wn <= 9 and enemy_def_id == "ENEMY_FAST":
		base_health = max(1, int(base_health * Config.ENEMY_FAST_WAVES_6_9_HP_MULT))
	var health_scale = wave.get("health_scale", 1.0)
	base_health = max(1, int(base_health * health_scale))
	var speed = enemy_def.get("speed", 80.0) * wave_def.get("speed_multiplier", 1.0) * diff_speed * wave_def.get("speed_multiplier_modifier", 1.0)
	speed *= Config.ENEMY_SPEED_GLOBAL_MULT
	if enemy_def_id == "ENEMY_TOUGH" or enemy_def_id == "ENEMY_TOUGH_2":
		speed *= Config.ENEMY_SPEED_TOUGH_MULT
	elif enemy_def_id == "ENEMY_DARKNESS_1" or enemy_def_id == "ENEMY_DARKNESS_2":
		speed *= Config.ENEMY_SPEED_DARKNESS_MULT
	elif enemy_def_id == "ENEMY_BOSS":
		speed *= Config.ENEMY_SPEED_BOSS_MULT
	var abilities: Array
	if wave.has("ability_sets") and wave.has("triplet_spawn_index"):
		var idx = wave["triplet_spawn_index"]
		abilities = wave["ability_sets"][idx].duplicate()
		if wave.has("evasion_chance_sets") and idx < wave["evasion_chance_sets"].size():
			wave["current_evasion_chance"] = wave["evasion_chance_sets"][idx]
		wave["triplet_spawn_index"] = idx + 1
	else:
		abilities = _get_wave_abilities(wave).duplicate()
		wave["current_evasion_chance"] = null
	if enemy_def_id == "ENEMY_HEALER":
		abilities.append("healer_aura")
		if wave.get("wave_number", 0) == 34:
			abilities.append("bkb")
	if enemy_def_id == "ENEMY_TANK":
		abilities.append("aggro")
	var flying = enemy_def.get("flying", false)
	var path_length_hexes = Config.REGEN_FLYING_PATH if flying else float(path.size())
	var base_regen = Config.get_regen_base_for_wave(source_wn)
	var regen_scale = Config.get_regen_scale(path_length_hexes, speed, abilities, flying)
	var regen_per_sec = base_regen * regen_scale * diff_regen * wave_def.get("regen_multiplier_modifier", 1.0)
	regen_per_sec = maxf(0.0, regen_per_sec)

	var is_gold = false
	if enemy_def_id != "ENEMY_BOSS":
		var wave_num = wave.get("wave_number", 1)
		var last_gold_wave = ecs.game_state.get("last_gold_spawned_wave", 0)
		var no_gold_first_5 = wave_num > 5
		var no_gold_within_5_after = last_gold_wave <= 0 or wave_num > last_gold_wave + 5
		if no_gold_first_5 and no_gold_within_5_after and not ecs.game_state.get("gold_spawned_this_wave", false):
			if ecs.game_state.get("success_level", Config.SUCCESS_LEVEL_DEFAULT) >= Config.GOLD_MIN_SUCCESS_LEVEL:
				if randf() < Config.GOLD_CREATURE_CHANCE:
					is_gold = true
					ecs.game_state["gold_spawned_this_wave"] = true
					ecs.game_state["last_gold_spawned_wave"] = wave_num
					base_health = max(1, int(base_health * Config.GOLD_CREATURE_HP_MULT))
	
	var enemy_id = ecs.create_entity()
	var start_hex = hex_map.entry
	var start_pos = start_hex.to_pixel(Config.HEX_SIZE)
	
	ecs.positions[enemy_id] = start_pos
	
	ecs.velocities[enemy_id] = Vector2.ZERO
	
	ecs.add_component(enemy_id, "health", {
		"current": base_health,
		"max": base_health
	})
	if ecs.game_state.has("wave_analytics"):
		var wa = ecs.game_state["wave_analytics"]
		wa["total_hp"] = wa.get("total_hp", 0) + base_health
	
	var phys_bonus = wave_def.get("physical_armor_bonus", 0) + Config.get_difficulty_physical_armor_bonus(diff)
	var mag_bonus = wave_def.get("magical_armor_bonus", 0) + Config.get_difficulty_magical_armor_bonus(diff)
	var mag_armor = (enemy_def.get("magical_armor", 0) + mag_bonus) * wave_def.get("magical_armor_multiplier", 1.0)
	var enemy_data = {
		"def_id": enemy_def_id,
		"spawned_wave": wave.get("wave_number", 1),
		"pure_damage_resistance": wave_def.get("pure_damage_resistance", 0.0),
		"physical_armor": enemy_def.get("physical_armor", 0) + phys_bonus,
		"magical_armor": mag_armor,
		"pure_armor": enemy_def.get("pure_armor", 0),
		"last_checkpoint_index": -1,
		"damage_to_player": wave["damage_per_enemy"].pop_front() if wave["damage_per_enemy"].size() > 0 else 10,
		"speed": speed,
		"is_highlighted": false,
		"flying": enemy_def.get("flying", false),
		"abilities": abilities,
		"regen": regen_per_sec,
		"evasion_chance": wave.get("current_evasion_chance") if wave.get("current_evasion_chance") != null else wave_def.get("evasion_chance", 0.0),
		"is_gold": is_gold
	}
	if abilities.has("rush"):
		var rush_start_mult = wave_def.get("rush_start_cooldown_multiplier", 1.0)
		enemy_data["rush_cooldown_left"] = Config.RUSH_COOLDOWN * rush_start_mult
		enemy_data["rush_duration_left"] = 0.0
	if abilities.has("blink"):
		var start_cd = wave_def.get("blink_start_cooldown", Config.BLINK_START_COOLDOWN)
		enemy_data["blink_cooldown_left"] = start_cd + randf() * 0.2
		if wave_def.has("blink_hexes"):
			enemy_data["blink_hexes"] = wave_def["blink_hexes"]
		if wave_def.has("blink_cooldown"):
			enemy_data["blink_cooldown"] = wave_def["blink_cooldown"]
	if abilities.has("reflection"):
		enemy_data["reflection_stacks"] = 0
		enemy_data["reflection_cooldown_left"] = Config.REFLECTION_COOLDOWN
	if abilities.has("aggro"):
		enemy_data["aggro_duration_left"] = 0.0
		enemy_data["aggro_cooldown_left"] = Config.AGGRO_COOLDOWN
	ecs.add_component(enemy_id, "enemy", enemy_data)
	
	if wave.get("wave_number", 0) == 40 and ecs.game_state.has("wave_40_triplet_ids"):
		ecs.game_state["wave_40_triplet_ids"].append(enemy_id)
	
	# Путь (для смешанной волны path уже посчитан выше, иначе из wave)
	ecs.add_component(enemy_id, "path", {
		"hexes": path.duplicate(),
		"current_index": 0
	})
	
	# Визуал (золотой цвет для голд-существа)
	if "visuals" in enemy_def:
		var vis = enemy_def["visuals"]
		var color_dict = vis.get("color", {"r": 128, "g": 128, "b": 128, "a": 255})
		var color = Color(color_dict["r"] / 255.0, color_dict["g"] / 255.0, color_dict["b"] / 255.0, color_dict["a"] / 255.0)
		if is_gold:
			color = Color(1.0, 0.84, 0.0, 1.0)
		ecs.add_component(enemy_id, "renderable", {
			"color": color,
			"radius": Config.HEX_SIZE * vis.get("radius_factor", 0.5),
			"visible": true
		})
	ecs.game_state["alive_enemies_count"] = ecs.game_state.get("alive_enemies_count", 0) + 1

# ============================================================================
# ЗАВЕРШЕНИЕ ВОЛНЫ
# ============================================================================

func _end_wave_phase():
	# Удаляем сущность волны
	if current_wave_entity != GameTypes.INVALID_ENTITY_ID:
		ecs.destroy_entity(current_wave_entity)
		current_wave_entity = GameTypes.INVALID_ENTITY_ID
	
	# Зоны крика и станы от крика — сбрасываем, чтобы визуал не оставался в фазе строительства
	ecs.scream_zones.clear()
	ecs.scream_stun.clear()
	ecs.scream_damage_bonus.clear()
	
	# Очищаем только снаряды (враги уже удалены в ProjectileSystem)
	for proj_id in ecs.projectiles.keys():
		ecs.destroy_entity(proj_id)
	
	# Возобновляемость руды: за волну ровно restore_per_round * wave_mult на жилу (остаток, если волна закончилась до 20 тиков)
	var wave_num = ecs.game_state.get("current_wave", 1)
	var wave_mult = Config.get_ore_restore_mult_for_wave(wave_num)
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
		var remainder = maxf(0.0, add_per_round * wave_mult - already_added)
		remainder = minf(remainder, max_r - cur)
		if remainder > 0.0:
			ore["current_reserve"] = cur + remainder
			_ore_restore_added_this_wave[ore_id] = already_added + remainder
	
	if ecs.game_state.has("wave_analytics"):
		var wa = ecs.game_state["wave_analytics"]
		wa["killed"] = wa.get("spawned", 0) - wa.get("passed", 0)
		wa["duration_sec"] = ecs.game_state.get("wave_game_time", 0.0)
		wa["success_level_after"] = ecs.game_state.get("success_level", Config.SUCCESS_LEVEL_DEFAULT)
		wa["ore_spent"] = ecs.game_state.get("wave_ore_spent_total", 0.0)
		var _wa_hp_after = 100
		for _wa_pid in ecs.player_states.keys():
			_wa_hp_after = ecs.player_states[_wa_pid].get("health", 100)
			break
		wa["player_hp_after"] = _wa_hp_after
	
	# Сохраняем для лога: сколько руды восстановлено за волну по секторам (с учётом остатка)
	var ore_restored_by_sector = {0: 0.0, 1: 0.0, 2: 0.0}
	for ore_id in _ore_restore_added_this_wave.keys():
		var ore = ecs.ores.get(ore_id)
		if ore:
			var s = clampi(ore.get("sector", 0), 0, 2)
			ore_restored_by_sector[s] = ore_restored_by_sector.get(s, 0.0) + _ore_restore_added_this_wave[ore_id]
	ecs.game_state["wave_ore_restored_by_sector"] = ore_restored_by_sector
	if GameManager:
		GameManager.log_wave_damage_report()
	
	# Пересобираем энергосеть по обновлённым запасам руды — к началу фазы строительства сеть уже корректна
	if GameManager.energy_network:
		GameManager.energy_network.rebuild_energy_network()
	
	# Автоматически переключаем в фазу строительства
	ecs.game_state["phase"] = GameTypes.GamePhase.BUILD_STATE
	ecs.game_state["towers_built_this_phase"] = 0
	ecs.game_state["placements_made_this_phase"] = 0
	if ecs.game_state.has("first_wave_attack_sequence"):
		ecs.game_state.erase("first_wave_attack_sequence")
	if GameManager:
		ecs.game_state["stash_queue"] = GameManager.get_initial_stash_letters()
	
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
	"""Способности врагов на этой волне (из wave_def; при перемешивании — из source_wave_number)"""
	var wave_def = DataRepository.get_wave_def(wave.get("source_wave_number", wave.get("wave_number", 1)))
	return wave_def.get("abilities", [])

func _count_alive_enemies() -> int:
	var count = 0
	for enemy_id in ecs.enemies.keys():
		var health = ecs.healths.get(enemy_id)
		if health and health.get("current", 0) > 0:
			count += 1
	return count

func _wave_has_boss(wave_def: Dictionary, enemy_def_id: String) -> bool:
	if enemy_def_id == "ENEMY_BOSS":
		return true
	if wave_def.has("enemies") and wave_def["enemies"] is Array:
		for e in wave_def["enemies"]:
			if e.get("enemy_id", "") == "ENEMY_BOSS":
				return true
	return false

func _distribute_damage(enemy_count: int, wave_def: Dictionary = {}) -> Array:
	var total_damage = int(wave_def.get("total_wave_damage", Config.TOTAL_WAVE_DAMAGE))
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

func _format_wave_enemy_summary(wave_def: Dictionary, enemy_count: int, enemy_def_id: String, spawn_order: Array, source_wave_number: int, ground_path_len: int) -> String:
	var diff = ecs.game_state.get("difficulty", GameTypes.Difficulty.MEDIUM)
	var diff_health = Config.get_difficulty_health_multiplier(diff)
	var diff_regen = Config.get_difficulty_regen_multiplier(diff)
	var diff_speed = Config.get_difficulty_speed_multiplier(diff)
	var regen_mod = wave_def.get("regen_multiplier_modifier", 1.0)
	var base_regen = Config.get_regen_base_for_wave(source_wave_number)
	var parts: Array = []
	if spawn_order.size() > 0:
		var count_by_id = {}
		for eid in spawn_order:
			count_by_id[eid] = count_by_id.get(eid, 0) + 1
		for eid in count_by_id.keys():
			var c = count_by_id[eid]
			var ed = DataRepository.get_enemy_def(eid)
			var name_short = ed.get("name", eid)
			var base_h = wave_def.get("health_override", ed.get("health", 100))
			if base_h <= 0:
				base_h = ed.get("health", 100)
			var hm = wave_def.get("health_multiplier", 1.0) * wave_def.get("health_multiplier_modifier", 1.0)
			var hp = int(base_h * hm * diff_health)
			var spd = ed.get("speed", 80) * wave_def.get("speed_multiplier", 1.0) * diff_speed * wave_def.get("speed_multiplier_modifier", 1.0)
			spd *= Config.ENEMY_SPEED_GLOBAL_MULT
			if eid == "ENEMY_TOUGH" or eid == "ENEMY_TOUGH_2":
				spd *= Config.ENEMY_SPEED_TOUGH_MULT
			elif eid == "ENEMY_DARKNESS_1" or eid == "ENEMY_DARKNESS_2":
				spd *= Config.ENEMY_SPEED_DARKNESS_MULT
			elif eid == "ENEMY_BOSS":
				spd *= Config.ENEMY_SPEED_BOSS_MULT
			var flying = ed.get("flying", false)
			var path_len = Config.REGEN_FLYING_PATH if flying else float(ground_path_len)
			var ab = wave_def.get("abilities", [])
			var regen_scale = Config.get_regen_scale(path_len, spd, ab, flying)
			var reg = base_regen * regen_scale * diff_regen * regen_mod
			var ab_str = ", ".join(ab) if ab.size() > 0 else "—"
			parts.append("%s x%d | HP≈%d скор.%.0f реген%.1f/с | спос.: %s" % [name_short, c, hp, spd, reg, ab_str])
	else:
		var ed = DataRepository.get_enemy_def(enemy_def_id)
		var name_short = ed.get("name", enemy_def_id)
		var base_h = wave_def.get("health_override", ed.get("health", 100))
		if base_h <= 0:
			base_h = ed.get("health", 100)
		var hm = wave_def.get("health_multiplier", 1.0) * wave_def.get("health_multiplier_modifier", 1.0)
		var hp = int(base_h * hm * diff_health)
		var spd = ed.get("speed", 80) * wave_def.get("speed_multiplier", 1.0) * diff_speed * wave_def.get("speed_multiplier_modifier", 1.0)
		spd *= Config.ENEMY_SPEED_GLOBAL_MULT
		if enemy_def_id == "ENEMY_TOUGH" or enemy_def_id == "ENEMY_TOUGH_2":
			spd *= Config.ENEMY_SPEED_TOUGH_MULT
		elif enemy_def_id == "ENEMY_DARKNESS_1" or enemy_def_id == "ENEMY_DARKNESS_2":
			spd *= Config.ENEMY_SPEED_DARKNESS_MULT
		elif enemy_def_id == "ENEMY_BOSS":
			spd *= Config.ENEMY_SPEED_BOSS_MULT
		var flying = ed.get("flying", false)
		var path_len = Config.REGEN_FLYING_PATH if flying else float(ground_path_len)
		var ab = wave_def.get("abilities", [])
		var regen_scale = Config.get_regen_scale(path_len, spd, ab, flying)
		var reg = base_regen * regen_scale * diff_regen * regen_mod
		var ab_str = ", ".join(ab) if ab.size() > 0 else "—"
		parts.append("%s x%d | HP≈%d скор.%.0f реген%.1f/с | спос.: %s" % [name_short, enemy_count, hp, spd, reg, ab_str])
	return " Враги: " + "; ".join(parts)

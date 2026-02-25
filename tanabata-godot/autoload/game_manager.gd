# game_manager.gd
# Главный менеджер игры (Autoload Singleton)
# Управляет ECS, системами, состоянием игры
extends Node

# ============================================================================
# ECS И КАРТА
# ============================================================================

var ecs: ECSWorld
var hex_map: HexMap
var map_seed: int = 0
var energy_network: EnergyNetworkSystem = null

# ============================================================================
# СИСТЕМЫ И КОНТРОЛЛЕРЫ
# ============================================================================

var systems: Array = []  # Пока не используется, но готово для будущего
var phase_controller: PhaseController = null

# Системы будут добавлены из GameRoot
var input_system = null
var wave_system = null
var movement_system = null
var combat_system = null
var crafting_system = null
var wall_renderer = null
var line_drag_handler = null  # Редактор энерголиний (U/молния)
var info_panel = null  # UI плашка для отображения информации
var recipe_book = null  # Книга рецептов (таблица крафта, клавиша B)
var crafting_visual = null  # Визуализация крафта
# - CombatSystem
# - ProjectileSystem
# - StatusEffectSystem
# - OreSystem
# - EnergyNetworkSystem

# ============================================================================
# СОБЫТИЙНАЯ СИСТЕМА
# ============================================================================

signal event_dispatched(event_type: GameTypes.EventType, data: Dictionary)
signal exit_to_menu_requested
signal restart_game_requested
# Завершён уровень обучения (tutorial_index 0..4)
signal tutorial_level_completed(tutorial_index: int)

# ============================================================================
# FIXED TIMESTEP
# ============================================================================

var accumulator: float = 0.0
var tick_count: int = 0

# Выбранная в меню сложность (используется при старте/рестарте)
var difficulty: int = GameTypes.Difficulty.MEDIUM

# Текущий конфиг уровня (null = основная игра, иначе обучение или кастомный уровень)
var current_level_config: Dictionary = {}

# Дебаунс пересчёта пути: быстрые постановки/снятия башен вызывают один пересчёт через 0.08 с
var _path_update_timer: Timer = null

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================================

func _ready():
	# При первом запуске используем конфиг основной игры (пустой = дефолт)
	_init_with_config({})

func _create_player():
	var player_id = ecs.create_entity()
	ecs.add_component(player_id, "player_state", {
		"level": 1,
		"current_xp": 0,
		"xp_to_next_level": Config.calculate_xp_for_level(1),
		"health": Config.BASE_HEALTH
	})

func _place_initial_walls():
	"""Размещение начальных стен (как в Go: placeInitialStones)"""
	var wall_hexes = hex_map.get_initial_wall_hexes()
	for hex in wall_hexes:
		# Используем фабрику для создания стен
		EntityFactory.create_wall(ecs, hex_map, hex)

func _generate_ore(vein_count: int = 3):
	var ore_system = OreGenerationSystem.new(ecs, hex_map, map_seed)
	ore_system.generate_ore(vein_count)
	ecs.game_state["ore_vein_hexes"] = ore_system.ore_vein_hexes

# Доля оставшейся руды в сети: сейчас осталось / сколько было (0..1). Один показатель для HUD.
func get_ore_network_ratio() -> float:
	var totals = get_ore_network_totals()
	if totals["total_max"] <= 0.0:
		return 1.0
	return clampf(totals["total_current"] / totals["total_max"], 0.0, 1.0)

# Вызов с отложенным выполнением (для смены фазы без просадки кадра).
func _deferred_recalculate_crafting() -> void:
	if crafting_system:
		crafting_system.recalculate_combinations()

# Текущее и макс. количество руды в сети (для HUD: бар + подпись "X / Y").
func get_ore_network_totals() -> Dictionary:
	var total_current := 0.0
	var total_max := 0.0
	for ore_id in ecs.ores.keys():
		var o = ecs.ores[ore_id]
		total_current += o.get("current_reserve", 0.0)
		total_max += o.get("max_reserve", 0.0)
	return {"total_current": total_current, "total_max": total_max}

# Списывает руду глобально (для крафта/упрощения). Списываем с жил по одной пока не набрали amount.
# Возвращает true если списали, false если руды недостаточно.
func spend_ore_global(amount: float) -> bool:
	if amount <= 0.0:
		return true
	var totals = get_ore_network_totals()
	if totals["total_current"] < amount:
		return false
	var remaining = amount
	var ore_ids = ecs.ores.keys()
	# Сортируем по убыванию current_reserve, чтобы списывать с самых полных
	ore_ids.sort_custom(func(a, b):
		var ra = ecs.ores[a].get("current_reserve", 0.0)
		var rb = ecs.ores[b].get("current_reserve", 0.0)
		return ra > rb
	)
	for ore_id in ore_ids:
		if remaining <= 0.0:
			break
		var ore = ecs.ores[ore_id]
		var cur = ore.get("current_reserve", 0.0)
		if cur < Config.ORE_DEPLETION_THRESHOLD:
			continue
		var deduct = min(remaining, cur)
		ore["current_reserve"] = max(0.0, cur - deduct)
		remaining -= deduct
	if remaining > 0.001:
		return false
	if energy_network:
		energy_network.rebuild_energy_network()
	return true

# ============================================================================
# ЗАГРУЗКА ДАННЫХ - УСТАРЕЛО, ИСПОЛЬЗУЕТСЯ DataRepository
# ============================================================================

# DEPRECATED: Данные теперь загружаются через DataRepository autoload
# Эти методы оставлены для обратной совместимости, но будут удалены

# ============================================================================
# ГЛАВНЫЙ ЦИКЛ (Fixed Timestep)
# ============================================================================

func _process(delta: float):
	# Ограничиваем delta для предотвращения спирали смерти
	delta = min(delta, Config.MAX_DELTA_TIME)
	
	# Учитываем паузу и скорость
	if ecs.game_state.get("paused", false):
		return
	
	var time_speed = ecs.game_state.get("time_speed", 1.0)
	delta *= time_speed
	
	# Fixed timestep накопитель
	accumulator += delta
	
	while accumulator >= Config.FIXED_DELTA:
		# Обновляем симуляцию (детерминировано)
		update_simulation(Config.FIXED_DELTA)
		accumulator -= Config.FIXED_DELTA
		tick_count += 1
		ecs.game_time += Config.FIXED_DELTA

# Обновление симуляции (вызывается с фиксированным шагом)
func update_simulation(delta: float):
	# Обновляем все системы по порядку
	for system in systems:
		if system.has_method("update"):
			system.update(delta)

# ============================================================================
# СОБЫТИЙНАЯ СИСТЕМА
# ============================================================================

func dispatch_event(event_type: GameTypes.EventType, data: Dictionary = {}):
	event_dispatched.emit(event_type, data)

# ============================================================================
# API ДЛЯ СИСТЕМ - ПРОКСИРУЕМ К DataRepository
# ============================================================================

# DEPRECATED: Используйте DataRepository напрямую
# Эти методы оставлены для обратной совместимости

# Получить определение башни по ID
func get_tower_def(tower_id: String) -> Dictionary:
	return DataRepository.get_tower_def(tower_id)

# Получить определение врага по ID
func get_enemy_def(enemy_id: String) -> Dictionary:
	return DataRepository.get_enemy_def(enemy_id)

# Получить loot table для уровня
func get_loot_table_for_level(level: int) -> Dictionary:
	return DataRepository.get_loot_table_for_level(level)

# Получить определение волны
func get_wave_def(wave_number: int) -> Dictionary:
	return DataRepository.get_wave_def(wave_number)

# ============================================================================
# УПРАВЛЕНИЕ ИГРОЙ
# ============================================================================

func pause_game():
	ecs.game_state["paused"] = true

func resume_game():
	ecs.game_state["paused"] = false

func toggle_pause():
	ecs.game_state["paused"] = not ecs.game_state.get("paused", false)

func set_time_speed(speed: float):
	ecs.game_state["time_speed"] = clamp(speed, 0.25, 4.0)

func cycle_time_speed():
	# Циклим скорость: 1x -> 2x -> 4x -> 1x (как в Go: 2^state)
	var current_speed = ecs.game_state.get("time_speed", 1.0)
	
	if current_speed < 1.5:
		ecs.game_state["time_speed"] = 2.0
	elif current_speed < 3.0:
		ecs.game_state["time_speed"] = 4.0
	else:
		ecs.game_state["time_speed"] = 1.0

func get_current_phase() -> GameTypes.GamePhase:
	return ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)

func set_phase(phase: GameTypes.GamePhase):
	ecs.game_state["phase"] = phase

# ============================================================================
# ДЕБАГ
# ============================================================================

func toggle_god_mode():
	Config.god_mode = not Config.god_mode

func toggle_visual_debug():
	Config.visual_debug_mode = not Config.visual_debug_mode

func print_game_state():
	print("=== Game State ===")
	print("  Tick: %d" % tick_count)
	print("  Game Time: %.2f" % ecs.game_time)
	print("  Phase: %s" % GameTypes.game_phase_to_string(get_current_phase()))
	print("  Paused: %s" % ecs.game_state.get("paused", false))
	print("  Time Speed: %.1fx" % ecs.game_state.get("time_speed", 1.0))
	ecs.print_stats()
	hex_map.print_info()

# ============================================================================
# ПЕРЕИНИЦИАЛИЗАЦИЯ (возврат в меню)
# ============================================================================

# Уклонение: пассивка врага (волны 9, 11, 24, 28, 32). true = удар прошёл мимо, урон не наносить.
func roll_evasion(entity_id: int) -> bool:
	if not ecs or not ecs.enemies.has(entity_id):
		return false
	var chance = ecs.enemies[entity_id].get("evasion_chance", 0.0)
	if chance <= 0.0:
		return false
	return randf() < chance

# Множитель входящего урона по броне (формула как в Dota 2).
# Фактор = 1 - (0.06 × ΣБроня) / (1 + 0.06 × |ΣБроня|). Отрицательная броня увеличивает урон.
func armor_to_damage_factor(armor: float) -> float:
	if armor == 0.0:
		return 1.0
	return 1.0 - (0.06 * armor) / (1.0 + 0.06 * abs(armor))

# Сумма дебаффа брони: поддерживает стакание — либо массив {amount, timer}, либо один объект (обратная совместимость).
func _sum_armor_debuff_amount(debuff_value) -> float:
	if debuff_value == null:
		return 0.0
	if debuff_value is Array:
		var total := 0.0
		for entry in debuff_value:
			if entry is Dictionary:
				total += float(entry.get("amount", 0))
		return total
	if debuff_value is Dictionary:
		return float(debuff_value.get("amount", 0))
	return 0.0

# Эффективная броня врага с учётом дебаффов (стакаются: -20 и -8 = -28) и реактивной брони. Может быть отрицательной.
func get_effective_physical_armor(entity_id: int) -> int:
	if not ecs:
		return 0
	var enemy = ecs.enemies.get(entity_id)
	if not enemy:
		return 0
	var base_val = enemy.get("physical_armor", 0)
	if ecs.phys_armor_debuffs.has(entity_id):
		base_val -= int(_sum_armor_debuff_amount(ecs.phys_armor_debuffs[entity_id]))
	if ecs.reactive_armor_stacks.has(entity_id):
		base_val += ecs.reactive_armor_stacks[entity_id].get("stacks", 0)
	return base_val

func get_effective_magical_armor(entity_id: int) -> int:
	if not ecs:
		return 0
	var enemy = ecs.enemies.get(entity_id)
	if not enemy:
		return 0
	var base_val = enemy.get("magical_armor", 0)
	if ecs.mag_armor_debuffs.has(entity_id):
		base_val -= int(_sum_armor_debuff_amount(ecs.mag_armor_debuffs[entity_id]))
	if ecs.reactive_armor_stacks.has(entity_id):
		base_val += ecs.reactive_armor_stacks[entity_id].get("stacks", 0)
	return base_val

# Для UI: сумма дебаффа брони и минимальный оставшийся таймер (стакание).
func get_armor_debuff_display(entity_id: int, phys: bool) -> Dictionary:
	var debuffs = ecs.phys_armor_debuffs if phys else ecs.mag_armor_debuffs
	if not debuffs.has(entity_id):
		return {"total": 0, "min_timer": 0.0}
	var data = debuffs[entity_id]
	var total = int(_sum_armor_debuff_amount(data))
	var min_timer := 0.0
	if data is Array:
		for entry in data:
			var t = entry.get("timer", 0.0)
			if min_timer <= 0 or t < min_timer:
				min_timer = t
	elif data is Dictionary:
		min_timer = data.get("timer", 0.0)
	return {"total": total, "min_timer": min_timer}

# Множитель урона от баффа MVP вышки: 0 -> 1.0, 1 -> 1.2, ..., 5 -> 2.0
func get_mvp_damage_mult(tower_id: int) -> float:
	if not ecs or not ecs.towers.has(tower_id):
		return 1.0
	var lv = int(ecs.towers[tower_id].get("mvp_level", 0))
	lv = clampi(lv, 0, 5)
	return 1.0 + lv * 0.2

# Вызывать после нанесения урона врагу. source_tower_id >= 0 — урон от вышки (для статистики).
func on_enemy_took_damage(entity_id: int, final_damage: int, source_tower_id: int = -1) -> void:
	if not ecs or not ecs.enemies.has(entity_id):
		return
	if source_tower_id >= 0:
		if not ecs.game_state.has("tower_damage_this_wave"):
			ecs.game_state["tower_damage_this_wave"] = {}
		var d = ecs.game_state["tower_damage_this_wave"]
		d[source_tower_id] = d.get(source_tower_id, 0) + final_damage
	var enemy = ecs.enemies[entity_id]
	var abilities = enemy.get("abilities", [])
	if abilities.has("reactive_armor"):
		if not ecs.reactive_armor_stacks.has(entity_id):
			ecs.reactive_armor_stacks[entity_id] = { "stacks": 0, "timer": 0.0 }
		var ra = ecs.reactive_armor_stacks[entity_id]
		ra["stacks"] = min(Config.REACTIVE_ARMOR_MAX_STACKS, ra.get("stacks", 0) + 1)
		ra["timer"] = Config.REACTIVE_ARMOR_STACK_DURATION
	if abilities.has("kraken_shell"):
		var k = ecs.kraken_damage_taken.get(entity_id, 0) + final_damage
		ecs.kraken_damage_taken[entity_id] = k
		if k >= Config.KRAKEN_SHELL_DAMAGE_THRESHOLD:
			ecs.kraken_damage_taken[entity_id] = 0
			ecs.slow_effects.erase(entity_id)
			ecs.poison_effects.erase(entity_id)
			ecs.jade_poisons.erase(entity_id)
			ecs.phys_armor_debuffs.erase(entity_id)
			ecs.mag_armor_debuffs.erase(entity_id)

# Топ-5 вышек по урону: за текущую волну (во время волны) или за прошлую (в фазе строительства).
# Каждый элемент: tower_id, def_id, name, damage, mvp_level, is_top1, has_max_mvp (для подсветки красным).
func get_top5_tower_damage() -> Array:
	var d = ecs.game_state.get("tower_damage_this_wave", {})
	var list = []
	for tid in d.keys():
		var tower = ecs.towers.get(tid)
		var def_id = tower.get("def_id", "?") if tower else "?"
		var def = DataRepository.get_tower_def(def_id) if def_id != "?" else {}
		var name = def.get("name", def_id) if not def.is_empty() else def_id
		var mvp = int(tower.get("mvp_level", 0)) if tower else 0
		list.append({ "tower_id": tid, "def_id": def_id, "name": name, "damage": d[tid], "mvp_level": mvp })
	if list.is_empty():
		list = ecs.game_state.get("last_wave_tower_damage", [])
	list.sort_custom(func(a, b): return a.damage > b.damage)
	var top5 = []
	for i in range(mini(5, list.size())):
		var e = list[i]
		var tid = e.tower_id
		var mvp_val = int(ecs.towers.get(tid, {}).get("mvp_level", 0))
		top5.append({
			"tower_id": tid,
			"def_id": e.get("def_id", "?"),
			"name": e.get("name", "?"),
			"damage": e.damage,
			"mvp_level": mvp_val,
			"is_top1": (i == 0),
			"has_max_mvp": (mvp_val >= 5)
		})
	return top5

# Вывод в консоль итогов урона по волне (для баланса): за волну и суммарно за все волны
func log_wave_damage_report() -> void:
	var wave = ecs.game_state.get("current_wave", 0)
	var d = ecs.game_state.get("tower_damage_this_wave", {})
	if not ecs.game_state.has("tower_damage_total"):
		ecs.game_state["tower_damage_total"] = {}
	if not ecs.game_state.has("tower_waves_with_damage"):
		ecs.game_state["tower_waves_with_damage"] = {}
	var total = ecs.game_state["tower_damage_total"]
	var waves_with_damage = ecs.game_state["tower_waves_with_damage"]
	for tid in d.keys():
		total[tid] = total.get(tid, 0) + d[tid]
		waves_with_damage[tid] = waves_with_damage.get(tid, 0) + 1

	var list = []
	for tid in d.keys():
		var tower = ecs.towers.get(tid)
		var def_id = tower.get("def_id", "?") if tower else "?"
		var def = DataRepository.get_tower_def(def_id) if def_id != "?" else {}
		var name = def.get("name", def_id) if not def.is_empty() else def_id
		list.append({ "tower_id": tid, "def_id": def_id, "name": name, "damage": d[tid] })
	list.sort_custom(func(a, b): return a.damage > b.damage)
	ecs.game_state["last_wave_tower_damage"] = list
	ecs.game_state["last_wave_number"] = wave

	# MVP: только если волна не была пропущена (враги доиграны, не skip)
	if ecs.game_state.get("wave_skipped", false):
		pass  # не даём MVP за пропущенную волну
	else:
		for entry in list:
			var tid = entry.tower_id
			if not ecs.towers.has(tid):
				continue
			var t = ecs.towers[tid]
			var cur = int(t.get("mvp_level", 0))
			if cur >= 5:
				continue
			t["mvp_level"] = mini(5, cur + 1)
			break

	if d.is_empty():
		print("[Wave %d] Урон вышек: (нет данных)" % wave)
	else:
		print("[Wave %d] Урон вышек (за волну):" % wave)
		for i in list.size():
			var e = list[i]
			print("  %d. %s (id=%d, def=%s): %d" % [i + 1, e.name, e.tower_id, e.def_id, e.damage])

	var list_total = []
	for tid in total.keys():
		var tower = ecs.towers.get(tid)
		var def_id = tower.get("def_id", "?") if tower else "?"
		var def = DataRepository.get_tower_def(def_id) if def_id != "?" else {}
		var name = def.get("name", def_id) if not def.is_empty() else def_id
		var waves = waves_with_damage.get(tid, 1)
		var avg = total[tid] / waves if waves > 0 else 0
		list_total.append({ "tower_id": tid, "def_id": def_id, "name": name, "damage": total[tid], "waves": waves, "avg": avg })
	list_total.sort_custom(func(a, b): return a.damage > b.damage)
	if list_total.is_empty():
		print("[Урон вышек всего]: (нет данных)")
	else:
		print("[Урон вышек всего]:")
		for i in list_total.size():
			var e = list_total[i]
			print("  %d. %s (id=%d, def=%s): %d (среднее за раунд: %d, раундов: %d)" % [i + 1, e.name, e.tower_id, e.def_id, e.damage, e.avg, e.waves])

# Запросить пересчёт пути с дебаунсом (0.08 с): несколько вызовов подряд дают один пересчёт
func _request_future_path_update() -> void:
	if _path_update_timer:
		_path_update_timer.start(0.08)

func _on_path_update_timer_timeout() -> void:
	update_future_path()

# Обновить предпросмотр пути врагов (Entry → чекпоинты → Exit), как в Go UpdateFuturePath
func update_future_path() -> void:
	if not hex_map or not ecs:
		return
	var path = Pathfinding.find_path_through_checkpoints(
		hex_map.entry,
		hex_map.checkpoints,
		hex_map.exit,
		hex_map
	)
	if path.is_empty():
		ecs.game_state["future_path"] = []
		return
	var full: Array = []
	full.append(hex_map.entry.to_key())
	for h in path:
		full.append(h.to_key())
	ecs.game_state["future_path"] = full

# Подсветка пройденных чекпоинтов по «последнему» живому врагу (мин. current_index), как в Go
func update_checkpoint_highlighting() -> void:
	if not ecs or not hex_map or hex_map.checkpoints.is_empty():
		return
	var last_enemy = null
	var min_index = 0x7FFFFFFF
	for enemy_id in ecs.enemies.keys():
		if not ecs.healths.has(enemy_id) or not ecs.paths.has(enemy_id):
			continue
		var health = ecs.healths[enemy_id]
		if health.get("current", 0) <= 0:
			continue
		var path = ecs.paths[enemy_id]
		var idx = path.get("current_index", 0)
		if idx < min_index:
			min_index = idx
			last_enemy = ecs.enemies[enemy_id]
	ecs.game_state["cleared_checkpoints"] = {}
	if last_enemy != null:
		var last_idx = last_enemy.get("last_checkpoint_index", -1)
		if last_idx >= 0 and last_idx < hex_map.checkpoints.size():
			for i in range(last_idx + 1):
				ecs.game_state["cleared_checkpoints"][hex_map.checkpoints[i].to_key()] = true

func request_exit_to_menu():
	exit_to_menu_requested.emit()

func request_restart_game():
	restart_game_requested.emit()

# Внутренняя инициализация ECS, карты, руды по конфигу (из _ready и reinit_game)
func _init_with_config(level_config: Dictionary):
	var map_radius = level_config.get(LevelConfig.KEY_MAP_RADIUS, Config.MAP_RADIUS)
	var ore_vein_count = level_config.get(LevelConfig.KEY_ORE_VEIN_COUNT, 3)
	var wave_max = level_config.get(LevelConfig.KEY_WAVE_MAX, 0)
	var is_tutorial = level_config.get(LevelConfig.KEY_IS_TUTORIAL, false)
	
	current_level_config = level_config
	ecs = ECSWorld.new()
	ecs.init_game_state()
	ecs.game_state["tutorial_wave_max"] = wave_max  # 0 = без лимита
	ecs.game_state["is_tutorial"] = is_tutorial
	ecs.game_state["tutorial_step_index"] = 0
	if is_tutorial:
		ecs.game_state["tutorial_index"] = level_config.get(LevelConfig.KEY_TUTORIAL_INDEX, 0)
		var steps = level_config.get(LevelConfig.KEY_STEPS, [])
		print("[Tutorial] level loaded: tutorial_index=%d steps_count=%d" % [ecs.game_state["tutorial_index"], steps.size()])
	_last_logged_tutorial_step = -1
	
	map_seed = randi()
	hex_map = HexMap.new(map_radius, map_seed)
	var checkpoint_count = level_config.get(LevelConfig.KEY_CHECKPOINT_COUNT, -1)
	hex_map.generate(checkpoint_count)
	_create_player()
	_place_initial_walls()
	_generate_ore(ore_vein_count)
	energy_network = EnergyNetworkSystem.new(ecs, hex_map)
	phase_controller = PhaseController.new(ecs, hex_map, energy_network)
	accumulator = 0.0
	tick_count = 0
	if _path_update_timer == null:
		_path_update_timer = Timer.new()
		_path_update_timer.one_shot = true
		_path_update_timer.timeout.connect(_on_path_update_timer_timeout)
		add_child(_path_update_timer)

func reinit_game(level_config: Dictionary = {}):
	"""Полная переинициализация для новой игры. level_config = {} — основная игра, иначе обучение/уровень."""
	resume_game()
	# Очищаем ссылки на системы (они будут пересозданы в GameRoot)
	input_system = null
	wave_system = null
	movement_system = null
	crafting_system = null
	wall_renderer = null
	line_drag_handler = null
	info_panel = null
	recipe_book = null
	crafting_visual = null
	combat_system = null
	# Пересоздаём ECS и карту по конфигу
	_init_with_config(level_config)

# ============================================================================
# ОБУЧЕНИЕ: ПОШАГОВЫЕ ПОДСКАЗКИ
# ============================================================================

func get_tutorial_steps() -> Array:
	if current_level_config.is_empty():
		return []
	return current_level_config.get(LevelConfig.KEY_STEPS, [])

func get_current_tutorial_message() -> String:
	var steps = get_tutorial_steps()
	if steps.is_empty():
		return ""
	var idx = ecs.game_state.get("tutorial_step_index", 0)
	if idx < 0 or idx >= steps.size():
		return ""
	var step = steps[idx]
	# Всегда только поле "message"; никогда не показывать trigger (на случай если где-то перепутаны ключи)
	var msg = step.get("message", "")
	if msg.is_empty() and step.has("trigger"):
		# Защита: если по ошибке подставили trigger — не показывать его в плашке
		msg = ""
	return msg

# Множитель расхода руды за выстрел (только для обучения уровень 1 — гиперболизация)
func get_ore_consumption_multiplier() -> float:
	return current_level_config.get(LevelConfig.KEY_ORE_CONSUMPTION_MULTIPLIER, 1.0)

# Принудительно перейти к следующему шагу (кнопка «Далее» в UI)
func advance_tutorial_step() -> void:
	if not ecs.game_state.get("is_tutorial", false):
		return
	var steps = get_tutorial_steps()
	if steps.is_empty():
		return
	var idx = ecs.game_state.get("tutorial_step_index", 0)
	if idx < steps.size():
		ecs.game_state["tutorial_step_index"] = idx + 1

# Вызывать каждый кадр из GameRoot, когда is_tutorial — проверяет триггер и продвигает шаг
var _last_logged_tutorial_step: int = -1
func update_tutorial() -> void:
	if not ecs.game_state.get("is_tutorial", false):
		return
	var steps = get_tutorial_steps()
	if steps.is_empty():
		return
	var idx = ecs.game_state.get("tutorial_step_index", 0)
	if idx >= steps.size():
		return
	# Лог при смене шага (не каждый кадр): индекс, триггер, длина сообщения и начало текста плашки
	if idx != _last_logged_tutorial_step:
		_last_logged_tutorial_step = idx
		var step = steps[idx]
		var trigger_id = step.get("trigger", "")
		var msg = step.get("message", "")
		var preview = msg.substr(0, 60) + "..." if msg.length() > 60 else msg
		print("[Tutorial] >>> step=%d trigger=%s | plaque: \"%s\"" % [idx, trigger_id, preview])
	var trigger_id = steps[idx].get("trigger", "")
	if trigger_id.is_empty():
		return
	if not _is_tutorial_trigger_fired(trigger_id):
		return
	ecs.game_state["tutorial_step_index"] = idx + 1
	print("[Tutorial] >>> advanced step %d -> %d (trigger '%s' fired)" % [idx, idx + 1, trigger_id])

func _is_tutorial_trigger_fired(trigger_id: String) -> bool:
	match trigger_id:
		LevelConfig.TRIGGER_GAME_START:
			return true
		LevelConfig.TRIGGER_TOWERS_5:
			return ecs.game_state.get("towers_built_this_phase", 0) >= 5
		LevelConfig.TRIGGER_PHASE_SELECTION:
			return ecs.game_state.get("phase", -1) == GameTypes.GamePhase.TOWER_SELECTION_STATE
		LevelConfig.TRIGGER_TOWERS_SAVED_2:
			var count = 0
			for tid in ecs.towers.keys():
				var t = ecs.towers[tid]
				if t.get("is_selected", false):
					count += 1
			return count >= 2
		LevelConfig.TRIGGER_PHASE_WAVE:
			return ecs.game_state.get("phase", -1) == GameTypes.GamePhase.WAVE_STATE
		LevelConfig.TRIGGER_WAVE_STARTED:
			return ecs.game_state.get("phase", -1) == GameTypes.GamePhase.WAVE_STATE and ecs.game_state.get("current_wave", 0) >= 1
		LevelConfig.TRIGGER_MINER_ON_ORE:
			for tid in ecs.towers.keys():
				var t = ecs.towers[tid]
				var def_id = t.get("def_id", "")
				var def = DataRepository.get_tower_def(def_id) if def_id else {}
				if def.get("type", "") == "MINER" and t.get("is_active", false):
					return true
			return false
		LevelConfig.TRIGGER_MINERS_3_ON_ORE:
			var count = 0
			for tid in ecs.towers.keys():
				var t = ecs.towers[tid]
				var def_id = t.get("def_id", "")
				var def = DataRepository.get_tower_def(def_id) if def_id else {}
				if def.get("type", "") == "MINER" and t.get("is_active", false):
					count += 1
			return count >= 3
		LevelConfig.TRIGGER_MINERS_2_ON_ORE:
			var count = 0
			for tid in ecs.towers.keys():
				var t = ecs.towers[tid]
				var def_id = t.get("def_id", "")
				var def = DataRepository.get_tower_def(def_id) if def_id else {}
				if def.get("type", "") == "MINER" and t.get("is_active", false):
					count += 1
			return count >= 2
		LevelConfig.TRIGGER_ATTACKER_CONNECTED:
			for tid in ecs.combat.keys():
				var t = ecs.towers.get(tid)
				if t and t.get("is_active", false):
					return true
			return false
		LevelConfig.TRIGGER_ORE_DEPLETES:
			var ratio = get_ore_network_ratio()
			return ratio < 1.0 and ratio > 0.0
		LevelConfig.TRIGGER_PHASE_BUILD_AFTER_WAVE:
			return ecs.game_state.get("phase", -1) == GameTypes.GamePhase.BUILD_STATE and ecs.game_state.get("current_wave", 0) >= 1
		LevelConfig.TRIGGER_NONE:
			return false
		_:
			return false

# ============================================================================
# ОЧИСТКА
# ============================================================================

func _exit_tree():
	pass

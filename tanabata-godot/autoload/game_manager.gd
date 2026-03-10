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

# Карты награды за босса (благословения и проклятия)
var pending_boss_cards: bool = false
var active_blessing_ids: Array = []
var active_curse_ids: Array = []

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

func get_current_path_length() -> int:
	if not ecs:
		return 0
	# В фазе BUILD показываем актуальную длину пути (после постановки/сноса башен); на волне — длину на старте волны.
	if get_current_phase() == GameTypes.GamePhase.BUILD_STATE:
		return int(ecs.game_state.get("current_path_length", 0))
	return int(ecs.game_state.get("wave_path_length", ecs.game_state.get("current_path_length", 0)))

# Длины сегментов пути в гексах: [в-1, 1-2, 2-3, 3-4, 4-5, 5-6, 6-в]. Пустой массив, если путь не посчитан.
func get_path_segment_lengths() -> Array:
	if not ecs:
		return []
	return ecs.game_state.get("path_segment_lengths", [])

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

# Основная сеть = та, к которой подключено больше всего атакующих вышек (не майнеры/стены). Возвращает остаток и долю израсходованной руды для логов.
func get_main_network_ore_stats() -> Dictionary:
	if not energy_network:
		return {"total_current": 0.0, "total_max": 0.0, "pct_remaining": 0.0, "pct_spent": 0.0, "attack_count": 0}
	var nets = energy_network.get_networks_ore_and_attack_count()
	if nets.is_empty():
		return {"total_current": 0.0, "total_max": 0.0, "pct_remaining": 0.0, "pct_spent": 0.0, "attack_count": 0}
	var best = nets[0]
	for n in nets:
		if n.get("attack_count", 0) > best.get("attack_count", 0):
			best = n
	var cur = best.get("total_current", 0.0)
	var mx = best.get("total_max", 0.0)
	var pct_remaining = (100.0 * cur / mx) if mx > 0.0 else 0.0
	var pct_spent = (100.0 * (mx - cur) / mx) if mx > 0.0 else 0.0
	return {
		"total_current": cur,
		"total_max": mx,
		"pct_remaining": pct_remaining,
		"pct_spent": pct_spent,
		"attack_count": best.get("attack_count", 0)
	}

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
	var depleted_ore_ids: Array = []
	for ore_id in ore_ids:
		if remaining <= 0.0:
			break
		var ore = ecs.ores[ore_id]
		var cur = ore.get("current_reserve", 0.0)
		if cur < Config.ORE_DEPLETION_THRESHOLD:
			continue
		var deduct = min(remaining, cur)
		ore["current_reserve"] = max(0.0, cur - deduct)
		record_ore_spent(deduct, ore.get("sector", 0))
		remaining -= deduct
		if ore["current_reserve"] < Config.ORE_DEPLETION_THRESHOLD:
			depleted_ore_ids.append(ore_id)
	for ore_id in depleted_ore_ids:
		if ecs.ores.has(ore_id):
			ecs.destroy_entity(ore_id)
	if remaining > 0.001:
		return false
	if energy_network:
		energy_network.rebuild_energy_network()
	return true

# Учёт расхода руды за волну (для логов и сводки). Вызывать при любом списании руды во время волны.
# tower_id: если >= 0, учитывается в tower_ore_spent_this_wave для лога "руда/сек по вышкам".
func record_ore_spent(amount: float, sector: int, tower_id: int = -1) -> void:
	if amount <= 0.0 or not ecs:
		return
	if not ecs.game_state.has("wave_ore_spent_total"):
		return
	ecs.game_state["wave_ore_spent_total"] = ecs.game_state["wave_ore_spent_total"] + amount
	ecs.game_state["total_ore_spent_cumulative"] = ecs.game_state.get("total_ore_spent_cumulative", 0.0) + amount
	var by_sector = ecs.game_state.get("wave_ore_spent_by_sector", {0: 0.0, 1: 0.0, 2: 0.0})
	var s = clampi(sector, 0, 2)
	by_sector[s] = by_sector.get(s, 0.0) + amount
	ecs.game_state["wave_ore_spent_by_sector"] = by_sector
	if tower_id >= 0 and ecs.game_state.has("tower_ore_spent_this_wave"):
		var by_tower = ecs.game_state["tower_ore_spent_this_wave"]
		by_tower[tower_id] = by_tower.get(tower_id, 0.0) + amount
		ecs.game_state["tower_ore_spent_this_wave"] = by_tower

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

# Начальная очередь стеша для фазы BUILD (5 букв Б/А по тем же правилам, что выбор типа в InputSystem)
func get_initial_stash_letters() -> Array:
	if not ecs:
		return []
	var result: Array = []
	var cw = ecs.game_state.get("current_wave", 0)
	var is_tutorial_0 = ecs.game_state.get("is_tutorial", false) and ecs.game_state.get("tutorial_index", -1) == 0
	var ti_state = ecs.game_state.get("tutorial_index", -1)
	var ti_config = -1
	if current_level_config.size() > 0:
		ti_config = current_level_config.get(LevelConfig.KEY_TUTORIAL_INDEX, -1)
	var is_tutorial_1 = ecs.game_state.get("is_tutorial", false) and (ti_state == 1 or ti_config == 1)
	for slot in range(5):
		if is_tutorial_0:
			result.append("Б" if (cw >= 1 and slot == 0) else "А")
		elif is_tutorial_1:
			result.append("Б" if (slot == 0 or slot == 2) else "А")
		else:
			result.append("Б" if (cw % 10 < 5 and slot == 0) else "А")
	return result

# ============================================================================
# УПРАВЛЕНИЕ ИГРОЙ
# ============================================================================

func pause_game():
	ecs.game_state["paused"] = true

func resume_game():
	ecs.game_state["paused"] = false

func toggle_pause():
	ecs.game_state["paused"] = not ecs.game_state.get("paused", false)

func on_boss_killed():
	pending_boss_cards = true
	pause_game()

func distribute_gold_creature_ore_reward() -> void:
	if not energy_network or not ecs:
		return
	var ore_ids = energy_network.get_all_network_ore_ids()
	if ore_ids.is_empty():
		return
	var total = float(Config.GOLD_CREATURE_ORE_REWARD)
	var per_ore = total / ore_ids.size()
	for ore_id in ore_ids:
		var ore = ecs.ores.get(ore_id)
		if not ore:
			continue
		var cur = ore.get("current_reserve", 0.0)
		var max_r = ore.get("max_reserve", 0.0)
		ore["current_reserve"] = minf(max_r, cur + per_ore)

func clear_pending_boss_cards():
	pending_boss_cards = false

func apply_boss_card(card_id: String, is_curse: bool):
	if is_curse:
		if card_id not in active_curse_ids:
			active_curse_ids.append(card_id)
	else:
		if card_id not in active_blessing_ids:
			active_blessing_ids.append(card_id)
		if card_id == "bless_remove_early_curses":
			clear_all_early_craft_curses()

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
	if enemy.get("abilities", []).has("ivasion"):
		return 9999  # для совместимости; при нанесении урона проверяют is_physical_immune() и дают 0
	var base_val = enemy.get("physical_armor", 0)
	if ecs.phys_armor_debuffs.has(entity_id):
		base_val -= int(_sum_armor_debuff_amount(ecs.phys_armor_debuffs[entity_id]))
	if ecs.reactive_armor_stacks.has(entity_id):
		base_val += ecs.reactive_armor_stacks[entity_id].get("stacks", 0)
	return base_val

# 100% физ. неуязвимость (Ивейжн): физический урон не проходит вообще.
func is_physical_immune(entity_id: int) -> bool:
	if not ecs:
		return false
	var enemy = ecs.enemies.get(entity_id)
	return enemy != null and enemy.get("abilities", []).has("ivasion")

# 100% маг. неуязвимость (БКБ): магический урон не проходит вообще. Не путать с высокой маг. бронёй.
func is_magic_immune(entity_id: int) -> bool:
	if not ecs:
		return false
	var enemy = ecs.enemies.get(entity_id)
	return enemy != null and enemy.get("abilities", []).has("bkb")

func get_effective_magical_armor(entity_id: int) -> int:
	if not ecs:
		return 0
	var enemy = ecs.enemies.get(entity_id)
	if not enemy:
		return 0
	if enemy.get("abilities", []).has("bkb"):
		return 9999  # для совместимости; при нанесении урона проверяют is_magic_immune() и дают 0
	var base_val = enemy.get("magical_armor", 0)
	if ecs.mag_armor_debuffs.has(entity_id):
		base_val -= int(_sum_armor_debuff_amount(ecs.mag_armor_debuffs[entity_id]))
	if ecs.reactive_armor_stacks.has(entity_id):
		base_val += ecs.reactive_armor_stacks[entity_id].get("stacks", 0)
	return base_val

# Броня к чистому урону (редуцирует PURE-урон по той же формуле Dota). По умолчанию 0.
func get_effective_pure_armor(entity_id: int) -> int:
	if not ecs:
		return 0
	var enemy = ecs.enemies.get(entity_id)
	if not enemy:
		return 0
	return enemy.get("pure_armor", 0)

# Доп. сопротивление чистому урону по волне (например волна 11: 0.1 = -10% урона). Берётся из enemy при спавне.
func get_pure_damage_resistance(entity_id: int) -> float:
	if not ecs:
		return 0.0
	var enemy = ecs.enemies.get(entity_id)
	if not enemy:
		return 0.0
	return enemy.get("pure_damage_resistance", 0.0)

# ============================================================================
# КАРТЫ НАГРАДЫ ЗА БОССА
# ============================================================================

func get_card_damage_bonus_global() -> int:
	return 9 if "bless_damage9" in active_blessing_ids else 0

# Базовый урон вышки (из combat) + бонус +1 для базовых вышек Lv.1 (crafting_level 0). Множители Lv.1/Lv.2 зашиты в data/towers.json.
func get_tower_base_damage(tower_id: int) -> int:
	if not ecs or not ecs.combat.has(tower_id):
		return 0
	var combat = ecs.combat[tower_id]
	var d = combat.get("damage", 0)
	var tower = ecs.towers.get(tower_id, {})
	if tower.get("crafting_level", 0) == 0 and tower.get("level", 1) == 1:
		d += 1
	return d

func get_card_attack_speed_mult() -> float:
	var mult = 1.0
	if "bless_attack_speed3" in active_blessing_ids:
		mult *= 1.03
	if "curse_attack_speed15" in active_curse_ids:
		mult *= 1.15
	return mult

func get_card_ore_restore_bonus() -> float:
	return 1.0 if "bless_ore1" in active_blessing_ids else 0.0

func get_card_enemy_speed_mult() -> float:
	return 0.9 if "bless_enemy_slow10" in active_blessing_ids else 1.0

func get_card_phys_damage_bonus() -> int:
	return 20 if "bless_phys20" in active_blessing_ids else 0

func get_card_mag_damage_bonus() -> int:
	return 20 if "bless_mag20" in active_blessing_ids else 0

func has_curse_hp_percent() -> bool:
	return "curse_hp_percent" in active_curse_ids

func get_curse_extra_ore_per_shot() -> float:
	return 0.5 if "curse_hp_percent" in active_curse_ids else 0.0

func has_curse_split() -> bool:
	return "curse_split" in active_curse_ids

func get_curse_split_extra_ore() -> float:
	return 2.0 if "curse_split" in active_curse_ids else 0.0

# ============================================================================
# ПРОКЛЯТИЕ РАННЕГО КРАФТА (ранняя сильная вышка = меньше урона до порога волны)
# ============================================================================
# Правила: def_id -> { threshold: int, penalties: Array[int] по волнам 0..threshold-1, bash_only: bool }
const EARLY_CRAFT_CURSE_RULES = {
	"TOWER_SILVER": { "threshold": 4, "penalties": [60, 50, 40, 30] },
	"TOWER_MALACHITE": { "threshold": 4, "penalties": [60, 50, 40, 30] },
	"TOWER_VOLCANO": { "threshold": 6, "penalties": [60, 50, 40, 30, 20, 10] },
	"TOWER_JADE": { "threshold": 8, "penalties": [60, 50, 40, 30, 20, 10] },
	"TOWER_GOLD": { "threshold": 7, "penalties": [] },
	"TOWER_LIBRA": { "threshold": 3, "penalties": [60, 50, 40] },
	"TOWER_GRUSS": { "threshold": 3, "penalties": [60, 50, 40] },
	"TOWER_AURIGA": { "threshold": 3, "penalties": [60, 50, 40] },
	"TOWER_QUARTZ": { "threshold": 7, "penalties": [] },
	"TOWER_EMERALD": { "threshold": 8, "penalties": [60, 50, 40, 30, 20, 10, 10, 10], "bash_only": true },
	"TOWER_MIMIC": { "threshold": 2, "penalties": [60, 50] },
	"TOWER_SILVER_KNIGHT": { "threshold": 16, "penalties": [] },
	"TOWER_VIVID_MALACHITE": { "threshold": 16, "penalties": [] },
	"TOWER_RUBY": { "threshold": 19, "penalties": [] },
	"TOWER_KAILUN": { "threshold": 18, "penalties": [] },
	"TOWER_EGYPT": { "threshold": 14, "penalties": [] },
	"TOWER_GREY": { "threshold": 17, "penalties": [] },
	"TOWER_PINK": { "threshold": 24, "penalties": [] },
	"TOWER_HUGE": { "threshold": 31, "penalties": [] },
	"TOWER_BLOODSTONE": { "threshold": 27, "penalties": [] },
	"TOWER_ANTIQUE": { "threshold": 35, "penalties": [] },
	"TOWER_238": { "threshold": 24, "penalties": [] },
	"TOWER_U235": { "threshold": 31, "penalties": [] },
}

func _get_early_craft_curse_percent(tower_id: int) -> int:
	if not ecs or not ecs.towers.has(tower_id):
		return 0
	var tower = ecs.towers[tower_id]
	if tower.get("early_craft_curse_cleared", false):
		return 0
	var def_id = tower.get("def_id", "")
	var rule = EARLY_CRAFT_CURSE_RULES.get(def_id, null)
	if rule == null:
		return 0
	var placed = int(tower.get("placed_at_wave", 0))
	var th = int(rule.get("threshold", 99))
	if placed >= th:
		return 0
	var penalties = rule.get("penalties", [])
	if penalties.size() > 0:
		var idx = mini(placed, penalties.size() - 1)
		return int(penalties[idx])
	# Standard gradation for last 6 waves before threshold
	var dist = th - 1 - placed
	if dist >= 6:
		return 60
	var grad = [60, 50, 40, 30, 20, 10]
	return int(grad[dist])

const TOUCH_CURSE_PERCENT: int = 15  # Проклятие касания (крафт в фазе выбора): фиксированно -15%

func get_touch_curse_multiplier(tower_id: int) -> float:
	"""Множитель проклятия касания (0.85). Не применяется к батарее и если проклятие снято."""
	if not ecs or not ecs.towers.has(tower_id):
		return 1.0
	var tower = ecs.towers[tower_id]
	if tower.get("touch_curse_cleared", false) or not tower.get("touch_curse", false):
		return 1.0
	var def_id = tower.get("def_id", "")
	var def = DataRepository.get_tower_def(def_id) if DataRepository else {}
	if def.get("type") == "BATTERY":
		return 1.0
	return 1.0 - (float(TOUCH_CURSE_PERCENT) / 100.0)

func get_touch_curse_info(tower_id: int) -> Dictionary:
	if not ecs or not ecs.towers.has(tower_id):
		return { "has_curse": false }
	var tower = ecs.towers[tower_id]
	var has_curse = tower.get("touch_curse", false) and not tower.get("touch_curse_cleared", false)
	if has_curse:
		var def_id = tower.get("def_id", "")
		var def = DataRepository.get_tower_def(def_id) if DataRepository else {}
		if def.get("type") == "BATTERY":
			has_curse = false
	return { "has_curse": has_curse, "percent": TOUCH_CURSE_PERCENT }

func get_early_craft_curse_damage_multiplier(tower_id: int) -> float:
	var pct = _get_early_craft_curse_percent(tower_id)
	var mult: float = 1.0
	if pct > 0:
		var rule = EARLY_CRAFT_CURSE_RULES.get(ecs.towers.get(tower_id, {}).get("def_id", ""), {})
		if not rule.get("bash_only", false):
			mult = 1.0 - (float(pct) / 100.0)
	mult *= get_touch_curse_multiplier(tower_id)
	return mult

func get_early_craft_curse_bash_multiplier(tower_id: int) -> float:
	var pct = _get_early_craft_curse_percent(tower_id)
	var mult: float = 1.0
	if pct > 0:
		mult = 1.0 - (float(pct) / 100.0)
	mult *= get_touch_curse_multiplier(tower_id)
	return mult

func get_early_craft_curse_info(tower_id: int) -> Dictionary:
	var percent = _get_early_craft_curse_percent(tower_id)
	var placed = int(ecs.towers.get(tower_id, {}).get("placed_at_wave", 0))
	return { "has_curse": percent > 0, "percent": percent, "wave_placed": placed }

func would_craft_have_early_curse(output_id: String) -> bool:
	"""Если скрафтить башню output_id сейчас — будет ли на ней проклятие раннего крафта (для подсветки рецепта красным)."""
	if not ecs:
		return false
	var rule = EARLY_CRAFT_CURSE_RULES.get(output_id, null)
	if rule == null:
		return false
	var cw = ecs.game_state.get("current_wave", 0)
	var th = int(rule.get("threshold", 99))
	return cw < th

func get_craft_after_save_status(tower_id: int) -> Dictionary:
	"""После сохранения этой башни (в фазе выбора) можно ли скрафтить и будет ли проклятие. Возвращает {can_craft: bool, has_curse: bool}. Зелёный приоритет над красным."""
	var result = {"can_craft": false, "has_curse": false}
	if not ecs or ecs.game_state.get("phase", 0) != GameTypes.GamePhase.TOWER_SELECTION_STATE:
		return result
	if not ecs.towers.has(tower_id) or not ecs.towers[tower_id].get("is_temporary", false):
		return result
	var ids_after_save: Dictionary = {}
	for tid in ecs.towers.keys():
		var t = ecs.towers[tid]
		if not t.get("is_temporary", false) or t.get("is_selected", false):
			ids_after_save[tid] = true
	# Учитываем саму проверяемую башню как «после сохранения», чтобы подсветить гекс зелёным, если с ней можно скрафтить
	ids_after_save[tower_id] = true
	if not ecs.combinables.has(tower_id):
		return result
	var crafts = ecs.combinables[tower_id].get("possible_crafts", [])
	var found_without_curse = false
	var found_with_curse = false
	for c in crafts:
		var combo = c.get("combination", [])
		var all_present = true
		for tid in combo:
			if not ids_after_save.has(tid):
				all_present = false
				break
		if not all_present:
			continue
		var out_id = c.get("recipe", {}).get("output_id", "")
		if would_craft_have_early_curse(out_id):
			found_with_curse = true
		else:
			found_without_curse = true
	result["can_craft"] = found_with_curse or found_without_curse
	result["has_curse"] = found_with_curse and not found_without_curse
	return result

func get_towers_part_of_craft_after_save() -> Dictionary:
	"""Только для подсветки гексов: башни, входящие в рецепт уровня крафта 1 или 2 при текущем наборе на карте. Не трогает combinables/крафт."""
	var part: Dictionary = {}
	if not ecs:
		return part
	# Ведра по def_id-level из ВСЕХ башен на карте (для подсветки TO1+PO1+DE1=Маяк и т.п.)
	var tower_buckets: Dictionary = {}
	for tid in ecs.towers.keys():
		var t = ecs.towers[tid]
		var def_id = t.get("def_id", "")
		if def_id.is_empty() or def_id == "TOWER_WALL":
			continue
		var key = "%s-%d" % [def_id, int(t.get("level", 1))]
		if not tower_buckets.has(key):
			tower_buckets[key] = []
		tower_buckets[key].append(tid)
	var recipe_defs = DataRepository.recipe_defs
	if not recipe_defs is Array:
		return part
	for recipe in recipe_defs:
		var out_id = recipe.get("output_id", "")
		if out_id.is_empty():
			continue
		var out_def = DataRepository.get_tower_def(out_id)
		if out_def.is_empty():
			continue
		var craft_level = out_def.get("crafting_level", 0)
		if craft_level < 1 or craft_level > 2:
			continue
		var needed: Dictionary = {}
		for inp in recipe.get("inputs", []):
			var k = "%s-%d" % [inp.get("id", ""), int(inp.get("level", 1))]
			needed[k] = needed.get(k, 0) + 1
		var has_enough = true
		for k in needed.keys():
			if tower_buckets.get(k, []).size() < needed[k]:
				has_enough = false
				break
		if not has_enough:
			continue
		var needed_keys = needed.keys()
		needed_keys.sort()
		var one_combo: Array = []
		for k in needed_keys:
			var ids = tower_buckets.get(k, [])
			for j in range(needed[k]):
				if j < ids.size():
					one_combo.append(ids[j])
		var has_curse = would_craft_have_early_curse(out_id)
		for cid in one_combo:
			if not ecs.towers.has(cid):
				continue
			if part.has(cid):
				part[cid]["has_curse"] = part[cid]["has_curse"] and has_curse
			else:
				part[cid] = {"has_curse": has_curse}
	return part

func get_craftable_output_ids_now() -> Array:
	"""output_id рецептов уровня крафта 1–2, которые можно скрафтить прямо сейчас с текущим набором башен на карте."""
	var out_ids: Array = []
	if not ecs:
		return out_ids
	var tower_buckets: Dictionary = {}
	for tid in ecs.towers.keys():
		var t = ecs.towers[tid]
		var def_id = t.get("def_id", "")
		if def_id.is_empty() or def_id == "TOWER_WALL":
			continue
		var key = "%s-%d" % [def_id, int(t.get("level", 1))]
		if not tower_buckets.has(key):
			tower_buckets[key] = []
		tower_buckets[key].append(tid)
	var recipe_defs = DataRepository.recipe_defs
	if not recipe_defs is Array:
		return out_ids
	for recipe in recipe_defs:
		var out_id = recipe.get("output_id", "")
		if out_id.is_empty():
			continue
		var out_def = DataRepository.get_tower_def(out_id)
		if out_def.is_empty():
			continue
		if out_def.get("crafting_level", 0) < 1 or out_def.get("crafting_level", 0) > 2:
			continue
		var needed: Dictionary = {}
		for inp in recipe.get("inputs", []):
			var k = "%s-%d" % [inp.get("id", ""), int(inp.get("level", 1))]
			needed[k] = needed.get(k, 0) + 1
		var has_enough = true
		for k in needed.keys():
			if tower_buckets.get(k, []).size() < needed[k]:
				has_enough = false
				break
		if has_enough and out_id not in out_ids:
			out_ids.append(out_id)
	return out_ids

func clear_all_early_craft_curses() -> void:
	"""Снимает все проклятия с вышек: раннего крафта и касания."""
	if not ecs:
		return
	for tid in ecs.towers.keys():
		if ecs.towers[tid].get("def_id", "").is_empty():
			continue
		ecs.towers[tid]["early_craft_curse_cleared"] = true
		ecs.towers[tid]["touch_curse_cleared"] = true

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

# Множитель урона от сопротивления сети: 1 - resistance (кап 0). Вышки типа Б = 0, каждая А на пути до ближайшей Б даёт +0.2.
func get_resistance_mult(tower_id: int) -> float:
	if not energy_network:
		return 1.0
	return energy_network.get_resistance_mult(tower_id)

# Множитель урона по врагу от длины лабиринта и «медленной второй половины». source_tower_id опционально — для бонуса Gold/Egypt по летающим (+50%).
func get_damage_to_enemy_multiplier(enemy_id: int, source_tower_id: int = -1) -> float:
	var path_len = ecs.game_state.get("wave_path_length", 0)
	var mult = Config.get_path_length_damage_to_enemies_mult(path_len)
	if ecs.enemies.get(enemy_id, {}).get("takes_slow_second_half_extra_damage", false):
		mult *= Config.MAZE_SLOW_SECOND_HALF_EXTRA_DAMAGE_MULT
	var bonus = ecs.flying_damage_taken_bonus.get(enemy_id, 0.0)
	mult *= (1.0 + bonus)
	var paraba_bonus = ecs.paraba_damage_taken_bonus.get(enemy_id, 0.0)
	mult *= (1.0 + paraba_bonus)
	var scream_entry = ecs.scream_damage_bonus.get(enemy_id, {})
	if scream_entry is Dictionary and scream_entry.get("timer", 0) > 0:
		mult *= (1.0 + scream_entry.get("bonus", 0.0))
	if source_tower_id >= 0 and ecs.towers.has(source_tower_id) and ecs.enemies.get(enemy_id, {}).get("flying", false):
		var def_id = ecs.towers[source_tower_id].get("def_id", "")
		if def_id == "TOWER_GOLD" or def_id == "TOWER_EGYPT":
			mult *= 1.5
	return mult

# Среднее игровое время прохождения сегмента между чекпоинтами (по прошлым волнам). 0.0 = нет данных.
func get_segment_average_game_time(segment_key: String) -> float:
	var totals = ecs.game_state.get("log_segment_totals", {})
	var counts = ecs.game_state.get("log_segment_counts", {})
	var total = totals.get(segment_key, 0.0)
	var count = counts.get(segment_key, 0)
	if count <= 0:
		return 0.0
	return total / float(count)

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
	var line_dmg = ecs.game_state.get("energy_line_damage_this_wave", 0)
	if line_dmg > 0:
		list.append({ "tower_id": -1, "def_id": "ENERGY_LINE", "name": "Линия (майнеры)", "damage": line_dmg, "mvp_level": 0 })
	if list.is_empty():
		list = ecs.game_state.get("last_wave_tower_damage", [])
	list.sort_custom(func(a, b): return a.damage > b.damage)
	var top5 = []
	for i in range(mini(5, list.size())):
		var e = list[i]
		var tid = e.tower_id
		var mvp_val = int(ecs.towers.get(tid, {}).get("mvp_level", 0)) if tid >= 0 else 0
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

# Рудa по секторам (0=центральный, 1=средний, 2=крайний). Сектор задаётся при генерации карты (OreGenerationSystem).
func get_ore_totals_by_sector() -> Dictionary:
	var by_sector = { 0: {"current": 0.0, "max": 0.0}, 1: {"current": 0.0, "max": 0.0}, 2: {"current": 0.0, "max": 0.0} }
	if not ecs:
		return by_sector
	for ore_id in ecs.ores.keys():
		var ore = ecs.ores[ore_id]
		var s = ore.get("sector", 0)
		if s < 0 or s > 2:
			s = 0
		if not by_sector.has(s):
			by_sector[s] = {"current": 0.0, "max": 0.0}
		by_sector[s]["current"] += ore.get("current_reserve", 0.0)
		by_sector[s]["max"] += ore.get("max_reserve", 0.0)
	return by_sector

# Количество майнеров по секторам и всего (для лога)
func get_miner_count_by_sector() -> Dictionary:
	var by_sector = {0: 0, 1: 0, 2: 0}
	var total = 0
	if not ecs or not hex_map:
		return {"by_sector": by_sector, "total": 0}
	for tid in ecs.towers.keys():
		var t = ecs.towers[tid]
		var def_t = DataRepository.get_tower_def(t.get("def_id", ""))
		if def_t.get("type", "") != "MINER":
			continue
		total += 1
		var h = t.get("hex")
		if not h:
			continue
		var ore_id = ecs.ore_hex_index.get(h.to_key(), -1)
		if ore_id < 0:
			continue
		var ore = ecs.ores.get(ore_id, {})
		var s = clampi(ore.get("sector", 0), 0, 2)
		by_sector[s] = by_sector.get(s, 0) + 1
	return {"by_sector": by_sector, "total": total}

# Записать прогресс врага по лабиринту перед удалением (для аналитики после волны)
func record_enemy_wave_progress(enemy_id: int) -> void:
	if not ecs or ecs.game_state.get("phase", -1) != GameTypes.GamePhase.WAVE_STATE:
		return
	if not ecs.enemies.has(enemy_id):
		return
	var enemy = ecs.enemies[enemy_id]
	var cp = enemy.get("last_checkpoint_index", -1)
	ecs.game_state["wave_enemy_checkpoints"] = ecs.game_state.get("wave_enemy_checkpoints", [])
	ecs.game_state["wave_enemy_checkpoints"].append(cp)
	var path_idx = 0
	if ecs.paths.has(enemy_id):
		path_idx = ecs.paths[enemy_id].get("current_index", 0)
	ecs.game_state["wave_enemy_path_indices"] = ecs.game_state.get("wave_enemy_path_indices", [])
	ecs.game_state["wave_enemy_path_indices"].append(path_idx)

# ============================================================================
# СИСТЕМА УСПЕХА (скрытый параметр: уровень 6..+inf, шкала 0..100)
# Влияет на количество врагов в волне. Чекпоинт/выход — штраф, убийство — бонус.
# ============================================================================

func get_success_level() -> int:
	return ecs.game_state.get("success_level", Config.SUCCESS_LEVEL_DEFAULT)

func get_success_scale() -> float:
	return ecs.game_state.get("success_scale", Config.SUCCESS_SCALE_MAX)

func _success_add(delta: float) -> void:
	var scale = ecs.game_state.get("success_scale", Config.SUCCESS_SCALE_MAX)
	var level = ecs.game_state.get("success_level", Config.SUCCESS_LEVEL_DEFAULT)
	scale += delta
	while scale < 0.0:
		level -= 1
		scale += Config.SUCCESS_SCALE_MAX
		if level < Config.SUCCESS_LEVEL_MIN:
			level = Config.SUCCESS_LEVEL_MIN
			scale = maxf(0.0, scale)
			break
	while scale > Config.SUCCESS_SCALE_MAX:
		level += 1
		scale -= Config.SUCCESS_SCALE_MAX
	ecs.game_state["success_level"] = level
	ecs.game_state["success_scale"] = clampf(scale, 0.0, Config.SUCCESS_SCALE_MAX)

func _success_enemy_mult() -> float:
	var N = ecs.game_state.get("current_wave_enemy_count", 10)
	if N <= 0:
		N = 10
	return 10.0 / float(N)

func on_enemy_reached_checkpoint(enemy_id: int, checkpoint_1based: int) -> void:
	if not ecs or not ecs.enemies.has(enemy_id) or not ecs.healths.has(enemy_id):
		return
	var health = ecs.healths[enemy_id]
	var cur = health.get("current", 0)
	var mx = health.get("max", 1)
	var ratio = float(cur) / float(max(1, mx))
	var base_arr = Config.SUCCESS_PENALTY_BASE_10
	var idx = clamp(checkpoint_1based - 1, 0, base_arr.size() - 1)
	var coeff = base_arr[idx] * _success_enemy_mult()
	_success_add(-coeff * ratio)

func on_enemy_reached_exit(enemy_id: int) -> void:
	if ecs and ecs.game_state.has("wave_analytics"):
		var wa = ecs.game_state["wave_analytics"]
		wa["passed"] = wa.get("passed", 0) + 1
	if not ecs or not ecs.enemies.has(enemy_id) or not ecs.healths.has(enemy_id):
		return
	var health = ecs.healths[enemy_id]
	var cur = health.get("current", 0)
	var mx = health.get("max", 1)
	var ratio = float(cur) / float(max(1, mx))
	var base_arr = Config.SUCCESS_PENALTY_BASE_10
	var exit_idx = base_arr.size() - 1
	var coeff = base_arr[exit_idx] * _success_enemy_mult()
	_success_add(-coeff * ratio)

func on_enemy_killed(enemy_id: int) -> void:
	if not ecs:
		return
	var bonus = Config.SUCCESS_KILL_BONUS_BASE_10 * _success_enemy_mult()
	_success_add(bonus)

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
	var line_dmg = ecs.game_state.get("energy_line_damage_this_wave", 0)
	if line_dmg > 0:
		list.append({ "tower_id": -1, "def_id": "ENERGY_LINE", "name": "Линия (майнеры)", "damage": line_dmg })
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

	# Аналитика лабиринта (время волны, чекпоинты, путь, руда по секторам)
	var start_t = ecs.game_state.get("wave_start_time", 0.0)
	var duration_real = Time.get_ticks_msec() / 1000.0 - start_t
	var duration_game = ecs.game_state.get("wave_game_time", 0.0)
	var path_max_pct_wave = 0.0
	var path_avg_pct_wave = 0.0
	var segment_avgs_this_wave = {}
	print("[Wave %d] Лабиринт: длительность волны игр. %.1f с, реал. %.1f с; врагов в волне: %d" % [wave, duration_game, duration_real, ecs.game_state.get("current_wave_enemy_count", 0)])

	# Накапливаем руду по вышкам за раунд (для итоговой таблицы)
	var ore_by_tower = ecs.game_state.get("tower_ore_spent_this_wave", {})
	if not ore_by_tower.is_empty():
		if not ecs.game_state.has("tower_ore_by_def_cumulative"):
			ecs.game_state["tower_ore_by_def_cumulative"] = {}
		var cum = ecs.game_state["tower_ore_by_def_cumulative"]
		for tid in ore_by_tower.keys():
			var tower = ecs.towers.get(tid)
			var def_id = tower.get("def_id", "?") if tower else "?"
			cum[def_id] = cum.get(def_id, 0.0) + ore_by_tower[tid]

	var n_enemies = ecs.game_state.get("current_wave_enemy_count", 0)
	if not ecs.game_state.has("log_segment_totals"):
		ecs.game_state["log_segment_totals"] = {}
	if not ecs.game_state.has("log_segment_counts"):
		ecs.game_state["log_segment_counts"] = {}
	if not ecs.game_state.has("log_path_pct_max_sum"):
		ecs.game_state["log_path_pct_max_sum"] = 0.0
	if not ecs.game_state.has("log_path_pct_avg_sum"):
		ecs.game_state["log_path_pct_avg_sum"] = 0.0
	if not ecs.game_state.has("log_path_wave_count"):
		ecs.game_state["log_path_wave_count"] = 0
	if not ecs.game_state.has("log_cp_reached_sum"):
		ecs.game_state["log_cp_reached_sum"] = {}
	if not ecs.game_state.has("log_enemies_total"):
		ecs.game_state["log_enemies_total"] = 0

	var max_cp = hex_map.checkpoints.size() - 1 if hex_map and hex_map.checkpoints.size() > 0 else 0
	var checkpoints = ecs.game_state.get("wave_enemy_checkpoints", [])
	ecs.game_state["log_enemies_total"] = ecs.game_state["log_enemies_total"] + n_enemies
	# Сколько врагов дошло до каждого чекпоинта (всегда показываем 0..max_cp)
	var cp_reached_this = {}
	for cp_idx in range(max_cp + 1):
		var n = 0
		for v in checkpoints:
			if v >= cp_idx:
				n += 1
		cp_reached_this[cp_idx] = n
	var g_cp = ecs.game_state["log_cp_reached_sum"]
	for cp_idx in cp_reached_this.keys():
		g_cp[cp_idx] = g_cp.get(cp_idx, 0) + cp_reached_this[cp_idx]
	var tot_enemies = ecs.game_state["log_enemies_total"]
	var cp_parts = []
	for cp_idx in range(max_cp + 1):
		var n = cp_reached_this.get(cp_idx, 0)
		var pct = (100.0 * n / n_enemies) if n_enemies > 0 else 0.0
		var g_pct = (100.0 * g_cp.get(cp_idx, 0) / tot_enemies) if tot_enemies > 0 else 0.0
		cp_parts.append("до %d: %d (%.0f%%, за игру ср. %.0f%%)" % [cp_idx, n, pct, g_pct])
	print("[Wave %d] Чекпоинты: %s" % [wave, ", ".join(cp_parts)])
	var times = ecs.game_state.get("wave_enemy_checkpoint_times", {})
	if checkpoints.size() > 0:
		var seg_totals = {}
		var seg_counts = {}
		for eid in times.keys():
			var t = times[eid]
			var indices = t.keys()
			indices.sort()
			for seg in range(indices.size() - 1):
				var i0 = indices[seg]
				var i1 = indices[seg + 1]
				var dt = t[i1] - t[i0]
				var key = "%d->%d" % [i0, i1]
				seg_totals[key] = seg_totals.get(key, 0.0) + dt
				seg_counts[key] = seg_counts.get(key, 0) + 1
		var g_seg_t = ecs.game_state["log_segment_totals"]
		var g_seg_c = ecs.game_state["log_segment_counts"]
		for key in seg_totals.keys():
			g_seg_t[key] = g_seg_t.get(key, 0.0) + seg_totals[key]
			g_seg_c[key] = g_seg_c.get(key, 0) + seg_counts[key]
		if seg_totals.size() > 0:
			var parts = []
			for key in seg_totals.keys():
				var cnt = seg_counts.get(key, 1)
				var avg = seg_totals[key] / cnt
				segment_avgs_this_wave[key] = avg
				var g_avg = g_seg_t[key] / g_seg_c[key] if g_seg_c.get(key, 0) > 0 else 0.0
				parts.append("%s: ср. %.1f с (за игру ср. %.1f с)" % [key, avg, g_avg])
			print("[Wave %d] Среднее время между чекпоинтами (игр. время): %s" % [wave, ", ".join(parts)])

	var path_len = ecs.game_state.get("wave_path_length", 0)
	var path_indices = ecs.game_state.get("wave_enemy_path_indices", [])
	if path_len > 0 and path_indices.size() > 0:
		var traveled_max = path_indices.max()
		var traveled_sum = 0
		for v in path_indices:
			traveled_sum += v
		var traveled_avg = traveled_sum / path_indices.size()
		var pct_max = (100.0 * traveled_max / path_len) if path_len > 0 else 0.0
		var pct_avg = (100.0 * traveled_avg / path_len) if path_len > 0 else 0.0
		ecs.game_state["log_path_pct_max_sum"] = ecs.game_state["log_path_pct_max_sum"] + pct_max
		ecs.game_state["log_path_pct_avg_sum"] = ecs.game_state["log_path_pct_avg_sum"] + pct_avg
		path_max_pct_wave = pct_max
		path_avg_pct_wave = pct_avg
		ecs.game_state["log_path_wave_count"] = ecs.game_state["log_path_wave_count"] + 1
		var n_path_waves = ecs.game_state["log_path_wave_count"]
		var g_pct_max = ecs.game_state["log_path_pct_max_sum"] / n_path_waves
		var g_pct_avg = ecs.game_state["log_path_pct_avg_sum"] / n_path_waves
		print("[Wave %d] Путь: всего %d гексов; враги прошли макс=%d (%.0f%%), в ср.=%.1f (%.0f%%) | за игру ср.: макс %.0f%%, в ср. %.0f%%" % [wave, path_len, traveled_max, pct_max, traveled_avg, pct_avg, g_pct_max, g_pct_avg])

	var ore_start = ecs.game_state.get("wave_ore_by_sector_start", {})
	var ore_end = get_ore_totals_by_sector()
	var ore_restored = ecs.game_state.get("wave_ore_restored_by_sector", {0: 0.0, 1: 0.0, 2: 0.0})
	var miner_info = get_miner_count_by_sector()
	var sector_names = ["центральный", "средний", "крайний"]
	for s in [0, 1, 2]:
		var st = ore_start.get(s, {"current": 0.0, "max": 0.0})
		var en = ore_end.get(s, {"current": 0.0, "max": 0.0})
		var rest = ore_restored.get(s, 0.0)
		var miners = miner_info["by_sector"].get(s, 0)
		print("[Wave %d] Руда сектор %s: до=%.0f, после=%.0f (макс=%.0f), восстановлено за волну=%.0f, майнеров=%d" % [wave, sector_names[s], st.get("current", 0.0), en.get("current", 0.0), en.get("max", 0.0), rest, miners])
	print("[Wave %d] Майнеров всего: %d" % [wave, miner_info["total"]])
	var ore_spent_total = ecs.game_state.get("wave_ore_spent_total", 0.0)
	var ore_spent_by_sector = ecs.game_state.get("wave_ore_spent_by_sector", {0: 0.0, 1: 0.0, 2: 0.0})
	var ore_per_sec = ore_spent_total / duration_real if duration_real > 0.0 else 0.0
	var ore_mined_total = ore_restored.get(0, 0.0) + ore_restored.get(1, 0.0) + ore_restored.get(2, 0.0)
	var miner_hexes = miner_info["total"]
	print("[Wave %d] Руда: израсходовано за раунд=%.0f, руда/сек (ср.)=%.1f, добыто за волну=%.0f, гексов занято майнерами=%d" % [wave, ore_spent_total, ore_per_sec, ore_mined_total, miner_hexes])
	print("[Wave %d] Руда траты по секторам: центр=%.0f, середина=%.0f, конец=%.0f" % [wave, ore_spent_by_sector.get(0, 0.0), ore_spent_by_sector.get(1, 0.0), ore_spent_by_sector.get(2, 0.0)])
	var main_net = get_main_network_ore_stats()
	if main_net.get("attack_count", 0) > 0:
		print("[Wave %d] Основная сеть (атакующих вышек %d): руда остаток %.0f%% (текущ/макс %.0f/%.0f), израсходовано %.0f%%" % [wave, main_net.attack_count, main_net.pct_remaining, main_net.total_current, main_net.total_max, main_net.pct_spent])

	var count_by_def = {}
	for tid in ecs.towers.keys():
		var t = ecs.towers[tid]
		var def_id = t.get("def_id", "?")
		count_by_def[def_id] = count_by_def.get(def_id, 0) + 1
	var tower_parts = []
	for def_id in count_by_def.keys():
		tower_parts.append("%s x%d" % [def_id, count_by_def[def_id]])
	tower_parts.sort()
	print("[Wave %d] Башен всего: %d. Стоит: %s" % [wave, ecs.towers.size(), ", ".join(tower_parts)])

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

	# Сводка волн для графика: накапливаем строки и выводим таблицу
	if not ecs.game_state.has("log_wave_summary"):
		ecs.game_state["log_wave_summary"] = []
	var player_hp = 100
	var player_lvl = 1
	var player_xp_total = 0
	for pid in ecs.player_states.keys():
		var ps = ecs.player_states[pid]
		player_hp = ps.get("health", 100)
		player_lvl = ps.get("level", 1)
		var cur_xp = ps.get("current_xp", 0)
		player_xp_total = Config.get_total_xp(player_lvl, cur_xp)
		break
	var total_spawned = ecs.game_state.get("log_enemies_total", 0)
	var total_killed = ecs.game_state.get("total_enemies_killed", 0)
	var enemies_leaked = total_spawned - total_killed
	var ore_cumulative = ecs.game_state.get("total_ore_spent_cumulative", 0.0)
	var success_level_val = get_success_level()
	var row = {
		"wave": wave,
		"duration_game": duration_game,
		"duration_real": duration_real,
		"n_enemies": n_enemies,
		"path_hexes": path_len,
		"path_max_pct": path_max_pct_wave,
		"path_avg_pct": path_avg_pct_wave,
		"ore_spent": ore_spent_total,
		"ore_per_sec": ore_per_sec,
		"ore_mined": ore_mined_total,
		"miner_hexes": miner_hexes,
		"ore_spent_center": ore_spent_by_sector.get(0, 0.0),
		"ore_spent_middle": ore_spent_by_sector.get(1, 0.0),
		"ore_spent_end": ore_spent_by_sector.get(2, 0.0),
		"hp_player": player_hp,
		"lvl_player": player_lvl,
		"xp_total": player_xp_total,
		"enemies_leaked": enemies_leaked,
		"ore_total": ore_cumulative,
		"success": success_level_val
	}
	for cp_idx in range(max_cp + 1):
		var n = cp_reached_this.get(cp_idx, 0)
		row["cp_%d" % cp_idx] = (100.0 * n / n_enemies) if n_enemies > 0 else 0.0
	for key in segment_avgs_this_wave.keys():
		row["seg_%s" % key] = segment_avgs_this_wave[key]
	ecs.game_state["log_wave_summary"].append(row)
	var segment_keys = []
	for i in range(max_cp):
		segment_keys.append("%d->%d" % [i, i + 1])
	var cp_header_parts = []
	for i in range(max_cp + 1):
		cp_header_parts.append("до_%d" % i)
	print("[Сводка волн для графика]")
	var ore_header = "руда_трат\tруда_сек\tруда_доб\tмайнер_гексов\tруда_центр\tруда_серед\tруда_конец"
	var extra_header = "hp_игрока\tlvl_игрока\txp_всего\tпропущено_врагов\tруда_всего\tуспех"
	print("волна\tдлит_игр\tдлит_реал\tврагов\tпуть_гексов\tпуть_макс%\tпуть_ср%\t" + ore_header + "\t" + "\t".join(cp_header_parts) + "\t" + "\t".join(segment_keys) + "\t" + extra_header)
	for r in ecs.game_state["log_wave_summary"]:
		var cells = [str(r.wave), "%.1f" % r.duration_game, "%.1f" % r.duration_real, str(r.n_enemies), str(r.get("path_hexes", 0)), "%.0f" % r.path_max_pct, "%.0f" % r.path_avg_pct]
		cells.append("%.0f" % r.get("ore_spent", 0.0))
		cells.append("%.1f" % r.get("ore_per_sec", 0.0))
		cells.append("%.0f" % r.get("ore_mined", 0.0))
		cells.append(str(r.get("miner_hexes", 0)))
		cells.append("%.0f" % r.get("ore_spent_center", 0.0))
		cells.append("%.0f" % r.get("ore_spent_middle", 0.0))
		cells.append("%.0f" % r.get("ore_spent_end", 0.0))
		for cp_idx in range(max_cp + 1):
			cells.append("%.0f" % r.get("cp_%d" % cp_idx, 0.0))
		for key in segment_keys:
			cells.append("%.1f" % r.get("seg_%s" % key, 0.0))
		cells.append(str(r.get("hp_player", 0)))
		cells.append(str(r.get("lvl_player", 1)))
		cells.append(str(r.get("xp_total", 0)))
		cells.append(str(r.get("enemies_leaked", 0)))
		cells.append("%.0f" % r.get("ore_total", 0.0))
		cells.append(str(r.get("success", Config.SUCCESS_LEVEL_DEFAULT)))
		print("\t".join(cells))

	# Итоговая таблица: руда по вышкам за раунд (всего и ср. руда/сек)
	var total_duration_game = 0.0
	for r in ecs.game_state["log_wave_summary"]:
		total_duration_game += r.get("duration_game", 0.0)
	var tower_ore_cum = ecs.game_state.get("tower_ore_by_def_cumulative", {})
	if not tower_ore_cum.is_empty() and total_duration_game > 0.0:
		var ore_by_def_list = []
		for def_id in tower_ore_cum.keys():
			var ore_total = tower_ore_cum[def_id]
			var defn = DataRepository.get_tower_def(def_id) if def_id != "?" else {}
			var tower_name = defn.get("name", def_id) if not defn.is_empty() else def_id
			var ore_sec = ore_total / total_duration_game
			ore_by_def_list.append({ "def_id": def_id, "name": tower_name, "total": ore_total, "ore_per_sec": ore_sec })
		ore_by_def_list.sort_custom(func(a, b): return a.total > b.total)
		print("[Руда по вышкам за раунд] (игр. время раунда %.1f с)" % total_duration_game)
		print("вышка\tdef_id\tруда_всего\tруда_сек")
		for i in ore_by_def_list.size():
			var e = ore_by_def_list[i]
			print("%s\t%s\t%.1f\t%.2f" % [e.name, e.def_id, e.total, e.ore_per_sec])

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
	var result = Pathfinding.find_path_through_checkpoints_with_segments(
		hex_map.entry,
		hex_map.checkpoints,
		hex_map.exit,
		hex_map
	)
	var path = result.get("path", [])
	var segment_lengths = result.get("segment_lengths", [])
	if path.is_empty():
		ecs.game_state["future_path"] = []
		ecs.game_state["current_path_length"] = 0
		ecs.game_state["path_segment_lengths"] = []
		return
	ecs.game_state["current_path_length"] = path.size()
	ecs.game_state["path_segment_lengths"] = segment_lengths
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

# Snapshot: воспроизводимый «вход» для симуляции (карта + seed + расстановка вышек и стен).
# run_seed нужен для воспроизведения одного забега; при 10k прогонах подменяем его.
func get_snapshot() -> Dictionary:
	var towers_list: Array = []
	for tid in ecs.towers.keys():
		var t = ecs.towers[tid]
		var h = t.get("hex", null)
		if h == null:
			continue
		towers_list.append({"q": h.q, "r": h.r, "def_id": t.get("def_id", "")})
	towers_list.sort_custom(func(a, b):
		if a.q != b.q: return a.q < b.q
		return a.r < b.r
	)
	return {
		"snapshot_version": 1,
		"seed": map_seed,
		"run_seed": ecs.game_state.get("run_seed", 0),
		"current_wave": ecs.game_state.get("current_wave", 0),
		"towers": towers_list
	}

func record_wave_snapshot() -> void:
	if not ecs:
		return
	if not ecs.game_state.has("wave_snapshots"):
		ecs.game_state["wave_snapshots"] = []
	ecs.game_state["wave_snapshots"].append(get_snapshot())

func log_snapshot_on_game_over() -> void:
	if not ecs:
		return
	if ecs.game_state.get("snapshot_logged", false):
		return
	ecs.game_state["snapshot_logged"] = true
	var wave_snapshots = ecs.game_state.get("wave_snapshots", [])
	var json_str = JSON.stringify(wave_snapshots)
	print("[Snapshot] ", json_str)
	_save_snapshots_to_file(wave_snapshots)

func _save_snapshots_to_file(wave_snapshots: Array) -> void:
	var base_dir = Config.get_project_snapshots_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		var err = DirAccess.make_dir_recursive_absolute(base_dir)
		if err != OK:
			push_warning("[Snapshot] Cannot create dir %s: %s" % [base_dir, err])
			return
	var json_text = JSON.stringify(wave_snapshots)
	var legacy_path = base_dir.path_join("last_run.json")
	var f = FileAccess.open(legacy_path, FileAccess.WRITE)
	if f:
		f.store_string(json_text)
		f.close()
	var max_wave = 0
	for snap in wave_snapshots:
		var cw = int(snap.get("current_wave", 0))
		if cw > max_wave:
			max_wave = cw
	var dt = Time.get_datetime_dict_from_system()
	var folder_name = "run_%04d%02d%02d_%02d%02d_w%d" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], max_wave]
	var run_dir = base_dir.path_join(folder_name)
	if not DirAccess.dir_exists_absolute(run_dir):
		DirAccess.make_dir_recursive_absolute(run_dir)
	var run_path = run_dir.path_join("snapshot.json")
	var rf = FileAccess.open(run_path, FileAccess.WRITE)
	if rf:
		rf.store_string(json_text)
		rf.close()
		print("[Snapshot] Saved to %s" % run_path)
	else:
		push_warning("[Snapshot] Cannot write %s" % run_path)

func request_exit_to_menu():
	exit_to_menu_requested.emit()

func request_restart_game():
	restart_game_requested.emit()

# Промежутки волн для перемешивания (реиграбельность): внутри каждого порядок рандомится, HP масштабируется по EHP.
const WAVE_SHUFFLE_INTERVALS: Array = [[6, 9], [11, 15], [16, 19], [21, 29], [31, 39]]

func _build_wave_shuffle_map(is_tutorial: bool) -> Dictionary:
	var map_result: Dictionary = {}
	for interval in WAVE_SHUFFLE_INTERVALS:
		var lo: int = interval[0]
		var hi: int = interval[1]
		var ordered: Array = []
		for wn in range(lo, hi + 1):
			ordered.append(wn)
		var ehp_by_wn: Dictionary = {}
		for wn in ordered:
			ehp_by_wn[wn] = WaveEffectiveHP.compute_wave_effective_hp(wn, is_tutorial)
		var shuffled: Array = ordered.duplicate()
		shuffled.shuffle()
		for i in range(ordered.size()):
			var slot_wn: int = ordered[i]
			var content_wn: int = shuffled[i]
			var e_slot = ehp_by_wn[slot_wn]
			var e_content = ehp_by_wn[content_wn]
			var scale: float = 1.0
			if e_content > 0.0:
				scale = e_slot / e_content
			map_result[slot_wn] = {"source_wave_number": content_wn, "health_scale": scale}
	return map_result

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
		ecs.game_state["wave_shuffle_map"] = {}
	else:
		ecs.game_state["wave_shuffle_map"] = _build_wave_shuffle_map(is_tutorial)
	_last_logged_tutorial_step = -1

	# Детерминированный рандом: один сид на весь прогон (карта + волны + криты/уклонения/золотые враги и т.д.)
	var run_seed: int = Config.get_initial_run_seed()
	if run_seed == 0:
		run_seed = randi()
		print("[Seed] Run seed (reproduce with --seed ", run_seed, " or Config.GAME_SEED = ", run_seed, "): ", run_seed)
	seed(run_seed)
	map_seed = randi()
	ecs.game_state["run_seed"] = run_seed
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
	Config.god_mode = false
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
	pending_boss_cards = false
	active_blessing_ids.clear()
	active_curse_ids.clear()
	# Пересоздаём ECS и карту по конфигу
	_init_with_config(level_config)
	update_future_path()

# Переинициализация из снепшота (одна карта/руда/башни, опционально другой run_seed для 10k прогонов).
# run_seed_override >= 0: использовать этот сид для RNG волн/врагов; иначе взять run_seed из снепшота.
func reinit_from_snapshot(snapshot: Dictionary, run_seed_override: int = -1) -> bool:
	if snapshot.is_empty() or not snapshot.has("seed") or not snapshot.has("towers"):
		push_warning("[Snapshot] Invalid snapshot: need seed and towers")
		return false
	var ver = snapshot.get("snapshot_version", 0)
	if ver > 1:
		push_warning("[Snapshot] Unknown snapshot_version %d" % ver)
		return false
	resume_game()
	Config.god_mode = false
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
	pending_boss_cards = false
	active_blessing_ids.clear()
	active_curse_ids.clear()
	_init_from_snapshot(snapshot, run_seed_override)
	update_future_path()
	return true

func _init_from_snapshot(snapshot: Dictionary, run_seed_override: int):
	var run_seed: int = run_seed_override if run_seed_override >= 0 else snapshot.get("run_seed", randi())
	seed(run_seed)
	map_seed = int(snapshot["seed"])
	current_level_config = {}
	ecs = ECSWorld.new()
	ecs.init_game_state()
	ecs.game_state["tutorial_wave_max"] = 0
	ecs.game_state["is_tutorial"] = false
	ecs.game_state["tutorial_step_index"] = 0
	ecs.game_state["wave_shuffle_map"] = _build_wave_shuffle_map(false)
	_last_logged_tutorial_step = -1
	ecs.game_state["run_seed"] = run_seed
	ecs.game_state["difficulty"] = difficulty
	var map_radius = Config.MAP_RADIUS
	var ore_vein_count = 3
	var checkpoint_count = -1
	hex_map = HexMap.new(map_radius, map_seed)
	hex_map.generate(checkpoint_count)
	_create_player()
	_place_towers_from_snapshot(snapshot.get("towers", []))
	_generate_ore(ore_vein_count)
	energy_network = EnergyNetworkSystem.new(ecs, hex_map)
	phase_controller = PhaseController.new(ecs, hex_map, energy_network)
	accumulator = 0.0
	tick_count = 0
	var cw = int(snapshot.get("current_wave", 1))
	ecs.game_state["current_wave"] = max(0, cw - 1)
	if _path_update_timer == null:
		_path_update_timer = Timer.new()
		_path_update_timer.one_shot = true
		_path_update_timer.timeout.connect(_on_path_update_timer_timeout)
		add_child(_path_update_timer)

func _place_towers_from_snapshot(towers_list: Array) -> void:
	for entry in towers_list:
		var q = int(entry.get("q", 0))
		var r = int(entry.get("r", 0))
		var def_id = str(entry.get("def_id", ""))
		if def_id.is_empty():
			continue
		var hex = Hex.new(q, r)
		if not hex_map.has_tile(hex):
			continue
		if def_id == "TOWER_WALL":
			EntityFactory.create_wall(ecs, hex_map, hex)
		else:
			var tid = EntityFactory.create_tower(ecs, hex_map, hex, def_id)
			if tid != GameTypes.INVALID_ENTITY_ID and ecs.towers.has(tid):
				ecs.towers[tid]["is_temporary"] = false
				ecs.towers[tid]["is_permanent"] = true

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

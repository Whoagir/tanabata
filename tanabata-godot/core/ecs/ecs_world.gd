# ecs_world.gd
# Entity-Component-System - центр игровой логики
# Перенесено из Go проекта (internal/entity/ecs.go)
class_name ECSWorld

# ============================================================================
# ENTITY MANAGEMENT
# ============================================================================

var entities: Dictionary = {}  # entity_id (int) -> bool (exists)
var next_id: int = 0
var game_time: float = 0.0

# Реестр всех хранилищ компонентов — для автоматической очистки в destroy_entity
var _component_stores: Array = []

# ============================================================================
# COMPONENTS (все компоненты хранятся в отдельных словарях)
# ============================================================================

# Базовые компоненты
var positions: Dictionary = {}      # entity_id -> Vector2
var velocities: Dictionary = {}     # entity_id -> Vector2
var healths: Dictionary = {}        # entity_id -> {current: int, max: int}

# Рендеринг
var renderables: Dictionary = {}    # entity_id -> {color: Color, radius: float}

# Башни
var towers: Dictionary = {}         # entity_id -> {def_id: String, level: int, hex: Hex, is_active: bool, ...}
var combat: Dictionary = {}         # entity_id -> {damage: int, fire_rate: float, range: int, ...}
var turrets: Dictionary = {}        # entity_id -> {current_angle: float, target_angle: float, ...}

# Враги
var enemies: Dictionary = {}        # entity_id -> {def_id: String, physical_armor: int, magical_armor: int}
var paths: Dictionary = {}          # entity_id -> {hexes: Array[Hex], current_index: int}

# Снаряды
var projectiles: Dictionary = {}    # entity_id -> {source_id: int, target_id: int, damage: int, ...}

# Руда
var ores: Dictionary = {}           # entity_id -> {power: float, max_reserve: float, current_reserve: float, hex: Hex}
var ore_hex_index: Dictionary = {}  # hex_key (String) -> ore_id (int) — O(1) поиск руды по гексу

# Статус-эффекты
var slow_effects: Dictionary = {}   # entity_id -> { source_key (def_id или "hit_"+def_id) -> {slow_factor: float, timer: float} }; разные источники стакаются (перемножение)
var bash_effects: Dictionary = {}  # entity_id -> {timer: float} — оглушение: не двигается, не использует активные скиллы
var poison_effects: Dictionary = {} # entity_id -> { def_id (NU1, NU2, ...) -> {timer, damage_per_sec, tick_timer, source_tower_id} }; разный def_id стакается
var phys_armor_debuffs: Dictionary = {}  # entity_id -> {amount: int, timer: float}
var mag_armor_debuffs: Dictionary = {}   # entity_id -> {amount: int, timer: float}
var jade_poisons: Dictionary = {}   # entity_id -> {target_id: int, instances: Array, ...}
var aura_effects: Dictionary = {}   # entity_id -> {speed_multiplier: float}

# Ауры башен
var auras: Dictionary = {}          # entity_id -> {radius: int, speed_multiplier: float, flying_only: bool, slow_factor: float}
# Замедление летающих от аур (Кварц, Чарминг): enemy_id -> множитель скорости (произведение (1 - slow) по башням; 1.0 = без замедления)
var flying_aura_slows: Dictionary = {}
# Бонус получаемого урона для летающих от аур (Чарминг): enemy_id -> bonus (0.2 = +20% урона)
var flying_damage_taken_bonus: Dictionary = {}
# Бонус получаемого урона в ауре Парайбы (all_enemies_slow + damage_taken_bonus): enemy_id -> bonus (0.15 = +15% урона)
var paraba_damage_taken_bonus: Dictionary = {}

# Визуальные эффекты
var damage_flashes: Dictionary = {} # entity_id -> {timer: float}
var lasers: Dictionary = {}         # entity_id -> {target_pos: Vector2, timer: float}
var aoe_effects: Dictionary = {}    # entity_id -> {max_radius: float, current_radius: float, timer: float}

# Линии энергосети
var energy_lines: Dictionary = {}   # entity_id -> {tower1_id: int, tower2_id: int, is_hidden: bool}

# Текст
var texts: Dictionary = {}          # entity_id -> {text: String, offset: Vector2}

# Крафт
var combinables: Dictionary = {}    # entity_id -> {crafts: Array[CraftInfo]}

# Волны
var waves: Dictionary = {}          # entity_id -> {enemies_to_spawn: int, spawn_interval: float, ...}

# Дизарм башен (от способности врагов): tower_id -> { "timer": float }
var tower_disarm: Dictionary = {}
# Замедление атаки башни (антачибл): tower_id -> { "timer": float, "multiplier": float }
var tower_attack_slow: Dictionary = {}
# Реактивная броня врага: enemy_id -> { "stacks": int, "timer": float }
var reactive_armor_stacks: Dictionary = {}
# Кракен шел: накопленный урон до сброса эффектов; enemy_id -> float
var kraken_damage_taken: Dictionary = {}

# Игрок
var player_states: Dictionary = {}  # entity_id -> {level: int, current_xp: int, xp_to_next_level: int, health: int}

# Спецбашни
var beacons: Dictionary = {}        # entity_id -> {current_angle: float, rotation_speed: float, ...}
var beacon_sectors: Dictionary = {} # entity_id -> {is_visible: bool, range: float, arc: float, angle: float}
var volcano_auras: Dictionary = {}  # entity_id -> {radius: int, tick_timer: float, ...}
var volcano_effects: Dictionary = {}# entity_id -> {max_radius: float, timer: float}
var auriga_lines: Dictionary = {}    # tower_id -> {is_visible: bool, hexes: Array[String]}

# Выбор башен
var manual_selection_markers: Dictionary = {} # entity_id -> bool

# Накопление дробного регена врагов (enemy_id -> float)
var enemy_regen_accumulator: Dictionary = {}

# Цепная молния (Бладстоун): массив { positions: Array[Vector2], timer: float }
var chain_lightning_effects: Array = []

# Крик (Турнамент): временные зоны { center: Vector2, radius_hex: float, created_at: float, duration: float, enemy_time: Dictionary }
# enemy_time: enemy_id -> накопленные секунды в зоне; при >= zone_duration накладываем стан 6 с и +50% урона 6 с
var scream_zones: Array = []
# Дебаффы от крика: стан (враг не двигается) и бонус получаемого урона
var scream_stun: Dictionary = {}       # enemy_id -> { timer: float }
var scream_damage_bonus: Dictionary = {}  # enemy_id -> { timer: float, bonus: float }

# Состояние игры (синглтон-компонент)
var game_state: Dictionary = {}     # Единственный экземпляр: {phase: GamePhase, current_wave: int, ...}

# ============================================================================
# СОЗДАНИЕ/УДАЛЕНИЕ СУЩНОСТЕЙ
# ============================================================================

func _init():
	_component_stores = [
		positions, velocities, healths, renderables,
		towers, combat, turrets, enemies, paths, projectiles, ores,
		slow_effects, bash_effects, poison_effects,
		phys_armor_debuffs, mag_armor_debuffs, jade_poisons,
		aura_effects, auras, flying_aura_slows, flying_damage_taken_bonus, paraba_damage_taken_bonus,
		damage_flashes, lasers, aoe_effects, energy_lines, texts,
		combinables, waves, player_states,
		tower_disarm, tower_attack_slow, reactive_armor_stacks, kraken_damage_taken,
		enemy_regen_accumulator,
		beacons, beacon_sectors, volcano_auras, volcano_effects, auriga_lines,
		manual_selection_markers,
		scream_stun, scream_damage_bonus
	]

func create_entity() -> int:
	var id = next_id
	next_id += 1
	entities[id] = true
	return id

func destroy_entity(entity_id: int):
	if not entity_id in entities:
		return
	
	# Очистка ore_hex_index перед удалением из ores
	if ores.has(entity_id):
		var ore = ores[entity_id]
		var hex = ore.get("hex")
		if hex:
			ore_hex_index.erase(hex.to_key())
	
	# Автоматическая очистка из всех зарегистрированных хранилищ
	for store in _component_stores:
		store.erase(entity_id)
	
	if game_state.has("tower_hit_stacks") and game_state["tower_hit_stacks"].has(entity_id):
		game_state["tower_hit_stacks"].erase(entity_id)
	
	entities.erase(entity_id)

func entity_exists(entity_id: int) -> bool:
	return entity_id in entities

# ============================================================================
# КОМПОНЕНТ-УТИЛИТЫ
# ============================================================================

# Добавить компонент
func add_component(entity_id: int, component_type: String, data: Dictionary):
	if not entity_exists(entity_id):
		push_error("Entity %d does not exist" % entity_id)
		return
	
	match component_type:
		"position": positions[entity_id] = data
		"velocity": velocities[entity_id] = data
		"health": healths[entity_id] = data
		"renderable": renderables[entity_id] = data
		"tower": towers[entity_id] = data
		"combat": combat[entity_id] = data
		"turret": turrets[entity_id] = data
		"enemy": enemies[entity_id] = data
		"path": paths[entity_id] = data
		"projectile": projectiles[entity_id] = data
		"ore": ores[entity_id] = data
		"slow_effect": slow_effects[entity_id] = data
		"poison_effect": poison_effects[entity_id] = data
		"phys_armor_debuff": phys_armor_debuffs[entity_id] = data
		"mag_armor_debuff": mag_armor_debuffs[entity_id] = data
		"jade_poison": jade_poisons[entity_id] = data
		"aura_effect": aura_effects[entity_id] = data
		"aura": auras[entity_id] = data
		"damage_flash": damage_flashes[entity_id] = data
		"laser": lasers[entity_id] = data
		"aoe_effect": aoe_effects[entity_id] = data
		"energy_line": energy_lines[entity_id] = data
		"text": texts[entity_id] = data
		"combinable": combinables[entity_id] = data
		"wave": waves[entity_id] = data
		"player_state": player_states[entity_id] = data
		"beacon": beacons[entity_id] = data
		"beacon_sector": beacon_sectors[entity_id] = data
		"volcano_aura": volcano_auras[entity_id] = data
		"volcano_effect": volcano_effects[entity_id] = data
		"auriga_line": auriga_lines[entity_id] = data
		"manual_selection": manual_selection_markers[entity_id] = data
		_:
			push_error("Unknown component type: %s" % component_type)

# Удалить компонент
func remove_component(entity_id: int, component_type: String):
	match component_type:
		"position": positions.erase(entity_id)
		"velocity": velocities.erase(entity_id)
		"health": healths.erase(entity_id)
		"renderable": renderables.erase(entity_id)
		"tower": towers.erase(entity_id)
		"combat": combat.erase(entity_id)
		"turret": turrets.erase(entity_id)
		"enemy": enemies.erase(entity_id)
		"path": paths.erase(entity_id)
		"projectile": projectiles.erase(entity_id)
		"ore": ores.erase(entity_id)
		"slow_effect": slow_effects.erase(entity_id)
		"poison_effect": poison_effects.erase(entity_id)
		"phys_armor_debuff": phys_armor_debuffs.erase(entity_id)
		"mag_armor_debuff": mag_armor_debuffs.erase(entity_id)
		"jade_poison": jade_poisons.erase(entity_id)
		"aura_effect": aura_effects.erase(entity_id)
		"aura": auras.erase(entity_id)
		"damage_flash": damage_flashes.erase(entity_id)
		"laser": lasers.erase(entity_id)
		"aoe_effect": aoe_effects.erase(entity_id)
		"energy_line": energy_lines.erase(entity_id)
		"text": texts.erase(entity_id)
		"combinable": combinables.erase(entity_id)
		"wave": waves.erase(entity_id)
		"player_state": player_states.erase(entity_id)
		"beacon": beacons.erase(entity_id)
		"beacon_sector": beacon_sectors.erase(entity_id)
		"volcano_aura": volcano_auras.erase(entity_id)
		"volcano_effect": volcano_effects.erase(entity_id)
		"auriga_line": auriga_lines.erase(entity_id)
		"manual_selection": manual_selection_markers.erase(entity_id)

# Проверить наличие компонента
func has_component(entity_id: int, component_type: String) -> bool:
	match component_type:
		"position": return entity_id in positions
		"velocity": return entity_id in velocities
		"health": return entity_id in healths
		"renderable": return entity_id in renderables
		"tower": return entity_id in towers
		"combat": return entity_id in combat
		"turret": return entity_id in turrets
		"enemy": return entity_id in enemies
		"path": return entity_id in paths
		"projectile": return entity_id in projectiles
		"ore": return entity_id in ores
		"slow_effect": return entity_id in slow_effects
		"poison_effect": return entity_id in poison_effects
		"phys_armor_debuff": return entity_id in phys_armor_debuffs
		"mag_armor_debuff": return entity_id in mag_armor_debuffs
		"jade_poison": return entity_id in jade_poisons
		"aura_effect": return entity_id in aura_effects
		"aura": return entity_id in auras
		"damage_flash": return entity_id in damage_flashes
		"laser": return entity_id in lasers
		"aoe_effect": return entity_id in aoe_effects
		"energy_line": return entity_id in energy_lines
		"text": return entity_id in texts
		"combinable": return entity_id in combinables
		"wave": return entity_id in waves
		"player_state": return entity_id in player_states
		"beacon": return entity_id in beacons
		"beacon_sector": return entity_id in beacon_sectors
		"volcano_aura": return entity_id in volcano_auras
		"volcano_effect": return entity_id in volcano_effects
		"auriga_line": return entity_id in auriga_lines
		"manual_selection": return entity_id in manual_selection_markers
		"energy_line": return entity_id in energy_lines
		_:
			return false

func get_combined_slow_factor(entity_id: int) -> float:
	"""Суммарный множитель скорости от всех стаков замедления (перемножение по источникам)."""
	if not slow_effects.has(entity_id):
		return 1.0
	var data = slow_effects[entity_id]
	if not data is Dictionary:
		return 1.0
	var combined := 1.0
	for source_key in data:
		var entry = data[source_key]
		if entry is Dictionary:
			combined *= entry.get("slow_factor", 1.0)
	return combined

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ СОСТОЯНИЯ ИГРЫ
# ============================================================================

func init_game_state():
	game_state = {
		"phase": GameTypes.GamePhase.BUILD_STATE,
		"current_wave": 0,
		"towers_built_this_phase": 0,
		"placements_made_this_phase": 0,
		"time_speed": 1.0,
		"paused": false,
		"total_enemies_killed": 0,
		"total_ore_spent_cumulative": 0.0,
		"line_edit_mode": false,  # Режим редактирования энерголиний (U)
		"drag_source_tower_id": 0,
		"drag_original_parent_id": 0,
		"hidden_line_id": 0,
		"future_path": [],           # Ключи гексов пути Entry→Exit (для отрисовки)
		"cleared_checkpoints": {},    # hex_key -> true (пройденные чекпоинты по последнему врагу)
		"difficulty": GameManager.difficulty if GameManager else GameTypes.Difficulty.MEDIUM,
		"success_level": Config.SUCCESS_LEVEL_DEFAULT,
		"success_scale": Config.SUCCESS_SCALE_MAX,
		"alive_enemies_count": 0,  # для HUD; обновляется в wave_system (_spawn_enemy) и kill_enemy
		"stash_queue": [],  # очередь стеша для фазы BUILD: массив "Б"/"А", при постановке — pop, при снятии Б — push в начало
		"tower_hit_stacks": {},  # enemy_id -> { "TOWER_U235" -> { stacks, timer } } для бонуса повторных попаданий
		"wave_snapshots": []  # снимки состояния в начале каждой волны (seed, current_wave, towers) для симуляций
	}

# ============================================================================
# УБИЙСТВО ВРАГА (единая точка вместо дублирования в 5 системах)
# ============================================================================

func kill_enemy(entity_id: int, source_tower_id: int = -1) -> void:
	if GameManager:
		GameManager.record_enemy_wave_progress(entity_id)
		GameManager.on_enemy_killed(entity_id)
	# Единый счётчик живых врагов для HUD (обновляется при убийстве и при спавне)
	if game_state.has("alive_enemies_count"):
		var c = game_state["alive_enemies_count"]
		if c > 0:
			game_state["alive_enemies_count"] = c - 1
	var enemy = enemies.get(entity_id)
	# Волна 40 (Тройник): при смерти одного босса у оставшихся удваиваются текущее/макс HP и реген
	var triplet_ids: Array = game_state.get("wave_40_triplet_ids", [])
	var was_in_triplet = entity_id in triplet_ids
	if was_in_triplet:
		for other_id in triplet_ids:
			if other_id == entity_id:
				continue
			if not enemies.has(other_id):
				continue
			var other_health = healths.get(other_id)
			var other_enemy = enemies.get(other_id)
			if other_health and other_health.get("current", 0) > 0 and other_enemy:
				other_health["current"] = mini(999999999, other_health["current"] * 2)
				other_health["max"] = mini(999999999, other_health["max"] * 2)
				other_enemy["regen"] = other_enemy.get("regen", 0) * 2.0
		triplet_ids.erase(entity_id)
		game_state["wave_40_triplet_ids"] = triplet_ids
	# Лут босса: на волне 40 только когда убиты все 3 босса (последний из triplet)
	if enemy and enemy.get("def_id", "") == "ENEMY_BOSS":
		if GameManager:
			if was_in_triplet and triplet_ids.size() == 0:
				GameManager.on_boss_killed()
			elif not was_in_triplet:
				GameManager.on_boss_killed()
	game_state["total_enemies_killed"] = game_state.get("total_enemies_killed", 0) + 1
	if enemy and enemy.get("is_gold", false) and GameManager:
		GameManager.distribute_gold_creature_ore_reward()
	PlayerSystem.grant_xp_for_kill()
	destroy_entity(entity_id)

func get_player_level() -> int:
	for _pid in player_states:
		return player_states[_pid].get("level", 1)
	return 1

# ============================================================================
# ДЕБАГ
# ============================================================================

func print_stats():
	print("=== ECS World Stats ===")
	print("  Entities: %d" % entities.size())
	print("  Positions: %d" % positions.size())
	print("  Towers: %d" % towers.size())
	print("  Enemies: %d" % enemies.size())
	print("  Projectiles: %d" % projectiles.size())
	print("  Ores: %d" % ores.size())
	print("  Energy lines: %d" % energy_lines.size())

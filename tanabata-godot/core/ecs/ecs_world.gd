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
var slow_effects: Dictionary = {}   # entity_id -> {slow_factor: float, timer: float}
var bash_effects: Dictionary = {}  # entity_id -> {timer: float} — оглушение: не двигается, не использует активные скиллы
var poison_effects: Dictionary = {} # entity_id -> {damage_per_sec: float, timer: float, tick_timer: float}
var phys_armor_debuffs: Dictionary = {}  # entity_id -> {amount: int, timer: float}
var mag_armor_debuffs: Dictionary = {}   # entity_id -> {amount: int, timer: float}
var jade_poisons: Dictionary = {}   # entity_id -> {target_id: int, instances: Array, ...}
var aura_effects: Dictionary = {}   # entity_id -> {speed_multiplier: float}

# Ауры башен
var auras: Dictionary = {}          # entity_id -> {radius: int, speed_multiplier: float, flying_only: bool, slow_factor: float}
# Замедление летающих от аур (Кварц): enemy_id -> slow_factor (0.6 = 60% slow)
var flying_aura_slows: Dictionary = {}

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

# Выбор башен
var manual_selection_markers: Dictionary = {} # entity_id -> bool

# Накопление дробного регена врагов (enemy_id -> float)
var enemy_regen_accumulator: Dictionary = {}

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
		aura_effects, auras, flying_aura_slows,
		damage_flashes, lasers, aoe_effects, energy_lines, texts,
		combinables, waves, player_states,
		tower_disarm, tower_attack_slow, reactive_armor_stacks, kraken_damage_taken,
		enemy_regen_accumulator,
		beacons, beacon_sectors, volcano_auras, volcano_effects,
		manual_selection_markers
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
		"manual_selection": manual_selection_markers[entity_id] = data
		"energy_line": energy_lines[entity_id] = data
		"ore": ores[entity_id] = data
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
		"manual_selection": return entity_id in manual_selection_markers
		"energy_line": return entity_id in energy_lines
		_:
			return false

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
		"line_edit_mode": false,  # Режим редактирования энерголиний (U)
		"drag_source_tower_id": 0,
		"drag_original_parent_id": 0,
		"hidden_line_id": 0,
		"future_path": [],           # Ключи гексов пути Entry→Exit (для отрисовки)
		"cleared_checkpoints": {},    # hex_key -> true (пройденные чекпоинты по последнему врагу)
		"difficulty": GameManager.difficulty if GameManager else GameTypes.Difficulty.MEDIUM
	}

# ============================================================================
# УБИЙСТВО ВРАГА (единая точка вместо дублирования в 5 системах)
# ============================================================================

func kill_enemy(entity_id: int, source_tower_id: int = -1) -> void:
	game_state["total_enemies_killed"] = game_state.get("total_enemies_killed", 0) + 1
	PlayerSystem.grant_xp_for_kill()
	destroy_entity(entity_id)

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

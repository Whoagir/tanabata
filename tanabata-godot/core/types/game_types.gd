# game_types.gd
# Все игровые типы, энумы и константы
# Перенесено из Go проекта
class_name GameTypes

# ============================================================================
# ENTITY ID
# ============================================================================

# В GDScript используем просто int для entity ID
# В Go это был отдельный тип type EntityID int
# Здесь просто соглашение: int >= 0 - валидный ID, -1 - invalid

const INVALID_ENTITY_ID = -1

# ============================================================================
# DIFFICULTY (Уровень сложности)
# ============================================================================

enum Difficulty {
	EASY,    # Враги на 60% меньше HP, на 10% медленнее
	MEDIUM,  # Базовые значения (текущий баланс)
	HARD     # Враги на 40% больше HP, на 20% больше регена
}

# ============================================================================
# GAME PHASE (Фазы игры)
# ============================================================================

enum GamePhase {
	BUILD_STATE,           # Строительство (размещение башен)
	WAVE_STATE,            # Волна (атака врагов)
	TOWER_SELECTION_STATE  # Выбор башен для сохранения
}

# ============================================================================
# TOWER TYPE (Типы башен)
# ============================================================================

enum TowerType {
	ATTACK,  # Атакующая башня
	MINER,   # Добывающая энергию (на руде)
	WALL     # Стена (препятствие)
}

# ============================================================================
# ATTACK TYPE (Типы атак)
# ============================================================================

enum AttackType {
	PROJECTILE,  # Снаряд
	LASER,       # Лазер (мгновенный)
	AOE,         # Area of Effect (вулкан)
	BEACON,      # Вращающийся луч (маяк)
	NONE         # Нет атаки (поддержка)
}

# ============================================================================
# DAMAGE TYPE (Типы урона)
# ============================================================================

enum DamageType {
	PHYSICAL,  # Физический (уменьшается физ. броней)
	MAGICAL,   # Магический (уменьшается маг. броней)
	PURE,      # Чистый (игнорирует броню)
	SLOW,      # Замедление (+ эффект)
	POISON,    # Яд (+ DOT эффект)
	INTERNAL   # Внутренний (для спец. башен)
}

# ============================================================================
# EVENT TYPE (Типы событий)
# ============================================================================

enum EventType {
	ENEMY_KILLED,
	TOWER_PLACED,
	TOWER_REMOVED,
	ORE_DEPLETED,
	WAVE_ENDED,
	ORE_CONSUMED,
	COMBINE_TOWERS_REQUEST,
	TOGGLE_TOWER_SELECTION_FOR_SAVE_REQUEST,
	ENEMY_REMOVED_FROM_GAME
}

# ============================================================================
# ВИЗУАЛЬНЫЕ ТИПЫ
# ============================================================================

enum ProjectileVisualType {
	SPHERE,    # Обычный снаряд
	ELLIPSE    # Эллипсоид (для Jade)
}

# ============================================================================
# УТИЛИТЫ ДЛЯ СТРОК
# ============================================================================

# Преобразование enum в строку для отладки
static func game_phase_to_string(phase: GamePhase) -> String:
	match phase:
		GamePhase.BUILD_STATE: return "BUILD"
		GamePhase.WAVE_STATE: return "WAVE"
		GamePhase.TOWER_SELECTION_STATE: return "SELECTION"
		_: return "UNKNOWN"

static func tower_type_to_string(type: TowerType) -> String:
	match type:
		TowerType.ATTACK: return "ATTACK"
		TowerType.MINER: return "MINER"
		TowerType.WALL: return "WALL"
		_: return "UNKNOWN"

static func attack_type_to_string(type: AttackType) -> String:
	match type:
		AttackType.PROJECTILE: return "PROJECTILE"
		AttackType.LASER: return "LASER"
		AttackType.AOE: return "AOE"
		AttackType.BEACON: return "BEACON"
		AttackType.NONE: return "NONE"
		_: return "UNKNOWN"

static func damage_type_to_string(type: DamageType) -> String:
	match type:
		DamageType.PHYSICAL: return "PHYSICAL"
		DamageType.MAGICAL: return "MAGICAL"
		DamageType.PURE: return "PURE"
		DamageType.SLOW: return "SLOW"
		DamageType.POISON: return "POISON"
		DamageType.INTERNAL: return "INTERNAL"
		_: return "UNKNOWN"

# ============================================================================
# ЦВЕТА ПО ТИПУ УРОНА
# ============================================================================

static func get_damage_type_color(type: DamageType) -> Color:
	match type:
		DamageType.PHYSICAL: return Config.PROJECTILE_COLOR_PHYSICAL
		DamageType.MAGICAL: return Config.PROJECTILE_COLOR_MAGICAL
		DamageType.PURE: return Config.PROJECTILE_COLOR_PURE
		DamageType.SLOW: return Config.PROJECTILE_COLOR_SLOW
		DamageType.POISON: return Config.PROJECTILE_COLOR_POISON
		_: return Color.WHITE

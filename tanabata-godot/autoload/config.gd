# config.gd
# Автозагружаемый синглтон с константами и настройками игры
# Перенесено из Go проекта (internal/config/config.go)
extends Node

# ============================================================================
# ЭКРАН И РЕНДЕРИНГ
# ============================================================================

const SCREEN_WIDTH = 1200
const SCREEN_HEIGHT = 993

# Размер гекса в пикселях (для 2D)
const HEX_SIZE = 20.0

# Радиус карты в гексах
const MAP_RADIUS = 15

# Максимальное время кадра (для предотвращения спирали смерти)
const MAX_DELTA_TIME = 0.05

# ============================================================================
# ИГРОВАЯ ЛОГИКА
# ============================================================================

# Симуляция (fixed timestep)
const TICK_RATE = 30  # тиков в секунду
const FIXED_DELTA = 1.0 / TICK_RATE

# Здоровье игрока (отдельно от прогресса по опыту)
const BASE_HEALTH = 100

# Лимиты строительства
const MAX_TOWERS_IN_BUILD_PHASE = 5
const TOWERS_TO_KEEP = 2  # Сколько башен сохраняется после фазы выбора

# ============================================================================
# СЛОЖНОСТЬ (множители врагов: HP, скорость, реген)
# ============================================================================

static func get_difficulty_health_multiplier(difficulty: int) -> float:
	match difficulty:
		GameTypes.Difficulty.EASY: return 0.4   # На 60% меньше HP
		GameTypes.Difficulty.HARD: return 1.61  # На 40% + ещё 15% больше HP
		_: return 1.0  # MEDIUM

static func get_difficulty_speed_multiplier(difficulty: int) -> float:
	match difficulty:
		GameTypes.Difficulty.EASY: return 0.9   # На 10% медленнее
		GameTypes.Difficulty.HARD: return 1.1   # На 10% быстрее
		_: return 1.0  # MEDIUM

static func get_difficulty_regen_multiplier(difficulty: int) -> float:
	match difficulty:
		GameTypes.Difficulty.HARD: return 1.2   # На 20% больше регена
		_: return 1.0  # EASY, MEDIUM

# Бонус брони на Hard: +5 физ, +5 маг всем врагам
static func get_difficulty_physical_armor_bonus(difficulty: int) -> int:
	return 5 if difficulty == GameTypes.Difficulty.HARD else 0

static func get_difficulty_magical_armor_bonus(difficulty: int) -> int:
	return 5 if difficulty == GameTypes.Difficulty.HARD else 0

# ============================================================================
# ЭНЕРГОСЕТЬ
# ============================================================================

const ENERGY_TRANSFER_RADIUS = 4  # Максимальная дистанция для майнер-майнер соединений
const ORE_DEPLETION_THRESHOLD = 0.1  # Минимальный запас руды для активности (как в Go)

# Плавное восстановление руды во время волны: каждые ORE_RESTORE_INTERVAL сек добавляем restore_per_round/ORE_RESTORE_TICKS_PER_WAVE
const ORE_RESTORE_INTERVAL = 1.0      # секунд между тиками восстановления
const ORE_RESTORE_TICKS_PER_WAVE = 20 # за волну всего restore_per_round (тиков * порция = полное восстановление)
# Все майнеры восстанавливают на 30% меньше руды (итоговый множитель 0.7)
const ORE_RESTORE_GLOBAL_MULT = 0.7
# Башни второго яруса крафта (crafting_level >= 1): расход руды на 70% больше
const ORE_COST_TIER2_MULTIPLIER = 1.7

# Башни с аурой (DE, DA, Volcano, Lighthouse): множитель расхода руды (0.6 = −40%)
const AURA_ORE_COST_FACTOR = 0.6
# Башня под аурой скорости: дополнительный множитель стоимости выстрела (0.7 = −30%)
const AURA_SPEED_ORE_COST_FACTOR = 0.7
# Яд Джейда: множитель регена врага (0.5 = режет реген вдвое)
const JADE_POISON_REGEN_FACTOR = 0.5
# Маяк: множитель дальности сектора (1.3 = +30%), множители урона за тик (base * DAMAGE_BASE * DAMAGE_BONUS)
const BEACON_RANGE_MULTIPLIER = 1.3
const BEACON_DAMAGE_BASE_MULT = 4.0
const BEACON_DAMAGE_BONUS_MULT = 1.2

# Стоимость крафта в энергии (руда): списывается при крафте
const CRAFT_COST_LEVEL_1 = 5   # крафт 1 уровня (3 башни → Silver/Malachite/...)
const CRAFT_COST_X2 = 2        # крафт х2 (2×L→L+1)
const CRAFT_COST_X4 = 3        # крафт х4 (4×L→L+2)
const CRAFT_COST_LEVEL_2 = 9   # крафт 2 уровня (Silver Knight, Vivid Malachite, ...)
const DOWNGRADE_COST = 3       # кнопка «Упростить» (даунгрейд башни на 1 уровень)

# ============================================================================
# БАШНИ
# ============================================================================
#
# Понятия:
#   • Уровень крафта (crafting_level) — ярус получения башни:
#     0 = первый ярус: базовые башни (дроп с волн, крафт TA+TE→TA2 и т.п.). У них есть ещё level 1–6.
#     1 = второй ярус: крафт из рецептов (Silver, Malachite, Jade, Volcano, Lighthouse и т.д.). Своей шкалы level нет.
#     (2, 3, … — задел на будущие ярусы.)
#   • Уровень башни (level) — только у башен первого яруса (crafting_level == 0): 1–6.
#     Влияет на урон, размер, расход руды (shot_cost). Дроп даёт 1–5, шестой только крафтом.
#     У Silver/Malachite/Jade и т.п. поле level в def может быть, но не используется для скейла.
#
# ============================================================================

const TOWER_RANGE_DEFAULT = 3  # гексов
const TOWER_RADIUS_FACTOR = 0.3

# Базовые линии первого яруса (crafting_level == 0) с уровнями 1–6
const TOWER_LEVELABLE_BASES = ["TA", "TE", "TO", "PA", "PE", "PO", "DE", "DA", "NI", "NU", "NA", "NE"]

# Распределение уровней вышки при дропе по уровню игрока: [вес Lv.1, Lv.2, Lv.3, Lv.4, Lv.5]
func get_tower_level_weights(player_level: int) -> Array:
	if player_level <= 1:
		return [97, 3, 0, 0, 0]
	if player_level == 2:
		return [55, 42, 3, 0, 0]
	if player_level == 3:
		return [35, 35, 27, 3, 0]
	if player_level == 4:
		return [15, 30, 35, 17, 3]
	# 5 и выше
	return [7, 25, 30, 28, 10]

# Случайный уровень вышки 1–5 по уровню игрока (для дропа)
func pick_tower_level_for_drop(player_level: int) -> int:
	var weights = get_tower_level_weights(player_level)
	var total = 0
	for w in weights:
		total += w
	if total <= 0:
		return 1
	var r = randi() % total
	for i in range(weights.size()):
		r -= weights[i]
		if r < 0:
			return i + 1
	return 1

# Визуальный размер башни по уровню (1–6): Lv.1 чуть меньше гекса (0.45), Lv.6 близок к гексу (0.95)
func get_tower_radius_factor_for_level(level: int) -> float:
	if level >= 1 and level <= 6:
		return 0.45 + 0.10 * (level - 1)
	return 0.6

# ============================================================================
# ЭНЕРГОСЕТЬ
# ============================================================================

# Максимальная дистанция соединения
const ENERGY_TRANSFER_RADIUS_NORMAL = 1  # для обычных башен
const ENERGY_TRANSFER_RADIUS_MINER = 4   # для шахтеров (на одной линии)

# Деградация энергии (множитель за каждую атакующую башню в цепи)
const LINE_DEGRADATION_FACTOR = 0.9

# Высота линии (для 3D, в 2D не используется)
const LINE_HEIGHT = 5.0

# ============================================================================
# РУДА
# ============================================================================

# Всего энергии на карте
const TOTAL_MAP_POWER_MIN = 240
const TOTAL_MAP_POWER_MAX = 270

# Бонус от количества руды (множители урона)
const ORE_RESERVE_LOW = 100.0   # При <= 100 множитель = 1.5
const ORE_RESERVE_HIGH = 1000.0 # При >= 1000 множитель = 0.75
const ORE_MULTIPLIER_LOW = 1.5
const ORE_MULTIPLIER_HIGH = 0.75

# ============================================================================
# ВРАГИ И ВОЛНЫ
# ============================================================================

# Стартовая волна
const INITIAL_WAVE = 1

# Интервалы спавна (мс)
const INITIAL_SPAWN_INTERVAL = 800
const MIN_SPAWN_INTERVAL = 100

# Урон от врагов (суммарно за волну)
const TOTAL_WAVE_DAMAGE = 100

# Урон от окружения (руда и энерголинии)
const ENV_DAMAGE_ORE_PER_TICK = 2  # Урон/тик на гексе с рудой
const ENV_DAMAGE_LINE_PER_TICK = 5  # Урон/тик при прохождении энерголинии

# ============================================================================
# СНАРЯДЫ
# ============================================================================

const PROJECTILE_SPEED = 185.0  # пикселей в секунду (увеличено для меньших промахов по быстрым/раш врагам)
const PROJECTILE_HIT_RADIUS = 32.0  # считаем попадание, если цель в этом радиусе
const PROJECTILE_RADIUS = 6.0  # Радиус визуала снаряда

# Потиковая донаводка (не каждый кадр): раз в N сек корректируем направление к цели
const HOMING_TICK_INTERVAL = 0.06  # сек между коррекциями
const HOMING_CORRECTION_STRENGTH = 0.18  # сила поворота к цели (0.1 = плавно, 0.3 = резче)
const HOMING_ACTIVATE_DISTANCE = 200.0  # начинать донаводку только когда до цели меньше этого (пиксели)

# Время анимации появления снаряда
const PROJECTILE_SCALE_UP_DURATION = 0.15

# ============================================================================
# ВИЗУАЛЬНЫЕ ЭФФЕКТЫ
# ============================================================================

# Время вспышки при уроне
const DAMAGE_FLASH_DURATION = 0.2

# Время лазера (визуал; должно пережить хотя бы один кадр отрисовки)
const LASER_DURATION = 0.4

# ============================================================================
# СТАТУС-ЭФФЕКТЫ
# ============================================================================

const SLOW_DURATION = 3.0       # Длительность замедления (секунды)
const SLOW_FACTOR = 0.5         # Множитель скорости (0.5 = 50% скорости)
const POISON_DURATION = 5.0     # Длительность яда (секунды)
const POISON_DPS = 5            # Урон в секунду от яда

# Способности врагов: дизарм (башни не стреляют в радиусе)
const DISARM_RANGE_HEX = 2     # Радиус наложения дизарма от врага (гексы)
const DISARM_DURATION = 2.0    # Длительность дизарма башни (секунды)
# Антачибл: замедление скорости атаки башни на 600% (в 6 раз)
const UNTOUCHABLE_SLOW_MULTIPLIER = 6.0
const UNTOUCHABLE_DURATION = 3.0
# Раш: ускорение врага 250%, длительность 2 с, кулдаун 5 с
const RUSH_SPEED_MULT = 2.5
const RUSH_DURATION = 6.0
const RUSH_COOLDOWN = 5.0
# Блинк: телепорт на 8 гексов вперёд, кулдаун 8 с, старт с кулдауна 4 с
const BLINK_HEXES = 8
const BLINK_COOLDOWN = 8.0
const BLINK_START_COOLDOWN = 4.0
# Рефлекшн: 4 слоя щита (каждый удар снимает 1), кулдаун 5 с
const REFLECTION_STACKS = 4
const REFLECTION_COOLDOWN = 5.0
# Хус: реген до 250% от базы при низком HP
const HUS_REGEN_MAX_MULT = 2.5
# Хиллер: аура +20 к регену, радиус 4 гекса
const HEALER_AURA_RADIUS = 4
const HEALER_AURA_REGEN_BONUS = 20
# Агрро (танк): вышки в радиусе 4 гекса бьют только танка, длительность 2 с, кулдаун 5 с
const AGGRO_DURATION = 2.0
const AGGRO_COOLDOWN = 5.0
const AGGRO_RADIUS_HEX = 4
# Реактивная броня: макс стаков +20 к броне и регену, таймер стака 4 сек
const REACTIVE_ARMOR_MAX_STACKS = 20
const REACTIVE_ARMOR_STACK_DURATION = 4.0
# Кракен шел: сброс дебаффов при получении 200 урона
const KRAKEN_SHELL_DAMAGE_THRESHOLD = 200
const PHYS_ARMOR_DEBUFF_AMOUNT = 8   # Снижение физ. брони от NA
const PHYS_ARMOR_DEBUFF_DURATION = 4.0
const MAG_ARMOR_DEBUFF_AMOUNT = 8    # Снижение маг. брони от NE
const MAG_ARMOR_DEBUFF_DURATION = 4.0

# Скорость вращения маяка (радианы/сек)
const BEACON_ROTATION_SPEED = 1.5

# Угол атаки маяка (градусы)
const BEACON_ARC_ANGLE = 90.0

# Тики в секунду для маяка и вулкана
const BEACON_TICK_RATE = 24
const VOLCANO_TICK_RATE = 4

# ============================================================================
# ОПЫТ И ПРОГРЕССИЯ
# ============================================================================

const XP_PER_KILL = 10

# Опыт для перехода на следующий уровень. Баланс: Lv.2 к волне 7–8, Lv.3 к волне 18–19.
func calculate_xp_for_level(level: int) -> int:
	if level <= 0:
		return 100
	if level == 1:
		return 580   # Lv.1→2: ~58 убийств к волне 8
	if level == 2:
		return 1310   # Lv.2→3: ещё ~131 убийство, к волне 18–19
	# Дальше плавный рост
	return 1310 + (level - 2) * 400

# Суммарный XP (для аналитики): сколько всего набрано за всё время
func get_total_xp(level: int, current_xp: int) -> int:
	var total = current_xp
	for l in range(1, level):
		total += calculate_xp_for_level(l)
	return total

# ============================================================================
# КАМЕРА (2D)
# ============================================================================

const CAMERA_ZOOM_MIN = 0.5
const CAMERA_ZOOM_MAX = 2.0
const CAMERA_ZOOM_STEP = 0.1

# ============================================================================
# UI КОНСТАНТЫ
# ============================================================================

const UI_BORDER_WIDTH = 2.0
const INDICATOR_OFFSET_X = 30
const INDICATOR_RADIUS = 10.0

# ============================================================================
# ЦВЕТА (из диздока - "Grounded Hex-Tech")
# ============================================================================

# Основная палитра (темный камень, железо, медь)
const COLOR_DARK_STONE = Color(0.15, 0.15, 0.18)       # Темный камень
const COLOR_OLD_WOOD = Color(0.25, 0.20, 0.15)        # Старое дерево
const COLOR_IRON = Color(0.35, 0.35, 0.38)            # Кованое железо
const COLOR_COPPER = Color(0.55, 0.35, 0.25)          # Тусклая медь
const COLOR_BRONZE = Color(0.50, 0.40, 0.25)          # Бронза

# Руда (ярко пульсирует)
const COLOR_ORE_BRIGHT = Color(0.4, 0.8, 1.0)         # Яркая руда
const COLOR_ORE_DIM = Color(0.2, 0.4, 0.6)            # Истощенная руда

# Энергосеть (светящиеся рунические каналы)
const COLOR_ENERGY_LINE = Color(0.3, 0.7, 1.0)        # Энергетическая линия
const COLOR_ENERGY_PULSE = Color(0.7, 0.9, 1.0)       # Импульс энергии

# Гексы и карта
const COLOR_HEX_NORMAL = Color(0.18, 0.18, 0.22)      # Обычный гекс
const COLOR_HEX_OUTLINE = Color(0.25, 0.25, 0.28)     # Обводка гекса (тусклая)
const COLOR_HEX_OUTLINE_DIM = Color(0.12, 0.12, 0.14) # Обводка гекса (очень тусклая, ~5% видимости)
const COLOR_HEX_HOVER = Color(0.9, 0.9, 0.95)         # Подсветка при наведении

# Порталы
const COLOR_ENTRY_PORTAL = Color(0.3, 0.15, 0.4)      # Вход (темная энергия)
const COLOR_EXIT_PORTAL = Color(0.8, 0.15, 0.15)      # Выход (красный)

# Чекпоинты (рунные резонаторы)
const COLOR_CHECKPOINT = Color(0.7, 0.5, 0.3)         # Чекпоинт (медь/бронза)
const COLOR_CHECKPOINT_ACTIVE = Color(1.0, 0.7, 0.4)  # Активированный чекпоинт
# Пройденный чекпоинт: окисленная медь (патина, зеленовато-бирюзовый)
const COLOR_CHECKPOINT_CLEARED = Color(0.22, 0.48, 0.42, 0.78)
const COLOR_FUTURE_PATH = Color(0, 0, 0, 0.16)       # Предпросмотр пути (тусклее)

# ============================================================================
# ЦВЕТА UI
# ============================================================================

const UI_COLOR_BLUE = Color(0.173, 0.333, 0.467)      # Приглушенный синий
const UI_COLOR_RED = Color(0.663, 0.267, 0.259)       # Приглушенный красный
const UI_COLOR_YELLOW = Color(0.8, 0.573, 0.263)      # Приглушенный желтый

const BUILD_STATE_COLOR = UI_COLOR_BLUE
const WAVE_STATE_COLOR = UI_COLOR_RED
const SELECTION_STATE_COLOR = UI_COLOR_YELLOW

const PAUSE_BUTTON_PLAY_COLOR = UI_COLOR_BLUE
const PAUSE_BUTTON_PAUSE_COLOR = UI_COLOR_RED

const XP_BAR_BACKGROUND_COLOR = Color(0.2, 0.2, 0.2)
const XP_BAR_FOREGROUND_COLOR = Color(0.302, 0.565, 0.302)  # Зеленый

# Индикатор руды (3 жилы: центральная, средняя, дальняя) — как в Go
const ORE_INDICATOR_FULL_COLOR = Color(0.173, 0.333, 0.467)       # Синий (полная)
const ORE_INDICATOR_EMPTY_COLOR = Color(0, 0, 0, 0)               # Прозрачный (пустой сегмент)
const ORE_INDICATOR_WARNING_COLOR = Color(0.85, 0.325, 0.31)      # Красный
const ORE_INDICATOR_CRITICAL_COLOR = Color(0.94, 0.678, 0.306)    # Жёлтый/оранжевый
const ORE_INDICATOR_DEPLETED_COLOR = Color(0.04, 0.04, 0.04, 0.86) # Почти чёрный
const ORE_INDICATOR_BORDER_COLOR = Color(0.4, 0.4, 0.45)

# ============================================================================
# ЦВЕТА ИГРОВЫХ ОБЪЕКТОВ
# ============================================================================

const BACKGROUND_COLOR = Color(0.118, 0.118, 0.118)
# Фон под картой (за гексами). Варианты:
# COLOR_GAME_BACKGROUND = тёмный нейтральный (текущий)
# Альтернативы в комментарии: патина, сумерки, земля
const COLOR_GAME_BACKGROUND = Color(0.09, 0.09, 0.11)   # тёмный нейтральный, чуть теплее чёрного
# Color(0.10, 0.14, 0.13)  # тёмная патина (в духе окисленной меди)
# Color(0.12, 0.14, 0.18)  # сумерки, синевато-серый
# Color(0.16, 0.14, 0.12)  # тёплая земля / песок
const GRID_COLOR = Color(0.196, 0.196, 0.196)
const HIGHLIGHT_COLOR = Color(1.0, 1.0, 0.0, 0.392)

const CHECKPOINT_COLOR = Color(1.0, 0.843, 0.0)  # Золотой

# Цвета снарядов
const PROJECTILE_COLOR_PHYSICAL = Color(1.0, 0.392, 0.0)
const PROJECTILE_COLOR_MAGICAL = Color(0.863, 0.196, 0.863)
const PROJECTILE_COLOR_PURE = Color(0.706, 0.941, 1.0)
const PROJECTILE_COLOR_SLOW = Color(0.68, 0.85, 0.90)      # Голубой (173, 216, 230)
const PROJECTILE_COLOR_POISON = Color(0.49, 0.99, 0.0)     # Ярко-зеленый (124, 252, 0)

# Цвета модуляции врагов при эффектах
const ENEMY_DAMAGE_COLOR = Color(1.5, 0.5, 0.5)            # Красная вспышка
const ENEMY_SLOW_COLOR = Color(0.6, 0.75, 1.4)             # Ярко-голубой (белее и заметнее)
const ENEMY_POISON_COLOR = Color(0.7, 1.2, 0.5)            # Зеленоватый
const ENEMY_JADE_POISON_COLOR = Color(0.15, 1.0, 0.25)    # Очень насыщенный зелёный (4+ стаков)
const ENEMY_PHYS_ARMOR_DEBUFF_COLOR = Color(0.95, 0.45, 0.25)   # Рыже-медный (NA)
const ENEMY_MAG_ARMOR_DEBUFF_COLOR = Color(0.55, 0.35, 1.0)    # Фиолетовый (NE)
const ENEMY_BASH_COLOR = Color(0.4, 1.0, 0.5)                  # Изумрудный (баш)

# Цвет линий энергосети
const ENERGY_LINE_COLOR = Color(1.0, 0.765, 0.0, 0.588)  # Золотистый

# Цвет руды
const ORE_COLOR = Color(0.0, 0.0, 1.0, 0.5)  # Синий полупрозрачный

# ============================================================================
# ДЕБАГ
# ============================================================================

var god_mode = false
var visual_debug_mode = false
var fast_tower_placement = false  # С pathfinding проверкой (по умолчанию)

# ============================================================================
# ПУТИ К ДАННЫМ
# ============================================================================

const PATH_TOWERS = "res://data/towers.json"
const PATH_ENEMIES = "res://data/enemies.json"
const PATH_RECIPES = "res://data/recipes.json"
const PATH_LOOT_TABLES = "res://data/loot_tables.json"
const PATH_WAVES = "res://data/waves.json"
const PATH_ABILITY_DEFINITIONS = "res://data/ability_definitions.json"

# Включить логи CombatSystem: почему башня не стреляет (no power, low reserve, not active). Один раз на башню за волну.
const COMBAT_DEBUG = false

# ============================================================================
# УТИЛИТЫ
# ============================================================================

# Загрузка JSON
func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("JSON file not found: " + path)
		return null
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open JSON file: " + path)
		return null
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	
	if error != OK:
		push_error("Failed to parse JSON: " + path + " at line " + str(json.get_error_line()))
		return null
	
	return json.data

# Интерполяция для бонуса руды
func calculate_ore_boost_multiplier(reserve: float) -> float:
	if reserve <= ORE_RESERVE_LOW:
		return ORE_MULTIPLIER_LOW
	elif reserve >= ORE_RESERVE_HIGH:
		return ORE_MULTIPLIER_HIGH
	else:
		# Линейная интерполяция
		var t = (reserve - ORE_RESERVE_LOW) / (ORE_RESERVE_HIGH - ORE_RESERVE_LOW)
		return lerp(ORE_MULTIPLIER_LOW, ORE_MULTIPLIER_HIGH, t)

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================================

func _ready():
	pass

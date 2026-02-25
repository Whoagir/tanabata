# data_repository.gd
# Центральное хранилище игровых данных (башни, враги, волны, рецепты)
# Вынесено из GameManager для разделения ответственности
extends Node

# ============================================================================
# ДАННЫЕ (JSON)
# ============================================================================

var tower_defs: Dictionary = {}
var enemy_defs: Dictionary = {}
var recipe_defs: Array = []
var loot_table_defs: Dictionary = {}
var wave_defs: Dictionary = {}
var ability_defs: Dictionary = {}

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================================

func _ready():
	load_all_data()

# ============================================================================
# ЗАГРУЗКА ДАННЫХ
# ============================================================================

func load_all_data():
	# Загружаем башни
	var towers_data = Config.load_json(Config.PATH_TOWERS)
	tower_defs = _process_tower_defs(towers_data)
	var enemies_data = Config.load_json(Config.PATH_ENEMIES)
	enemy_defs = _process_enemy_defs(enemies_data)
	recipe_defs = Config.load_json(Config.PATH_RECIPES)
	var loot_data = Config.load_json(Config.PATH_LOOT_TABLES)
	loot_table_defs = _process_loot_table_defs(loot_data)
	var waves_data = Config.load_json(Config.PATH_WAVES)
	wave_defs = _process_wave_defs(waves_data)
	var abilities_data = Config.load_json(Config.PATH_ABILITY_DEFINITIONS)
	ability_defs = _process_ability_defs(abilities_data)

# ============================================================================
# ОБРАБОТКА ДАННЫХ
# ============================================================================

func _process_tower_defs(data: Variant) -> Dictionary:
	var result = {}
	if data is Array:
		# JSON - это массив башен
		for tower in data:
			if "id" in tower:
				result[tower["id"]] = tower
	elif data is Dictionary and "towers" in data:
		# Если вдруг обернуто в объект
		for tower in data["towers"]:
			if "id" in tower:
				result[tower["id"]] = tower
	return result

func _process_enemy_defs(data: Variant) -> Dictionary:
	var result = {}
	if data is Array:
		# JSON - это массив врагов
		for enemy in data:
			if "id" in enemy:
				result[enemy["id"]] = enemy
	elif data is Dictionary and "enemies" in data:
		for enemy in data["enemies"]:
			if "id" in enemy:
				result[enemy["id"]] = enemy
	return result

func _process_loot_table_defs(data: Variant) -> Dictionary:
	var result = {}
	if data is Array:
		# JSON - это массив loot tables
		for table in data:
			if "player_level" in table:
				var level = int(table["player_level"])  # КОНВЕРТИРУЕМ В INT
				result[level] = table
	elif data is Dictionary and "loot_tables" in data:
		for table in data["loot_tables"]:
			if "player_level" in table:
				var level = int(table["player_level"])  # КОНВЕРТИРУЕМ В INT
				result[level] = table
	return result

func _process_wave_defs(data: Variant) -> Dictionary:
	var result = {}
	if data is Array:
		# JSON - массив волн
		for wave in data:
			if "wave_number" in wave:
				var wave_num = int(wave["wave_number"])  # Конвертируем в int
				result[wave_num] = wave
	elif data is Dictionary and "waves" in data:
		# Объект с полем waves
		for wave in data["waves"]:
			if "wave_number" in wave:
				var wave_num = int(wave["wave_number"])  # Конвертируем в int
				result[wave_num] = wave
	return result

func _process_ability_defs(data: Variant) -> Dictionary:
	var result = {}
	if data is Array:
		for ab in data:
			if ab is Dictionary and ab.get("id", ""):
				result[str(ab.id)] = ab
	return result

# ============================================================================
# ПУБЛИЧНЫЕ МЕТОДЫ (API)
# ============================================================================

# Получить определение башни по ID
func get_tower_def(tower_id: String) -> Dictionary:
	if tower_id in tower_defs:
		return tower_defs[tower_id]
	else:
		push_warning("Tower definition not found: %s" % tower_id)
		return {}

# Получить определение врага по ID
func get_enemy_def(enemy_id: String) -> Dictionary:
	if enemy_id in enemy_defs:
		return enemy_defs[enemy_id]
	else:
		push_warning("Enemy definition not found: %s" % enemy_id)
		return {}

# Получить определение волны по номеру
func get_wave_def(wave_number: int) -> Dictionary:
	# Явно заданные волны (в т.ч. 30, 31, 32, 33)
	if wave_number in wave_defs:
		return wave_defs[wave_number]
	# После 17 цикл по волнам 6–10 (для старых номеров без явной волны)
	if wave_number > 10:
		var actual_wave = 6 + ((wave_number - 11) % 5)
		if actual_wave in wave_defs:
			return wave_defs[actual_wave]
	push_warning("Wave definition not found: %d" % wave_number)
	return {}

# Определение способности (пассив/актив, имя). Для UI и будущих механик (истощение, сайленс).
func get_ability_def(ability_id: String) -> Dictionary:
	if ability_id in ability_defs:
		return ability_defs[ability_id]
	return {}

# Получить loot table для уровня игрока
func get_loot_table_for_level(player_level: int) -> Dictionary:
	if player_level in loot_table_defs:
		return loot_table_defs[player_level]
	return loot_table_defs.get(1, {})

# Получить случайную атакующую башню (для RANDOM_ATTACK режима)
func get_random_attack_tower_id() -> String:
	var attack_towers = []
	for tower_id in tower_defs:
		var tower_def = tower_defs[tower_id]
		if tower_def.get("type", "") == "ATTACK":
			attack_towers.append(tower_id)
	
	if attack_towers.is_empty():
		return "TA1"  # Fallback
	
	return attack_towers[randi() % attack_towers.size()]

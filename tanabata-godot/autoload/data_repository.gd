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
var wave_balance: Dictionary = {}
var ability_defs: Dictionary = {}
var mimic_weights: Dictionary = {}

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
	var balance_data = Config.load_json(Config.PATH_WAVE_BALANCE)
	wave_balance = balance_data.get("wave_health", {}) if balance_data is Dictionary else {}
	var abilities_data = Config.load_json(Config.PATH_ABILITY_DEFINITIONS)
	ability_defs = _process_ability_defs(abilities_data)
	var mimic_data = Config.load_json(Config.PATH_MIMIC_WEIGHTS)
	mimic_weights = _process_mimic_weights(mimic_data)

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

func _process_mimic_weights(data: Variant) -> Dictionary:
	if data is Dictionary:
		return data
	return {}

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

# Код-множитель HP врагов по номеру волны (из wave_balance.json). Применяется после base * health_mult * health_multiplier_modifier * diff_health.
func get_wave_health_code_multiplier(wave_number: int, is_tutorial: bool) -> float:
	var wb = wave_balance
	if wb.is_empty():
		return 1.0
	var mult := 1.0
	var wn = wave_number
	if wn >= 1 and wn <= 3:
		mult *= float(wb.get("range_1_3_multiplier", 1.0))
	elif wn >= 5 and wn <= 6:
		mult *= float(wb.get("range_5_6_multiplier", 1.0))
	if wn >= 1 and wn <= 5:
		var early = wb.get("early_waves_1_5", [1.0, 1.0, 1.0, 1.0, 1.0])
		if early is Array and early.size() >= wn:
			mult *= float(early[wn - 1])
	if wn == 2:
		mult *= float(wb.get("extra_wave_2", 1.0))
	elif wn == 3:
		mult *= float(wb.get("extra_wave_3", 1.0))
	elif wn == 4:
		mult *= float(wb.get("extra_wave_4", 1.0))
	elif wn == 5:
		mult *= float(wb.get("extra_wave_5", 1.0))
	if wn == 8:
		mult *= float(wb.get("wave_8_multiplier", 1.0))
	if wn == 11:
		mult *= float(wb.get("wave_11_multiplier", 1.0))
	if wn == 37:
		mult *= float(wb.get("wave_37_multiplier", 1.0))
	if wn == 38:
		mult *= float(wb.get("wave_38_multiplier", 1.0))
	if wn == 39:
		mult *= float(wb.get("wave_39_multiplier", 1.0))
	var per_wave_key = "wave_%d_multiplier" % wn
	if wb.get(per_wave_key) != null:
		mult *= float(wb[per_wave_key])
	if is_tutorial:
		mult *= float(wb.get("tutorial_multiplier", 1.0))
	return mult

# Множитель HP летающих на волнах 11–15 (0.7 = −30% HP). Используется в WaveSystem.
func get_flying_waves_11_15_hp_multiplier() -> float:
	return float(wave_balance.get("flying_waves_11_15_multiplier", 1.0))

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

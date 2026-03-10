# crafting_system.gd
# Система крафта башен (находит возможные рецепты)
extends RefCounted

const CRAFT_DEBUG = false  # вывод в Output для отладки крафта (включить при отладке)

var ecs: ECSWorld

func _init(ecs_world: ECSWorld):
	ecs = ecs_world

# Пересчитывает все возможные комбинации для крафта
func recalculate_combinations():
	
	# 1. Очищаем старые данные о крафте
	ecs.combinables = {}
	
	# 2. Группируем башни по типу (def_id) и уровню.
	# В фазе SELECTION учитываем только поставленные в этом раунде (is_temporary) — крафт только из них.
	# В BUILD и WAVE — все башни на карте.
	var phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	var only_temporary = (phase == GameTypes.GamePhase.TOWER_SELECTION_STATE)
	
	var tower_buckets: Dictionary = {}
	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		var def_id = tower.get("def_id", "")
		
		if def_id == "TOWER_WALL":
			continue
		if only_temporary and not tower.get("is_temporary", false):
			continue
		
		var level = int(tower.get("level", 1))
		var key = "%s-%d" % [def_id, level]
		
		if not tower_buckets.has(key):
			tower_buckets[key] = []
		tower_buckets[key].append(tower_id)
	
	if CRAFT_DEBUG and (phase == GameTypes.GamePhase.TOWER_SELECTION_STATE or phase == GameTypes.GamePhase.WAVE_STATE):
		var bucket_info = []
		for k in tower_buckets.keys():
			bucket_info.append("%s=%d" % [k, tower_buckets[k].size()])
		print("[Craft] recalc phase=%s only_temp=%s buckets=%s" % [GameTypes.game_phase_to_string(phase), only_temporary, ", ".join(bucket_info)])
	
	# 3. Итерируем по всем рецептам (recipe_defs — массив из JSON)
	var recipe_defs = DataRepository.recipe_defs
	if recipe_defs == null or not (recipe_defs is Array):
		if CRAFT_DEBUG:
			print("[Craft] ERROR: recipe_defs null or not Array")
		return
	for i in range(recipe_defs.size()):
		var recipe = recipe_defs[i]
		# Апгрейд уровня (2×L→L+1) только в фазе выбора
		if phase == GameTypes.GamePhase.WAVE_STATE and recipe.get("selection_only", false):
			continue
		var output_id = recipe.get("output_id", "?")
		
		# 4. Собираем требования для рецепта
		# Ключ: "ID-уровень", значение: количество
		var needed: Dictionary = {}
		for input in recipe.get("inputs", []):
			var inp_id = input.get("id", "")
			var inp_lv = input.get("level", 1)
			var input_key = "%s-%d" % [inp_id, int(inp_lv)]
			if not needed.has(input_key):
				needed[input_key] = 0
			needed[input_key] += 1
		
		# 5. Проверяем достаточно ли ингредиентов
		var has_enough = true
		for key in needed.keys():
			var required_count = needed[key]
			var available_count = tower_buckets.get(key, []).size()
			if available_count < required_count:
				has_enough = false
				break
		
		if CRAFT_DEBUG and (phase == GameTypes.GamePhase.TOWER_SELECTION_STATE or phase == GameTypes.GamePhase.WAVE_STATE) and not tower_buckets.is_empty():
			var need_str = []
			for k in needed.keys():
				var avail = tower_buckets.get(k, []).size()
				need_str.append("%s need=%d have=%d" % [k, needed[k], avail])
			print("[Craft] recipe %s: %s => has_enough=%s" % [output_id, " | ".join(need_str), has_enough])
		
		if not has_enough:
			continue  # Следующий рецепт
		
		# 6. Если ингредиентов достаточно, находим все возможные комбинации
		_find_and_mark_combinations(recipe, needed, tower_buckets)
	
	# 7. Shift-выделение: если ровно 3 (или 2/4) башни с is_manually_selected образуют рецепт — добавляем эту комбинацию в начало possible_crafts
	_inject_manual_selection_combinations(phase)
	
	if CRAFT_DEBUG and (phase == GameTypes.GamePhase.TOWER_SELECTION_STATE or phase == GameTypes.GamePhase.WAVE_STATE):
		print("[Craft] recalc done: combinables.size=%d" % ecs.combinables.size())
	

# Находит все уникальные наборы башен для рецепта
func _find_and_mark_combinations(recipe: Dictionary, needed: Dictionary, buckets: Dictionary):
	var needed_keys = needed.keys()
	needed_keys.sort()  # Предсказуемый порядок
	
	var found_combinations: Dictionary = {}  # Избегаем дубликатов
	
	# Рекурсия без вложенного callable: для каждого ведра явно перебираем каждую башню (чтобы при 2x DA1 обе попали в combinables)
	_find_combos_recursive(recipe, needed, needed_keys, buckets, found_combinations, 0, [])

func _find_combos_recursive(recipe: Dictionary, needed: Dictionary, needed_keys: Array, buckets: Dictionary, found_combinations: Dictionary, key_index: int, current_combination: Array):
	if key_index == needed_keys.size():
		var sorted_combo = current_combination.duplicate()
		sorted_combo.sort()
		var combo_key = _combination_key(sorted_combo)
		if not found_combinations.has(combo_key):
			found_combinations[combo_key] = true
			var craft_info = {
				"recipe": recipe,
				"combination": sorted_combo
			}
			for id in sorted_combo:
				if not ecs.combinables.has(id):
					ecs.combinables[id] = {
						"possible_crafts": []
					}
				ecs.combinables[id]["possible_crafts"].append(craft_info)
			if CRAFT_DEBUG:
				print("[Craft] комбо добавлена: %s -> tower_ids %s" % [recipe.get("output_id", "?"), sorted_combo])
		return
	var ingredient_key = needed_keys[key_index]
	var required_count = needed[ingredient_key]
	var available_towers = buckets.get(ingredient_key, [])
	# Перебираем все способы набрать required_count башен из ведра (без повторов, по индексам)
	_pick_from_bucket(recipe, needed, needed_keys, buckets, found_combinations, key_index, current_combination, available_towers, required_count, 0, [])

func _pick_from_bucket(recipe: Dictionary, needed: Dictionary, needed_keys: Array, buckets: Dictionary, found_combinations: Dictionary, key_index: int, current_combination: Array, available_towers: Array, required_count: int, start_idx: int, picked: Array):
	if picked.size() == required_count:
		var new_combo = current_combination.duplicate()
		new_combo.append_array(picked)
		_find_combos_recursive(recipe, needed, needed_keys, buckets, found_combinations, key_index + 1, new_combo)
		return
	if start_idx >= available_towers.size():
		return
	for i in range(start_idx, available_towers.size()):
		var new_picked = picked.duplicate()
		new_picked.append(available_towers[i])
		_pick_from_bucket(recipe, needed, needed_keys, buckets, found_combinations, key_index, current_combination, available_towers, required_count, i + 1, new_picked)

# Создает уникальный ключ для комбинации
func _combination_key(ids: Array) -> String:
	return str(ids)

# Если ровно N башен с is_manually_selected образуют рецепт — добавляем эту комбинацию в начало possible_crafts для каждой из них
func _inject_manual_selection_combinations(phase: int):
	var manual_ids: Array = []
	for tower_id in ecs.towers.keys():
		var t = ecs.towers[tower_id]
		if t.get("def_id", "") == "TOWER_WALL":
			continue
		if phase == GameTypes.GamePhase.TOWER_SELECTION_STATE and not t.get("is_temporary", false):
			continue
		if t.get("is_manually_selected", false):
			manual_ids.append(tower_id)
	for n in [3, 2, 4]:
		if manual_ids.size() != n:
			continue
		var keys_from_towers: Array = []
		for tid in manual_ids:
			var t = ecs.towers[tid]
			var def_id = t.get("def_id", "")
			var lv = int(t.get("level", 1))
			keys_from_towers.append("%s-%d" % [def_id, lv])
		keys_from_towers.sort()
		var recipe_defs = DataRepository.recipe_defs
		if recipe_defs == null or not (recipe_defs is Array):
			continue
		for recipe in recipe_defs:
			if phase == GameTypes.GamePhase.WAVE_STATE and recipe.get("selection_only", false):
				continue
			var inputs = recipe.get("inputs", [])
			if inputs.size() != n:
				continue
			var needed_keys: Array = []
			for input in inputs:
				var inp_id = input.get("id", "")
				var inp_lv = int(input.get("level", 1))
				needed_keys.append("%s-%d" % [inp_id, inp_lv])
			needed_keys.sort()
			if keys_from_towers != needed_keys:
				continue
			var sorted_combo = manual_ids.duplicate()
			sorted_combo.sort()
			var craft_info = {
				"recipe": recipe,
				"combination": sorted_combo
			}
			for tid in sorted_combo:
				if not ecs.combinables.has(tid):
					ecs.combinables[tid] = { "possible_crafts": [] }
				ecs.combinables[tid]["possible_crafts"].insert(0, craft_info)
			if CRAFT_DEBUG:
				print("[Craft] manual combo: %s -> %s" % [recipe.get("output_id", "?"), sorted_combo])
			return

# ============================================================================
# ВЫПОЛНЕНИЕ КРАФТА (как в Go: in-place трансформация)
# ============================================================================

# Стоимость крафта в энергии (руда): для проверки и отображения в UI
func _get_craft_energy_cost(recipe: Dictionary, output_def: Dictionary, combination_size: int) -> int:
	if recipe.get("selection_only", false):
		if combination_size == 2:
			return Config.CRAFT_COST_X2
		if combination_size == 4:
			return Config.CRAFT_COST_X4
	var cl = output_def.get("crafting_level", 0)
	if cl >= 2:
		return Config.CRAFT_COST_LEVEL_2
	if cl >= 1:
		return Config.CRAFT_COST_LEVEL_1
	return 0

# Публичный метод: стоимость крафта по рецепту и размеру комбинации (для UI).
func get_craft_energy_cost_for_recipe(recipe: Dictionary, combination_size: int) -> int:
	var output_id = recipe.get("output_id", "")
	if output_id.is_empty():
		return 0
	var output_def = DataRepository.get_tower_def(output_id)
	if output_def.is_empty():
		return 0
	return _get_craft_energy_cost(recipe, output_def, combination_size)

# Упростить (даунгрейд): башня уровня L -> случайная башня уровня 1..L-1. Только для базовых (crafting_level 0) с level >= 2.
func perform_downgrade(tower_id: int) -> bool:
	if not ecs.towers.has(tower_id):
		return false
	var tower = ecs.towers[tower_id]
	var def_id = tower.get("def_id", "")
	var crafting_level = tower.get("crafting_level", 0)
	var level = int(tower.get("level", 1))
	if crafting_level != 0 or level < 2:
		return false
	var new_def_id = _get_random_downgrade_def_id(def_id, level)
	if new_def_id.is_empty():
		return false
	if not GameManager.spend_ore_global(float(Config.DOWNGRADE_COST)):
		return false
	var new_def = DataRepository.get_tower_def(new_def_id)
	if new_def.is_empty():
		return false
	_transform_tower_to_output(tower_id, new_def)
	tower["is_selected"] = true
	recalculate_combinations()
	if GameManager.energy_network:
		GameManager.energy_network.rebuild_energy_network()
	if GameManager.wall_renderer:
		GameManager.wall_renderer.force_immediate_update()
	return true

func _get_random_downgrade_def_id(def_id: String, current_level: int) -> String:
	if current_level <= 1:
		return ""
	var base = def_id.substr(0, def_id.length() - 1)
	var new_level = randi_range(1, current_level - 1)
	return base + str(new_level)

# Выполняет крафт: кликнутая башня -> результат, остальные -> стены
func perform_craft(clicked_tower_id: int, combination: Array, recipe: Dictionary) -> int:
	"""
	Как в Go: clicked_tower_id превращается в результат (output tower),
	остальные башни из combination превращаются в стены (TOWER_WALL).
	Крафт только в фазе WAVE.
	"""
	var phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	if CRAFT_DEBUG:
		print("[Craft] perform_craft called: phase=%s clicked=%d combination=%s output=%s" % [GameTypes.game_phase_to_string(phase), clicked_tower_id, combination, recipe.get("output_id", "?")])
	# Крафт только в фазе выбора (из 5 поставленных) или в волне
	if phase != GameTypes.GamePhase.WAVE_STATE and phase != GameTypes.GamePhase.TOWER_SELECTION_STATE:
		print("[Craft] perform_craft REJECT: phase not SELECTION/WAVE")
		return GameTypes.INVALID_ENTITY_ID
	
	
	if not ecs.towers.has(clicked_tower_id):
		print("[CraftingSystem] ERROR: Clicked tower %d not found!" % clicked_tower_id)
		return GameTypes.INVALID_ENTITY_ID
	
	var output_id = recipe.get("output_id", "")
	if output_id.is_empty():
		print("[CraftingSystem] ERROR: No output_id in recipe!")
		return GameTypes.INVALID_ENTITY_ID
	
	# Мимик: при крафте подменяем на случайную вышку уровня крафта 1
	if output_id == "TOWER_MIMIC":
		output_id = _get_random_crafting_level_1_tower_id()
		if output_id.is_empty():
			output_id = "TOWER_SILVER"  # fallback
	
	var output_def = DataRepository.get_tower_def(output_id)
	if output_def.is_empty():
		print("[CraftingSystem] ERROR: Output def %s not found!" % output_id)
		return GameTypes.INVALID_ENTITY_ID
	
	var wall_def = DataRepository.get_tower_def("TOWER_WALL")
	if wall_def.is_empty():
		print("[CraftingSystem] ERROR: TOWER_WALL def not found!")
		return GameTypes.INVALID_ENTITY_ID
	
	# Стоимость крафта в руде: списываем до трансформации
	var cost = _get_craft_energy_cost(recipe, output_def, combination.size())
	if cost > 0 and not GameManager.spend_ore_global(float(cost)):
		if CRAFT_DEBUG:
			print("[Craft] perform_craft REJECT: not enough ore (need %d)" % cost)
		return GameTypes.INVALID_ENTITY_ID
	
	# MVP при крафте: среднее арифметическое по комбинации, округление вверх, не выше 5
	var mvp_sum = 0
	for tid in combination:
		if ecs.towers.has(tid):
			mvp_sum += int(ecs.towers[tid].get("mvp_level", 0))
	var new_mvp = mini(5, int(ceil(float(mvp_sum) / max(1, combination.size()))))

	# 1. Кликнутая башня -> результат
	_transform_tower_to_output(clicked_tower_id, output_def)
	ecs.towers[clicked_tower_id]["mvp_level"] = new_mvp
	# Крафт с касания (в фазе выбора): результат без проклятия раннего крафта. Проклятие касания -15% только если получилась вышка уровня крафта 1+ (Auriga, Silver и т.д.); x2/x4 (TO1+TO1=TO2) — crafting_level 0, без проклятия. Батарея не получает проклятие касания.
	var output_crafting_level = output_def.get("crafting_level", 0)
	if phase == GameTypes.GamePhase.TOWER_SELECTION_STATE and output_def.get("type") != "BATTERY" and output_crafting_level >= 1:
		ecs.towers[clicked_tower_id]["touch_curse"] = true
	ecs.towers[clicked_tower_id]["early_craft_curse_cleared"] = true

	# 2. Остальные из combination -> стены
	for tower_id in combination:
		if tower_id == clicked_tower_id:
			continue
		if ecs.towers.has(tower_id):
			_transform_tower_to_wall(tower_id, wall_def)
	
	if CRAFT_DEBUG:
		print("[Craft] perform_craft OK -> tower %d" % clicked_tower_id)
	# 3. Пересчёт
	recalculate_combinations()
	if GameManager.energy_network:
		GameManager.energy_network.rebuild_energy_network()
	if GameManager.wall_renderer:
		GameManager.wall_renderer.force_immediate_update()
	# Ауры пересчитаются в следующем кадре (aura_system.update вызывается каждый кадр)
	
	return clicked_tower_id

func _transform_tower_to_output(tower_id: int, output_def: Dictionary):
	"""Превращает башню в результат крафта (in-place). Проклятие раннего крафта не наследуется — считаем по текущей волне."""
	var tower = ecs.towers[tower_id]
	tower["def_id"] = output_def.get("id", "")
	tower["level"] = int(output_def.get("level", 1))
	tower["crafting_level"] = output_def.get("crafting_level", 0)
	tower["placed_at_wave"] = ecs.game_state.get("current_wave", 0)
	if tower.has("early_craft_curse_cleared"):
		tower.erase("early_craft_curse_cleared")
	if tower.has("touch_curse"):
		tower.erase("touch_curse")
	if tower.has("touch_curse_cleared"):
		tower.erase("touch_curse_cleared")
	
	# Combat
	var combat_def = output_def.get("combat", {})
	if not combat_def.is_empty():
		var attack_def = combat_def.get("attack", {})
		var params = attack_def.get("params", {})
		ecs.combat[tower_id] = {
			"damage": combat_def.get("damage", 10),
			"fire_rate": combat_def.get("fire_rate", 1.0),
			"range": combat_def.get("range", 3),
			"fire_cooldown": 0.0,
			"shot_cost": combat_def.get("shot_cost", 1.0),
			"attack_type": attack_def.get("damage_type", "PHYSICAL"),
			"split_count": params.get("split_count", 1) if typeof(params) == TYPE_DICTIONARY else 1,
			"attack_type_data": attack_def
		}
	else:
		ecs.combat.erase(tower_id)
	
	# Aura
	var aura_def = output_def.get("aura", {})
	if not aura_def.is_empty():
		var aura_comp = {
			"radius": aura_def.get("radius", 2),
			"speed_multiplier": aura_def.get("speed_multiplier", 1.0),
			"damage_bonus": aura_def.get("damage_bonus", 0),
			"damage_bonus_percent": aura_def.get("damage_bonus_percent", 0.0)
		}
		if aura_def.get("flying_only", false):
			aura_comp["flying_only"] = true
			aura_comp["slow_factor"] = aura_def.get("slow_factor", 0.0)
			aura_comp["flying_damage_taken_bonus"] = aura_def.get("flying_damage_taken_bonus", 0.0)
		if aura_def.get("all_enemies_slow", false):
			aura_comp["all_enemies_slow"] = true
			aura_comp["slow_factor"] = aura_def.get("slow_factor", 0.0)
			aura_comp["exit_slow_factor"] = aura_def.get("exit_slow_factor", 1.0)
			aura_comp["exit_slow_duration"] = aura_def.get("exit_slow_duration", 0.0)
			aura_comp["damage_taken_bonus"] = aura_def.get("damage_taken_bonus", 0.0)
			if aura_def.has("ore_cost"):
				aura_comp["ore_cost"] = aura_def.get("ore_cost", 0.0)
		if aura_def.get("debuff_immunity", false):
			aura_comp["debuff_immunity"] = true
		ecs.auras[tower_id] = aura_comp
	else:
		ecs.auras.erase(tower_id)
	
	# Renderable (размер по уровню: Lv.1 меньше, Lv.6 близок к гексу)
	var visuals = output_def.get("visuals", {})
	var level = output_def.get("level", 1)
	var radius_factor = visuals.get("radius_factor", 0.5)
	if level >= 1 and level <= 6:
		radius_factor = Config.get_tower_radius_factor_for_level(level)
	var color_val = visuals.get("color", "#FF8C00")
	var c: Color
	if typeof(color_val) == TYPE_STRING:
		c = Color.html(color_val)
	elif typeof(color_val) == TYPE_DICTIONARY:
		c = Color(color_val.get("r", 255) / 255.0, color_val.get("g", 140) / 255.0, color_val.get("b", 0) / 255.0, color_val.get("a", 255) / 255.0)
	else:
		c = Color.ORANGE
	ecs.renderables[tower_id] = {
		"color": c,
		"radius": Config.HEX_SIZE * radius_factor,
		"visible": true
	}

func _transform_tower_to_wall(tower_id: int, wall_def: Dictionary):
	"""Превращает башню в стену (in-place)"""
	var tower = ecs.towers[tower_id]
	tower["def_id"] = "TOWER_WALL"
	tower["crafting_level"] = 0
	ecs.combat.erase(tower_id)
	ecs.auras.erase(tower_id)
	
	var visuals = wall_def.get("visuals", {})
	var color_val = visuals.get("color", "#696969")
	var c: Color
	if typeof(color_val) == TYPE_STRING:
		c = Color.html(color_val)
	elif typeof(color_val) == TYPE_DICTIONARY:
		c = Color(color_val.get("r", 105) / 255.0, color_val.get("g", 105) / 255.0, color_val.get("b", 105) / 255.0, color_val.get("a", 255) / 255.0)
	else:
		c = Color.DARK_GRAY
	ecs.renderables[tower_id] = {
		"color": c,
		"radius": Config.HEX_SIZE * visuals.get("radius_factor", 0.6),
		"visible": true
	}

func _get_random_crafting_level_1_tower_id() -> String:
	"""Взвешенный случайный id вышки уровня крафта 1 (ATTACK), кроме Мимика. Веса в data/mimic_weights.json."""
	var ids = []
	var weights = []
	var total = 0.0
	for tid in DataRepository.tower_defs:
		var def = DataRepository.tower_defs[tid]
		if def.get("type", "") != "ATTACK":
			continue
		if int(def.get("crafting_level", 0)) != 1:
			continue
		if tid == "TOWER_MIMIC":
			continue
		var w = 1.0
		if DataRepository.mimic_weights.has(tid):
			w = float(DataRepository.mimic_weights[tid])
		if w <= 0.0:
			continue
		ids.append(tid)
		weights.append(w)
		total += w
	if total <= 0.0:
		return ""
	var r = randf() * total
	for i in ids.size():
		r -= weights[i]
		if r <= 0.0:
			return ids[i]
	return ids[ids.size() - 1]

# input_system.gd
# Система обработки ввода игрока
class_name InputSystem

var ecs: ECSWorld
var hex_map: HexMap
var camera: Camera2D

# Оптимизация: очередь команд (батчинг кликов)
var command_queue: Array = []
const MAX_COMMANDS_PER_FRAME = 10

var selected_hex: Hex = null
var hovered_hex: Hex = null
var highlighted_tower_id: int = GameTypes.INVALID_ENTITY_ID

# Кэш def_id атакующих башен для RANDOM_ATTACK (шаг 1.2 — из данных, не хардкод)
var _random_attack_tower_ids: Array = []
const CRAFT_DEBUG = false  # лог постановки вышек для отладки крафта (включить при отладке)

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================================

func _init(ecs_: ECSWorld, hex_map_: HexMap, camera_: Camera2D):
	ecs = ecs_
	hex_map = hex_map_
	camera = camera_

# ============================================================================
# UPDATE - ОБРАБОТКА ОЧЕРЕДИ КОМАНД
# ============================================================================

func update(_delta: float):
	# Обрабатываем команды из очереди (батчинг для производительности)
	var commands_processed = 0
	while command_queue.size() > 0 and commands_processed < MAX_COMMANDS_PER_FRAME:
		var cmd = command_queue.pop_front()
		_execute_command(cmd)
		commands_processed += 1

func _execute_command(cmd: Dictionary):
	match cmd.get("type"):
		"place_tower":
			var hex = cmd.get("hex")
			if hex:
				place_tower(hex)
		"remove_tower":
			var hex = cmd.get("hex")
			if hex:
				remove_tower(hex)
		"select_tower":
			var tower_id = cmd.get("tower_id")
			if tower_id != null:
				select_tower(tower_id)
		"toggle_selection":
			var tower_id = cmd.get("tower_id")
			if tower_id != null:
				toggle_tower_selection(tower_id)
		"toggle_manual_selection":
			var tower_id = cmd.get("tower_id")
			if tower_id != null:
				toggle_manual_selection(tower_id)

# ============================================================================
# ОБРАБОТКА ВВОДА
# ============================================================================

func handle_mouse_click(mouse_pos: Vector2, button: int):
	# Преобразуем экранные координаты в мировые через камеру
	var world_pos = camera.get_screen_center_position() + (mouse_pos - camera.get_viewport_rect().size / 2) / camera.zoom
	
	# Преобразуем мировые координаты в гекс
	var hex = Hex.from_pixel(world_pos, Config.HEX_SIZE)
	
	# Проверяем что гекс существует
	if not hex_map.has_tile(hex):
		return
	
	var current_phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	var is_shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	
	# ЛКМ - обработка в зависимости от фазы
	if button == MOUSE_BUTTON_LEFT:
		if current_phase == GameTypes.GamePhase.BUILD_STATE:
			# ФАЗА СТРОИТЕЛЬСТВА
			var tower_id = hex_map.get_tower_id(hex)
			if tower_id != GameTypes.INVALID_ENTITY_ID:
				# Кликнули на башню
				var tower = ecs.towers.get(tower_id)
				if tower:
					var tower_def = DataRepository.get_tower_def(tower.get("def_id", ""))
					if tower_def.get("type") != "WALL":
						if GameManager.info_panel:
							GameManager.info_panel.show_entity(tower_id)
						command_queue.append({"type": "select_tower", "tower_id": tower_id})
			else:
				# Кликнули на пустой гекс (руда или нет) — ставим башню
				clear_highlight()
				if GameManager.info_panel:
					GameManager.info_panel.hide_panel()
				command_queue.append({"type": "place_tower", "hex": hex})
		
		elif current_phase == GameTypes.GamePhase.TOWER_SELECTION_STATE:
			# ФАЗА ВЫБОРА БАШЕН
			var clicked_entity = _get_entity_at_hex(hex)
			if clicked_entity >= 0:
				# Кликнули на сущность
				var is_wall = false
				if ecs.has_component(clicked_entity, "tower"):
					var tower = ecs.towers[clicked_entity]
					var tower_def = DataRepository.get_tower_def(tower.get("def_id", ""))
					if tower_def.get("type") == "WALL":
						is_wall = true
				
				if not is_wall:
					# Shift + клик = множественное выделение
					if is_shift_pressed and ecs.has_component(clicked_entity, "tower"):
						command_queue.append({"type": "toggle_manual_selection", "tower_id": clicked_entity})
					else:
						# Обычный клик = показываем InfoPanel
						if GameManager.info_panel:
							GameManager.info_panel.show_entity(clicked_entity)
						if ecs.has_component(clicked_entity, "tower") or ecs.has_component(clicked_entity, "enemy") or ecs.has_component(clicked_entity, "ore"):
							command_queue.append({"type": "select_tower", "tower_id": clicked_entity})
			else:
				# Кликнули на пустое место - сбрасываем выделение
				if not is_shift_pressed:
					if GameManager.info_panel:
						GameManager.info_panel.hide_panel()
					clear_highlight()
					for tid in ecs.towers.keys():
						ecs.towers[tid]["is_manually_selected"] = false
		
		elif current_phase == GameTypes.GamePhase.WAVE_STATE:
			# ФАЗА ВОЛНЫ — выбор башен и врагов (для InfoPanel и крафта)
			var clicked_entity = _get_entity_at_hex(hex)
			if clicked_entity >= 0:
				var is_wall = false
				if ecs.has_component(clicked_entity, "tower"):
					var tower = ecs.towers[clicked_entity]
					var tower_def = DataRepository.get_tower_def(tower.get("def_id", ""))
					if tower_def.get("type") == "WALL":
						is_wall = true
				
				if not is_wall:
					if is_shift_pressed and ecs.has_component(clicked_entity, "tower"):
						command_queue.append({"type": "toggle_manual_selection", "tower_id": clicked_entity})
					else:
						if GameManager.info_panel:
							GameManager.info_panel.show_entity(clicked_entity)
						if ecs.has_component(clicked_entity, "tower") or ecs.has_component(clicked_entity, "enemy") or ecs.has_component(clicked_entity, "ore"):
							command_queue.append({"type": "select_tower", "tower_id": clicked_entity})
			else:
				if not is_shift_pressed:
					if GameManager.info_panel:
						GameManager.info_panel.hide_panel()
					clear_highlight()
					for tid in ecs.towers.keys():
						ecs.towers[tid]["is_manually_selected"] = false
	
	# ПКМ - удаление башни
	elif button == MOUSE_BUTTON_RIGHT:
		if current_phase == GameTypes.GamePhase.BUILD_STATE:
			command_queue.append({"type": "remove_tower", "hex": hex})

# ============================================================================
# РАЗМЕЩЕНИЕ БАШНИ
# ============================================================================

func place_tower(hex: Hex) -> bool:
	var current_phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	if current_phase != GameTypes.GamePhase.BUILD_STATE:
		return false
	
	# Дебаг режим: игнорируем только лимит, но НЕ фазу
	var is_debug_tower = ecs.game_state.has("debug_tower_type")
	
	# Проверка лимита башен (только для обычных башен)
	var towers_built = ecs.game_state.get("towers_built_this_phase", 0)
	if not is_debug_tower and towers_built >= Config.MAX_TOWERS_IN_BUILD_PHASE:
		return false
	
	# Проверка что можно ставить (включая блокировку пути)
	if not _can_place_tower(hex):
		return false
	
	# Выбираем тип башни: если в стеке майнер (удалили в этом раунде) — ставим его
	var tower_def_id: String
	if ecs.game_state.get("removed_miner_stash", false):
		ecs.game_state["removed_miner_stash"] = false
		tower_def_id = "TOWER_MINER"
	else:
		tower_def_id = _determine_tower_id()
	
	if ecs.game_state.get("is_tutorial", false):
		var placements = ecs.game_state.get("placements_made_this_phase", 0)
		var ti = ecs.game_state.get("tutorial_index", -1)
		print("[Tutorial] place #%d -> %s (tutorial_index=%d)" % [placements, tower_def_id, ti])
	
	# Создаем башню через фабрику
	var tower_id = EntityFactory.create_tower(ecs, hex_map, hex, tower_def_id)
	
	if tower_id == GameTypes.INVALID_ENTITY_ID:
		return false
	
	if CRAFT_DEBUG:
		print("[Craft] поставлена вышка def=%s entity_id=%d" % [tower_def_id, tower_id])
	
	var tower_def = DataRepository.get_tower_def(tower_def_id)
	# Майнер: уровень = уровень игрока (лвл 2+ даёт +30% эффективности руды)
	if tower_def.get("type") == "MINER":
		var player_level = 1
		for _pid in ecs.player_states:
			player_level = ecs.player_states[_pid].get("level", 1)
			break
		ecs.towers[tower_id]["level"] = player_level
		ecs.towers[tower_id]["is_selected"] = true
	
	# Добавляем в энергосеть (активирует если может)
	if GameManager.energy_network:
		GameManager.energy_network.add_tower_to_network(tower_id)
	
	# Обновляем счетчики (только для обычных башен, не дебаг)
	if not is_debug_tower:
		towers_built += 1
		ecs.game_state["towers_built_this_phase"] = towers_built
		var placements = ecs.game_state.get("placements_made_this_phase", 0) + 1
		ecs.game_state["placements_made_this_phase"] = placements
		
		
		# Автопереход в SELECTION фазу после 5 башен (как в Go)
		if towers_built >= Config.MAX_TOWERS_IN_BUILD_PHASE:
			ecs.game_state["towers_to_keep"] = Config.TOWERS_TO_KEEP
			ecs.game_state["phase"] = GameTypes.GamePhase.TOWER_SELECTION_STATE
			# Обучение уровень 0: во второй фазе выбора показываем плашку про майнер и сеть (шаг 8)
			if ecs.game_state.get("is_tutorial", false) and ecs.game_state.get("tutorial_index", -1) == 0:
				var cw = ecs.game_state.get("current_wave", 0)
				var idx = ecs.game_state.get("tutorial_step_index", 0)
				var steps = GameManager.get_tutorial_steps() if GameManager else []
				if cw >= 1 and idx >= 6 and steps.size() > 8:
					ecs.game_state["tutorial_step_index"] = 8
	else:
		# Дебаг башни не временные и не считаются
		ecs.towers[tower_id]["is_temporary"] = false
	
	# КРИТИЧНО: Мгновенное обновление визуала стен (не ждем _process)
	var tower_def_for_wall = DataRepository.get_tower_def(tower_def_id)
	if tower_def_for_wall.get("type") == "WALL":
		if GameManager.wall_renderer:
			GameManager.wall_renderer.force_immediate_update()
	
	# Пересчитываем возможности крафта
	if GameManager.crafting_system:
		GameManager.crafting_system.recalculate_combinations()
	
	# Предпросмотр пути врагов — отложенно, чтобы не тормозить кадр постановки башни
	GameManager.call_deferred("_request_future_path_update")
	return true

# ============================================================================
# УДАЛЕНИЕ БАШНИ
# ============================================================================

func remove_tower(hex: Hex):
	var tower_id = hex_map.get_tower_id(hex)
	if tower_id == GameTypes.INVALID_ENTITY_ID:
		return
	
	if not ecs.towers.has(tower_id):
		return
	
	var tower = ecs.towers[tower_id]
	var def_id = tower.get("def_id", "")
	var is_temporary = tower.get("is_temporary", false)
	var is_wall = (def_id == "TOWER_WALL")
	var current_phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	
	# Сначала удаляем линии к этой башне (до destroy), затем инкрементальный reconnect
	if GameManager.energy_network:
		GameManager.energy_network.remove_lines_connected_to_tower(tower_id)
	
	# Удаляем сущность
	ecs.destroy_entity(tower_id)
	
	# Восстанавливаем проходимость тайла
	var tile = hex_map.get_tile(hex)
	if tile:
		tile.passable = true
		hex_map.set_tile(hex, tile)
	
	# Обновляем карту
	hex_map.remove_tower(hex)
	
	# Инкрементальное переподключение (сохраняет линии из режима U)
	if GameManager.energy_network:
		GameManager.energy_network.handle_tower_removal()
	
	# Пересчитываем возможности крафта
	if GameManager.crafting_system:
		GameManager.crafting_system.recalculate_combinations()
	
	# Предпросмотр пути — отложенно, чтобы не тормозить кадр удаления башни
	GameManager.call_deferred("_request_future_path_update")
	
	# Учёт удаления: стена или обычная вышка — ничего. Майнер этого раунда — слот освобождается и майнер в стек.
	if current_phase == GameTypes.GamePhase.BUILD_STATE and is_temporary and not is_wall and def_id == "TOWER_MINER":
		var towers_built = ecs.game_state.get("towers_built_this_phase", 0)
		if towers_built > 0:
			ecs.game_state["towers_built_this_phase"] = towers_built - 1
		ecs.game_state["removed_miner_stash"] = true
	

# ============================================================================
# ВЫБОР БАШНИ
# ============================================================================

func select_tower(tower_id: int):
	# Снимаем подсветку с предыдущей сущности
	clear_highlight()
	
	# Подсвечиваем новую
	highlighted_tower_id = tower_id
	if ecs.has_component(tower_id, "tower"):
		# СТЕНЫ НЕ ВЫДЕЛЯЕМ
		var tower = ecs.towers[tower_id]
		var tower_def = GameManager.get_tower_def(tower.get("def_id", ""))
		if tower_def.get("type") == "WALL":
			return
		
		ecs.towers[tower_id]["is_highlighted"] = true
	elif ecs.has_component(tower_id, "enemy"):
		ecs.enemies[tower_id]["is_highlighted"] = true
	elif ecs.has_component(tower_id, "ore"):
		ecs.ores[tower_id]["is_highlighted"] = true

func clear_highlight():
	if highlighted_tower_id != GameTypes.INVALID_ENTITY_ID:
		if ecs.has_component(highlighted_tower_id, "tower"):
			ecs.towers[highlighted_tower_id]["is_highlighted"] = false
		elif ecs.has_component(highlighted_tower_id, "enemy"):
			ecs.enemies[highlighted_tower_id]["is_highlighted"] = false
		elif ecs.has_component(highlighted_tower_id, "ore"):
			ecs.ores[highlighted_tower_id]["is_highlighted"] = false
		highlighted_tower_id = GameTypes.INVALID_ENTITY_ID

# Множественное выделение (is_manually_selected) для крафта
func toggle_manual_selection(tower_id: int):
	if not ecs.towers.has(tower_id):
		return
	
	var tower = ecs.towers[tower_id]
	var was_selected = tower.get("is_manually_selected", false)
	tower["is_manually_selected"] = not was_selected
	

func clear_manual_selection():
	"""Сбрасывает множественное выделение у всех башен"""
	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		tower["is_manually_selected"] = false

# Переключить выбор башни для сохранения (фаза SELECTION)
func toggle_tower_selection(tower_id: int):
	if not ecs.towers.has(tower_id):
		return
	
	var tower = ecs.towers[tower_id]
	
	# Только для временных башен
	if not tower.get("is_temporary", false):
		return
	
	# Переключаем IsSelected
	var was_selected = tower.get("is_selected", false)
	tower["is_selected"] = not was_selected
	
	# Считаем сколько выбрано
	var selected_count = 0
	for tid in ecs.towers.keys():
		var t = ecs.towers[tid]
		if t.get("is_temporary", false) and t.get("is_selected", false):
			selected_count += 1

# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ============================================================================

func _can_place_tower(hex: Hex) -> bool:
	# Проверка 1: Базовые условия
	if not hex_map.has_tile(hex):
		return false
	
	var tile = hex_map.get_tile(hex)
	if not tile or not tile.passable or not tile.can_place_tower:
		return false
	
	# Проверка 2: Нет башни
	if tile.has_tower:
		return false
	
	# Проверка 3: Не блокирует путь (ОТКЛЮЧЕНО для скорости, как в Go)
	# В Go проверка пути делается только при старте волны
	if not Config.fast_tower_placement:
		if _would_block_path(hex):
			return false
	
	return true

func _would_block_path(hex: Hex) -> bool:
	var tile = hex_map.get_tile(hex)
	var original_passable = tile.passable
	tile.passable = false
	hex_map.set_tile(hex, tile)
	
	var blocked = not Pathfinding.path_exists_through_checkpoints(
		hex_map.entry, hex_map.checkpoints, hex_map.exit, hex_map
	)
	
	tile.passable = original_passable
	hex_map.set_tile(hex, tile)
	return blocked

# Список def_id только базовых атакующих (crafting_level == 0) для RANDOM_ATTACK и лута.
# Улучшенные (Silver, Malachite и т.п.) не выпадают из случайного выбора.
func _get_random_attack_tower_ids() -> Array:
	if not _random_attack_tower_ids.is_empty():
		return _random_attack_tower_ids
	for tower_id in DataRepository.tower_defs:
		var def = DataRepository.tower_defs[tower_id]
		if def.get("type") == "ATTACK" and def.get("crafting_level", 0) == 0 and not def.get("no_random", false):
			_random_attack_tower_ids.append(tower_id)
	return _random_attack_tower_ids

# Только вышки 1 уровня (TA1, TE1, TO1, PA1, PE1, PO1) для обучения «Основы».
var _tutorial_0_tower_ids: Array = []
func _get_tutorial_0_attack_tower_ids() -> Array:
	if not _tutorial_0_tower_ids.is_empty():
		return _tutorial_0_tower_ids
	for tower_id in DataRepository.tower_defs:
		var def = DataRepository.tower_defs[tower_id]
		if def.get("type") == "ATTACK" and def.get("crafting_level", 0) == 0 and def.get("level", 1) == 1 and not def.get("no_random", false):
			_tutorial_0_tower_ids.append(tower_id)
	return _tutorial_0_tower_ids

# Классический набор без аур: только TA, TE, TO, PA, PE, PO (уровень 1) — для второй фазы строительства в обучении
const _TUTORIAL_CLASSIC_BASES = ["TA", "TE", "TO", "PA", "PE", "PO"]
var _tutorial_classic_tower_ids: Array = []
func _get_tutorial_classic_attack_tower_ids() -> Array:
	if not _tutorial_classic_tower_ids.is_empty():
		return _tutorial_classic_tower_ids
	for tower_id in DataRepository.tower_defs:
		var def = DataRepository.tower_defs[tower_id]
		if def.get("type") != "ATTACK" or def.get("crafting_level", 0) != 0 or def.get("level", 1) != 1:
			continue
		var base = tower_id.substr(0, 2) if tower_id.length() >= 2 else ""
		if base in _TUTORIAL_CLASSIC_BASES:
			_tutorial_classic_tower_ids.append(tower_id)
	return _tutorial_classic_tower_ids

func _determine_tower_id() -> String:
	# Дебаг режим: если установлен debug_tower_type, используем его
	if ecs.game_state.has("debug_tower_type") and ecs.game_state["debug_tower_type"] != "":
		var debug_type = ecs.game_state["debug_tower_type"]
		
		# Специальный случай: случайная атакующая башня (из данных: type==ATTACK и не no_random)
		if debug_type == "RANDOM_ATTACK":
			var ids = _get_random_attack_tower_ids()
			if ids.is_empty():
				return "TA1"
			var random_tower = ids[randi() % ids.size()]
			return random_tower
		
		return debug_type
	
	
	# Обучение уровень 0 (Основы): первая фаза — только атакующие; вторая фаза (после волны) — майнер + только классические атакующие TA/TE/TO/PA/PE/PO
	var is_tutorial_0 = ecs.game_state.get("is_tutorial", false) and ecs.game_state.get("tutorial_index", -1) == 0
	if is_tutorial_0:
		var cw = ecs.game_state.get("current_wave", 0)
		var placements_made_0 = ecs.game_state.get("placements_made_this_phase", 0)
		if cw >= 1 and placements_made_0 == 0:
			return "TOWER_MINER"
		# Вторая фаза: только классический набор без аур (TA, TE, TO, PA, PE, PO)
		var ids = _get_tutorial_classic_attack_tower_ids() if cw >= 1 else _get_tutorial_0_attack_tower_ids()
		return ids[randi() % ids.size()] if not ids.is_empty() else "TA1"
	
	var placements_made = ecs.game_state.get("placements_made_this_phase", 0)
	# Обучение уровень 1 (Энергия и руда): фиксированная очередь Б А Б А А в КАЖДОЙ фазе строительства
	# Проверяем и по game_state, и по конфигу уровня — чтобы на втором заходе (после волны) тоже работало
	var ti_state = ecs.game_state.get("tutorial_index", -1)
	var ti_config = -1
	if GameManager and GameManager.current_level_config.size() > 0:
		ti_config = GameManager.current_level_config.get(LevelConfig.KEY_TUTORIAL_INDEX, -1)
	var is_tutorial_1 = ecs.game_state.get("is_tutorial", false) and (ti_state == 1 or ti_config == 1)
	if is_tutorial_1:
		# Позиция в очереди 0..4: 0 и 2 — майнер, 1,3,4 — атакующая
		var slot = placements_made % 5
		if slot == 0 or slot == 2:
			return "TOWER_MINER"
		var ids = _get_tutorial_0_attack_tower_ids()
		return ids[randi() % ids.size()] if not ids.is_empty() else "TA1"
	
	# Правило: первая ПОСТАВКА в блоке = майнер (placements_made не уменьшается при удалении)
	var current_wave = ecs.game_state.get("current_wave", 0)
	
	var wave_mod_10 = (current_wave - 1) % 10
	if wave_mod_10 < 4 and placements_made == 0:
		return "TOWER_MINER"
	
	# Остальные - СЛУЧАЙНЫЕ атакующие из loot table
	var player_level = 1
	for player_id in ecs.player_states.keys():
		var player = ecs.player_states[player_id]
		player_level = player.get("level", 1)
		break
	
	return _pick_from_loot_table(player_level)

const _FIRST_WAVE_ALLOWED_BASES = ["TA", "TE", "TO", "PA", "PE", "PO"]  # Только на первой волне (до волны 1)

func _pick_from_loot_table(player_level: int) -> String:
	var loot_table = GameManager.get_loot_table_for_level(player_level)
	if loot_table.is_empty() or not "entries" in loot_table:
		return _resolve_leveled_tower_id("TA", player_level)  # Fallback
	
	var entries = loot_table["entries"]
	# Только на первой волне (фаза строительства до волны 1) — выпадают только TA, TE, TO, PA, PE, PO. Со второй волны — полная таблица.
	var current_wave = ecs.game_state.get("current_wave", 0)
	var restrict_to_six = (current_wave < 1)
	if restrict_to_six:
		var allowed = []
		for e in entries:
			var bid = e.get("tower_id", "")
			if bid in _FIRST_WAVE_ALLOWED_BASES:
				allowed.append(e)
		if not allowed.is_empty():
			entries = allowed
	
	if entries.is_empty():
		return _resolve_leveled_tower_id("TA", player_level)
	
	var idx = randi() % entries.size()
	var base_id = entries[idx].get("tower_id", "TA")
	return _resolve_leveled_tower_id(base_id, player_level)

func _resolve_leveled_tower_id(base_id: String, player_level: int) -> String:
	if base_id in Config.TOWER_LEVELABLE_BASES:
		var drop_level = Config.pick_tower_level_for_drop(player_level)
		return base_id + str(drop_level)
	return base_id

# ============================================================================
# УДАЛЕНО: _create_tower_entity - теперь используется EntityFactory
# ============================================================================
# Используйте EntityFactory.create_tower(ecs, hex_map, hex, def_id)

func _get_entity_at_hex(hex: Hex) -> int:
	"""Возвращает ID башни, врага или руды на данном гексе"""
	# Сначала проверяем башню
	var tower_id = hex_map.get_tower_id(hex)
	if tower_id != GameTypes.INVALID_ENTITY_ID:
		return tower_id
	
	var hex_pos = hex.to_pixel(Config.HEX_SIZE)
	var search_radius = Config.HEX_SIZE * 1.2  # Увеличил радиус для лучшего выделения
	
	# Затем проверяем врагов (увеличенный радиус)
	for enemy_id in ecs.enemies.keys():
		var enemy_pos = ecs.positions.get(enemy_id)
		if enemy_pos and hex_pos.distance_to(enemy_pos) < search_radius:
			return enemy_id
	
	# Наконец проверяем руду
	for ore_id in ecs.ores.keys():
		var ore_pos = ecs.positions.get(ore_id)
		if ore_pos and hex_pos.distance_to(ore_pos) < search_radius:
			return ore_id
	
	return -1

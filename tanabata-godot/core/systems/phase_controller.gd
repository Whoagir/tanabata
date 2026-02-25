# phase_controller.gd
# Контроллер переходов между фазами игры
# Единая точка истины для логики смены фаз
class_name PhaseController

var ecs: ECSWorld
var hex_map: HexMap
var energy_network: EnergyNetworkSystem

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================================

func _init(ecs_: ECSWorld, hex_map_: HexMap, energy_network_: EnergyNetworkSystem):
	ecs = ecs_
	hex_map = hex_map_
	energy_network = energy_network_

# ============================================================================
# ПЕРЕХОДЫ МЕЖДУ ФАЗАМИ
# ============================================================================

# Перейти в следующую фазу
func cycle_phase():
	var current_phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	
	match current_phase:
		GameTypes.GamePhase.BUILD_STATE:
			transition_to_selection()
		GameTypes.GamePhase.TOWER_SELECTION_STATE:
			transition_to_wave()
		GameTypes.GamePhase.WAVE_STATE:
			transition_to_build()

# Переход BUILD → SELECTION
func transition_to_selection():
	ecs.game_state["phase"] = GameTypes.GamePhase.TOWER_SELECTION_STATE
	# Обучение уровень 0: во второй фазе выбора (после волны) показываем плашку про майнер и сеть (шаг 8)
	if ecs.game_state.get("is_tutorial", false) and ecs.game_state.get("tutorial_index", -1) == 0:
		var cw = ecs.game_state.get("current_wave", 0)
		var idx = ecs.game_state.get("tutorial_step_index", 0)
		var steps = GameManager.get_tutorial_steps() if GameManager else []
		if cw >= 1 and idx >= 6 and steps.size() > 8:
			ecs.game_state["tutorial_step_index"] = 8
	GameManager.call_deferred("_deferred_recalculate_crafting")

# Переход SELECTION → WAVE
func transition_to_wave():
	# Дебаг: старт с выбранной волны только один раз за переход (дальше 7, 8, 9...)
	var debug_wave = ecs.game_state.get("debug_start_wave", 0)
	if debug_wave > 0:
		ecs.game_state["current_wave"] = debug_wave - 1
		ecs.game_state["debug_start_wave"] = 0  # сброс — следующая волна уже по счётчику
	
	# Финализируем выбор башен
	finalize_tower_selection()
	
	# Обновляем путь (тропинки) и путь врагов — отложенно, чтобы не тормозить смену фазы
	if GameManager:
		GameManager.call_deferred("_request_future_path_update")
	
	# Сначала меняем фазу, потом пересчёт: в WAVE учитываются все башни (only_temporary=false)
	ecs.game_state["phase"] = GameTypes.GamePhase.WAVE_STATE
	# Обучение: после finalize у сохранённых башен уже нет is_selected, поэтому триггер TOWERS_SAVED_2 не сработает.
	# Если мы на шаге 2 или 3 (выбор / перейди к волне), сразу переходим на шаг 4 — плашка «Фаза ВОЛНЫ».
	if ecs.game_state.get("is_tutorial", false):
		var idx = ecs.game_state.get("tutorial_step_index", 0)
		var steps = GameManager.get_tutorial_steps() if GameManager else []
		if steps.size() > 4 and (idx == 2 or idx == 3):
			ecs.game_state["tutorial_step_index"] = 4
			if GameManager:
				print("[Tutorial] phase -> WAVE, step set to 4")
		elif GameManager:
			GameManager.update_tutorial()
	GameManager.call_deferred("_deferred_recalculate_crafting")
	# Сбрасываем кэш источников питания в CombatSystem, чтобы первая атакующая башня точно стреляла (избегаем гонки с rebuild)
	if GameManager.combat_system:
		GameManager.combat_system.clear_power_cache()
	# Сбрасываем режим редактирования линий
	ecs.game_state["line_edit_mode"] = false
	ecs.game_state["drag_source_tower_id"] = 0
	ecs.game_state["drag_original_parent_id"] = 0
	ecs.game_state["hidden_line_id"] = 0

# Переход WAVE → BUILD (в т.ч. при пропуске волны игроком)
func transition_to_build():
	ecs.game_state["wave_skipped"] = true  # MVP не даём за пропущенную волну
	# Очищаем врагов, снаряды, эффекты
	clear_wave_entities()
	
	# Сбрасываем счётчики башен и стек удалённого майнера
	ecs.game_state["towers_built_this_phase"] = 0
	ecs.game_state["placements_made_this_phase"] = 0
	ecs.game_state["removed_miner_stash"] = false
	
	# Сбрасываем is_temporary у всех башен
	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		tower["is_temporary"] = false
		tower["is_selected"] = false
	
	# Меняем фазу
	ecs.game_state["phase"] = GameTypes.GamePhase.BUILD_STATE
	# Обучение: при переходе в строительство после волны показываем плашку про майнеры и сеть (шаг 6 — четвёртая плашка)
	if ecs.game_state.get("is_tutorial", false):
		var idx = ecs.game_state.get("tutorial_step_index", 0)
		var steps = GameManager.get_tutorial_steps() if GameManager else []
		if steps.size() > 6 and (idx == 4 or idx == 5):
			ecs.game_state["tutorial_step_index"] = 6
			if GameManager:
				print("[Tutorial] >>> forced step -> 6 (phase BUILD after wave)")

# ============================================================================
# ФИНАЛИЗАЦИЯ ВЫБОРА БАШЕН
# ============================================================================

# Финализировать выбор башен (убрать невыбранные, создать стены)
func finalize_tower_selection():
	var towers_to_convert_to_walls = []
	var ids_to_remove = []
	var saved: Array = []  # для лога: какие сохранили
	
	# Проходим по всем башням
	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		
		# Проверяем только временные башни
		if not tower.get("is_temporary", false):
			continue
		
		if tower.get("is_selected", false):
			saved.append("id=%d def=%s" % [tower_id, tower.get("def_id", "?")])
			# Башня выбрана → делаем постоянной
			tower["is_temporary"] = false
			tower["is_permanent"] = true
			tower["is_selected"] = false
			tower["is_highlighted"] = false
		else:
			# Башня НЕ выбрана → удаляем и ставим стену
			ids_to_remove.append(tower_id)
			var hex = tower.get("hex")
			if hex:
				towers_to_convert_to_walls.append(hex)
	
	if saved.size() > 0:
		pass  # [Craft] логи отключены: print("сохранены вышки: ...")
	
	# Удаляем невыбранные башни
	for tower_id in ids_to_remove:
		var tower = ecs.towers[tower_id]
		var hex = tower.get("hex")
		
		# Удаляем из карты
		if hex:
			hex_map.remove_tower(hex)
		
		# Удаляем сущность из ECS
		ecs.destroy_entity(tower_id)
	
	# Создаём стены на местах удалённых башен
	for hex in towers_to_convert_to_walls:
		create_wall_at(hex)
	
	# Перестраиваем энергосеть
	if energy_network:
		energy_network.rebuild_energy_network()

# ============================================================================
# СОЗДАНИЕ СТЕН
# ============================================================================

# Создать стену на указанном гексе
func create_wall_at(hex: Hex) -> int:
	return EntityFactory.create_wall(ecs, hex_map, hex)

# ============================================================================
# ОЧИСТКА СУЩНОСТЕЙ
# ============================================================================

# Очистить сущности после волны (враги, снаряды, эффекты)
func clear_wave_entities():
	var enemies_cleared = 0
	var projectiles_cleared = 0
	var effects_cleared = 0
	
	# Очищаем врагов
	var enemy_ids = ecs.enemies.keys()
	for enemy_id in enemy_ids:
		ecs.destroy_entity(enemy_id)
		enemies_cleared += 1
	
	# Очищаем снаряды
	var projectile_ids = ecs.projectiles.keys()
	for projectile_id in projectile_ids:
		ecs.destroy_entity(projectile_id)
		projectiles_cleared += 1
	
	# Очищаем лазеры
	var laser_ids = ecs.lasers.keys()
	for laser_id in laser_ids:
		ecs.destroy_entity(laser_id)
		effects_cleared += 1
	
	# Очищаем вспышки урона
	var flash_ids = ecs.damage_flashes.keys()
	for flash_id in flash_ids:
		ecs.destroy_entity(flash_id)
		effects_cleared += 1

# ============================================================================
# ПРОВЕРКИ
# ============================================================================

# Проверить можно ли перейти в следующую фазу
func can_transition_to_next_phase() -> bool:
	var current_phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	
	match current_phase:
		GameTypes.GamePhase.BUILD_STATE:
			# Всегда можно перейти к выбору
			return true
		
		GameTypes.GamePhase.TOWER_SELECTION_STATE:
			# Можно перейти к волне если выбрано достаточно башен
			return _count_selected_towers() >= Config.TOWERS_TO_KEEP
		
		GameTypes.GamePhase.WAVE_STATE:
			# Можно перейти к стройке только если волна завершена
			return ecs.enemies.is_empty() and ecs.projectiles.is_empty()
	
	return false

# Подсчитать количество выбранных башен
func _count_selected_towers() -> int:
	var count = 0
	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		if tower.get("is_temporary", false) and tower.get("is_selected", false):
			count += 1
	return count

# game_root.gd
# Корневой узел игры (рендеринг и управление)
extends Node2D

# ============================================================================
# ССЫЛКИ НА СЛОИ
# ============================================================================

@onready var camera: Camera2D = $Camera2D
@onready var hex_layer: Node2D = $HexLayer
@onready var tower_layer: Node2D = $TowerLayer
@onready var enemy_layer: Node2D = $EnemyLayer
@onready var projectile_layer: Node2D = $ProjectileLayer
@onready var effect_layer: Node2D = $EffectLayer
@onready var ui_layer: CanvasLayer = $UILayer

# ============================================================================
# СИСТЕМЫ
# ============================================================================

var input_system: InputSystem
var wave_system: WaveSystem
var movement_system: MovementSystem
var combat_system
var projectile_system
var status_effect_system
var aura_system
var crafting_system
var volcano_system
var beacon_system
var line_drag_handler
var ore_renderer: Node2D
var energy_line_renderer: Node2D
var wall_renderer: Node2D

# Debug mode
var debug_mode: bool = false
var debug_key_pressed: bool = false
var debug_labels_created: bool = false
var debug_wave_panel: Control = null  # Панель выбора волны (видна при I)
var debug_wave_label: Label = null   # Ссылка на лейбл числа волны (чтобы кнопки работали)
var debug_level_label: Label = null  # Дебаг: уровень игрока (для теста дропа по лвлу)
const DEBUG_WAVE_MAX: int = 40
const DEBUG_LEVEL_MIN: int = 1
const DEBUG_LEVEL_MAX: int = 10
const DEBUG_PANEL_WIDTH: int = 220
const DEBUG_PANEL_HEIGHT: int = 110  # две строки: волна + уровень
const DEBUG_PANEL_Y: int = 178  # ниже индикатора руды (руда y=140, высота ~30)

# Перетаскивание карты средней кнопкой мыши
var pan_dragging: bool = false
var pan_last_pos: Vector2 = Vector2.ZERO

# Hover optimization
var hovered_hex: Hex = null
var previous_hovered_hex: Hex = null
var hex_visuals: Dictionary = {}  # Словарь polygon/line по hex
var hover_time: float = 0.0

# След за мышкой
var trail_hexes: Dictionary = {}  # hex_key -> timestamp
const TRAIL_FADE_TIME = 0.65
const TRAIL_INITIAL_BRIGHTNESS = 0.25

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================================

func _ready():
	camera.position = Vector2.ZERO
	camera.zoom = Vector2.ONE
	
	# Добавляем фон (лес)
	_add_forest_background()
	
	# Рендерим карту
	render_hex_map()
	
	# Предпросмотр пути врагов (как в Go)
	GameManager.update_future_path()
	
	# Создаем системы
	input_system = InputSystem.new(GameManager.ecs, GameManager.hex_map, camera)
	wave_system = WaveSystem.new(GameManager.ecs, GameManager.hex_map)
	movement_system = MovementSystem.new(GameManager.ecs, GameManager.hex_map)
	
	# Боевые системы
	var CombatSystemScript = preload("res://core/systems/combat_system.gd")
	var ProjectileSystemScript = preload("res://core/systems/projectile_system.gd")
	var StatusEffectSystemScript = preload("res://core/systems/status_effect_system.gd")
	var AuraSystemScript = preload("res://core/systems/aura_system.gd")
	var CraftingSystemScript = preload("res://core/systems/crafting_system.gd")
	var VolcanoSystemScript = preload("res://core/systems/volcano_system.gd")
	var BeaconSystemScript = preload("res://core/systems/beacon_system.gd")
	combat_system = CombatSystemScript.new(GameManager.ecs, GameManager.hex_map)
	projectile_system = ProjectileSystemScript.new(GameManager.ecs)
	status_effect_system = StatusEffectSystemScript.new(GameManager.ecs)
	aura_system = AuraSystemScript.new(GameManager.ecs, GameManager.hex_map)
	crafting_system = CraftingSystemScript.new(GameManager.ecs)
	var power_finder = func(tid): return GameManager.energy_network._find_power_sources(tid) if GameManager.energy_network else []
	volcano_system = VolcanoSystemScript.new(GameManager.ecs, power_finder)
	beacon_system = BeaconSystemScript.new(GameManager.ecs, power_finder)
	var LineDragHandlerScript = preload("res://core/systems/line_drag_handler.gd")
	line_drag_handler = LineDragHandlerScript.new(GameManager.ecs, GameManager.hex_map, GameManager.energy_network)
	
	# Регистрируем в GameManager
	GameManager.input_system = input_system
	GameManager.line_drag_handler = line_drag_handler
	GameManager.wave_system = wave_system
	GameManager.movement_system = movement_system
	GameManager.combat_system = combat_system
	GameManager.crafting_system = crafting_system
	
	# Устанавливаем z-index для слоев
	hex_layer.z_index = 0
	tower_layer.z_index = 10
	enemy_layer.z_index = 20
	projectile_layer.z_index = 25
	effect_layer.z_index = 30
	
	# Добавляем EntityRenderer
	var entity_renderer = preload("res://godot_adapter/rendering/entity_renderer.gd").new()
	add_child(entity_renderer)
	
	# Добавляем OreRenderer (руда)
	ore_renderer = preload("res://godot_adapter/rendering/ore_renderer.gd").new(GameManager.ecs)
	hex_layer.add_child(ore_renderer)
	
	# Добавляем EnergyLineRenderer (линии энергосети)
	energy_line_renderer = preload("res://godot_adapter/rendering/energy_line_renderer.gd").new(GameManager.ecs)
	hex_layer.add_child(energy_line_renderer)
	
	# Добавляем AttackLinkRenderer (линии между атакующими башнями)
	var attack_link_renderer = preload("res://godot_adapter/rendering/attack_link_renderer.gd").new(GameManager.ecs, GameManager.hex_map)
	hex_layer.add_child(attack_link_renderer)
	
	# Добавляем CraftingVisualRenderer (подсветка крафта)
	var crafting_visual_renderer = preload("res://godot_adapter/rendering/crafting_visual_renderer.gd").new(GameManager.ecs, GameManager.hex_map)
	hex_layer.add_child(crafting_visual_renderer)
	GameManager.crafting_visual = crafting_visual_renderer
	
	# Добавляем WallRenderer (красивые liquid glass стены)
	wall_renderer = preload("res://godot_adapter/rendering/wall_renderer.gd").new()
	hex_layer.add_child(wall_renderer)
	GameManager.wall_renderer = wall_renderer
	
	# Добавляем AuraRenderer (визуализация аур)
	var aura_renderer = preload("res://godot_adapter/rendering/aura_renderer.gd").new()
	hex_layer.add_child(aura_renderer)
	
	# Future path + cleared checkpoints (как в Go)
	var path_overlay = preload("res://godot_adapter/rendering/path_overlay_layer.gd").new()
	hex_layer.add_child(path_overlay)
	path_overlay.z_index = 5  # Поверх гексов, под башнями
	
	# Добавляем TowerPreview (preview на курсоре)
	var tower_preview = preload("res://godot_adapter/rendering/tower_preview.gd").new()
	hex_layer.add_child(tower_preview)
	
	# Добавляем HUD
	var hud = preload("res://godot_adapter/ui/game_hud.gd").new()
	add_child(hud)
	
	# Добавляем InfoPanel (плашка информации о башне/враге)
	var info_panel = preload("res://godot_adapter/ui/info_panel.gd").new()
	ui_layer.add_child(info_panel)
	GameManager.info_panel = info_panel

	# Добавляем RecipeBook на отдельном CanvasLayer поверх всего (layer=10)
	var recipe_book_layer = CanvasLayer.new()
	recipe_book_layer.layer = 10
	add_child(recipe_book_layer)
	var recipe_book = preload("res://godot_adapter/ui/recipe_book.gd").new()
	recipe_book_layer.add_child(recipe_book)
	GameManager.recipe_book = recipe_book

# ============================================================================
# ФОН (ЛЕС)
# ============================================================================

func _add_forest_background():
	var bg = ColorRect.new()
	bg.color = Config.COLOR_GAME_BACKGROUND
	bg.size = Vector2(10000, 10000)
	bg.position = Vector2(-5000, -5000)
	bg.z_index = -100
	hex_layer.add_child(bg)
	hex_layer.move_child(bg, 0)  # На самый задний план

# ============================================================================
# РЕНДЕРИНГ КАРТЫ (ТЕСТ)
# ============================================================================

func render_hex_map():
	var hex_map = GameManager.hex_map
	
	for tile in hex_map.get_all_tiles():
		var hex = tile.hex
		var pixel_pos = hex.to_pixel(Config.HEX_SIZE)
		
		# Создаем визуализацию гекса
		var polygon = Polygon2D.new()
		polygon.position = pixel_pos
		polygon.polygon = _get_hex_polygon(Config.HEX_SIZE)
		
		# Цвет зависит от типа (применяем палитру из диздока)
		var is_checkpoint = false
		for cp in hex_map.checkpoints:
			if hex.equals(cp):
				is_checkpoint = true
				break
		
		if hex.equals(hex_map.entry):
			polygon.color = Config.COLOR_ENTRY_PORTAL
		elif hex.equals(hex_map.exit):
			polygon.color = Config.COLOR_EXIT_PORTAL
		elif is_checkpoint:
			polygon.color = Config.COLOR_CHECKPOINT
		elif tile.has_tower:
			polygon.color = Config.COLOR_IRON
		elif not tile.passable:
			polygon.color = Config.COLOR_DARK_STONE
		else:
			polygon.color = Config.COLOR_HEX_NORMAL
		
		# Обводка через Line2D
		var line = Line2D.new()
		line.position = pixel_pos
		line.points = _get_hex_outline(Config.HEX_SIZE)
		line.width = 1.5
		line.default_color = Config.COLOR_HEX_OUTLINE_DIM
		line.closed = true
		line.antialiased = true
		line.z_index = 10  # Обводка всегда сверху
		
		hex_layer.add_child(polygon)
		polygon.z_index = 0  # Полигоны внизу
		hex_layer.add_child(line)
		
		# Сохраняем ссылки для hover эффекта
		hex_visuals[hex.to_key()] = {"polygon": polygon, "line": line, "base_color": polygon.color}
		
		# Добавляем номера чекпоинтов
		if is_checkpoint:
			# Ищем индекс через equals() (find не работает для объектов)
			var cp_index = -1
			for i in range(hex_map.checkpoints.size()):
				if hex.equals(hex_map.checkpoints[i]):
					cp_index = i
					break
			
			if cp_index >= 0:
				_add_hex_label(pixel_pos, str(cp_index + 1), Color.WHITE, 20)  # z_index 20 — поверх оверлеев пути
		
		# Debug labels создаются только при включении debug mode (оптимизация памяти)

# Добавить текстовую метку на гекс (центрированную). z_index_override — чтобы рисовать поверх оверлеев (номера чекпоинтов).
func _add_hex_label(pos: Vector2, text: String, color: Color, z_index_override: int = 0):
	var label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(30, 30)
	label.position = pos - Vector2(15, 15)
	if z_index_override > 0:
		label.z_index = z_index_override
	hex_layer.add_child(label)

# ============================================================================
# ГЕОМЕТРИЯ ГЕКСА
# ============================================================================

# Получить точки многоугольника гекса (pointy-top)
func _get_hex_polygon(size: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(6):
		var angle_deg = 60.0 * i - 30.0
		var angle_rad = deg_to_rad(angle_deg)
		var x = size * cos(angle_rad)
		var y = size * sin(angle_rad)
		points.append(Vector2(x, y))
	return points

# Получить контур гекса (для Line2D) - все 6 сторон
func _get_hex_outline(size: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(6):  # 6 точек для замкнутой линии
		var angle_deg = 60.0 * i - 30.0
		var angle_rad = deg_to_rad(angle_deg)
		var x = size * cos(angle_rad)
		var y = size * sin(angle_rad)
		points.append(Vector2(x, y))
	return points

# ============================================================================
# ОБНОВЛЕНИЕ
# ============================================================================

func _process(delta):
	# Обновляем камеру
	_update_camera_controls(delta)
	
	# Обновляем hovered hex каждый кадр
	_update_hovered_hex()
	
	# Обновляем hover эффект
	_update_hover_effect(delta)
	
	# Debug mode обрабатывается в _input
	
	# Profiler toggle (клавиша P)
	if Input.is_action_just_pressed("ui_page_up") and Input.is_key_pressed(KEY_SHIFT):
		Profiler.enabled = !Profiler.enabled
		if Profiler.enabled:
			Profiler.clear()
		print("Profiler: %s" % ("ON" if Profiler.enabled else "OFF"))
	
	# Обучение: проверка триггеров и продвижение шага подсказок
	if GameManager.ecs.game_state.get("is_tutorial", false):
		GameManager.update_tutorial()
	
	# Проверяем паузу (как в Go - State Machine)
	var is_paused = GameManager.ecs.game_state.get("paused", false)
	
	if not is_paused:
		# Применяем скорость времени (как в Go: delta * SpeedMultiplier)
		var time_speed = GameManager.ecs.game_state.get("time_speed", 1.0)
		var scaled_delta = delta * time_speed
		
		# Обновляем системы
		input_system.update(delta)  # Обрабатываем очередь команд
		wave_system.update(scaled_delta)
		movement_system.update(scaled_delta)
		if GameManager.ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE) == GameTypes.GamePhase.WAVE_STATE:
			GameManager.update_checkpoint_highlighting()
		status_effect_system.update(scaled_delta)
		aura_system.update()  # Без delta - просто обновление состояния
		combat_system.update(scaled_delta)
		volcano_system.update(scaled_delta)
		beacon_system.update(scaled_delta)
		projectile_system.update(scaled_delta)
	
	# Дебаг-панель: только обновить подпись (0 = не прыгать, дальше по счётчику)
	if debug_mode and debug_wave_panel and debug_wave_panel.visible and debug_wave_label:
		var v = GameManager.ecs.game_state.get("debug_start_wave", 0)
		debug_wave_label.text = "—" if v <= 0 else str(clampi(v, 1, DEBUG_WAVE_MAX))
	
	# ВСЕГДА вызываем queue_redraw для FPS счетчика
	queue_redraw()

func _input(event):
	# Зум колёсиком мыши (когда книга рецептов закрыта и курсор НЕ над плашкой информации — там скролл)
	if not (GameManager.recipe_book and GameManager.recipe_book.visible):
		var mouse_over_info = false
		if GameManager.info_panel and GameManager.info_panel.visible:
			if GameManager.info_panel.get_blocking_rect().has_point(get_viewport().get_mouse_position()):
				mouse_over_info = true
		if not mouse_over_info and event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				camera.zoom *= 1.1
				camera.zoom = camera.zoom.clamp(Vector2(0.5, 0.5), Vector2(2.0, 2.0))
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				camera.zoom /= 1.1
				camera.zoom = camera.zoom.clamp(Vector2(0.5, 0.5), Vector2(2.0, 2.0))
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_MIDDLE:
				if event.pressed:
					pan_dragging = true
					pan_last_pos = get_viewport().get_mouse_position()
					get_viewport().set_input_as_handled()
				else:
					pan_dragging = false
					get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and pan_dragging:
		var pos = get_viewport().get_mouse_position()
		var delta = pos - pan_last_pos
		pan_last_pos = pos
		# Как в онлайн-досках: захваченная точка остаётся под курсором (камера сдвигается так, чтобы world под мышью не «уезжал»)
		camera.position -= Vector2(delta.x / camera.zoom.x, delta.y / camera.zoom.y)
		get_viewport().set_input_as_handled()
	# Хоткеи
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_P:
				# Пауза (как в Go: KEY_F9 или KEY_P)
				GameManager.toggle_pause()
			KEY_I:
				debug_mode = !debug_mode
				_toggle_debug_labels(debug_mode)
				# Также включаем visual debug для FPS счетчика
				Config.visual_debug_mode = debug_mode
				print("[Debug] Debug mode: %s, visual_debug_mode: %s" % [debug_mode, Config.visual_debug_mode])
				queue_redraw()
			KEY_1:
				# Режим случайной атакующей башни
				GameManager.ecs.game_state["debug_tower_type"] = "RANDOM_ATTACK"
				print("[Debug] Random attack mode ON - каждый клик = случайная башня")
			KEY_2:
				GameManager.ecs.game_state["debug_tower_type"] = "TOWER_MINER"
				print("[Debug] TOWER_MINER")
			KEY_3:
				GameManager.ecs.game_state["debug_tower_type"] = "TOWER_WALL"
				print("[Debug] TOWER_WALL")
			KEY_0:
				# Выключить дебаг режим
				GameManager.ecs.game_state.erase("debug_tower_type")
				print("[Debug] Debug mode OFF")
			KEY_B:
				# Книга рецептов (как в Go)
				if GameManager.recipe_book:
					GameManager.recipe_book.toggle()
			KEY_U:
				# Режим редактирования энерголиний (только в BUILD и TOWER_SELECTION, как в Go)
				var phase = GameManager.ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
				if phase == GameTypes.GamePhase.BUILD_STATE or phase == GameTypes.GamePhase.TOWER_SELECTION_STATE:
					var was_on = GameManager.ecs.game_state.get("line_edit_mode", false)
					GameManager.ecs.game_state["line_edit_mode"] = not was_on
					if was_on and line_drag_handler:  # Выключили — отменяем перетаскивание
						line_drag_handler.cancel_line_drag()
	
	# Обработка кликов мыши - проверяем что не попали в UI
	if event is InputEventMouseButton and event.pressed:
		var mouse_pos = get_viewport().get_mouse_position()
		
	# Пауза — не перехватываем, пусть кнопки паузы (Продолжить, Начать заново, В меню) получат клик
		if GameManager.ecs.game_state.get("paused", false):
			return
		# Попап победы туториала — не обрабатываем клики по карте
		if GameManager.ecs.game_state.get("tutorial_complete_popup_visible", false):
			return
		# Книга рецептов открыта — не трогаем клики, пусть идут в UI
		if GameManager.recipe_book and GameManager.recipe_book.visible:
			return

		# Проверяем НЕ попали ли в область UI кнопок
		if _is_ui_area(mouse_pos):
			return

		# Блокируем клик только если попали в саму плашку (не в затемнённую область)
		if GameManager.info_panel and GameManager.info_panel.visible:
			if GameManager.info_panel.get_blocking_rect().has_point(mouse_pos):
				return

		# Режим редактирования линий (U) — маршрутизируем клики в line_drag_handler
		var phase = GameManager.ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
		if GameManager.ecs.game_state.get("line_edit_mode", false) and (phase == GameTypes.GamePhase.BUILD_STATE or phase == GameTypes.GamePhase.TOWER_SELECTION_STATE):
			var world_pos = camera.get_screen_center_position() + (mouse_pos - camera.get_viewport_rect().size / 2) / camera.zoom
			var hex = Hex.from_pixel(world_pos, Config.HEX_SIZE)
			if not GameManager.hex_map.has_tile(hex):
				if line_drag_handler:
					line_drag_handler.cancel_line_drag()
				get_viewport().set_input_as_handled()
				return
			if event.button_index == MOUSE_BUTTON_RIGHT:
				if line_drag_handler:
					line_drag_handler.cancel_line_drag()
				get_viewport().set_input_as_handled()
				return
			if event.button_index == MOUSE_BUTTON_LEFT:
				if line_drag_handler:
					line_drag_handler.handle_line_drag_click(hex, world_pos)
				get_viewport().set_input_as_handled()
				return

		input_system.handle_mouse_click(mouse_pos, event.button_index)
		get_viewport().set_input_as_handled()

func _is_ui_area(pos: Vector2) -> bool:
	# Панель сверху слева: зона Рецепты (не сливать с дебаг-панелью)
	if pos.x < 270 and pos.y < 165:
		return true
	# Дебаг-панель волны справа (когда включена по I)
	if debug_wave_panel and debug_wave_panel.visible:
		var px = Config.SCREEN_WIDTH - DEBUG_PANEL_WIDTH - 10
		if pos.x >= px and pos.x <= px + DEBUG_PANEL_WIDTH and pos.y >= DEBUG_PANEL_Y and pos.y <= DEBUG_PANEL_Y + DEBUG_PANEL_HEIGHT:
			return true
	# Индикаторы справа сверху (молния + фаза)
	if pos.x > Config.SCREEN_WIDTH - 95 and pos.y < 60:
		return true
	# Кнопки снизу справа
	if pos.x > Config.SCREEN_WIDTH - 160 and pos.y > Config.SCREEN_HEIGHT - 70:
		return true
	return false

func _cycle_phase():
	# Используем PhaseController для переходов между фазами
	if GameManager.phase_controller:
		GameManager.phase_controller.cycle_phase()
	else:
		push_warning("[GameRoot] PhaseController not available")

func _update_camera_controls(delta):
	# WASD - движение камеры
	var move_speed = 300.0
	var move_dir = Vector2.ZERO
	
	if Input.is_key_pressed(KEY_W):
		move_dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		move_dir.y += 1
	if Input.is_key_pressed(KEY_A):
		move_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		move_dir.x += 1
	
	if move_dir.length() > 0:
		camera.position += move_dir.normalized() * move_speed * delta
	
	# Zoom колесиком (только когда книга рецептов закрыта)
	if not (GameManager.recipe_book and GameManager.recipe_book.visible):
		if Input.is_action_just_released("ui_page_up"):  # Колесо вверх
			camera.zoom *= 1.1
			camera.zoom = camera.zoom.clamp(Vector2(0.5, 0.5), Vector2(2.0, 2.0))

		if Input.is_action_just_released("ui_page_down"):  # Колесо вниз
			camera.zoom /= 1.1
			camera.zoom = camera.zoom.clamp(Vector2(0.5, 0.5), Vector2(2.0, 2.0))
	
	# R/T - zoom клавишами
	if Input.is_key_pressed(KEY_R):
		camera.zoom *= 1.0 + delta
		camera.zoom = camera.zoom.clamp(Vector2(0.5, 0.5), Vector2(2.0, 2.0))
	
	if Input.is_key_pressed(KEY_T):
		camera.zoom /= 1.0 + delta
		camera.zoom = camera.zoom.clamp(Vector2(0.5, 0.5), Vector2(2.0, 2.0))
	
	# Y - reset zoom
	if Input.is_key_pressed(KEY_Y):
		camera.zoom = Vector2.ONE

# ============================================================================
# HOVER ЭФФЕКТ
# ============================================================================

func _update_hovered_hex():
	var mouse_pos = get_viewport().get_mouse_position()
	var world_pos = camera.get_screen_center_position() + (mouse_pos - get_viewport_rect().size / 2) / camera.zoom
	var hex = Hex.from_pixel(world_pos, Config.HEX_SIZE)
	
	# Сохраняем предыдущий для оптимизации
	var old_hovered = hovered_hex
	previous_hovered_hex = hovered_hex
	
	if not GameManager.hex_map.has_tile(hex):
		hovered_hex = null
		hover_time = 0.0
		return
	
	# Если гекс изменился
	if hovered_hex == null or not hex.equals(hovered_hex):
		# Добавляем СТАРЫЙ hex в след (если был на карте)
		if old_hovered != null:
			trail_hexes[old_hovered.to_key()] = Time.get_ticks_msec() / 1000.0
		
		hovered_hex = hex
		
		# Сбрасываем таймер ТОЛЬКО если пришли С ПУСТОГО места (не с другого гекса)
		if old_hovered == null:
			hover_time = 0.0  # Плавное появление когда мышка вернулась на карту
		else:
			# Мышка уже была на карте - оставляем яркость, не сбрасываем
			pass  # hover_time сохраняется

func _update_hover_effect(delta: float):
	# ОПТИМИЗАЦИЯ: Обновляем только если hovered_hex изменился или анимация активна
	var hex_changed = (hovered_hex != previous_hovered_hex)
	
	# ВСЕГДА обновляем след (даже если мышка ушла с карты)
	_update_trail(delta)
	
	if hovered_hex == null:
		if hex_changed and previous_hovered_hex != null:
			# Сбрасываем только предыдущий гекс и его соседей
			_reset_hex_highlight(previous_hovered_hex)
		return
	
	hover_time += delta
	
	# Задержка перед подсветкой (0.15 секунды) с плавной анимацией
	var delay = 0.15
	var hover_strength = clamp((hover_time - delay) / 0.4, 0.0, 1.0)
	# Применяем ease-out для плавности
	hover_strength = ease(hover_strength, -2.0)
	
	# Обновляем только если гекс изменился или анимация еще идет
	if hex_changed or hover_strength < 1.0:
		# Сбрасываем предыдущий гекс если он изменился
		if hex_changed and previous_hovered_hex != null:
			_reset_hex_highlight(previous_hovered_hex)
		
		# Обновляем только текущий гекс и его соседей (7 гексов вместо 300+)
		_update_hex_cluster(hovered_hex, hover_strength)

func _update_trail(_delta: float):
	var current_time = Time.get_ticks_msec() / 1000.0
	var to_remove = []
	
	# Собираем соседей текущего hovered_hex (они подсвечиваются, а не отображаются как след)
	var neighbor_keys = {}
	if hovered_hex != null:
		neighbor_keys[hovered_hex.to_key()] = true  # Сам центр тоже
		for neighbor in hovered_hex.get_neighbors():
			neighbor_keys[neighbor.to_key()] = true
	
	for hex_key in trail_hexes.keys():
		var spawn_time = trail_hexes[hex_key]
		var age = current_time - spawn_time
		
		# Удаляем старые
		if age > TRAIL_FADE_TIME:
			to_remove.append(hex_key)
			# Сбрасываем визуал (только если НЕ в hover зоне)
			if hex_key in hex_visuals and not neighbor_keys.has(hex_key):
				var vis = hex_visuals[hex_key]
				vis["line"].default_color = Config.COLOR_HEX_OUTLINE_DIM
				vis["line"].width = 1.5
				vis["line"].z_index = 10
			continue
		
		# ПРОПУСКАЕМ если гекс сейчас в hover зоне (его рисует _update_hex_cluster)
		if neighbor_keys.has(hex_key):
			continue
		
		# Затухание (1.0 -> 0.0)
		var fade = 1.0 - (age / TRAIL_FADE_TIME)
		fade = ease(fade, -2.0)
		
		# Применяем
		if hex_key in hex_visuals:
			var vis = hex_visuals[hex_key]
			var trail_brightness = TRAIL_INITIAL_BRIGHTNESS * fade
			var brightness = Config.COLOR_HEX_OUTLINE_DIM.lightened(trail_brightness)
			
			vis["line"].default_color = brightness
			vis["line"].width = 1.5 + 0.5 * fade
			vis["line"].z_index = 12
	
	for hex_key in to_remove:
		trail_hexes.erase(hex_key)

# ОПТИМИЗАЦИЯ: Обновляем только кластер из 7 гексов (центр + 6 соседей)
func _update_hex_cluster(center_hex: Hex, strength: float):
	var neighbors = center_hex.get_neighbors()
	
	# Центральный гекс (всегда подсвечиваем, даже если в следе)
	var center_key = center_hex.to_key()
	if center_key in hex_visuals:
		var vis = hex_visuals[center_key]
		var hover_color = Config.COLOR_HEX_OUTLINE_DIM.lerp(Config.COLOR_HEX_HOVER, strength * 0.6)
		vis["line"].default_color = hover_color
		vis["line"].width = 2.5
		vis["line"].z_index = 20
	
	# Соседи (всегда подсвечиваем, даже если в следе)
	for neighbor in neighbors:
		var neighbor_key = neighbor.to_key()
		if neighbor_key in hex_visuals:
			var vis = hex_visuals[neighbor_key]
			var neighbor_color = Config.COLOR_HEX_OUTLINE_DIM.lerp(Config.COLOR_HEX_HOVER, strength * 0.15)
			vis["line"].default_color = neighbor_color
			vis["line"].width = 2.0
			vis["line"].z_index = 15

# ОПТИМИЗАЦИЯ: Сбрасываем только кластер из 7 гексов
func _reset_hex_highlight(center_hex: Hex):
	var neighbors = center_hex.get_neighbors()
	
	# Сбрасываем центральный (НЕ сбрасываем если в следе - след сам управляет)
	var center_key = center_hex.to_key()
	if center_key in hex_visuals and not trail_hexes.has(center_key):
		var vis = hex_visuals[center_key]
		vis["line"].default_color = Config.COLOR_HEX_OUTLINE_DIM
		vis["line"].width = 1.5
		vis["line"].z_index = 10
	
	# Сбрасываем соседей (НЕ сбрасываем если в следе)
	for neighbor in neighbors:
		var neighbor_key = neighbor.to_key()
		if neighbor_key in hex_visuals and not trail_hexes.has(neighbor_key):
			var vis = hex_visuals[neighbor_key]
			vis["line"].default_color = Config.COLOR_HEX_OUTLINE_DIM
			vis["line"].width = 1.5
			vis["line"].z_index = 10

# ============================================================================
# DEBUG
# ============================================================================

func _toggle_debug_labels(show_labels: bool):
	if show_labels and not debug_labels_created:
		_create_debug_labels()
		debug_labels_created = true
	
	for child in hex_layer.get_children():
		if child.name.begins_with("CoordLabel_"):
			child.visible = show_labels
	
	# Панель выбора волны (дебаг)
	if show_labels:
		if debug_wave_panel == null:
			_create_debug_wave_panel()
		if debug_wave_panel:
			debug_wave_panel.visible = true
			_update_debug_wave_label()
			_update_debug_level_label()
	elif debug_wave_panel:
		debug_wave_panel.visible = false

func _create_debug_labels():
	var hex_map = GameManager.hex_map
	for tile in hex_map.get_all_tiles():
		var hex = tile.hex
		var pixel_pos = hex.to_pixel(Config.HEX_SIZE)
		
		var coord_label = Label.new()
		coord_label.text = "%d,%d" % [hex.q, hex.r]  # Без скобочек
		coord_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
		coord_label.add_theme_font_size_override("font_size", 10)
		coord_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		coord_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		coord_label.custom_minimum_size = Vector2(40, 20)
		coord_label.position = pixel_pos - Vector2(20, 10)  # Центрируем
		coord_label.visible = false
		coord_label.name = "CoordLabel_%s" % hex.to_key()
		hex_layer.add_child(coord_label)

func _create_debug_wave_panel():
	# Панель справа: волна для старта [+][-] и кнопка "В BUILD"
	debug_wave_panel = PanelContainer.new()
	debug_wave_panel.position = Vector2(Config.SCREEN_WIDTH - DEBUG_PANEL_WIDTH - 10, DEBUG_PANEL_Y)
	debug_wave_panel.custom_minimum_size = Vector2(DEBUG_PANEL_WIDTH, DEBUG_PANEL_HEIGHT)
	debug_wave_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # клики проходят к кнопкам
	ui_layer.add_child(debug_wave_panel)
	
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_wave_panel.add_child(vbox)
	
	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hbox)
	
	var lbl = Label.new()
	lbl.text = "Start wave:"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)
	
	debug_wave_label = Label.new()
	debug_wave_label.text = "—"
	debug_wave_label.add_theme_font_size_override("font_size", 16)
	debug_wave_label.custom_minimum_size = Vector2(28, 0)
	debug_wave_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(debug_wave_label)
	
	var btn_minus = Button.new()
	btn_minus.text = " − "
	btn_minus.custom_minimum_size = Vector2(36, 28)
	btn_minus.pressed.connect(_on_debug_wave_minus)
	hbox.add_child(btn_minus)
	
	var btn_plus = Button.new()
	btn_plus.text = " + "
	btn_plus.custom_minimum_size = Vector2(36, 28)
	btn_plus.pressed.connect(_on_debug_wave_plus)
	hbox.add_child(btn_plus)
	
	# Строка: уровень игрока (для теста дропа вышек по лвлу)
	var hbox_level = HBoxContainer.new()
	hbox_level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hbox_level)
	var lbl_level = Label.new()
	lbl_level.text = "Player Lv:"
	lbl_level.add_theme_font_size_override("font_size", 14)
	lbl_level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox_level.add_child(lbl_level)
	debug_level_label = Label.new()
	debug_level_label.text = "1"
	debug_level_label.add_theme_font_size_override("font_size", 16)
	debug_level_label.custom_minimum_size = Vector2(28, 0)
	debug_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox_level.add_child(debug_level_label)
	var btn_level_minus = Button.new()
	btn_level_minus.text = " − "
	btn_level_minus.custom_minimum_size = Vector2(36, 28)
	btn_level_minus.pressed.connect(_on_debug_level_minus)
	hbox_level.add_child(btn_level_minus)
	var btn_level_plus = Button.new()
	btn_level_plus.text = " + "
	btn_level_plus.custom_minimum_size = Vector2(36, 28)
	btn_level_plus.pressed.connect(_on_debug_level_plus)
	hbox_level.add_child(btn_level_plus)
	
	var btn_build = Button.new()
	btn_build.text = "В фазу BUILD"
	btn_build.custom_minimum_size = Vector2(140, 28)
	btn_build.pressed.connect(_debug_go_to_build)
	vbox.add_child(btn_build)
	
	if not GameManager.ecs.game_state.has("debug_start_wave"):
		GameManager.ecs.game_state["debug_start_wave"] = 0  # 0 = не прыгать, идти по счётчику

func _update_debug_wave_label():
	var n = GameManager.ecs.game_state.get("debug_start_wave", 0)
	n = clampi(n, 0, DEBUG_WAVE_MAX)
	GameManager.ecs.game_state["debug_start_wave"] = n
	if debug_wave_label:
		debug_wave_label.text = "—" if n <= 0 else str(n)

func _on_debug_wave_minus():
	var v = GameManager.ecs.game_state.get("debug_start_wave", 0)
	GameManager.ecs.game_state["debug_start_wave"] = clampi(v - 1, 0, DEBUG_WAVE_MAX)
	_update_debug_wave_label()

func _on_debug_wave_plus():
	var v = GameManager.ecs.game_state.get("debug_start_wave", 0)
	GameManager.ecs.game_state["debug_start_wave"] = clampi(v + 1, 0, DEBUG_WAVE_MAX)
	_update_debug_wave_label()

func _update_debug_level_label():
	var lv = 1
	for _pid in GameManager.ecs.player_states.keys():
		var p = GameManager.ecs.player_states[_pid]
		lv = clampi(int(p.get("level", 1)), DEBUG_LEVEL_MIN, DEBUG_LEVEL_MAX)
		break
	if debug_level_label:
		debug_level_label.text = str(lv)

func _on_debug_level_minus():
	for pid in GameManager.ecs.player_states.keys():
		var p = GameManager.ecs.player_states[pid]
		var lv = clampi(int(p.get("level", 1)) - 1, DEBUG_LEVEL_MIN, DEBUG_LEVEL_MAX)
		p["level"] = lv
		p["xp_to_next_level"] = Config.calculate_xp_for_level(lv)
		_update_debug_level_label()
		return

func _on_debug_level_plus():
	for pid in GameManager.ecs.player_states.keys():
		var p = GameManager.ecs.player_states[pid]
		var lv = clampi(int(p.get("level", 1)) + 1, DEBUG_LEVEL_MIN, DEBUG_LEVEL_MAX)
		p["level"] = lv
		p["xp_to_next_level"] = Config.calculate_xp_for_level(lv)
		_update_debug_level_label()
		return

func _debug_go_to_build():
	var phase = GameManager.ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	if phase == GameTypes.GamePhase.WAVE_STATE and GameManager.phase_controller:
		GameManager.phase_controller.transition_to_build()
	else:
		GameManager.ecs.game_state["phase"] = GameTypes.GamePhase.BUILD_STATE
		GameManager.ecs.game_state["towers_built_this_phase"] = 0
		GameManager.ecs.game_state["placements_made_this_phase"] = 0
		if GameManager.wave_system:
			GameManager.wave_system.current_wave_entity = GameTypes.INVALID_ENTITY_ID
	print("[Debug] Phase → BUILD (next wave will be %d)" % GameManager.ecs.game_state.get("debug_start_wave", 1))

func _draw():
	# FPS перенесён в game_hud (над кнопками паузы и ускорения), здесь только дебаг-инфо
	var y_offset = 30
	var screen_width = get_viewport_rect().size.x
	const FPS_X = 320
	
	if debug_mode:
		# Дополнительная инфа только в дебаг режиме
		
		# Количество сущностей
		var tower_count = GameManager.ecs.towers.size()
		var enemy_count = 0
		for id in GameManager.ecs.entities:
			if GameManager.ecs.has_component(id, "enemy"):
				enemy_count += 1
		
		draw_string(ThemeDB.fallback_font, Vector2(FPS_X, y_offset), "Towers: %d | Enemies: %d" % [tower_count, enemy_count], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		y_offset += 22
		
		# Режим быстрой постановки
		var fast_text = "Fast Placement: " + ("ON" if Config.fast_tower_placement else "OFF")
		draw_string(ThemeDB.fallback_font, Vector2(FPS_X, y_offset), fast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.CYAN)
		y_offset += 20
	
	# Профайлер (всегда если включен)
	if Config.visual_debug_mode:
		if Profiler.enabled:
			var stats = Profiler.get_formatted_stats()
			if stats.length() > 0:
				draw_string(ThemeDB.fallback_font, Vector2(10, y_offset), "=== Profiler ===", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.YELLOW)
				y_offset += 20
				for line in stats.split("\n"):
					draw_string(ThemeDB.fallback_font, Vector2(10, y_offset), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.YELLOW)
					y_offset += 18

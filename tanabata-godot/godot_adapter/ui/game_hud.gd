# game_hud.gd
# HUD как в Go версии
extends CanvasLayer

var health_label: Label
var wave_label: Label
var tower_count_label: Label
var kills_label: Label
var level_label: Label  # Уровень и XP (Lv.1 0/100)
var state_indicator: Control
var state_indicator_button: Button
var speed_button: Control
var speed_button_clickable: Button
var pause_button: Control
var pause_button_clickable: Button
var pause_overlay: ColorRect  # Затемнение при паузе (блокирует клики)
var pause_panel: Control  # Контейнер кнопок паузы (Продолжить, Начать заново, В меню)
var recipe_button: Button  # Кнопка "Рецепты" — открывает таблицу крафта
var recipe_container: Control = null  # Зона клика "Рецепты" (для лога хитбокса)
var line_edit_indicator: Control  # Молния — режим редактирования энерголиний
var line_edit_button: Button  # Кликабельная область для переключения
var ore_sector_indicator: Control  # Прогресс-бары руды: по одному на каждую сеть (главная сверху)
var next_wave_label: RichTextLabel  # Следующая волна: название врага и количество (жирным)
var success_label: Label  # Уровень успеха (выше длины пути)
var ore_path_length_label: Label  # Строка 1: общая длина "250 гексов" (по центру)
var ore_path_segments_label: Label  # Строка 2: подписи сегментов в-1 1-2 ...
var ore_path_values_label: Label  # Строка 3: значения сегментов под подписями
var _ore_network_labels: Array = []  # Подпись "X/Y" под каждым баром руды (Label по одному на сеть)
var cards_effects_label: RichTextLabel  # Активные карты и проклятия вышек: слева внизу над стешем (Б А А А А)
var top5_damage_label: RichTextLabel  # Топ-5 вышек по урону за волну (во время волны); красная подсветка для топа и MVP 5
var stash_label: RichTextLabel  # Стеш: буквы Б А А А А слева снизу (Б — желтый, А — серый)
var fps_label: Label  # FPS над кнопками паузы и ускорения
var tutorial_hint_panel: Control = null  # Панель подсказки обучения (внизу по центру)
var tutorial_hint_label: Label = null
var tutorial_hint_next_btn: Button = null

# Кэш руды по сетям для HUD: массив { total_current, total_max }, отсортирован по total_max (главная сеть первая)
var _ore_networks_cache: Array = []
var _ore_totals_cache_time: float = -1.0
const ORE_CACHE_INTERVAL: float = 0.25  # обновлять не чаще раза в 0.25 сек
const ORE_BAR_HEIGHT: float = 20.0
const ORE_LABEL_OFFSET: float = 2.0   # отступ подписи от бара
const ORE_LABEL_ROW: float = 14.0     # высота строки подписи
const ORE_BAR_GAP: float = 24.0       # между блоками: отступ к подписи + строка + 8 px
const ORE_WIDTH: float = 120.0        # базовая ширина блока руды и подписи волны
const WAVE_LABEL_MAX_WIDTH: float = 380.0  # макс. ширина надписи волны при расширении влево (без переноса)

# Счётчики/здоровье/топ5 обновляем каждый кадр; FPS — каждый кадр
const UPDATE_UI_INTERVAL: float = 0.25

func _ready():
	_create_ui()
	call_deferred("_log_recipe_button_rect_once")

func _log_recipe_button_rect_once():
	pass  # if recipe_container: print("[Recipe debug] ...")

func _create_ui():
	# Панель сверху слева
	var top_panel = PanelContainer.new()
	top_panel.position = Vector2(10, 10)
	top_panel.custom_minimum_size = Vector2(250, 80)
	top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # НЕ блокируем клики!
	add_child(top_panel)
	
	var top_vbox = VBoxContainer.new()
	top_panel.add_child(top_vbox)
	
	health_label = Label.new()
	health_label.text = "Health: 100"
	health_label.add_theme_font_size_override("font_size", 14)
	top_vbox.add_child(health_label)
	
	wave_label = Label.new()
	wave_label.text = "Wave: 0"
	wave_label.add_theme_font_size_override("font_size", 14)
	top_vbox.add_child(wave_label)
	
	tower_count_label = Label.new()
	tower_count_label.text = "Towers: 0/5"
	tower_count_label.add_theme_font_size_override("font_size", 14)
	top_vbox.add_child(tower_count_label)
	
	kills_label = Label.new()
	kills_label.text = "Kills: 0"
	kills_label.add_theme_font_size_override("font_size", 14)
	top_vbox.add_child(kills_label)
	
	level_label = Label.new()
	level_label.text = "Lv.1 (0/100 XP)"
	level_label.add_theme_font_size_override("font_size", 14)
	level_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.5))  # Желтоватый
	top_vbox.add_child(level_label)

	# Зона "Рецепты": только полоса внизу панели (фиксированная высота), без расширения вверх
	recipe_container = Control.new()
	recipe_container.custom_minimum_size = Vector2(250, 32)
	recipe_container.mouse_filter = Control.MOUSE_FILTER_STOP
	recipe_container.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_recipe_button_pressed()
			recipe_container.accept_event()
	)
	top_vbox.add_child(recipe_container)
	
	recipe_button = Button.new()
	recipe_button.text = "Рецепты (B)"
	recipe_button.custom_minimum_size = Vector2(100, 26)
	recipe_button.position = Vector2(0, 4)
	recipe_button.pressed.connect(_on_recipe_button_pressed)
	recipe_container.add_child(recipe_button)

	# Увеличиваем высоту панели под кнопку и индикатор уровня
	top_panel.custom_minimum_size = Vector2(250, 130)

	# Стеш: Б А А А А слева снизу (Б желтый, А серый), только в фазе BUILD
	stash_label = RichTextLabel.new()
	stash_label.position = Vector2(10, Config.SCREEN_HEIGHT - 40)
	stash_label.custom_minimum_size = Vector2(200, 28)
	stash_label.add_theme_font_size_override("normal_font_size", 17)
	stash_label.add_theme_font_size_override("bold_font_size", 17)
	stash_label.bbcode_enabled = true
	stash_label.fit_content = true
	stash_label.scroll_active = false
	stash_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stash_label.visible = false
	add_child(stash_label)

	# Топ-5 урона вышек (слева под панелью; во время волны — текущий, в строительстве — прошлая волна)
	top5_damage_label = RichTextLabel.new()
	top5_damage_label.position = Vector2(10, 165)
	top5_damage_label.custom_minimum_size = Vector2(260, 75)
	top5_damage_label.add_theme_font_size_override("normal_font_size", 12)
	top5_damage_label.add_theme_color_override("default_color", Color(0.85, 0.85, 0.7))
	top5_damage_label.bbcode_enabled = true
	top5_damage_label.fit_content = true
	top5_damage_label.scroll_active = false
	top5_damage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top5_damage_label)

	# Индикатор руды: по одному прогресс-бару на каждую сеть (главная = с макс. рудой сверху)
	ore_sector_indicator = Control.new()
	ore_sector_indicator.position = Vector2(Config.SCREEN_WIDTH - 17 - ORE_WIDTH, 170)
	ore_sector_indicator.custom_minimum_size = Vector2(ORE_WIDTH, ORE_BAR_HEIGHT)
	ore_sector_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ore_sector_indicator.draw.connect(_draw_ore_sector_indicator.bind(ore_sector_indicator))
	add_child(ore_sector_indicator)
	next_wave_label = RichTextLabel.new()
	next_wave_label.position = Vector2(Config.SCREEN_WIDTH - 17 - ORE_WIDTH, 68)
	next_wave_label.custom_minimum_size = Vector2(ORE_WIDTH, 24)
	next_wave_label.add_theme_font_size_override("normal_font_size", 11)
	next_wave_label.add_theme_color_override("default_color", Color(0.85, 0.88, 0.92))
	next_wave_label.bbcode_enabled = true
	next_wave_label.fit_content = true
	next_wave_label.scroll_active = false
	next_wave_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	next_wave_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(next_wave_label)
	success_label = Label.new()
	success_label.position = Vector2(Config.SCREEN_WIDTH - 17 - ORE_WIDTH, 104)
	success_label.add_theme_font_size_override("font_size", 11)
	success_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.6))
	success_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(success_label)
	var path_block_x = Config.SCREEN_WIDTH - 17 - ORE_WIDTH
	ore_path_length_label = Label.new()
	ore_path_length_label.position = Vector2(path_block_x, 122)
	ore_path_length_label.custom_minimum_size = Vector2(ORE_WIDTH, 14)
	ore_path_length_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ore_path_length_label.add_theme_font_size_override("font_size", 11)
	ore_path_length_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
	ore_path_length_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ore_path_length_label)
	ore_path_segments_label = Label.new()
	ore_path_segments_label.position = Vector2(path_block_x, 136)
	ore_path_segments_label.custom_minimum_size = Vector2(ORE_WIDTH, 14)
	ore_path_segments_label.add_theme_font_size_override("font_size", 10)
	ore_path_segments_label.add_theme_color_override("font_color", Color(0.6, 0.68, 0.78))
	ore_path_segments_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ore_path_segments_label)
	ore_path_values_label = Label.new()
	ore_path_values_label.position = Vector2(path_block_x, 150)
	ore_path_values_label.custom_minimum_size = Vector2(ORE_WIDTH, 14)
	ore_path_values_label.add_theme_font_size_override("font_size", 10)
	ore_path_values_label.add_theme_color_override("font_color", Color(0.6, 0.68, 0.78))
	ore_path_values_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ore_path_values_label)

	# Список активных карт и проклятий вышек: слева внизу над стешем (Б А А А А), построчно
	var cards_label_width = 280.0
	var cards_label_height = 110.0
	cards_effects_label = RichTextLabel.new()
	cards_effects_label.position = Vector2(10, Config.SCREEN_HEIGHT - 40 - 28 - cards_label_height)
	cards_effects_label.custom_minimum_size = Vector2(cards_label_width, cards_label_height)
	cards_effects_label.add_theme_font_size_override("normal_font_size", 11)
	cards_effects_label.add_theme_color_override("default_color", Color(0.85, 0.88, 0.9))
	cards_effects_label.bbcode_enabled = true
	cards_effects_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cards_effects_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cards_effects_label)

	# Молния — режим редактирования энерголиний, размер как у паузы/скорости
	var line_edit_size = 40.0
	line_edit_indicator = Control.new()
	line_edit_indicator.position = Vector2(Config.SCREEN_WIDTH - 100, 15)
	line_edit_indicator.custom_minimum_size = Vector2(line_edit_size, line_edit_size)
	line_edit_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Пропускаем клики к кнопке
	line_edit_indicator.draw.connect(_draw_line_edit_indicator)
	add_child(line_edit_indicator)
	
	line_edit_button = Button.new()
	line_edit_button.flat = true
	line_edit_button.custom_minimum_size = Vector2(line_edit_size, line_edit_size)
	line_edit_button.modulate = Color(1, 1, 1, 0)
	line_edit_button.pressed.connect(_on_line_edit_clicked)
	line_edit_indicator.add_child(line_edit_button)

	# StateIndicator - круг справа сверху
	var indicator_size = Config.INDICATOR_RADIUS * 2 + 10
	
	state_indicator = Control.new()
	state_indicator.position = Vector2(Config.SCREEN_WIDTH - 50, 20)
	state_indicator.custom_minimum_size = Vector2(indicator_size, indicator_size)
	state_indicator.draw.connect(_draw_state_indicator)
	add_child(state_indicator)
	
	# Кнопка для кликов
	state_indicator_button = Button.new()
	state_indicator_button.flat = true
	state_indicator_button.custom_minimum_size = Vector2(indicator_size, indicator_size)
	state_indicator_button.modulate = Color(1, 1, 1, 0)
	state_indicator_button.pressed.connect(_on_state_indicator_clicked)
	state_indicator.add_child(state_indicator_button)
	
	# SpeedButton - два треугольника (как в Go)
	var speed_size = 40.0
	speed_button = Control.new()
	speed_button.position = Vector2(Config.SCREEN_WIDTH - 60, Config.SCREEN_HEIGHT - 60)
	speed_button.custom_minimum_size = Vector2(speed_size, speed_size)
	speed_button.draw.connect(_draw_speed_button)
	add_child(speed_button)
	
	# Прозрачная кнопка для кликов
	speed_button_clickable = Button.new()
	speed_button_clickable.flat = true
	speed_button_clickable.custom_minimum_size = Vector2(speed_size, speed_size)
	speed_button_clickable.modulate = Color(1, 1, 1, 0)
	speed_button_clickable.pressed.connect(_on_speed_clicked)
	speed_button.add_child(speed_button_clickable)
	
	# FPS — над кнопками паузы и ускорения (в экранных координатах, всегда видно)
	fps_label = Label.new()
	fps_label.position = Vector2(Config.SCREEN_WIDTH - 135, Config.SCREEN_HEIGHT - 95)
	fps_label.add_theme_font_size_override("font_size", 16)
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fps_label)

	# PauseButton - треугольник или два прямоугольника (как в Go)
	var pause_size = 40.0
	pause_button = Control.new()
	pause_button.position = Vector2(Config.SCREEN_WIDTH - 120, Config.SCREEN_HEIGHT - 60)
	pause_button.custom_minimum_size = Vector2(pause_size, pause_size)
	pause_button.draw.connect(_draw_pause_button)
	add_child(pause_button)
	
	# Прозрачная кнопка для кликов
	pause_button_clickable = Button.new()
	pause_button_clickable.flat = true
	pause_button_clickable.custom_minimum_size = Vector2(pause_size, pause_size)
	pause_button_clickable.modulate = Color(1, 1, 1, 0)
	pause_button_clickable.pressed.connect(_on_pause_clicked)
	pause_button.add_child(pause_button_clickable)
	
	# Оверлей для паузы — затемнение + блокировка кликов (как в Go)
	pause_overlay = ColorRect.new()
	pause_overlay.color = Color(0, 0, 0, 0.7)
	pause_overlay.size = Vector2(Config.SCREEN_WIDTH, Config.SCREEN_HEIGHT)
	pause_overlay.position = Vector2(0, 0)
	pause_overlay.visible = false
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # Блокируем клики в игру
	add_child(pause_overlay)
	# Панель кнопок паузы (как в Go: Продолжить, Начать заново, Главное меню)
	pause_panel = VBoxContainer.new()
	pause_panel.visible = false
	pause_panel.add_theme_constant_override("separation", 20)
	var btn_w = 250
	var btn_h = 50
	pause_panel.position = Vector2(Config.SCREEN_WIDTH / 2.0 - btn_w / 2.0, Config.SCREEN_HEIGHT / 2.0 - (btn_h * 3 + 40) / 2.0)
	pause_panel.custom_minimum_size = Vector2(btn_w, btn_h * 3 + 40)
	var btn_continue = Button.new()
	btn_continue.text = "Продолжить"
	btn_continue.custom_minimum_size = Vector2(btn_w, btn_h)
	btn_continue.pressed.connect(_on_pause_continue_clicked)
	pause_panel.add_child(btn_continue)
	var btn_restart = Button.new()
	btn_restart.text = "Начать заново"
	btn_restart.custom_minimum_size = Vector2(btn_w, btn_h)
	btn_restart.pressed.connect(_on_pause_restart_clicked)
	pause_panel.add_child(btn_restart)
	var btn_menu = Button.new()
	btn_menu.text = "В меню"
	btn_menu.custom_minimum_size = Vector2(btn_w, btn_h)
	btn_menu.pressed.connect(_on_pause_menu_clicked)
	pause_panel.add_child(btn_menu)
	add_child(pause_panel)
	move_child(pause_overlay, 2)
	move_child(pause_panel, 3)
	
	# Панель подсказок обучения (внизу по центру)
	_create_tutorial_hint_panel()

func _create_tutorial_hint_panel():
	tutorial_hint_panel = PanelContainer.new()
	tutorial_hint_panel.name = "TutorialHintPanel"
	tutorial_hint_panel.visible = false
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.2, 0.95)
	style.set_border_width_all(2)
	style.border_color = Color(0.4, 0.5, 0.7)
	style.set_corner_radius_all(6)
	tutorial_hint_panel.add_theme_stylebox_override("panel", style)
	var panel_width = min(500, Config.SCREEN_WIDTH - 80)
	tutorial_hint_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tutorial_hint_panel.offset_left = -panel_width / 2
	tutorial_hint_panel.offset_top = -192   # плашка выше: отступ от низа экрана
	tutorial_hint_panel.offset_right = panel_width / 2
	tutorial_hint_panel.offset_bottom = -72  # низ плашки на 72px выше низа экрана
	tutorial_hint_panel.custom_minimum_size = Vector2(panel_width, 120)
	tutorial_hint_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	tutorial_hint_panel.add_child(margin)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	tutorial_hint_label = Label.new()
	tutorial_hint_label.name = "TutorialHintLabel"
	tutorial_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_hint_label.custom_minimum_size = Vector2(panel_width - 32, 60)
	tutorial_hint_label.add_theme_font_size_override("font_size", 14)
	tutorial_hint_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	vbox.add_child(tutorial_hint_label)
	tutorial_hint_next_btn = Button.new()
	tutorial_hint_next_btn.text = "Далее"
	tutorial_hint_next_btn.custom_minimum_size = Vector2(80, 28)
	tutorial_hint_next_btn.pressed.connect(_on_tutorial_hint_next)
	tutorial_hint_next_btn.visible = false  # Только плашка с текстом, без кнопки «Далее»
	vbox.add_child(tutorial_hint_next_btn)
	add_child(tutorial_hint_panel)

func _on_tutorial_hint_next():
	if GameManager:
		GameManager.advance_tutorial_step()

func _draw_state_indicator():
	var ecs = GameManager.ecs
	var phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	
	var color = Config.BUILD_STATE_COLOR
	match phase:
		GameTypes.GamePhase.BUILD_STATE:
			color = Config.BUILD_STATE_COLOR
		GameTypes.GamePhase.WAVE_STATE:
			color = Config.WAVE_STATE_COLOR
		GameTypes.GamePhase.TOWER_SELECTION_STATE:
			color = Config.SELECTION_STATE_COLOR
	
	var center = state_indicator.custom_minimum_size / 2
	state_indicator.draw_circle(center, Config.INDICATOR_RADIUS, color)
	state_indicator.draw_arc(center, Config.INDICATOR_RADIUS, 0, TAU, 32, Color.WHITE, 2.0)

func _process(_delta: float):
	if not GameManager or not GameManager.ecs:
		return
	var ecs = GameManager.ecs
	# FPS и пауза — каждый кадр
	var fps = Engine.get_frames_per_second()
	var frame_time = 1000.0 / fps if fps > 0 else 0.0
	fps_label.text = "FPS: %d (%.1f ms)" % [fps, frame_time]
	if fps >= 60:
		fps_label.add_theme_color_override("font_color", Color.GREEN)
	elif fps >= 30:
		fps_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		fps_label.add_theme_color_override("font_color", Color.RED)
	var is_paused = ecs.game_state.get("paused", false)
	pause_overlay.visible = is_paused
	pause_panel.visible = is_paused
	
	# Остальной HUD: обновляем каждый кадр (как раньше), чтобы не ломать постановку/ввод
	_update_ui()
	
	state_indicator.queue_redraw()
	speed_button.queue_redraw()
	pause_button.queue_redraw()
	line_edit_indicator.queue_redraw()

func _update_ui():
	var ecs = GameManager.ecs
	
	var health = 100
	for player_id in ecs.player_states.keys():
		health = ecs.player_states[player_id].get("health", 100)
		break
	health_label.text = "Health: %d" % health
	
	if health > 50:
		health_label.add_theme_color_override("font_color", Color.GREEN)
	elif health > 25:
		health_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		health_label.add_theme_color_override("font_color", Color.RED)
	
	wave_label.text = "Wave: %d" % ecs.game_state.get("current_wave", 0)
	tower_count_label.text = "Towers: %d/%d" % [ecs.game_state.get("towers_built_this_phase", 0), Config.MAX_TOWERS_IN_BUILD_PHASE]
	
	# Врагов: убито за всё время | живых сейчас / размер волны (alive из game_state)
	var total_kills = ecs.game_state.get("total_enemies_killed", 0)
	var alive = ecs.game_state.get("alive_enemies_count", 0)
	var in_wave = ecs.game_state.get("current_wave_enemy_count", 0)
	kills_label.text = "Врагов: %d | %d / %d" % [total_kills, alive, in_wave]
	
	# Обновляем уровень и XP
	var level = 1
	var current_xp = 0
	var xp_to_next = 100
	for player_id in ecs.player_states.keys():
		var player = ecs.player_states[player_id]
		level = player.get("level", 1)
		current_xp = player.get("current_xp", 0)
		xp_to_next = player.get("xp_to_next_level", 100)
		break
	level_label.text = "Lv.%d (%d/%d XP)" % [level, current_xp, xp_to_next]
	
	# Молния — видна только в BUILD и TOWER_SELECTION (цвет задаётся в _draw_line_edit_indicator)
	var phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	var can_line_edit = (phase == GameTypes.GamePhase.BUILD_STATE or phase == GameTypes.GamePhase.TOWER_SELECTION_STATE)
	line_edit_indicator.visible = can_line_edit
	
	# Стеш: очередь оставшихся слотов (Б А А ...) слева снизу, только в BUILD
	if stash_label:
		if phase == GameTypes.GamePhase.BUILD_STATE:
			var queue = ecs.game_state.get("stash_queue", [])
			if queue.is_empty() and ecs.game_state.get("towers_built_this_phase", 0) == 0 and GameManager:
				ecs.game_state["stash_queue"] = GameManager.get_initial_stash_letters()
				queue = ecs.game_state["stash_queue"]
			stash_label.visible = true
			var parts: Array = []
			for letter in queue:
				if letter == "Б":
					parts.append("[color=#e6c230][b]%s[/b][/color]" % letter)
				else:
					parts.append("[color=#a6a6b0][b]%s[/b][/color]" % letter)
			stash_label.text = "   ".join(parts)
		else:
			stash_label.visible = false
	
	# Топ-5 урона вышек: во время волны — текущий, в строительстве — за прошлую волну (не скрываем)
	var wave_num = ecs.game_state.get("current_wave", 0)
	if phase == GameTypes.GamePhase.BUILD_STATE or phase == GameTypes.GamePhase.TOWER_SELECTION_STATE:
		wave_num = ecs.game_state.get("last_wave_number", 0)
	top5_damage_label.visible = true
	if GameManager:
		var top5 = GameManager.get_top5_tower_damage()
		if top5.is_empty():
			top5_damage_label.text = "Урон (волна %d): —" % wave_num
		else:
			var lines = ["Урон (волна %d):" % wave_num]
			for i in top5.size():
				var display_name = top5[i].name if int(top5[i].get("mvp_level", 0)) == 0 else "%s MVP %d" % [top5[i].name, top5[i].mvp_level]
				var line = "%d. %s: %d" % [i + 1, display_name, top5[i].damage]
				if top5[i].get("is_top1", false) or top5[i].get("has_max_mvp", false):
					lines.append("[color=red]%s[/color]" % line)
				else:
					lines.append(line)
			top5_damage_label.text = "\n".join(lines)
	
	ore_sector_indicator.queue_redraw()
	
	# Подсказки обучения: показываем панель, когда есть сообщение
	if tutorial_hint_panel and tutorial_hint_label:
		var is_tutorial = ecs.game_state.get("is_tutorial", false)
		var msg = GameManager.get_current_tutorial_message() if GameManager else ""
		# Не показывать в плашке значения триггеров — только нормальный текст сообщения
		if msg == "none" or msg == "TRIGGER_NONE":
			if is_tutorial:
				push_warning("[Tutorial] HUD: got trigger instead of message ('%s'), hiding plaque" % msg)
			msg = ""
		tutorial_hint_panel.visible = is_tutorial and not msg.is_empty()
		if tutorial_hint_panel.visible:
			tutorial_hint_label.text = msg
	
	if next_wave_label and ecs:
		var current_wave = ecs.game_state.get("current_wave", 0)
		# В фазе волны показываем эту волну; в строительстве и выборе — следующую
		var wave_show = current_wave if (phase == GameTypes.GamePhase.WAVE_STATE) else (current_wave + 1)
		# Контент волны может быть из другой (перемешивание): показываем то, что реально пойдёт
		var source_wn = wave_show
		var shuffle_map = ecs.game_state.get("wave_shuffle_map", {})
		if shuffle_map.has(wave_show):
			source_wn = shuffle_map[wave_show].get("source_wave_number", wave_show)
		var wdef = DataRepository.get_wave_def(source_wn)
		if wdef.is_empty():
			next_wave_label.text = ""
		else:
			var parts: Array = []
			if wdef.has("enemy_id"):
				var eid = wdef.get("enemy_id", "")
				var edef = DataRepository.get_enemy_def(eid)
				var ename = edef.get("name", eid)
				parts.append("[b]%s[/b] x %d" % [ename, int(wdef.get("count", 0))])
			elif wdef.has("enemies"):
				for e in wdef.get("enemies", []):
					var eid = e.get("enemy_id", "")
					var edef = DataRepository.get_enemy_def(eid)
					var ename = edef.get("name", eid)
					parts.append("[b]%s[/b] x %d" % [ename, int(e.get("count", 0))])
			var content = ", ".join(parts) if parts.size() > 0 else ""
			var info = _wave_label_resistance_and_flying(wdef)
			var color_hex: String = info.get("color_hex", "#dddddd")
			var has_flying: bool = info.get("flying", false)
			if has_flying:
				content = "[u]" + content + "[/u]"
			next_wave_label.text = "[color=%s]%s[/color]" % [color_hex, content]
		call_deferred("_apply_wave_label_geometry")
	if success_label and GameManager:
		var lvl = GameManager.get_success_level()
		var scale_val = GameManager.get_success_scale()
		success_label.text = "Успех: %d (%.0f%%)" % [lvl, scale_val]
	if ore_path_length_label and ecs:
		var path_len = GameManager.get_current_path_length() if GameManager else 0
		var seg = GameManager.get_path_segment_lengths() if GameManager else []
		ore_path_length_label.text = "%d гексов" % path_len
		if seg.size() >= 7:
			ore_path_segments_label.text = "в-1  1-2  2-3  3-4  4-5  5-6  6-в"
			ore_path_values_label.text = "%4d %4d %4d %4d %4d %4d %4d" % [seg[0], seg[1], seg[2], seg[3], seg[4], seg[5], seg[6]]
			ore_path_segments_label.visible = true
			ore_path_values_label.visible = true
		else:
			ore_path_segments_label.visible = false
			ore_path_values_label.visible = false
	if GameManager:
		var now = Time.get_ticks_msec() / 1000.0
		if now - _ore_totals_cache_time >= ORE_CACHE_INTERVAL or _ore_networks_cache.is_empty():
			if GameManager.energy_network:
				var list = GameManager.energy_network.get_networks_ore_and_attack_count()
				list = list.filter(func(n): return n.get("total_max", 0.0) > 0.0)
				list.sort_custom(func(a, b): return a.get("total_max", 0.0) > b.get("total_max", 0.0))
				_ore_networks_cache = []
				for n in list:
					_ore_networks_cache.append({
						"total_current": n.get("total_current", 0.0),
						"total_max": n.get("total_max", 0.0)
					})
			else:
				var t = GameManager.get_ore_network_totals()
				_ore_networks_cache = [{"total_current": t.get("total_current", 0.0), "total_max": t.get("total_max", 0.0)}]
			_ore_totals_cache_time = now
		var n_count = _ore_networks_cache.size()
		var block_h = n_count * ORE_BAR_HEIGHT + max(0, n_count - 1) * ORE_BAR_GAP
		ore_sector_indicator.custom_minimum_size.y = block_h
		while _ore_network_labels.size() > n_count:
			var lbl = _ore_network_labels.pop_back()
			remove_child(lbl)
			lbl.queue_free()
		while _ore_network_labels.size() < n_count:
			var lbl = Label.new()
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(lbl)
			_ore_network_labels.append(lbl)
		var ore_x = Config.SCREEN_WIDTH - 17 - 120.0
		for i in range(n_count):
			var n = _ore_networks_cache[i]
			var lbl: Label = _ore_network_labels[i]
			lbl.position = Vector2(ore_x, 170.0 + i * (ORE_BAR_HEIGHT + ORE_BAR_GAP) + ORE_BAR_HEIGHT + ORE_LABEL_OFFSET)
			lbl.text = "%.0f/%.0f" % [n.get("total_current", 0.0), n.get("total_max", 0.0)]
	if cards_effects_label:
		var blessing_ids = GameManager.active_blessing_ids if GameManager else []
		var curse_ids = GameManager.active_curse_ids if GameManager else []
		var lines: Array = []
		for bid in blessing_ids:
			var desc = CardsData.get_card_desc(bid)
			if desc.is_empty():
				lines.append("[color=#70c070]Бонус - " + CardsData.get_card_name(bid) + "[/color]")
			else:
				lines.append("[color=#70c070]Бонус - " + desc + "[/color]")
		for cid in curse_ids:
			lines.append("[color=#cc5555]Проклятие - " + CardsData.get_card_name(cid) + "[/color]")
		if GameManager and GameManager.ecs:
			for tid in GameManager.ecs.towers.keys():
				var info = GameManager.get_early_craft_curse_info(tid)
				if info.get("has_curse", false):
					var pct = info.get("percent", 0)
					var def_id = GameManager.ecs.towers.get(tid, {}).get("def_id", "?")
					var tdef = DataRepository.get_tower_def(def_id) if DataRepository else {}
					var tname = tdef.get("name", def_id)
					lines.append("[color=#cc5555]Проклятие раннего крафта (" + str(tname) + " " + str(pct) + "%)[/color]")
			for tid in GameManager.ecs.towers.keys():
				var touch_info = GameManager.get_touch_curse_info(tid)
				if touch_info.get("has_curse", false):
					var def_id = GameManager.ecs.towers.get(tid, {}).get("def_id", "?")
					var tdef = DataRepository.get_tower_def(def_id) if DataRepository else {}
					var tname = tdef.get("name", def_id)
					lines.append("[color=#cc5555]Проклятие касания (" + str(tname) + " 15%)[/color]")
		cards_effects_label.text = "\n".join(lines) if lines.size() > 0 else ""

func _wave_label_resistance_and_flying(wdef: Dictionary) -> Dictionary:
	var phys_sum := 0.0
	var mag_sum := 0.0
	var has_flying := false
	var entries: Array = []
	if wdef.has("enemy_id"):
		entries.append({"enemy_id": wdef.get("enemy_id", ""), "count": int(wdef.get("count", 0))})
	else:
		for e in wdef.get("enemies", []):
			entries.append({"enemy_id": e.get("enemy_id", ""), "count": int(e.get("count", 0))})
	for entry in entries:
		var eid = entry.get("enemy_id", "")
		var cnt = entry.get("count", 1)
		var edef = DataRepository.get_enemy_def(eid)
		if edef.is_empty():
			continue
		phys_sum += float(edef.get("physical_armor", 0)) * cnt
		mag_sum += float(edef.get("magical_armor", 0)) * cnt
		if edef.get("flying", false):
			has_flying = true
	var pure_val: float = wdef.get("pure_damage_resistance", 0.0) * 100.0
	var color_hex := "#dddddd"
	if phys_sum >= mag_sum and phys_sum >= pure_val and phys_sum > 0.0:
		color_hex = "#cc4444"
	elif mag_sum >= phys_sum and mag_sum >= pure_val and mag_sum > 0.0:
		color_hex = "#aa66cc"
	elif pure_val > 0.0:
		color_hex = "#eeeeee"
	return {"color_hex": color_hex, "flying": has_flying}

func _apply_wave_label_geometry() -> void:
	if not next_wave_label:
		return
	var content_w = next_wave_label.get_minimum_size().x
	var w = clampf(content_w, ORE_WIDTH, WAVE_LABEL_MAX_WIDTH)
	next_wave_label.custom_minimum_size.x = w
	next_wave_label.position.x = (Config.SCREEN_WIDTH - 17) - w

func _draw_ore_sector_indicator(canvas: Control):
	# По одному бару на сеть: заполнение = осталось/макс; синий, при руда < 10 — красный, при руда < 3 — красное мигание. Без вышек/сетей — ничего не рисуем.
	var total_width := 120.0
	var border := 2
	var networks = _ore_networks_cache
	for i in range(networks.size()):
		var n = networks[i]
		var tmax = n.get("total_max", 0.0)
		var ore_cur = n.get("total_current", 0.0)
		var ratio := 1.0
		if tmax > 0.0:
			ratio = clampf(ore_cur / tmax, 0.0, 1.0)
		ratio = clampf(ratio, 0.0, 1.0)
		var y0 = i * (ORE_BAR_HEIGHT + ORE_BAR_GAP)
		canvas.draw_rect(Rect2(0, y0, total_width, ORE_BAR_HEIGHT), Color(0.15, 0.15, 0.2, 0.95))
		var fill_w := total_width * ratio
		if fill_w > 0.5:
			var fill_color: Color
			if ore_cur < 10.0:
				if ore_cur > 0.0 and ore_cur < Config.ORE_FLICKER_THRESHOLD:
					var t = Time.get_ticks_msec() / 120.0
					var a = 0.5 + 0.5 * sin(t)
					fill_color = Color(0.9, 0.2, 0.2, 0.5 + 0.45 * a)
				else:
					fill_color = Color(0.85, 0.25, 0.25, 0.95)
			else:
				fill_color = Color(0.25, 0.5, 0.9, 0.95)
			canvas.draw_rect(Rect2(0, y0, fill_w, ORE_BAR_HEIGHT), fill_color)
		canvas.draw_rect(Rect2(0, y0, total_width, border), Color(0.4, 0.45, 0.55))
		canvas.draw_rect(Rect2(0, y0 + ORE_BAR_HEIGHT - border, total_width, border), Color(0.4, 0.45, 0.55))
		canvas.draw_rect(Rect2(0, y0, border, ORE_BAR_HEIGHT), Color(0.4, 0.45, 0.55))
		canvas.draw_rect(Rect2(total_width - border, y0, border, ORE_BAR_HEIGHT), Color(0.4, 0.45, 0.55))

func _draw_line_edit_indicator():
	var is_active = GameManager.ecs.game_state.get("line_edit_mode", false)
	var color = Color(1.0, 0.85, 0.2) if is_active else Color(0.5, 0.5, 0.55, 0.8)
	
	var sz = line_edit_indicator.size
	if sz.x < 5 or sz.y < 5:
		sz = Vector2(40, 40)  # фикс: Control без Container может иметь size 0
	var cx = sz.x / 2.0
	# Молния (масштаб под размер): верх -> правый зиг -> левый -> кончик -> ветка вверх -> обратно
	var pts = PackedVector2Array([
		Vector2(cx, 3),
		Vector2(cx + sz.x * 0.35, sz.y * 0.35),
		Vector2(cx - sz.x * 0.2, sz.y * 0.48),
		Vector2(cx + sz.x * 0.25, sz.y - 3),
		Vector2(cx, sz.y * 0.55),
		Vector2(cx - sz.x * 0.35, sz.y * 0.2),
		Vector2(cx, 3)
	])
	line_edit_indicator.draw_polyline(pts, color, 2.5)

func _on_line_edit_clicked():
	var phase = GameManager.ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	if phase != GameTypes.GamePhase.BUILD_STATE and phase != GameTypes.GamePhase.TOWER_SELECTION_STATE:
		return
	var was_on = GameManager.ecs.game_state.get("line_edit_mode", false)
	GameManager.ecs.game_state["line_edit_mode"] = not was_on
	if was_on and GameManager.line_drag_handler:
		GameManager.line_drag_handler.cancel_line_drag()
	print("[HUD] Line edit mode: %s" % GameManager.ecs.game_state["line_edit_mode"])

func _on_recipe_button_pressed():
	if GameManager.recipe_book:
		GameManager.recipe_book.toggle()

func _on_state_indicator_clicked():
	# Индикатор фазы кликабелен только в режиме разработчика (I)
	if not GameManager.ecs.game_state.get("developer_mode", false):
		return
	if GameManager.ecs.game_state.get("game_over", false):
		return
	
	var current_phase = GameManager.ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	
	if GameManager.phase_controller:
		GameManager.phase_controller.cycle_phase()
		
		# Дополнительные UI действия при переходе SELECTION → WAVE
		if current_phase == GameTypes.GamePhase.TOWER_SELECTION_STATE:
			# Закрываем InfoPanel
			if GameManager.info_panel:
				GameManager.info_panel.hide_panel()
			
			# Снимаем выделение
			if GameManager.input_system:
				GameManager.input_system.clear_highlight()
	else:
		push_warning("[HUD] PhaseController not available")
	
	# Обновляем кружок
	state_indicator.queue_redraw()

# ============================================================================
# УДАЛЕНО: Логика переходов фаз теперь в PhaseController
# ============================================================================
# _clear_enemies(), _clear_projectiles(), _remove_unselected_towers(), _create_permanent_wall()
# Используйте GameManager.phase_controller для управления фазами

func _on_speed_clicked():
	GameManager.cycle_time_speed()

func _on_pause_clicked():
	GameManager.toggle_pause()

func _on_pause_continue_clicked():
	GameManager.toggle_pause()

func _on_pause_restart_clicked():
	GameManager.request_restart_game()

func _on_pause_menu_clicked():
	GameManager.request_exit_to_menu()

# ============================================================================
# ОТРИСОВКА КНОПОК (КАК В GO)
# ============================================================================

func _draw_speed_button():
	var ecs = GameManager.ecs
	var speed = ecs.game_state.get("time_speed", 1.0)
	
	# Цвет в зависимости от скорости
	var color = Config.BUILD_STATE_COLOR
	if speed <= 1.0:
		color = Config.BUILD_STATE_COLOR
	elif speed <= 2.0:
		color = Config.SELECTION_STATE_COLOR
	else:
		color = Config.WAVE_STATE_COLOR
	
	# Два треугольника >> (как в Go)
	var size = speed_button.custom_minimum_size
	var center = size / 2
	var tri_size = 12.0
	var tri_height = tri_size * 1.2
	var tri_width = tri_size
	var tri_offset = tri_width * 0.8
	
	# Левый треугольник
	var p1_left = Vector2(center.x - tri_width, center.y - tri_height/2)
	var p2_left = Vector2(center.x, center.y)
	var p3_left = Vector2(center.x - tri_width, center.y + tri_height/2)
	speed_button.draw_colored_polygon(PackedVector2Array([p1_left, p2_left, p3_left]), color)
	speed_button.draw_polyline(PackedVector2Array([p1_left, p2_left, p3_left, p1_left]), Color.WHITE, 2.0)
	
	# Правый треугольник
	var p1_right = Vector2(center.x - tri_width + tri_offset, center.y - tri_height/2)
	var p2_right = Vector2(center.x + tri_offset, center.y)
	var p3_right = Vector2(center.x - tri_width + tri_offset, center.y + tri_height/2)
	speed_button.draw_colored_polygon(PackedVector2Array([p1_right, p2_right, p3_right]), color)
	speed_button.draw_polyline(PackedVector2Array([p1_right, p2_right, p3_right, p1_right]), Color.WHITE, 2.0)

func _draw_pause_button():
	var ecs = GameManager.ecs
	var is_paused = ecs.game_state.get("paused", false)
	
	var size = pause_button.custom_minimum_size
	var center = size / 2
	var rect_size = 15.0
	
	if is_paused:
		# Треугольник (play) - когда на паузе показываем play
		var tri_height = rect_size * 1.5
		var tri_width = rect_size * 1.2
		var p1 = Vector2(center.x - tri_width*0.4, center.y - tri_height/2)
		var p2 = Vector2(center.x - tri_width*0.4, center.y + tri_height/2)
		var p3 = Vector2(center.x + tri_width*0.6, center.y)
		pause_button.draw_colored_polygon(PackedVector2Array([p1, p2, p3]), Config.PAUSE_BUTTON_PLAY_COLOR)
		pause_button.draw_polyline(PackedVector2Array([p1, p2, p3, p1]), Color.WHITE, 2.0)
	else:
		# Два прямоугольника (pause) - когда играет показываем pause
		var rect_width = rect_size * 0.4
		var rect_height = rect_size * 1.3
		var spacing = rect_size * 0.3
		
		var left_rect = Rect2(center.x - rect_width - spacing/2, center.y - rect_height/2, rect_width, rect_height)
		var right_rect = Rect2(center.x + spacing/2, center.y - rect_height/2, rect_width, rect_height)
		
		pause_button.draw_rect(left_rect, Config.PAUSE_BUTTON_PAUSE_COLOR)
		pause_button.draw_rect(right_rect, Config.PAUSE_BUTTON_PAUSE_COLOR)
		
		pause_button.draw_rect(left_rect, Color.WHITE, false, 2.0)
		pause_button.draw_rect(right_rect, Color.WHITE, false, 2.0)

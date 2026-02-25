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
var ore_sector_indicator: Control  # Бар руды в сети (заполнение = сколько израсходовано)
var ore_ore_label: Label  # Подпись "X / Y" к бару руды (то же, что в get_ore_network_totals)
var top5_damage_label: RichTextLabel  # Топ-5 вышек по урону за волну (во время волны); красная подсветка для топа и MVP 5
var fps_label: Label  # FPS над кнопками паузы и ускорения
var tutorial_hint_panel: Control = null  # Панель подсказки обучения (внизу по центру)
var tutorial_hint_label: Label = null
var tutorial_hint_next_btn: Button = null

# Кэш руды в сети для HUD: get_all_networks_ore_totals() тяжёлый — не вызывать каждый кадр
var _ore_totals_cache: Dictionary = {}
var _ore_totals_cache_time: float = -1.0
const ORE_CACHE_INTERVAL: float = 0.25  # обновлять не чаще раза в 0.25 сек

func _ready():
	_create_ui()
	call_deferred("_log_recipe_button_rect_once")

func _log_recipe_button_rect_once():
	"""Один раз в лог: где находится зона кнопки Рецепты (глобальный rect). Выключено — включать при отладке UI."""
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

	# Индикатор руды: бар = израсходовано (1 - осталось/макс), подпись "X / Y"
	var ore_width := 120.0
	var ore_bar_h := 20.0
	ore_sector_indicator = Control.new()
	ore_sector_indicator.position = Vector2(Config.SCREEN_WIDTH - 10 - ore_width, 140)
	ore_sector_indicator.custom_minimum_size = Vector2(ore_width, ore_bar_h)
	ore_sector_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ore_sector_indicator.draw.connect(_draw_ore_sector_indicator.bind(ore_sector_indicator))
	add_child(ore_sector_indicator)
	ore_ore_label = Label.new()
	ore_ore_label.position = Vector2(Config.SCREEN_WIDTH - 10 - ore_width, 162)
	ore_ore_label.add_theme_font_size_override("font_size", 11)
	ore_ore_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	ore_ore_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ore_ore_label)

	# Молния (⚡) — режим редактирования энерголиний, размер как у паузы/скорости
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

func _process(_delta):
	_update_ui()
	state_indicator.queue_redraw()
	speed_button.queue_redraw()
	pause_button.queue_redraw()
	line_edit_indicator.queue_redraw()
	
	# Обновляем видимость оверлея паузы и панели кнопок
	var is_paused = GameManager.ecs.game_state.get("paused", false)
	pause_overlay.visible = is_paused
	pause_panel.visible = is_paused

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
	
	# Врагов: убито за всё время | живых сейчас / размер волны
	var total_kills = ecs.game_state.get("total_enemies_killed", 0)
	var alive = _count_alive_enemies()
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
	
	# FPS над кнопками паузы и ускорения
	var fps = Engine.get_frames_per_second()
	var frame_time = 1000.0 / fps if fps > 0 else 0.0
	fps_label.text = "FPS: %d (%.1f ms)" % [fps, frame_time]
	if fps >= 60:
		fps_label.add_theme_color_override("font_color", Color.GREEN)
	elif fps >= 30:
		fps_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		fps_label.add_theme_color_override("font_color", Color.RED)

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
			var lines: Array[String] = ["Урон (волна %d):" % wave_num]
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
	
	if GameManager and ore_ore_label:
		# Тяжёлый get_all_networks_ore_totals — кэшируем, обновляем не чаще ORE_CACHE_INTERVAL
		var now = Time.get_ticks_msec() / 1000.0
		if now - _ore_totals_cache_time >= ORE_CACHE_INTERVAL or _ore_totals_cache.is_empty():
			if GameManager.energy_network:
				_ore_totals_cache = GameManager.energy_network.get_all_networks_ore_totals()
			else:
				_ore_totals_cache = GameManager.get_ore_network_totals()
			_ore_totals_cache_time = now
		var totals = _ore_totals_cache
		ore_ore_label.text = "Руда: %.0f / %.0f" % [totals.get("total_current", 0.0), totals.get("total_max", 0.0)]

func _count_alive_enemies() -> int:
	"""Количество живых врагов на карте (для счётчика в HUD)."""
	var count = 0
	var ecs = GameManager.ecs
	if not ecs:
		return 0
	for enemy_id in ecs.enemies.keys():
		var health = ecs.healths.get(enemy_id)
		if health and health.get("current", 0) > 0:
			count += 1
	return count

func _draw_ore_sector_indicator(canvas: Control):
	# Бар = осталось в сети / макс (то же, что на майнере — по сетям). Используем кэш, не вызываем get_all_networks_ore_totals здесь.
	var total_width := 120.0
	var bar_height := 20.0
	var ratio := 1.0
	var totals = _ore_totals_cache
	if not totals.is_empty():
		var tmax = totals.get("total_max", 0.0)
		if tmax > 0.0:
			ratio = clampf(totals.get("total_current", 0.0) / tmax, 0.0, 1.0)
	ratio = clampf(ratio, 0.0, 1.0)
	# Фон (тёмный)
	canvas.draw_rect(Rect2(0, 0, total_width, bar_height), Color(0.15, 0.15, 0.2, 0.95))
	# Заполнение синим = осталось (X / Y из подписи — то же самое)
	var fill_w := total_width * ratio
	if fill_w > 0.5:
		canvas.draw_rect(Rect2(0, 0, fill_w, bar_height), Color(0.25, 0.5, 0.9, 0.95))
	# Рамка
	var border := 2
	canvas.draw_rect(Rect2(0, 0, total_width, border), Color(0.4, 0.45, 0.55))
	canvas.draw_rect(Rect2(0, bar_height - border, total_width, border), Color(0.4, 0.45, 0.55))
	canvas.draw_rect(Rect2(0, 0, border, bar_height), Color(0.4, 0.45, 0.55))
	canvas.draw_rect(Rect2(total_width - border, 0, border, bar_height), Color(0.4, 0.45, 0.55))

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
	print("[HUD] State indicator clicked")
	
	var current_phase = GameManager.ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	
	# Используем PhaseController для переходов
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

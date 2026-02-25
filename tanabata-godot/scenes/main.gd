# main.gd
# Главная сцена игры
extends Node

var _menu: Control
var _game_root: Node2D
var _tutorial_level_select: Control = null
var _tutorial_complete_popup: Node = null  # CanvasLayer с попапом победы
var _tutorial_completed_index: int = -1

func _ready():
	GameManager.exit_to_menu_requested.connect(_on_exit_to_menu)
	GameManager.restart_game_requested.connect(_on_restart_game)
	GameManager.tutorial_level_completed.connect(_on_tutorial_level_completed)
	_show_menu()

func _show_menu():
	if _game_root:
		_game_root.queue_free()
		_game_root = null
	if _tutorial_level_select and is_instance_valid(_tutorial_level_select):
		if _tutorial_level_select.get_parent() == self:
			remove_child(_tutorial_level_select)
	_menu = preload("res://scenes/menu.tscn").instantiate()
	_menu.start_game_pressed.connect(_on_start_game)
	_menu.tutorial_pressed.connect(_on_tutorial_pressed)
	_menu.exit_pressed.connect(_on_exit)
	add_child(_menu)

func _on_start_game():
	if _menu:
		_menu.queue_free()
		_menu = null
	GameManager.ecs.game_state["difficulty"] = GameManager.difficulty
	_game_root = preload("res://scenes/game_root.tscn").instantiate()
	add_child(_game_root)

func _on_tutorial_pressed():
	if _menu:
		_menu.queue_free()
		_menu = null
	if _tutorial_level_select == null:
		_tutorial_level_select = _build_tutorial_level_select()
	add_child(_tutorial_level_select)

func _build_tutorial_level_select() -> Control:
	var panel = Control.new()
	panel.name = "TutorialLevelSelect"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.12, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(bg)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -140
	vbox.offset_top = -200
	vbox.offset_right = 140
	vbox.offset_bottom = 200
	panel.add_child(vbox)
	var title = Label.new()
	title.text = "Обучение"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var levels = LevelConfig.get_tutorial_levels()
	for i in range(levels.size()):
		var cfg = levels[i]
		var btn = Button.new()
		btn.text = "%d. %s" % [i + 1, cfg.get(LevelConfig.KEY_TITLE, "Уровень %d" % (i + 1))]
		btn.custom_minimum_size = Vector2(280, 44)
		var level_index = i
		btn.pressed.connect(func(): _start_tutorial_level(level_index))
		vbox.add_child(btn)
	var back_btn = Button.new()
	back_btn.text = "Назад"
	back_btn.custom_minimum_size = Vector2(280, 44)
	back_btn.pressed.connect(_on_tutorial_back)
	vbox.add_child(back_btn)
	return panel

func _on_tutorial_back():
	if _tutorial_level_select and is_instance_valid(_tutorial_level_select) and _tutorial_level_select.get_parent() == self:
		remove_child(_tutorial_level_select)
	_show_menu()

func _start_tutorial_level(index: int):
	if _tutorial_level_select and is_instance_valid(_tutorial_level_select) and _tutorial_level_select.get_parent() == self:
		remove_child(_tutorial_level_select)
	var level_config = LevelConfig.get_tutorial_level(index)
	GameManager.reinit_game(level_config)
	GameManager.ecs.game_state["difficulty"] = GameManager.difficulty
	_game_root = preload("res://scenes/game_root.tscn").instantiate()
	add_child(_game_root)

func _on_tutorial_level_completed(tutorial_index: int):
	_tutorial_completed_index = tutorial_index
	_show_tutorial_complete_popup()

func _show_tutorial_complete_popup():
	if _tutorial_complete_popup and is_instance_valid(_tutorial_complete_popup):
		GameManager.ecs.game_state["tutorial_complete_popup_visible"] = false
		_tutorial_complete_popup.queue_free()
	# Как пауза: CanvasLayer поверх всего, экранные координаты, кнопки работают
	var layer = CanvasLayer.new()
	layer.name = "TutorialCompleteLayer"
	layer.layer = 100
	var root = Control.new()
	root.name = "TutorialCompletePopup"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP  # перехватывать все клики, не пускать в игру
	var view_size = get_viewport().get_visible_rect().size
	root.set_size(view_size)
	layer.add_child(root)
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_position(Vector2.ZERO)
	overlay.set_size(view_size)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(overlay)
	var pw = 360
	var ph = 220
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_position(Vector2(view_size.x / 2.0 - pw / 2.0, view_size.y / 2.0 - ph / 2.0))
	panel.set_size(Vector2(pw, ph))
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.13, 0.18, 0.98)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.45, 0.5, 0.6)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	root.add_child(panel)
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	margin.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(margin)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_child(vbox)
	var title = Label.new()
	title.text = LevelConfig.get_tutorial_level(_tutorial_completed_index).get(LevelConfig.KEY_TITLE, "Обучение")
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)
	var lbl = Label.new()
	lbl.text = "ВЫ ПОБЕДИЛИ!"
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(lbl)
	var idx = _tutorial_completed_index
	if idx >= 0 and idx < 4:
		var next_btn = Button.new()
		next_btn.text = "Дальше"
		next_btn.custom_minimum_size = Vector2(200, 44)
		next_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var next_idx = idx
		next_btn.pressed.connect(func(): _on_tutorial_next_level(next_idx))
		vbox.add_child(next_btn)
	var menu_btn = Button.new()
	menu_btn.text = "В меню"
	menu_btn.custom_minimum_size = Vector2(200, 44)
	menu_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_btn.pressed.connect(_on_tutorial_complete_back_to_menu)
	vbox.add_child(menu_btn)
	_tutorial_complete_popup = layer
	add_child(layer)
	GameManager.ecs.game_state["tutorial_complete_popup_visible"] = true

func _on_tutorial_next_level(completed_index: int):
	GameManager.ecs.game_state["tutorial_complete_popup_visible"] = false
	if _tutorial_complete_popup and is_instance_valid(_tutorial_complete_popup):
		remove_child(_tutorial_complete_popup)
		_tutorial_complete_popup.queue_free()
		_tutorial_complete_popup = null
	_remove_game_root()
	var next_index = completed_index + 1
	GameManager.reinit_game(LevelConfig.get_tutorial_level(next_index))
	GameManager.ecs.game_state["difficulty"] = GameManager.difficulty
	_game_root = preload("res://scenes/game_root.tscn").instantiate()
	add_child(_game_root)

func _on_tutorial_complete_back_to_menu():
	GameManager.ecs.game_state["tutorial_complete_popup_visible"] = false
	if _tutorial_complete_popup and is_instance_valid(_tutorial_complete_popup):
		remove_child(_tutorial_complete_popup)
		_tutorial_complete_popup.queue_free()
		_tutorial_complete_popup = null
	_remove_game_root()
	GameManager.reinit_game()
	_show_menu()

func _on_exit():
	get_tree().quit()

func _on_exit_to_menu():
	if _tutorial_complete_popup and is_instance_valid(_tutorial_complete_popup):
		if _tutorial_complete_popup.get_parent() == self:
			remove_child(_tutorial_complete_popup)
		_tutorial_complete_popup.queue_free()
		_tutorial_complete_popup = null
	_remove_game_root()
	GameManager.reinit_game()
	_show_menu()

func _on_restart_game():
	_remove_game_root()
	# В обучении — перезапуск текущего уровня обучения; в основной игре — заново основная игра
	var cfg = GameManager.current_level_config
	if cfg.get(LevelConfig.KEY_IS_TUTORIAL, false):
		GameManager.reinit_game(cfg)
		GameManager.ecs.game_state["difficulty"] = GameManager.difficulty
		_game_root = preload("res://scenes/game_root.tscn").instantiate()
		add_child(_game_root)
	else:
		GameManager.reinit_game()
		_on_start_game()

func _remove_game_root():
	if _game_root:
		# Удаляем из дерева СРАЗУ, чтобы старый GameRoot не выполнял _process
		# в том же кадре, что и новый (иначе старый combat_system с устаревшим ECS
		# может конфликтовать с новой энергосетью и вызывать баг «первая башня не стреляет»)
		remove_child(_game_root)
		_game_root.queue_free()
		_game_root = null

func _input(event):
	# Глобальные горячие клавиши
	if event.is_action_pressed("ui_pause"):
		GameManager.toggle_pause()
	
	# F10 - God Mode
	if event is InputEventKey and event.pressed and event.keycode == KEY_F10:
		GameManager.toggle_god_mode()
	
	# F3 - Visual Debug
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		GameManager.toggle_visual_debug()
	
	# F12 - Print State
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		GameManager.print_game_state()

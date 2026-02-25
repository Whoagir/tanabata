# menu.gd
# Главное меню: сложность, "Начать игру", "Выход"
# Портировано из Go: internal/state/menu_state.go
extends Control

signal start_game_pressed
signal exit_pressed
signal tutorial_pressed

var _difficulty_option: OptionButton = null

func _ready():
	# Заполняем весь экран
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	_build_ui()

func _build_ui():
	# Затемнённый фон
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.1, 0.1, 0.12, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# Заголовок
	var title = Label.new()
	title.name = "Title"
	title.text = "Tanabata"
	title.add_theme_font_size_override("font_size", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(title)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 180
	title.offset_left = -150
	title.offset_right = 150
	title.offset_bottom = 250
	
	# Контейнер для кнопок (по центру)
	var vbox = VBoxContainer.new()
	vbox.name = "Buttons"
	vbox.add_theme_constant_override("separation", 20)
	add_child(vbox)
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -110
	vbox.offset_top = -130
	vbox.offset_right = 110
	vbox.offset_bottom = 130
	
	# Сложность: подпись + OptionButton
	var diff_hbox = HBoxContainer.new()
	diff_hbox.add_theme_constant_override("separation", 12)
	var diff_label = Label.new()
	diff_label.text = "Сложность:"
	diff_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	diff_hbox.add_child(diff_label)
	_difficulty_option = OptionButton.new()
	_difficulty_option.custom_minimum_size = Vector2(180, 36)
	_difficulty_option.add_item("Лёгкая (Easy)", GameTypes.Difficulty.EASY)
	_difficulty_option.add_item("Средняя (Medium)", GameTypes.Difficulty.MEDIUM)
	_difficulty_option.add_item("Сложная (Hard)", GameTypes.Difficulty.HARD)
	_difficulty_option.selected = GameTypes.Difficulty.MEDIUM
	diff_hbox.add_child(_difficulty_option)
	vbox.add_child(diff_hbox)
	
	# Кнопка "Начать игру"
	var start_btn = Button.new()
	start_btn.name = "StartButton"
	start_btn.text = "Начать игру"
	start_btn.custom_minimum_size = Vector2(220, 50)
	start_btn.pressed.connect(_on_start_pressed)
	vbox.add_child(start_btn)
	
	# Кнопка "Обучение"
	var tutorial_btn = Button.new()
	tutorial_btn.name = "TutorialButton"
	tutorial_btn.text = "Обучение"
	tutorial_btn.custom_minimum_size = Vector2(220, 50)
	tutorial_btn.pressed.connect(_on_tutorial_pressed)
	vbox.add_child(tutorial_btn)
	
	# Кнопка "Выход"
	var exit_btn = Button.new()
	exit_btn.name = "ExitButton"
	exit_btn.text = "Выход"
	exit_btn.custom_minimum_size = Vector2(220, 50)
	exit_btn.pressed.connect(_on_exit_pressed)
	vbox.add_child(exit_btn)

func _on_start_pressed():
	GameManager.difficulty = _difficulty_option.get_selected_id()
	start_game_pressed.emit()

func _on_tutorial_pressed():
	GameManager.difficulty = _difficulty_option.get_selected_id()
	tutorial_pressed.emit()

func _on_exit_pressed():
	exit_pressed.emit()

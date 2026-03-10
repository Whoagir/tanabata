# recipe_book.gd
# Панель с таблицей рецептов крафта (книга рецептов)
# Портировано из Go: internal/ui/recipe_book.go
# Открывается по клавише B или по кнопке "Рецепты"
extends Control

var _panel: Panel
var _scroll: ScrollContainer
var _recipe_column_left: VBoxContainer
var _recipe_column_right: VBoxContainer
var _close_button: Button

const PANEL_WIDTH = 980
const PANEL_HEIGHT = 630
const COLUMN_SEPARATION = 12
const RECIPE_ENTRY_HEIGHT = 28
const PADDING = 12
const TITLE_FONT_SIZE = 20
const ENTRY_FONT_SIZE = 16
# Цвета: контрастные на тёмном фоне (синий / белый / серый)
const BLUE = Color(0.25, 0.6, 1.0)
const WHITE = Color(1.0, 1.0, 1.0)
const GRAY_NO_TOWER = Color(0.38, 0.38, 0.42)
const GRAY_CANNOT_CRAFT = Color(0.45, 0.45, 0.5)
const LIGHT_NEUTRAL = Color(0.9, 0.93, 0.98)
const UNDERLINE_HEIGHT = 2

func _ready():
	# Полный экран, блокируем все клики
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# CanvasLayer-дети в Godot 4 должны сами задать размер — используем viewport
	var vs = Vector2(Config.SCREEN_WIDTH, Config.SCREEN_HEIGHT)
	# На случай если viewport уже доступен и другой размер
	if get_viewport():
		vs = get_viewport().get_visible_rect().size
	offset_right = vs.x
	offset_bottom = vs.y
	_build_ui()
	visible = false

func _build_ui():
	# Затемнённый фон — перехватывает клики и закрывает по клику
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0, 0, 0, 0.5)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_bg_input)
	add_child(bg)

	# Центрируем панель
	var center_x = (Config.SCREEN_WIDTH - PANEL_WIDTH) / 2.0
	var center_y = (Config.SCREEN_HEIGHT - PANEL_HEIGHT) / 2.0

	_panel = Panel.new()
	_panel.position = Vector2(center_x, center_y)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.98)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.6, 1.0)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PADDING)
	margin.add_theme_constant_override("margin_top", PADDING)
	margin.add_theme_constant_override("margin_right", PADDING)
	margin.add_theme_constant_override("margin_bottom", PADDING)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Заголовок
	var title = Label.new()
	title.text = "Рецепты крафта"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Скролл с рецептами (mouse_filter STOP чтобы ловить колёсико)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 500)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(_scroll)

	var columns_hbox = HBoxContainer.new()
	columns_hbox.add_theme_constant_override("separation", COLUMN_SEPARATION)
	columns_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns_hbox.custom_minimum_size.x = PANEL_WIDTH - PADDING * 4
	_scroll.add_child(columns_hbox)

	_recipe_column_left = VBoxContainer.new()
	_recipe_column_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_column_left.custom_minimum_size.x = (PANEL_WIDTH - PADDING * 4 - COLUMN_SEPARATION) / 2
	columns_hbox.add_child(_recipe_column_left)

	_recipe_column_right = VBoxContainer.new()
	_recipe_column_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_column_right.custom_minimum_size.x = (PANEL_WIDTH - PADDING * 4 - COLUMN_SEPARATION) / 2
	columns_hbox.add_child(_recipe_column_right)

	# Подсказка
	var hint = Label.new()
	hint.text = "Закрыть: B или Escape"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	vbox.add_child(hint)

	# Кнопка закрыть
	_close_button = Button.new()
	_close_button.text = "Закрыть"
	_close_button.pressed.connect(toggle)
	vbox.add_child(_close_button)

	_populate_recipes()

func _populate_recipes():
	for child in _recipe_column_left.get_children():
		child.queue_free()
	for child in _recipe_column_right.get_children():
		child.queue_free()

	var recipes = DataRepository.recipe_defs
	if not recipes is Array:
		return

	var available = _get_available_tower_counts()
	var entries: Array = []

	for recipe in recipes:
		var inputs = recipe.get("inputs", [])
		var output_id = recipe.get("output_id", "")
		if output_id.is_empty():
			continue
		var out_def = DataRepository.get_tower_def(output_id)
		# В книге рецептов только вышки уровня крафта 1 (Сильвер, Малахит, Джейд и т.д.)
		if out_def.get("crafting_level", 0) < 1:
			continue

		var input_ids: Array[String] = []
		var can_craft = true
		for inp in inputs:
			var tid = inp.get("id", "")
			if tid.is_empty():
				continue
			input_ids.append(tid)
			var count = available.get(tid, 0)
			if count < 1:
				can_craft = false

		var out_name = _display_name_for_def_id(output_id)
		var base_color = LIGHT_NEUTRAL if can_craft else GRAY_CANNOT_CRAFT
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 4)
		for i in range(input_ids.size()):
			if i > 0:
				var plus = Label.new()
				plus.text = "+"
				plus.add_theme_font_size_override("font_size", ENTRY_FONT_SIZE)
				plus.add_theme_color_override("font_color", base_color)
				hbox.add_child(plus)
			var tid = input_ids[i]
			var have = available.get(tid, 0) >= 1
			var from_this_phase = _is_def_id_only_from_this_phase(tid)
			var both_saved_and_this_wave = _has_both_saved_and_this_phase(tid)
			var lbl = Label.new()
			lbl.text = _display_name_for_def_id(tid)
			lbl.add_theme_font_size_override("font_size", ENTRY_FONT_SIZE)
			if have and from_this_phase:
				lbl.add_theme_color_override("font_color", BLUE)
				hbox.add_child(lbl)
			elif have and both_saved_and_this_wave:
				lbl.add_theme_color_override("font_color", WHITE)
				hbox.add_child(_make_underline_wrapper(lbl))
			elif have:
				lbl.add_theme_color_override("font_color", WHITE)
				hbox.add_child(lbl)
			else:
				lbl.add_theme_color_override("font_color", GRAY_NO_TOWER)
				hbox.add_child(lbl)
		var eq = Label.new()
		eq.text = "= "
		eq.add_theme_font_size_override("font_size", ENTRY_FONT_SIZE)
		eq.add_theme_color_override("font_color", base_color)
		hbox.add_child(eq)
		var have_out = available.get(output_id, 0) >= 1
		var out_from_this_phase = _is_def_id_only_from_this_phase(output_id)
		var out_both = _has_both_saved_and_this_phase(output_id)
		var out_lbl = Label.new()
		out_lbl.text = out_name
		out_lbl.add_theme_font_size_override("font_size", ENTRY_FONT_SIZE)
		if have_out and out_from_this_phase:
			out_lbl.add_theme_color_override("font_color", BLUE)
			hbox.add_child(out_lbl)
		elif have_out and out_both:
			out_lbl.add_theme_color_override("font_color", WHITE)
			hbox.add_child(_make_underline_wrapper(out_lbl))
		elif have_out:
			out_lbl.add_theme_color_override("font_color", WHITE)
			hbox.add_child(out_lbl)
		else:
			out_lbl.add_theme_color_override("font_color", GRAY_NO_TOWER)
			hbox.add_child(out_lbl)
		entries.append(hbox)

	var half = ceili(entries.size() / 2.0)
	for i in range(entries.size()):
		if i < half:
			_recipe_column_left.add_child(entries[i])
		else:
			_recipe_column_right.add_child(entries[i])

func _display_name_for_def_id(def_id: String) -> String:
	"""Для отображения в книге рецептов: TOWER_* и прочие крафтовые показываем по-русски из towers.json, остальное как есть."""
	if def_id.begins_with("TOWER_"):
		var d = DataRepository.get_tower_def(def_id)
		if not d.is_empty():
			var name_str = d.get("name", "")
			if not name_str.is_empty():
				return name_str
	return def_id

func _make_underline_wrapper(lbl: Label) -> Control:
	"""Контейнер: лейбл + синяя линия снизу (сохранённая вышка + поставлена в этой волне)."""
	var v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(lbl)
	var line = ColorRect.new()
	line.custom_minimum_size = Vector2(0, UNDERLINE_HEIGHT)
	line.color = WHITE
	v.add_child(line)
	return v

func _get_available_tower_counts() -> Dictionary:
	"""Считает башни на карте по def_id (игнорируем стены)."""
	var counts: Dictionary = {}
	if not GameManager.ecs:
		return counts
	var towers = GameManager.ecs.towers
	for entity_id in towers:
		var t = towers[entity_id]
		var def_id = t.get("def_id", "")
		if def_id.is_empty() or def_id == "TOWER_WALL":
			continue
		counts[def_id] = counts.get(def_id, 0) + 1
	return counts

func _is_def_id_only_from_this_phase(def_id: String) -> bool:
	"""True если на карте есть башня с def_id только среди построенных в этой фазе (is_temporary). Приоритет: если есть хоть одна постоянная — белый."""
	if not GameManager.ecs:
		return false
	var has_temporary = false
	var has_permanent = false
	for entity_id in GameManager.ecs.towers:
		var t = GameManager.ecs.towers[entity_id]
		if t.get("def_id", "") != def_id:
			continue
		if t.get("is_temporary", false):
			has_temporary = true
		else:
			has_permanent = true
	return has_temporary and not has_permanent

func _has_both_saved_and_this_phase(def_id: String) -> bool:
	"""True если на карте есть и постоянная, и временная (этой волны) башня с def_id."""
	if not GameManager.ecs:
		return false
	var has_temporary = false
	var has_permanent = false
	for entity_id in GameManager.ecs.towers:
		var t = GameManager.ecs.towers[entity_id]
		if t.get("def_id", "") != def_id:
			continue
		if t.get("is_temporary", false):
			has_temporary = true
		else:
			has_permanent = true
	return has_temporary and has_permanent

func _on_bg_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		toggle()
		get_viewport().set_input_as_handled()

func toggle():
	visible = !visible
	if visible:
		_populate_recipes()

func _input(event: InputEvent):
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			toggle()
			get_viewport().set_input_as_handled()

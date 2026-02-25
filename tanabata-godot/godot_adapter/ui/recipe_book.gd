# recipe_book.gd
# Панель с таблицей рецептов крафта (книга рецептов)
# Портировано из Go: internal/ui/recipe_book.go
# Открывается по клавише B или по кнопке "Рецепты"
extends Control

var _panel: Panel
var _scroll: ScrollContainer
var _recipe_vbox: VBoxContainer
var _close_button: Button

const PANEL_WIDTH = 700
const PANEL_HEIGHT = 420
const RECIPE_ENTRY_HEIGHT = 28
const PADDING = 12
const TITLE_FONT_SIZE = 20
const ENTRY_FONT_SIZE = 16

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
	_scroll.custom_minimum_size = Vector2(0, 300)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(_scroll)

	_recipe_vbox = VBoxContainer.new()
	_recipe_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_vbox.custom_minimum_size.x = PANEL_WIDTH - PADDING * 4  # Широко, чтобы рецепты в одну строку
	_scroll.add_child(_recipe_vbox)

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
	for child in _recipe_vbox.get_children():
		child.queue_free()

	var recipes = DataRepository.recipe_defs
	if not recipes is Array:
		return

	var available = _get_available_tower_counts()

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

		var out_name = out_def.get("name", output_id) if not out_def.is_empty() else output_id
		# Подсветка: белый = уже есть с прошлых фаз, голубой = только построены в этой фазе
		var parts: Array[String] = []
		for i in range(input_ids.size()):
			var tid = input_ids[i]
			var have = available.get(tid, 0) >= 1
			var from_this_phase = _is_def_id_only_from_this_phase(tid)
			var col = "[color=#6eb8ff]" if (have and from_this_phase) else ("[color=#ffffff]" if have else "[color=#8c8c99]")
			parts.append(col + tid + "[/color]")
		var line_bb = " + ".join(parts) + " = "
		var have_out = available.get(output_id, 0) >= 1
		var out_from_this_phase = _is_def_id_only_from_this_phase(output_id)
		if have_out:
			line_bb += ("[color=#6eb8ff]" + out_name + "[/color]") if out_from_this_phase else ("[color=#ffffff]" + out_name + "[/color]")
		else:
			line_bb += "[color=#8c8c99]" + out_name + "[/color]"

		var rtl = RichTextLabel.new()
		rtl.bbcode_enabled = true
		rtl.text = line_bb
		rtl.fit_content = true
		rtl.scroll_active = false
		rtl.add_theme_font_size_override("normal_font_size", ENTRY_FONT_SIZE)
		if can_craft:
			rtl.add_theme_color_override("default_color", Color(0.85, 0.9, 0.95))
		else:
			rtl.add_theme_color_override("default_color", Color(0.55, 0.55, 0.6))
		_recipe_vbox.add_child(rtl)

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

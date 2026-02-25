# info_panel.gd
# UI плашка с информацией о выбранной башне/враге
# Портировано из Go: internal/ui/info_panel.go
extends Control

var ecs: ECSWorld
var selected_entity_id: int = -1
var is_visible_flag: bool = false

# UI элементы
var panel: Panel
var header_hbox: HBoxContainer
var title_label: Label
var info_icon: Label  # Буква "i" рядом с названием
var content_section: Control  # Описание — показывается при наведении
var info_vbox: VBoxContainer
var scroll_container: ScrollContainer
var buttons_hbox: HBoxContainer
var select_button: Button
var craft_button: Button
var craft_button_2: Button  # Второй вариант крафта (другое здание)
var simplify_button: Button  # Упростить (даунгрейд на случайный уровень ниже, 3 руды)
var x2_button: Button
var x4_button: Button
var close_button: Button  # Крестик — закрыть панель выбора
var _pending_craft: Dictionary = {}
var _pending_craft_2: Dictionary = {}  # Второй рецепт (3 башни, другое здание)
var _pending_craft_x2: Dictionary = {}
var _pending_craft_x4: Dictionary = {}
var _hover_timer: Timer

# Окошко слева — фиксированный размер, никогда не растёт при наведении
const PANEL_HEIGHT = 240
const PANEL_WIDTH = 600
# Вкладыш с доп. описанием (при наведении на "i")
const INFO_BLOCK_WIDTH = 570
const INFO_CONTENT_HEIGHT = 120
const INFO_SCROLL_HEIGHT = 96
const PANEL_MARGIN = 5
const BUTTON_HEIGHT = 40

func _ready():
	ecs = GameManager.ecs
	
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Корень: клики проходят сквозь пустые области (карта остаётся кликабельной)
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Плашка внизу слева (без общего бекграунда — только квадратик с инфой)
	panel = Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 15
	panel.offset_top = -PANEL_HEIGHT - 15
	panel.offset_right = 15 + PANEL_WIDTH
	panel.offset_bottom = -15
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.15, 0.92)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.4, 0.4, 0.5, 1.0)
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)
	
	var margin_container = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_left", 15)
	margin_container.add_theme_constant_override("margin_top", 12)
	margin_container.add_theme_constant_override("margin_right", 15)
	margin_container.add_theme_constant_override("margin_bottom", 12)
	margin_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin_container.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(margin_container)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	margin_container.add_child(vbox)
	
	# Заголовок: [Название] [i] — фиксирован, не двигается
	header_hbox = HBoxContainer.new()
	header_hbox.custom_minimum_size = Vector2(0, 32)
	header_hbox.add_theme_constant_override("separation", 6)
	header_hbox.mouse_filter = Control.MOUSE_FILTER_STOP
	header_hbox.mouse_entered.connect(_on_header_hover_enter)
	header_hbox.mouse_exited.connect(_on_header_hover_exit)
	vbox.add_child(header_hbox)
	
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_hbox.add_child(title_label)
	
	# Буква i (без смайлов)
	var icon_center = CenterContainer.new()
	icon_center.custom_minimum_size = Vector2(24, 24)
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_hbox.add_child(icon_center)
	info_icon = Label.new()
	info_icon.text = "i"
	info_icon.add_theme_font_size_override("font_size", 14)
	info_icon.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	icon_center.add_child(info_icon)
	
	# Крестик — закрыть панель
	close_button = Button.new()
	close_button.text = "×"
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.custom_minimum_size = Vector2(36, 32)
	close_button.flat = true
	close_button.tooltip_text = "Закрыть"
	close_button.pressed.connect(hide_panel)
	header_hbox.add_child(close_button)
	
	# Секция с описанием — при наведении только показывается/скрывается, ширина задаётся константой
	content_section = VBoxContainer.new()
	content_section.custom_minimum_size = Vector2(INFO_BLOCK_WIDTH, INFO_CONTENT_HEIGHT)
	content_section.mouse_filter = Control.MOUSE_FILTER_STOP
	content_section.mouse_entered.connect(_on_header_hover_enter)
	content_section.mouse_exited.connect(_on_header_hover_exit)
	vbox.add_child(content_section)
	
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.custom_minimum_size = Vector2(0, INFO_SCROLL_HEIGHT)
	scroll_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_section.add_child(scroll_container)
	
	info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(info_vbox)
	
	# Кнопки — всегда внизу, фиксированы
	buttons_hbox = HBoxContainer.new()
	buttons_hbox.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	buttons_hbox.add_theme_constant_override("separation", 10)
	buttons_hbox.mouse_filter = Control.MOUSE_FILTER_STOP
	buttons_hbox.mouse_entered.connect(_on_header_hover_enter)
	buttons_hbox.mouse_exited.connect(_on_header_hover_exit)
	vbox.add_child(buttons_hbox)
	
	select_button = Button.new()
	select_button.text = "СОХРАНИТЬ"
	select_button.custom_minimum_size = Vector2(120, BUTTON_HEIGHT)
	select_button.visible = false
	select_button.mouse_filter = Control.MOUSE_FILTER_STOP
	select_button.pressed.connect(_on_select_button_pressed)
	select_button.button_down.connect(_on_select_button_pressed)
	select_button.gui_input.connect(_on_button_gui_input)
	buttons_hbox.add_child(select_button)
	
	craft_button = Button.new()
	craft_button.text = "ОБЪЕДИНИТЬ"  # Подставляется имя результата при показе крафта
	craft_button.custom_minimum_size = Vector2(130, BUTTON_HEIGHT)
	craft_button.visible = false
	craft_button.mouse_filter = Control.MOUSE_FILTER_STOP
	craft_button.pressed.connect(_on_craft_button_pressed)
	craft_button.button_down.connect(_on_craft_button_pressed)
	craft_button.gui_input.connect(_on_craft_gui_input)
	buttons_hbox.add_child(craft_button)
	
	craft_button_2 = Button.new()
	craft_button_2.text = "ОБЪЕДИНИТЬ"
	craft_button_2.custom_minimum_size = Vector2(130, BUTTON_HEIGHT)
	craft_button_2.visible = false
	craft_button_2.mouse_filter = Control.MOUSE_FILTER_STOP
	craft_button_2.pressed.connect(_on_craft_button_2_pressed)
	craft_button_2.button_down.connect(_on_craft_button_2_pressed)
	craft_button_2.gui_input.connect(_on_craft_2_gui_input)
	buttons_hbox.add_child(craft_button_2)
	
	simplify_button = Button.new()
	simplify_button.text = "УПРОСТИТЬ (3)"
	simplify_button.custom_minimum_size = Vector2(120, BUTTON_HEIGHT)
	simplify_button.visible = false
	simplify_button.mouse_filter = Control.MOUSE_FILTER_STOP
	simplify_button.pressed.connect(_on_simplify_button_pressed)
	buttons_hbox.add_child(simplify_button)
	
	x2_button = Button.new()
	x2_button.text = "х2"
	x2_button.custom_minimum_size = Vector2(44, BUTTON_HEIGHT)
	x2_button.visible = false
	x2_button.mouse_filter = Control.MOUSE_FILTER_STOP
	x2_button.pressed.connect(_on_x2_button_pressed)
	x2_button.button_down.connect(_on_x2_button_pressed)
	x2_button.gui_input.connect(_on_x2_gui_input)
	buttons_hbox.add_child(x2_button)
	
	x4_button = Button.new()
	x4_button.text = "х4"
	x4_button.custom_minimum_size = Vector2(44, BUTTON_HEIGHT)
	x4_button.visible = false
	x4_button.mouse_filter = Control.MOUSE_FILTER_STOP
	x4_button.pressed.connect(_on_x4_button_pressed)
	x4_button.button_down.connect(_on_x4_button_pressed)
	x4_button.gui_input.connect(_on_x4_gui_input)
	buttons_hbox.add_child(x4_button)
	
	_hover_timer = Timer.new()
	_hover_timer.one_shot = true
	_hover_timer.timeout.connect(_on_hover_timer_timeout)
	add_child(_hover_timer)
	
	anchors_preset = Control.PRESET_BOTTOM_WIDE
	offset_top = -PANEL_HEIGHT - PANEL_MARGIN
	offset_bottom = -PANEL_MARGIN
	offset_left = PANEL_MARGIN
	offset_right = -PANEL_MARGIN
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	hide()

func show_entity(entity_id: int):
	"""Показать информацию о сущности"""
	selected_entity_id = entity_id
	is_visible_flag = true
	_update_info()
	_set_content_visible(false)
	show()
	# Дебаг крафта: один раз при открытии инфо о башне в SELECTION/WAVE
	var phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	if (phase == GameTypes.GamePhase.TOWER_SELECTION_STATE or phase == GameTypes.GamePhase.WAVE_STATE) and ecs.towers.has(entity_id):
		var t = ecs.towers[entity_id]
		var in_combinables = ecs.combinables.has(entity_id)
		var num_crafts = 0
		if in_combinables:
			num_crafts = ecs.combinables[entity_id].get("possible_crafts", []).size()
		# if CRAFT_DEBUG: print("[Craft] открыта башня ...")  # отключено, чтобы не засорять консоль

func get_blocking_rect() -> Rect2:
	"""Область, в которой клики не уходят в игру (сама плашка). Для game_root."""
	if is_instance_valid(panel):
		return panel.get_global_rect()
	return Rect2()

func hide_panel():
	"""Скрыть панель"""
	selected_entity_id = -1
	is_visible_flag = false
	_hover_timer.stop()
	craft_button.visible = false
	x2_button.visible = false
	x4_button.visible = false
	craft_button_2.visible = false
	simplify_button.visible = false
	_pending_craft = {}
	_pending_craft_2 = {}
	_pending_craft_x2 = {}
	_pending_craft_x4 = {}
	if GameManager.crafting_visual:
		GameManager.crafting_visual.clear_selection()
	hide()

func _set_content_visible(show_content: bool):
	"""Показать/скрыть только текст описания. Размер панели не меняется."""
	scroll_container.modulate.a = 1.0 if show_content else 0.0
	scroll_container.mouse_filter = Control.MOUSE_FILTER_STOP if show_content else Control.MOUSE_FILTER_IGNORE

func _on_header_hover_enter():
	_hover_timer.stop()
	_set_content_visible(true)

func _on_header_hover_exit():
	_hover_timer.start(0.2)

func _on_hover_timer_timeout():
	var mouse_pos = get_global_mouse_position()
	if not get_global_rect().has_point(mouse_pos):
		_set_content_visible(false)

func _process(_delta):
	if is_visible_flag and selected_entity_id >= 0:
		_update_info()

func _update_info():
	"""Обновляет информацию о выбранной сущности"""
	# Очищаем старую информацию
	for child in info_vbox.get_children():
		child.queue_free()
	
	# Проверяем что сущность ещё существует
	if not ecs.entities.has(selected_entity_id):
		hide_panel()
		return
	
	# Башня
	if ecs.towers.has(selected_entity_id):
		_show_tower_info()
	# Враг
	elif ecs.enemies.has(selected_entity_id):
		_show_enemy_info()
	# Руда
	elif ecs.ores.has(selected_entity_id):
		_show_ore_info()
	else:
		title_label.text = "Unknown Entity"
		craft_button.visible = false
		craft_button_2.visible = false
		simplify_button.visible = false
		x2_button.visible = false
		x4_button.visible = false
		select_button.visible = false
		_pending_craft = {}
		_pending_craft_2 = {}
		_pending_craft_x2 = {}
		_pending_craft_x4 = {}

func _show_tower_info():
	"""Отображает информацию о башне"""
	var tower = ecs.towers[selected_entity_id]
	var tower_def = GameManager.get_tower_def(tower.get("def_id", ""))
	
	if tower_def.is_empty():
		title_label.text = "Unknown Tower"
		return
	
	title_label.text = tower_def.get("name", "Tower")
	
	# Level
	_add_info_line("Level: %d" % tower.get("level", 1))
	
	# Type
	_add_info_line("Type: %s" % tower_def.get("type", "UNKNOWN"))
	
	# Active status
	var is_active = tower.get("is_active", false)
	_add_info_line("Active: %s" % ("Yes" if is_active else "No"))
	
	# MVP бафф (у каждой вышки 0–5, +20% урона за уровень)
	var mvp_level = int(tower.get("mvp_level", 0))
	if mvp_level > 0:
		var mvp_pct = mvp_level * 20
		_add_info_line("MVP: %d — урон +%d%%" % [mvp_level, mvp_pct], Color(1.0, 0.85, 0.4))

	# Combat info
	if ecs.combat.has(selected_entity_id):
		var combat = ecs.combat[selected_entity_id]
		var base_dmg = combat.get("damage", 0)
		var aura_dmg = ecs.aura_effects.get(selected_entity_id, {}).get("damage_bonus", 0)
		var dmg_before_mvp = base_dmg + aura_dmg
		var mvp_mult = GameManager.get_mvp_damage_mult(selected_entity_id) if GameManager else 1.0
		var effective_dmg = int(dmg_before_mvp * mvp_mult)
		if mvp_level > 0:
			_add_info_line("Damage: %d (база %d, MVP x%.1f) = %d" % [effective_dmg, dmg_before_mvp, mvp_mult, effective_dmg])
		elif aura_dmg > 0:
			_add_info_line("Damage: %d (+%d) = %d" % [base_dmg, aura_dmg, dmg_before_mvp])
		else:
			_add_info_line("Damage: %d" % base_dmg)
		_add_info_line("Fire Rate: %.2f/s" % combat.get("fire_rate", 0.0))
		_add_info_line("Range: %d" % combat.get("range", 0))
		_add_info_line("Attack Type: %s" % combat.get("attack_type", "NONE"))
		
		# Aura buff (полученный от DE/DA соседей)
		if ecs.aura_effects.has(selected_entity_id):
			var aura = ecs.aura_effects[selected_entity_id]
			var speed_mult = aura.get("speed_multiplier", 1.0)
			var dmg_bonus = aura.get("damage_bonus", 0)
			if speed_mult > 1.0:
				_add_info_line("Aura Buff: x%.1f speed" % speed_mult, Color.GREEN)
			if dmg_bonus > 0:
				_add_info_line("Damage bonus: +%d" % dmg_bonus, Color.GREEN)
	
	# Aura (если это аура-башня — сама раздаёт бафф)
	if ecs.auras.has(selected_entity_id):
		var aura = ecs.auras[selected_entity_id]
		_add_info_line("Aura Radius: %d" % aura.get("radius", 0), Color.GREEN)
		var speed_mult = aura.get("speed_multiplier", 1.0)
		var dmg_bonus = aura.get("damage_bonus", 0)
		if speed_mult > 1.0:
			_add_info_line("Speed Mult: x%.1f" % speed_mult, Color.GREEN)
		if dmg_bonus > 0:
			_add_info_line("Damage Bonus: +%d per hit" % dmg_bonus, Color.GREEN)
	
	# === КРАФТ — в SELECTION (из 5 поставленных) или в WAVE ===
	var current_phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	var is_temporary = tower.get("is_temporary", false)
	var is_selected = tower.get("is_selected", false)
	
	var show_craft_block = (current_phase == GameTypes.GamePhase.TOWER_SELECTION_STATE or current_phase == GameTypes.GamePhase.WAVE_STATE)
	show_craft_block = show_craft_block and ecs.combinables.has(selected_entity_id)
	_pending_craft = {}
	_pending_craft_2 = {}
	_pending_craft_x2 = {}
	_pending_craft_x4 = {}
	craft_button.visible = false
	craft_button_2.visible = false
	x2_button.visible = false
	x4_button.visible = false
	if show_craft_block:
		var combinable = ecs.combinables[selected_entity_id]
		var possible_crafts = combinable.get("possible_crafts", [])
		if possible_crafts.size() > 0:
			_add_separator()
			_add_info_line("CRAFTING AVAILABLE!", Color(1.0, 0.84, 0.0))
			_add_info_line("Possible: %d recipe(s)" % possible_crafts.size())
			var crafts_3: Array = []
			var crafts_2: Array = []
			var crafts_4: Array = []
			var seen_3: Dictionary = {}
			var seen_2: Dictionary = {}
			var seen_4: Dictionary = {}
			for c in possible_crafts:
				var combo = c.get("combination", [])
				var sz = combo.size()
				var out_id = c.get("recipe", {}).get("output_id", "")
				if sz == 3 and not seen_3.get(out_id, false):
					seen_3[out_id] = true
					crafts_3.append(c)
				elif sz == 2 and not seen_2.get(out_id, false):
					seen_2[out_id] = true
					crafts_2.append(c)
				elif sz == 4 and not seen_4.get(out_id, false):
					seen_4[out_id] = true
					crafts_4.append(c)
			if crafts_3.size() > 0:
				var c0 = crafts_3[0]
				_pending_craft = {"combination": c0.get("combination", []), "recipe": c0.get("recipe", {})}
				craft_button.visible = true
				var cost0 = GameManager.crafting_system.get_craft_energy_cost_for_recipe(c0.get("recipe", {}), c0.get("combination", []).size()) if GameManager.crafting_system else 0
				craft_button.text = _get_output_tower_name(c0.get("recipe", {}).get("output_id", "")) + (" (%d)" % cost0 if cost0 > 0 else "")
				var ore_total = GameManager.get_ore_network_totals().get("total_current", 0.0)
				craft_button.disabled = cost0 > 0 and ore_total < cost0
				if GameManager.crafting_visual:
					GameManager.crafting_visual.set_selected_combination(c0.get("combination", []), c0.get("recipe", {}))
			if crafts_3.size() > 1:
				var c1 = crafts_3[1]
				_pending_craft_2 = {"combination": c1.get("combination", []), "recipe": c1.get("recipe", {})}
				craft_button_2.visible = true
				var cost1 = GameManager.crafting_system.get_craft_energy_cost_for_recipe(c1.get("recipe", {}), c1.get("combination", []).size()) if GameManager.crafting_system else 0
				craft_button_2.text = _get_output_tower_name(c1.get("recipe", {}).get("output_id", "")) + (" (%d)" % cost1 if cost1 > 0 else "")
				var ore_total_2 = GameManager.get_ore_network_totals().get("total_current", 0.0)
				craft_button_2.disabled = cost1 > 0 and ore_total_2 < cost1
			if current_phase == GameTypes.GamePhase.TOWER_SELECTION_STATE and crafts_2.size() > 0:
				var c2 = crafts_2[0]
				_pending_craft_x2 = {"combination": c2.get("combination", []), "recipe": c2.get("recipe", {})}
				x2_button.visible = true
				var cost2 = GameManager.crafting_system.get_craft_energy_cost_for_recipe(c2.get("recipe", {}), 2) if GameManager.crafting_system else 0
				x2_button.text = _get_output_tower_name(c2.get("recipe", {}).get("output_id", "")) + (" (%d)" % cost2 if cost2 > 0 else "")
				var ore_x2 = GameManager.get_ore_network_totals().get("total_current", 0.0)
				x2_button.disabled = cost2 > 0 and ore_x2 < cost2
			if current_phase == GameTypes.GamePhase.TOWER_SELECTION_STATE and crafts_4.size() > 0:
				var c4 = crafts_4[0]
				_pending_craft_x4 = {"combination": c4.get("combination", []), "recipe": c4.get("recipe", {})}
				x4_button.visible = true
				var cost4 = GameManager.crafting_system.get_craft_energy_cost_for_recipe(c4.get("recipe", {}), 4) if GameManager.crafting_system else 0
				x4_button.text = _get_output_tower_name(c4.get("recipe", {}).get("output_id", "")) + (" (%d)" % cost4 if cost4 > 0 else "")
				var ore_x4 = GameManager.get_ore_network_totals().get("total_current", 0.0)
				x4_button.disabled = cost4 > 0 and ore_x4 < cost4
			if _pending_craft.is_empty() and GameManager.crafting_visual:
				if crafts_2.size() > 0:
					GameManager.crafting_visual.set_selected_combination(crafts_2[0].get("combination", []), crafts_2[0].get("recipe", {}))
				elif crafts_4.size() > 0:
					GameManager.crafting_visual.set_selected_combination(crafts_4[0].get("combination", []), crafts_4[0].get("recipe", {}))
	
	# Кнопка "Сохранить" только в фазе TOWER_SELECTION_STATE для временных башен
	if current_phase == GameTypes.GamePhase.TOWER_SELECTION_STATE and is_temporary:
		select_button.visible = true
		select_button.disabled = false
		if is_selected:
			select_button.text = "ОТМЕНИТЬ"
			select_button.modulate = Color(1.0, 0.8, 0.3)
		else:
			select_button.text = "СОХРАНИТЬ"
			select_button.modulate = Color.WHITE
	else:
		select_button.visible = false
	
	# Кнопка "Упростить" (даунгрейд): только в SELECTION, только временные базовые башни уровня >= 2. Стоимость 3 руды.
	var can_downgrade = (current_phase == GameTypes.GamePhase.TOWER_SELECTION_STATE and is_temporary
		and tower.get("crafting_level", 0) == 0 and tower.get("level", 1) >= 2)
	var ore_total_simp = GameManager.get_ore_network_totals().get("total_current", 0.0)
	simplify_button.visible = can_downgrade
	simplify_button.disabled = not can_downgrade or ore_total_simp < Config.DOWNGRADE_COST
	simplify_button.text = "УПРОСТИТЬ (%d)" % Config.DOWNGRADE_COST
	
	# Кнопки крафта: ОБЪЕДИНИТЬ (3 башни), х2 (2 башни), х4 (4 башни — только в SELECTION)
	var can_craft = (current_phase == GameTypes.GamePhase.TOWER_SELECTION_STATE or current_phase == GameTypes.GamePhase.WAVE_STATE)
	can_craft = can_craft and ecs.combinables.has(selected_entity_id) and ecs.combinables[selected_entity_id].get("possible_crafts", []).size() > 0
	if not can_craft:
		craft_button.visible = false
		craft_button_2.visible = false
		craft_button.text = "ОБЪЕДИНИТЬ"
		craft_button_2.text = "ОБЪЕДИНИТЬ"
		x2_button.visible = false
		x2_button.text = "х2"
		x4_button.visible = false
		x4_button.text = "х4"
		_pending_craft = {}
		_pending_craft_2 = {}
		_pending_craft_x2 = {}
		_pending_craft_x4 = {}
		if GameManager.crafting_visual:
			GameManager.crafting_visual.clear_selection()
	
	# Обучение уровень 0 (Основы): в фазе выбора только кнопка «Сохранить», без х2/х4/даунгрейд/объединить
	var is_tutorial_0 = ecs.game_state.get("is_tutorial", false) and ecs.game_state.get("tutorial_index", 0) == 0
	if is_tutorial_0 and current_phase == GameTypes.GamePhase.TOWER_SELECTION_STATE:
		craft_button.visible = false
		craft_button_2.visible = false
		x2_button.visible = false
		x4_button.visible = false
		simplify_button.visible = false
	
	# Для майнера: руда под ним и сеть
	if tower_def.get("type") == "MINER":
		_add_separator()
		_add_miner_ore_and_network_info(selected_entity_id, tower)

func _show_ore_info():
	"""Информация о руде (при клике на руду)"""
	craft_button.visible = false
	craft_button_2.visible = false
	simplify_button.visible = false
	x2_button.visible = false
	x4_button.visible = false
	select_button.visible = false
	_pending_craft = {}
	_pending_craft_2 = {}
	_pending_craft_x2 = {}
	_pending_craft_x4 = {}
	if GameManager.crafting_visual:
		GameManager.crafting_visual.clear_selection()
	
	var ore = ecs.ores[selected_entity_id]
	var cur = ore.get("current_reserve", 0.0)
	var max_r = ore.get("max_reserve", 1.0)
	var pct = (cur / max_r * 100.0) if max_r > 0 else 0.0
	var power = ore.get("power", 0.0) * 100.0
	
	title_label.text = "Руда"
	_add_info_line("Запас: %.0f / %.0f (%.0f%%)" % [cur, max_r, pct])
	_add_info_line("Мощность: %.1f%%" % power)
	var active = cur >= Config.ORE_DEPLETION_THRESHOLD
	_add_info_line("Активна: %s" % ("Да" if active else "Нет (истощена)"))

func _add_miner_ore_and_network_info(tower_id: int, tower: Dictionary):
	"""Блок для майнера: руда под ним + сеть"""
	var tower_hex = tower.get("hex")
	if tower_hex == null:
		return
	# Руда на этом гексе
	var ore_under: Dictionary = {}
	for oid in ecs.ores.keys():
		var o = ecs.ores[oid]
		var oh = o.get("hex")
		if oh != null and oh.equals(tower_hex):
			ore_under = o
			break
	if not ore_under.is_empty():
		var cur = ore_under.get("current_reserve", 0.0)
		var max_r = ore_under.get("max_reserve", 1.0)
		var pct = (cur / max_r * 100.0) if max_r > 0 else 0.0
		_add_info_line("Руда под майнером: %.0f / %.0f (%.0f%%)" % [cur, max_r, pct])
		var active = cur >= Config.ORE_DEPLETION_THRESHOLD
		_add_info_line("Руда активна: %s" % ("Да" if active else "Нет"))
	else:
		_add_info_line("Руда под майнером: нет")
	# Сеть: активен, корень (на руде), кол-во линий
	var is_active = tower.get("is_active", false)
	_add_info_line("Сеть: %s" % ("активен" if is_active else "неактивен"))
	var line_count = 0
	for line in ecs.energy_lines.values():
		if line.get("tower1_id") == tower_id or line.get("tower2_id") == tower_id:
			line_count += 1
	_add_info_line("Подключено линий: %d" % line_count)
	var on_ore = not ore_under.is_empty() and (ore_under.get("current_reserve", 0.0) >= Config.ORE_DEPLETION_THRESHOLD)
	if on_ore:
		_add_info_line("Корень сети (питание от руды)", Color(0.5, 1.0, 0.5))
	# Всего руды в сети и сколько добыто
	if GameManager and GameManager.energy_network:
		var stats = GameManager.energy_network.get_network_ore_stats(tower_id)
		if stats.get("total_max", 0.0) > 0 or stats.get("total_current", 0.0) > 0:
			_add_info_line("В сети руды: %.0f / %.0f (добыто: %.0f)" % [
				stats.get("total_current", 0.0), stats.get("total_max", 0.0), stats.get("mined", 0.0)
			])

func _show_enemy_info():
	"""Отображает информацию о враге"""
	craft_button.visible = false
	craft_button_2.visible = false
	simplify_button.visible = false
	x2_button.visible = false
	x4_button.visible = false
	
	var enemy = ecs.enemies[selected_entity_id]
	var enemy_def = GameManager.get_enemy_def(enemy.get("def_id", ""))
	
	if enemy_def.is_empty():
		title_label.text = "Unknown Enemy"
		return
	
	title_label.text = enemy_def.get("name", "Enemy")
	
	# Health
	if ecs.healths.has(selected_entity_id):
		var health = ecs.healths[selected_entity_id]
		_add_info_line("Health: %d / %d" % [health.get("current", 0), health.get("max", 100)])
	
	# Speed
	var speed = enemy.get("speed", 80.0)
	_add_info_line("Base Speed: %.1f" % speed)
	
	# Armor (показываем эффективную — база минус стакающиеся дебаффы)
	var eff_phys = GameManager.get_effective_physical_armor(selected_entity_id)
	var eff_mag = GameManager.get_effective_magical_armor(selected_entity_id)
	_add_info_line("Physical Armor: %d" % eff_phys)
	_add_info_line("Magical Armor: %d" % eff_mag)
	
	# Abilities (имя и тип пассив/актив из ability_definitions при наличии)
	var abilities = enemy.get("abilities", [])
	if abilities.size() > 0:
		var names = []
		for ab in abilities:
			var def = DataRepository.get_ability_def(str(ab))
			var name_str = def.get("name", _ability_display_name(ab))
			if def.size() > 0 and def.get("type", "") in ["passive", "active"]:
				name_str += " (Пассив)" if def.type == "passive" else " (Актив)"
			names.append(name_str)
		_add_info_line("Способности: %s" % ", ".join(names))
	
	# Status effects
	if ecs.slow_effects.has(selected_entity_id):
		var slow = ecs.slow_effects[selected_entity_id]
		_add_info_line("SLOWED: %.1f%% speed (%.1fs)" % [(slow.get("slow_factor", 1.0) * 100), slow.get("timer", 0.0)], Config.ENEMY_SLOW_COLOR)
	if ecs.bash_effects.has(selected_entity_id):
		var bash = ecs.bash_effects[selected_entity_id]
		_add_info_line("BASHED: стоит на месте, без скиллов (%.1fs)" % bash.get("timer", 0.0), Config.ENEMY_BASH_COLOR)
	
	if ecs.poison_effects.has(selected_entity_id):
		var poison = ecs.poison_effects[selected_entity_id]
		_add_info_line("POISONED: %d dps (%.1fs)" % [poison.get("damage_per_sec", 0), poison.get("timer", 0.0)], Config.ENEMY_POISON_COLOR)
	if ecs.phys_armor_debuffs.has(selected_entity_id):
		var d = GameManager.get_armor_debuff_display(selected_entity_id, true)
		_add_info_line("Phys armor -%d (%.1fs)" % [d.total, d.min_timer], Config.ENEMY_PHYS_ARMOR_DEBUFF_COLOR)
	if ecs.mag_armor_debuffs.has(selected_entity_id):
		var d = GameManager.get_armor_debuff_display(selected_entity_id, false)
		_add_info_line("Mag armor -%d (%.1fs)" % [d.total, d.min_timer], Config.ENEMY_MAG_ARMOR_DEBUFF_COLOR)

func _get_output_tower_name(output_id: String) -> String:
	"""Возвращает отображаемое имя башни по output_id рецепта (для кнопок объединения)."""
	if output_id.is_empty():
		return "?"
	var def = DataRepository.get_tower_def(output_id)
	if def.is_empty():
		return output_id
	return def.get("name", output_id)

func _ability_display_name(ability_id: String) -> String:
	var def = DataRepository.get_ability_def(ability_id)
	if def.size() > 0:
		return def.get("name", ability_id)
	match str(ability_id):
		"effect_immunity": return "Иммунитет к эффектам"
		"disarm": return "Разоружение"
		"rush": return "Рывок"
		"reactive_armor": return "Реактивная броня"
		"untouchable": return "Неприкасаемый"
		"kraken_shell": return "Панцирь кракена"
		"evasion": return "Уклонение"
		"blink": return "Блинк"
		"reflection": return "Рефлекшн"
		"hus": return "Хус"
		"healer_aura": return "Аура лечения"
		"aggro": return "Агрро"
		_: return ability_id

func _add_info_line(text: String, color: Color = Color.WHITE):
	"""Добавляет строку информации"""
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	info_vbox.add_child(label)

func _add_separator():
	"""Добавляет разделитель"""
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	info_vbox.add_child(spacer)

func _on_craft_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_craft_button_pressed()
		get_viewport().set_input_as_handled()

func _on_craft_2_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_craft_button_2_pressed()
		get_viewport().set_input_as_handled()

func _on_craft_button_pressed():
	"""Обработчик кнопки Объединить — в фазе выбора (из 5 поставленных) или волны"""
	var phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	if phase != GameTypes.GamePhase.WAVE_STATE and phase != GameTypes.GamePhase.TOWER_SELECTION_STATE:
		return
	if _pending_craft.is_empty() or selected_entity_id < 0:
		return
	_perform_craft(selected_entity_id, _pending_craft.get("combination", []), _pending_craft.get("recipe", {}))

func _on_craft_button_2_pressed():
	"""Вторая кнопка крафта (другое здание из 3 башен)."""
	var phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	if phase != GameTypes.GamePhase.WAVE_STATE and phase != GameTypes.GamePhase.TOWER_SELECTION_STATE:
		return
	if _pending_craft_2.is_empty() or selected_entity_id < 0:
		return
	_perform_craft(selected_entity_id, _pending_craft_2.get("combination", []), _pending_craft_2.get("recipe", {}))

func _on_simplify_button_pressed():
	"""Упростить: даунгрейд башни на случайный уровень ниже, стоимость 3 руды. Как х2/х4 — только эта вышка сохраняется, остальные в камень, переход в волну."""
	if selected_entity_id < 0 or not GameManager.crafting_system:
		return
	if GameManager.crafting_system.perform_downgrade(selected_entity_id):
		var phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
		if phase == GameTypes.GamePhase.TOWER_SELECTION_STATE and GameManager.phase_controller:
			# Упрощённая вышка остаётся; только уже сохранённый майнер не в камень; остальные временные → стены
			var saved_miner_ids: Array = []
			for tid in ecs.towers.keys():
				var t = ecs.towers[tid]
				if not t.get("is_temporary", false) or not t.get("is_selected", false):
					continue
				var def = DataRepository.get_tower_def(t.get("def_id", ""))
				if def.get("type", "") == "MINER":
					saved_miner_ids.append(tid)
			for tid in ecs.towers.keys():
				var t = ecs.towers[tid]
				if not t.get("is_temporary", false):
					continue
				if tid == selected_entity_id:
					t["is_selected"] = true
				elif tid in saved_miner_ids:
					pass
				else:
					t["is_selected"] = false
			GameManager.phase_controller.transition_to_wave()
		hide_panel()
		return
	_update_info()

func _on_x2_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_x2_button_pressed()
		get_viewport().set_input_as_handled()

func _on_x4_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_x4_button_pressed()
		get_viewport().set_input_as_handled()

func _on_x2_button_pressed():
	"""Обработчик кнопки х2 (2×L→L+1) — только в фазе выбора башен"""
	var phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	if phase != GameTypes.GamePhase.TOWER_SELECTION_STATE:
		return
	if _pending_craft_x2.is_empty() or selected_entity_id < 0:
		return
	_perform_craft(selected_entity_id, _pending_craft_x2.get("combination", []), _pending_craft_x2.get("recipe", {}))

func _on_x4_button_pressed():
	"""Обработчик кнопки х4 (4×L→L+2) — только в фазе выбора башен"""
	var phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	if phase != GameTypes.GamePhase.TOWER_SELECTION_STATE:
		return
	if _pending_craft_x4.is_empty() or selected_entity_id < 0:
		return
	_perform_craft(selected_entity_id, _pending_craft_x4.get("combination", []), _pending_craft_x4.get("recipe", {}))

func _perform_craft(clicked_tower_id: int, combination: Array, recipe: Dictionary):
	"""Выполняет крафт (как в Go: in-place). В SELECTION после крафта — результат сохраняется; только уже сохранённый майнер не в камень; остальные временные → стены."""
	
	if GameManager.crafting_system:
		var phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
		var saved_miner_ids: Array = []
		if phase == GameTypes.GamePhase.TOWER_SELECTION_STATE:
			for tid in ecs.towers.keys():
				var t = ecs.towers[tid]
				if not t.get("is_temporary", false) or not t.get("is_selected", false):
					continue
				var def = DataRepository.get_tower_def(t.get("def_id", ""))
				if def.get("type", "") == "MINER":
					saved_miner_ids.append(tid)
		var result_id = GameManager.crafting_system.perform_craft(clicked_tower_id, combination, recipe)
		if result_id != GameTypes.INVALID_ENTITY_ID:
			if GameManager.crafting_visual:
				GameManager.crafting_visual.clear_selection()
			if phase == GameTypes.GamePhase.TOWER_SELECTION_STATE:
				for tid in ecs.towers.keys():
					var t = ecs.towers[tid]
					if not t.get("is_temporary", false):
						continue
					if tid == result_id:
						t["is_selected"] = true
					elif tid in saved_miner_ids:
						pass
					else:
						t["is_selected"] = false
				if GameManager.phase_controller:
					GameManager.phase_controller.transition_to_wave()
			show_entity(result_id)
		else:
			if GameManager.crafting_visual:
				GameManager.crafting_visual.clear_selection()

# ============================================================================
# УДАЛЕНО: Логика теперь в PhaseController
# ============================================================================
# _finalize_tower_selection() и _create_permanent_wall()
# Используйте GameManager.phase_controller.finalize_tower_selection()

func _on_button_gui_input(event: InputEvent):
	"""Обработчик gui_input для кнопки"""
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_select_button_pressed()

func _on_select_button_pressed():
	"""Обработчик нажатия кнопки Сохранить"""
	if selected_entity_id < 0:
		return
	
	if not ecs.towers.has(selected_entity_id):
		return
	
	var tower = ecs.towers[selected_entity_id]
	var was_selected = tower.get("is_selected", false)
	
	if was_selected:
		# Снимаем сохранение
		tower["is_selected"] = false
	else:
		# Проверяем сколько уже сохранено
		var saved_count = 0
		for tid in ecs.towers.keys():
			var t = ecs.towers[tid]
			if t.get("is_temporary", false) and t.get("is_selected", false):
				saved_count += 1
		
		if saved_count >= 2:
			return
		
		# Сохраняем
		tower["is_selected"] = true
		
		# Проверяем сколько сохранено ПОСЛЕ сохранения
		var final_saved_count = 0
		for tid in ecs.towers.keys():
			var t = ecs.towers[tid]
			if t.get("is_temporary", false) and t.get("is_selected", false):
				final_saved_count += 1
		
		# Если сохранено Config.TOWERS_TO_KEEP башен -> автопереход в WAVE
		if final_saved_count >= Config.TOWERS_TO_KEEP:
			# Используем PhaseController для перехода в WAVE (он автоматически финализирует выбор)
			if GameManager.phase_controller:
				GameManager.phase_controller.transition_to_wave()
			# Закрываем панель
			hide_panel()
			return
	
	# Обновляем UI
	_update_info()

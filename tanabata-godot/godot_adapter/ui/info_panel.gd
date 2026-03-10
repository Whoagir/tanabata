# info_panel.gd
# UI плашка с информацией о выбранной башне/враге
# Портировано из Go: internal/ui/info_panel.go
extends Control

var ecs: ECSWorld
var selected_entity_id: int = -1
var is_visible_flag: bool = false

# UI элементы (дерево сцены: Panel/MarginContainer/MainHBox -> LeftColumn + CraftsInfoPanel)
var panel: Panel
var header_row: HBoxContainer
var header_tower_switch: HBoxContainer  # 50px отступ + слайдер вкл/выкл (только для башен, не стена)
var tower_enabled_slider: HSlider
var _tower_slider_block: bool = false  # не реагировать на value_changed при программном set value
var crafts_info_panel: VBoxContainer
var title_label: Label
var info_icon: Label  # Буква "i" рядом с названием
var crafts_into_label: RichTextLabel  # "Crafts into: X", зелёный только то что можно скрафтить сейчас
var content_section: Control  # HBox: описание (скролл) + квадратики скиллов
var info_vbox: VBoxContainer
var scroll_container: ScrollContainer
var status_bar: HBoxContainer  # Мини-квадраты в полоске над контентом (эффекты на вышку)
var skills_row: HBoxContainer  # Горизонтальный ряд скиллов (3–6 иконок)
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
	# Ссылки на узлы из сцены info_panel.tscn (верстку можно править в редакторе)
	panel = get_node("VBox/Panel")
	header_row = get_node("VBox/Panel/MarginContainer/MainHBox/LeftColumn/HeaderRow")
	header_tower_switch = get_node("VBox/Panel/MarginContainer/MainHBox/LeftColumn/HeaderRow/HeaderTowerSwitch")
	_setup_tower_enabled_slider()
	crafts_info_panel = get_node("VBox/Panel/MarginContainer/MainHBox/CraftsInfoPanel")
	title_label = get_node("VBox/Panel/MarginContainer/MainHBox/LeftColumn/HeaderRow/TitleLabel")
	info_icon = get_node("VBox/Panel/MarginContainer/MainHBox/LeftColumn/HeaderRow/IconCenter/InfoIcon")
	crafts_into_label = get_node("VBox/Panel/MarginContainer/MainHBox/CraftsInfoPanel/CraftsIntoLabel")
	close_button = get_node("VBox/Panel/MarginContainer/MainHBox/CraftsInfoPanel/CloseRow/CloseButton")
	content_section = get_node("VBox/Panel/MarginContainer/MainHBox/LeftColumn/ContentSection")
	scroll_container = get_node("VBox/Panel/MarginContainer/MainHBox/LeftColumn/ContentSection/DescriptionScroll")
	info_vbox = get_node("VBox/Panel/MarginContainer/MainHBox/LeftColumn/ContentSection/DescriptionScroll/InfoVbox")
	status_bar = get_node("VBox/StatusBarWrapper/StatusBar")
	skills_row = get_node("VBox/Panel/MarginContainer/MainHBox/LeftColumn/ContentSection/SkillsRow")
	buttons_hbox = get_node("VBox/Panel/MarginContainer/MainHBox/LeftColumn/ButtonsHbox")
	select_button = get_node("VBox/Panel/MarginContainer/MainHBox/LeftColumn/ButtonsHbox/SelectButton")
	craft_button = get_node("VBox/Panel/MarginContainer/MainHBox/LeftColumn/ButtonsHbox/CraftButton")
	craft_button_2 = get_node("VBox/Panel/MarginContainer/MainHBox/LeftColumn/ButtonsHbox/CraftButton2")
	simplify_button = get_node("VBox/Panel/MarginContainer/MainHBox/LeftColumn/ButtonsHbox/SimplifyButton")
	x2_button = get_node("VBox/Panel/MarginContainer/MainHBox/LeftColumn/ButtonsHbox/X2Button")
	x4_button = get_node("VBox/Panel/MarginContainer/MainHBox/LeftColumn/ButtonsHbox/X4Button")
	# Сигналы (логика остаётся в коде)
	header_row.mouse_entered.connect(_on_header_hover_enter)
	header_row.mouse_exited.connect(_on_header_hover_exit)
	crafts_info_panel.mouse_entered.connect(_on_header_hover_enter)
	crafts_info_panel.mouse_exited.connect(_on_header_hover_exit)
	content_section.mouse_entered.connect(_on_header_hover_enter)
	content_section.mouse_exited.connect(_on_header_hover_exit)
	buttons_hbox.mouse_entered.connect(_on_header_hover_enter)
	buttons_hbox.mouse_exited.connect(_on_header_hover_exit)
	close_button.pressed.connect(hide_panel)
	close_button.tooltip_text = "Закрыть"
	select_button.pressed.connect(_on_select_button_pressed)
	select_button.button_down.connect(_on_select_button_pressed)
	select_button.gui_input.connect(_on_button_gui_input)
	craft_button.pressed.connect(_on_craft_button_pressed)
	craft_button.button_down.connect(_on_craft_button_pressed)
	craft_button.gui_input.connect(_on_craft_gui_input)
	craft_button_2.pressed.connect(_on_craft_button_2_pressed)
	craft_button_2.button_down.connect(_on_craft_button_2_pressed)
	craft_button_2.gui_input.connect(_on_craft_2_gui_input)
	simplify_button.pressed.connect(_on_simplify_button_pressed)
	x2_button.pressed.connect(_on_x2_button_pressed)
	x2_button.button_down.connect(_on_x2_button_pressed)
	x2_button.gui_input.connect(_on_x2_gui_input)
	x4_button.pressed.connect(_on_x4_button_pressed)
	x4_button.button_down.connect(_on_x4_button_pressed)
	x4_button.gui_input.connect(_on_x4_gui_input)
	_hover_timer = Timer.new()
	_hover_timer.one_shot = true
	_hover_timer.timeout.connect(_on_hover_timer_timeout)
	add_child(_hover_timer)
	# Слайдер вкл/выкл башни (в заголовке, 50px правее названия)
	# Корень: клики сквозь пустые области; позиция панели внизу
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	anchors_preset = Control.PRESET_BOTTOM_WIDE
	offset_top = -PANEL_HEIGHT - PANEL_MARGIN
	offset_bottom = -PANEL_MARGIN
	offset_left = PANEL_MARGIN
	offset_right = -PANEL_MARGIN
	hide()

func show_entity(entity_id: int):
	"""Показать информацию о сущности"""
	selected_entity_id = entity_id
	is_visible_flag = true
	_update_info()
	_set_content_visible(true)  # Описание всегда показывается
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
	"""Область, в которой клики не уходят в игру (StatusBar + Panel). Для game_root."""
	if is_instance_valid(panel) and is_instance_valid(panel.get_parent()):
		return panel.get_parent().get_global_rect()
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
	"""Показать/скрыть только текст описания (описание всегда показывается — наведение на i не требуется)."""
	scroll_container.modulate.a = 1.0 if show_content else 0.0
	scroll_container.mouse_filter = Control.MOUSE_FILTER_STOP if show_content else Control.MOUSE_FILTER_IGNORE

func _on_header_hover_enter():
	_hover_timer.stop()
	_set_content_visible(true)

func _on_header_hover_exit():
	_hover_timer.start(0.2)

func _on_hover_timer_timeout():
	# Описание всегда видно, не скрываем по таймеру
	pass

func _process(_delta: float):
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
	
	# Слайдер вкл/выкл показываем только для башни (не стена)
	header_tower_switch.visible = false
	# Статус-бар над MarginContainer: мини-квадраты эффектов (скрыть для не-башни)
	_update_status_bar()
	# Скиллы по умолчанию скрыты; показываем только если у сущности есть способности
	_set_skills_visible([])
	
	# Башня
	if ecs.towers.has(selected_entity_id):
		_show_tower_info()
	# Враг
	elif ecs.enemies.has(selected_entity_id):
		crafts_into_label.visible = false
		_show_enemy_info()
	# Руда
	elif ecs.ores.has(selected_entity_id):
		crafts_into_label.visible = false
		_show_ore_info()
	else:
		crafts_into_label.visible = false
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
	# Слайдер вкл/выкл или режим батареи (Добыча/Трата)
	if tower_def.get("type") == "WALL":
		header_tower_switch.visible = false
	elif tower_def.get("type") == "BATTERY":
		header_tower_switch.visible = true
		_tower_slider_block = true
		tower_enabled_slider.value = 1.0 if tower.get("battery_manual_discharge", false) else 0.0
		_tower_slider_block = false
		tower_enabled_slider.tooltip_text = "Добыча (накопление) / Трата (отдача в сеть)"
		_update_tower_slider_style()
	else:
		header_tower_switch.visible = true
		_tower_slider_block = true
		tower_enabled_slider.value = 1.0 if not tower.get("is_manually_disabled", false) else 0.0
		_tower_slider_block = false
		tower_enabled_slider.tooltip_text = "Вкл/выкл башню (или ПКМ по башне)"
		_update_tower_slider_style()
	var tower_abilities = tower_def.get("abilities", [])
	_set_skills_visible(tower_abilities)
	
	var def_id = tower.get("def_id", "")
	var tw_level = tower.get("level", 1)
	var outputs = _get_crafts_into_outputs(def_id, tw_level)
	crafts_into_label.visible = true
	if outputs.is_empty():
		crafts_into_label.text = ""
	else:
		var craftable_ids: Dictionary = {}
		for oid in (GameManager.get_craftable_output_ids_now() if GameManager else []):
			craftable_ids[oid] = true
		var lines: Array = []
		for item in outputs:
			var name_str = item.get("name", "")
			var out_id = item.get("output_id", "")
			if craftable_ids.get(out_id, false):
				lines.append("[color=#4cd964]" + name_str + "[/color]")
			else:
				lines.append(name_str)
		crafts_into_label.text = "\n".join(lines)
	
	var mvp_level = int(tower.get("mvp_level", 0))

	# Для майнера: в первую очередь руда под ним и сеть
	if tower_def.get("type") == "MINER":
		_add_separator()
		_add_miner_ore_and_network_info(selected_entity_id, tower)

	# Combat info (важные показатели)
	if ecs.combat.has(selected_entity_id):
		var combat = ecs.combat[selected_entity_id]
		var base_dmg = combat.get("damage", 0)
		var aura_eff = ecs.aura_effects.get(selected_entity_id, {})
		var aura_dmg = aura_eff.get("damage_bonus", 0)
		var aura_dmg_pct = aura_eff.get("damage_bonus_percent", 0.0)
		var dmg_before_mvp = int(base_dmg * (1.0 + aura_dmg_pct)) + aura_dmg if aura_dmg_pct > 0 else (base_dmg + aura_dmg)
		var mvp_mult = GameManager.get_mvp_damage_mult(selected_entity_id) if GameManager else 1.0
		var early_mult = GameManager.get_early_craft_curse_damage_multiplier(selected_entity_id) if GameManager else 1.0
		var effective_dmg = int(dmg_before_mvp * mvp_mult * early_mult)
		var early_info = GameManager.get_early_craft_curse_info(selected_entity_id) if GameManager else {}
		var touch_info = GameManager.get_touch_curse_info(selected_entity_id) if GameManager else {}
		var has_curse = early_info.get("has_curse", false)
		var has_touch = touch_info.get("has_curse", false)
		if mvp_level > 0 or has_curse or has_touch:
			var parts = ["Damage: %d" % effective_dmg]
			parts.append("база %d" % dmg_before_mvp)
			if mvp_level > 0:
				parts.append("MVP x%.2f" % mvp_mult)
			if has_curse:
				var early_only_mult = 1.0 - (float(early_info.get("percent", 0)) / 100.0)
				parts.append("раннего крафта x%.2f" % early_only_mult)
			if has_touch:
				parts.append("касания x0.85")
			_add_info_line("%s (%s) = %d" % [parts[0], ", ".join(parts.slice(1, parts.size())), effective_dmg])
		elif aura_dmg_pct > 0:
			_add_info_line("Damage: %d (+%d%%) = %d" % [base_dmg, int(aura_dmg_pct * 100), dmg_before_mvp])
		elif aura_dmg > 0:
			_add_info_line("Damage: %d (+%d) = %d" % [base_dmg, aura_dmg, dmg_before_mvp])
		else:
			_add_info_line("Damage: %d" % base_dmg)
		_add_info_line("Fire Rate: %.2f/s" % combat.get("fire_rate", 0.0))
		_add_info_line("Range: %d" % combat.get("range", 0))
		_add_info_line("Attack Type: %s" % combat.get("attack_type", "NONE"))
		if has_curse:
			_add_info_line("Проклятие раннего крафта: -%d%% урона (при крафте снимется)" % early_info.get("percent", 0), Color(0.9, 0.5, 0.3))
		if has_touch:
			_add_info_line("Проклятие касания: -15% урона (при крафте или благословении снимется)", Color(0.9, 0.5, 0.3))
	
	# Второстепенные показатели (ниже)
	_add_separator()
	if mvp_level > 0:
		var mvp_pct = mvp_level * 20
		_add_info_line("MVP: %d — урон +%d%%" % [mvp_level, mvp_pct], Color(1.0, 0.85, 0.4))
	
	# Aura buff (полученный от DE/DA/Дипсеа соседей)
	if ecs.combat.has(selected_entity_id) and ecs.aura_effects.has(selected_entity_id):
		var aura = ecs.aura_effects[selected_entity_id]
		var speed_mult = aura.get("speed_multiplier", 1.0)
		var dmg_bonus = aura.get("damage_bonus", 0)
		var dmg_bonus_pct = aura.get("damage_bonus_percent", 0.0)
		var debuff_immunity = aura.get("debuff_immunity", false)
		if speed_mult > 1.0:
			_add_info_line("Aura Buff: x%.1f speed" % speed_mult, Color.GREEN)
		if dmg_bonus_pct > 0:
			_add_info_line("Damage: +%d%%" % int(dmg_bonus_pct * 100), Color.GREEN)
		if dmg_bonus > 0:
			_add_info_line("Damage bonus: +%d" % dmg_bonus, Color.GREEN)
		if debuff_immunity:
			_add_info_line("Immunity to debuffs (Dipsea)", Color.GREEN)
	
	# Aura (если это аура-башня — сама раздаёт бафф)
	if ecs.auras.has(selected_entity_id):
		var aura = ecs.auras[selected_entity_id]
		_add_info_line("Aura Radius: %d" % aura.get("radius", 0), Color.GREEN)
		var speed_mult = aura.get("speed_multiplier", 1.0)
		var dmg_bonus = aura.get("damage_bonus", 0)
		var dmg_bonus_pct = aura.get("damage_bonus_percent", 0.0)
		if speed_mult > 1.0:
			_add_info_line("Speed Mult: x%.1f" % speed_mult, Color.GREEN)
		if dmg_bonus_pct > 0:
			_add_info_line("Damage: +%d%%" % int(dmg_bonus_pct * 100), Color.GREEN)
		if dmg_bonus > 0:
			_add_info_line("Damage Bonus: +%d per hit" % dmg_bonus, Color.GREEN)
		if aura.get("debuff_immunity", false):
			_add_info_line("Grants: Immunity to debuffs", Color.GREEN)
	
	# Дебафф неприкасаемости (враг с Untouchable попал по вышке)
	if ecs.tower_attack_slow.has(selected_entity_id):
		var entry = ecs.tower_attack_slow[selected_entity_id]
		var timer = entry.get("timer", 0.0)
		var mult = entry.get("multiplier", Config.UNTOUCHABLE_SLOW_MULTIPLIER)
		_add_info_line("Дебафф неприкасаемости: атака в %.0f раз медленнее, осталось %.1f с" % [mult, timer], Color(1.0, 0.5, 0.4))
	
	# Для батареи: запас, режим, сеть (после основной инфы, до карт босса)
	if tower_def.get("type") == "BATTERY":
		_add_separator()
		_add_battery_info(selected_entity_id, tower)
	
	# Карты босса — всегда после основной информации о вышке
	var blessing_ids = GameManager.active_blessing_ids if GameManager else []
	var curse_ids = GameManager.active_curse_ids if GameManager else []
	if blessing_ids.size() > 0 or curse_ids.size() > 0:
		_add_separator()
		_add_info_line("Карты босса:", Color(0.9, 0.85, 0.6))
		for bid in blessing_ids:
			_add_info_line("  " + CardsData.get_card_name(bid), Color(0.5, 0.9, 0.5))
		for cid in curse_ids:
			_add_info_line("  " + CardsData.get_card_name(cid), Color(0.95, 0.5, 0.5))
	
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
			# Shift-выделение: комбинации, целиком из is_manually_selected, ставим первыми
			crafts_3 = _prefer_manual_selection_crafts(crafts_3)
			crafts_2 = _prefer_manual_selection_crafts(crafts_2)
			crafts_4 = _prefer_manual_selection_crafts(crafts_4)
			if crafts_3.size() > 0:
				var c0 = crafts_3[0]
				_pending_craft = {"combination": c0.get("combination", []), "recipe": c0.get("recipe", {})}
				craft_button.visible = true
				var cost0 = GameManager.crafting_system.get_craft_energy_cost_for_recipe(c0.get("recipe", {}), c0.get("combination", []).size()) if GameManager.crafting_system else 0
				var out_id0 = c0.get("recipe", {}).get("output_id", "")
				craft_button.text = _get_output_tower_name(out_id0) + (" (%d)" % cost0 if cost0 > 0 else "")
				craft_button.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35) if GameManager.would_craft_have_early_curse(out_id0) else Color.WHITE)
				var ore_total = GameManager.get_ore_network_totals().get("total_current", 0.0)
				craft_button.disabled = cost0 > 0 and ore_total < cost0
				if GameManager.crafting_visual:
					var all_comb = ecs.combinables.keys()
					GameManager.crafting_visual.set_selected_combination(c0.get("combination", []), c0.get("recipe", {}), all_comb, selected_entity_id)
			if crafts_3.size() > 1:
				var c1 = crafts_3[1]
				_pending_craft_2 = {"combination": c1.get("combination", []), "recipe": c1.get("recipe", {})}
				craft_button_2.visible = true
				var cost1 = GameManager.crafting_system.get_craft_energy_cost_for_recipe(c1.get("recipe", {}), c1.get("combination", []).size()) if GameManager.crafting_system else 0
				var out_id1 = c1.get("recipe", {}).get("output_id", "")
				craft_button_2.text = _get_output_tower_name(out_id1) + (" (%d)" % cost1 if cost1 > 0 else "")
				craft_button_2.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35) if GameManager.would_craft_have_early_curse(out_id1) else Color.WHITE)
				var ore_total_2 = GameManager.get_ore_network_totals().get("total_current", 0.0)
				craft_button_2.disabled = cost1 > 0 and ore_total_2 < cost1
			if current_phase == GameTypes.GamePhase.TOWER_SELECTION_STATE and crafts_2.size() > 0:
				var c2 = crafts_2[0]
				_pending_craft_x2 = {"combination": c2.get("combination", []), "recipe": c2.get("recipe", {})}
				x2_button.visible = true
				var cost2 = GameManager.crafting_system.get_craft_energy_cost_for_recipe(c2.get("recipe", {}), 2) if GameManager.crafting_system else 0
				var out_id2 = c2.get("recipe", {}).get("output_id", "")
				x2_button.text = _get_output_tower_name(out_id2) + (" (%d)" % cost2 if cost2 > 0 else "")
				x2_button.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35) if GameManager.would_craft_have_early_curse(out_id2) else Color.WHITE)
				var ore_x2 = GameManager.get_ore_network_totals().get("total_current", 0.0)
				x2_button.disabled = cost2 > 0 and ore_x2 < cost2
			if current_phase == GameTypes.GamePhase.TOWER_SELECTION_STATE and crafts_4.size() > 0:
				var c4 = crafts_4[0]
				_pending_craft_x4 = {"combination": c4.get("combination", []), "recipe": c4.get("recipe", {})}
				x4_button.visible = true
				var cost4 = GameManager.crafting_system.get_craft_energy_cost_for_recipe(c4.get("recipe", {}), 4) if GameManager.crafting_system else 0
				var out_id4 = c4.get("recipe", {}).get("output_id", "")
				x4_button.text = _get_output_tower_name(out_id4) + (" (%d)" % cost4 if cost4 > 0 else "")
				x4_button.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35) if GameManager.would_craft_have_early_curse(out_id4) else Color.WHITE)
				var ore_x4 = GameManager.get_ore_network_totals().get("total_current", 0.0)
				x4_button.disabled = cost4 > 0 and ore_x4 < cost4
			if _pending_craft.is_empty() and GameManager.crafting_visual:
				var all_comb = ecs.combinables.keys()
				if crafts_2.size() > 0:
					GameManager.crafting_visual.set_selected_combination(crafts_2[0].get("combination", []), crafts_2[0].get("recipe", {}), all_comb, selected_entity_id)
				elif crafts_4.size() > 0:
					GameManager.crafting_visual.set_selected_combination(crafts_4[0].get("combination", []), crafts_4[0].get("recipe", {}), all_comb, selected_entity_id)
	
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

func _add_battery_info(tower_id: int, tower: Dictionary):
	"""Блок для батареи: запас, режим, сеть"""
	var storage = tower.get("battery_storage", 0.0)
	var def = GameManager.get_tower_def(tower.get("def_id", "")) if GameManager else {}
	var storage_max = 200.0
	if def and def.get("energy", {}).has("storage_max"):
		storage_max = float(def["energy"]["storage_max"])
	_add_info_line("Запас: %.0f / %.0f" % [storage, storage_max])
	var manual = tower.get("battery_manual_discharge", false)
	var mode_text = "Трата" if manual else "Добыча"
	_add_info_line("Режим: %s" % mode_text)
	var is_active = tower.get("is_active", false)
	_add_info_line("Сеть: %s" % ("активна" if is_active else "неактивна"))
	if GameManager and GameManager.energy_network:
		var stats = GameManager.energy_network.get_network_ore_stats(tower_id)
		if stats.get("total_max", 0.0) > 0 or stats.get("total_current", 0.0) > 0:
			_add_info_line("В сети руды: %.0f / %.0f" % [stats.get("total_current", 0.0), stats.get("total_max", 0.0)])

func _set_skills_visible(abilities: Array):
	"""Показывает ряд скиллов только если у сущности есть способности; видимы первые N квадратов по числу способностей."""
	skills_row.visible = abilities.size() > 0
	var children = skills_row.get_children()
	for i in range(children.size()):
		children[i].visible = i < abilities.size()

func _update_status_bar():
	"""Заполняет мини-квадраты над MarginContainer: эффекты, воздействующие на вышку (пока без иконок — цветом)."""
	var slots = status_bar.get_children()
	for s in slots:
		if s is ColorRect:
			s.visible = false
	if not ecs.towers.has(selected_entity_id):
		return
	var idx = 0
	# Аура: скорость
	if ecs.aura_effects.has(selected_entity_id) and ecs.aura_effects[selected_entity_id].get("speed_multiplier", 1.0) > 1.0:
		if idx < slots.size() and slots[idx] is ColorRect:
			slots[idx].color = Color(0.3, 0.8, 0.4, 1)
			slots[idx].visible = true
		idx += 1
	# Аура: урон
	if ecs.aura_effects.has(selected_entity_id) and (ecs.aura_effects[selected_entity_id].get("damage_bonus", 0) > 0 or ecs.aura_effects[selected_entity_id].get("damage_bonus_percent", 0) > 0):
		if idx < slots.size() and slots[idx] is ColorRect:
			slots[idx].color = Color(0.4, 0.6, 1.0, 1)
			slots[idx].visible = true
		idx += 1
	# Иммунитет к дебаффам
	if ecs.aura_effects.has(selected_entity_id) and ecs.aura_effects[selected_entity_id].get("debuff_immunity", false):
		if idx < slots.size() and slots[idx] is ColorRect:
			slots[idx].color = Color(0.6, 0.5, 1.0, 1)
			slots[idx].visible = true
		idx += 1
	# Дебафф неприкасаемости (атака замедлена)
	if ecs.tower_attack_slow.has(selected_entity_id):
		if idx < slots.size() and slots[idx] is ColorRect:
			slots[idx].color = Color(1.0, 0.45, 0.3, 1)
			slots[idx].visible = true
		idx += 1
	# Проклятие раннего крафта
	var early_info = GameManager.get_early_craft_curse_info(selected_entity_id) if GameManager else {}
	if early_info.get("has_curse", false):
		if idx < slots.size() and slots[idx] is ColorRect:
			slots[idx].color = Color(0.9, 0.5, 0.2, 1)
			slots[idx].visible = true
		idx += 1
	# Проклятие касания
	var touch_info = GameManager.get_touch_curse_info(selected_entity_id) if GameManager else {}
	if touch_info.get("has_curse", false):
		if idx < slots.size() and slots[idx] is ColorRect:
			slots[idx].color = Color(0.85, 0.45, 0.25, 1)
			slots[idx].visible = true
		idx += 1
	# MVP бафф
	var tower = ecs.towers[selected_entity_id]
	if int(tower.get("mvp_level", 0)) > 0:
		if idx < slots.size() and slots[idx] is ColorRect:
			slots[idx].color = Color(1.0, 0.8, 0.2, 1)
			slots[idx].visible = true
		idx += 1

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
	var enemy_abilities = enemy.get("abilities", [])
	_set_skills_visible(enemy_abilities)
	
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
	var eff_pure = GameManager.get_effective_pure_armor(selected_entity_id)
	if eff_pure != 0:
		_add_info_line("Pure Armor: %d" % eff_pure)
	
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
		var combined = ecs.get_combined_slow_factor(selected_entity_id)
		var max_timer = 0.0
		var by_source = ecs.slow_effects[selected_entity_id]
		if by_source is Dictionary:
			for k in by_source:
				var e = by_source[k]
				if e is Dictionary:
					max_timer = maxf(max_timer, e.get("timer", 0.0))
		_add_info_line("SLOWED: %.1f%% speed (%.1fs)" % [(combined * 100), max_timer], Config.ENEMY_SLOW_COLOR)
	if ecs.bash_effects.has(selected_entity_id):
		var bash = ecs.bash_effects[selected_entity_id]
		_add_info_line("BASHED: стоит на месте, без скиллов (%.1fs)" % bash.get("timer", 0.0), Config.ENEMY_BASH_COLOR)
	
	if ecs.poison_effects.has(selected_entity_id):
		var poison = ecs.poison_effects[selected_entity_id]
		var total_dps = 0
		var max_timer = 0.0
		if poison.get("timer", null) != null and poison.get("damage_per_sec", null) != null:
			total_dps = poison.get("damage_per_sec", 0)
			max_timer = poison.get("timer", 0.0)
		else:
			for _def_id in poison:
				var eff = poison[_def_id] if poison[_def_id] is Dictionary else {}
				total_dps += eff.get("damage_per_sec", 0)
				max_timer = maxf(max_timer, eff.get("timer", 0.0))
		_add_info_line("POISONED: %d dps (%.1fs)" % [total_dps, max_timer], Config.ENEMY_POISON_COLOR)
	if ecs.phys_armor_debuffs.has(selected_entity_id):
		var d = GameManager.get_armor_debuff_display(selected_entity_id, true)
		_add_info_line("Phys armor -%d (%.1fs)" % [d.total, d.min_timer], Config.ENEMY_PHYS_ARMOR_DEBUFF_COLOR)
	if ecs.mag_armor_debuffs.has(selected_entity_id):
		var d = GameManager.get_armor_debuff_display(selected_entity_id, false)
		_add_info_line("Mag armor -%d (%.1fs)" % [d.total, d.min_timer], Config.ENEMY_MAG_ARMOR_DEBUFF_COLOR)

func _prefer_manual_selection_crafts(crafts_list: Array) -> Array:
	"""Ставит первыми комбинации, целиком из shift-выделенных башен (is_manually_selected). Без шифта порядок не меняется."""
	var manual_first: Array = []
	var rest: Array = []
	for c in crafts_list:
		var combo = c.get("combination", [])
		var all_manual = true
		for tid in combo:
			var t = ecs.towers.get(tid, {})
			if not t.get("is_manually_selected", false):
				all_manual = false
				break
		if all_manual:
			manual_first.append(c)
		else:
			rest.append(c)
	manual_first.append_array(rest)
	return manual_first

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
		"bkb": return "БКБ"
		"ivasion": return "Ивейжн"
		_: return ability_id

func _get_crafts_into_outputs(def_id: String, level: int) -> Array:
	"""Рецепты уровня крафта 1 и 2, в которых эта башня — ингредиент. Возвращает [{"name": str, "output_id": str}, ...] без дубликатов по output_id."""
	var out_list: Array = []
	var seen_ids: Dictionary = {}
	var recipes = DataRepository.recipe_defs
	if not recipes is Array:
		return out_list
	for recipe in recipes:
		var out_id = recipe.get("output_id", "")
		if out_id.is_empty() or seen_ids.has(out_id):
			continue
		var out_def = DataRepository.get_tower_def(out_id)
		if out_def.is_empty():
			continue
		if out_def.get("crafting_level", 0) < 1 or out_def.get("crafting_level", 0) > 2:
			continue
		for inp in recipe.get("inputs", []):
			if inp.get("id", "") == def_id and int(inp.get("level", 1)) == level:
				seen_ids[out_id] = true
				out_list.append({"name": out_def.get("name", out_id), "output_id": out_id})
				break
	return out_list

func _add_info_line(text: String, color: Color = Color.WHITE):
	"""Добавляет строку информации"""
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	info_vbox.add_child(label)

func _setup_tower_enabled_slider():
	"""Слайдер вкл/выкл в заголовке (тип замок в самолёте: влево = выкл, вправо = вкл)."""
	var container = get_node("VBox/Panel/MarginContainer/MainHBox/LeftColumn/HeaderRow/HeaderTowerSwitch/TowerEnabledSwitch")
	tower_enabled_slider = HSlider.new()
	tower_enabled_slider.custom_minimum_size = Vector2(54, 66)
	tower_enabled_slider.min_value = 0.0
	tower_enabled_slider.max_value = 1.0
	tower_enabled_slider.step = 1.0
	tower_enabled_slider.value = 1.0
	tower_enabled_slider.tooltip_text = "Вкл/выкл башню (или ПКМ по башне)"
	# Дорожка (линия) в 3 раза толще; приглушённые цвета по диз. доку
	var groove = StyleBoxFlat.new()
	groove.bg_color = Color(0.22, 0.22, 0.26, 1)
	groove.set_corner_radius_all(33)
	groove.set_content_margin_all(4)
	tower_enabled_slider.add_theme_stylebox_override("slider", groove)
	var grabber = StyleBoxFlat.new()
	grabber.bg_color = Color(0.4, 0.6, 0.4)
	grabber.set_corner_radius_all(24)
	tower_enabled_slider.add_theme_stylebox_override("grabber_area", grabber)
	tower_enabled_slider.add_theme_stylebox_override("grabber_area_highlight", grabber)
	tower_enabled_slider.value_changed.connect(_on_tower_slider_value_changed)
	container.add_child(tower_enabled_slider)

func _deferred_battery_rebuild() -> void:
	if GameManager and GameManager.energy_network:
		GameManager.energy_network.rebuild_energy_network()
	_update_info()

func _update_tower_slider_style():
	"""Цвет ползунка: для обычных башен зелёный = вкл (1), красный = выкл (0). Для батареи: зелёный = Добыча (0), красный = Трата (1)."""
	if not tower_enabled_slider:
		return
	var grabber = tower_enabled_slider.get_theme_stylebox("grabber_area")
	if grabber is StyleBoxFlat:
		var is_battery = false
		if selected_entity_id >= 0 and ecs.towers.has(selected_entity_id):
			var def = GameManager.get_tower_def(ecs.towers[selected_entity_id].get("def_id", "")) if GameManager else {}
			is_battery = def.get("type") == "BATTERY"
		var on_right = tower_enabled_slider.value >= 0.5
		if is_battery:
			# Добыча (0) = зелёный, Трата (1) = красный
			(grabber as StyleBoxFlat).bg_color = Color(0.65, 0.4, 0.4) if on_right else Color(0.4, 0.6, 0.4)
		else:
			(grabber as StyleBoxFlat).bg_color = Color(0.4, 0.6, 0.4) if on_right else Color(0.65, 0.4, 0.4)
		tower_enabled_slider.queue_redraw()

func _on_tower_slider_value_changed(_val: float):
	if _tower_slider_block or selected_entity_id < 0:
		return
	var v = 1.0 if _val >= 0.5 else 0.0
	_tower_slider_block = true
	tower_enabled_slider.value = v
	_tower_slider_block = false
	_update_tower_slider_style()
	if ecs.towers.has(selected_entity_id):
		var tower = ecs.towers[selected_entity_id]
		var def = GameManager.get_tower_def(tower.get("def_id", "")) if GameManager else {}
		if def.get("type") == "BATTERY":
			tower["battery_manual_discharge"] = (v >= 0.5)
			# Отложенный rebuild на следующий кадр, чтобы не фризить при переключении
			if get_tree():
				get_tree().create_timer(0.0).timeout.connect(_deferred_battery_rebuild, CONNECT_ONE_SHOT)
			return
	if GameManager and GameManager.input_system:
		GameManager.input_system.toggle_tower_enabled(selected_entity_id)
		_update_info()

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

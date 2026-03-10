# boss_reward_overlay.gd
# Оверлей выбора карты награды за убийство босса: затемнение, 3 карты (2 благословения, 1 проклятие — красная)
extends Control

var _overlay: ColorRect
var _cards_container: HBoxContainer
var _current_offers: Array = []  # [ {card: {}, is_curse: bool}, ... ]

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0, 0, 0, 0.75)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	
	_cards_container = HBoxContainer.new()
	_cards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_container.add_theme_constant_override("separation", 24)
	center.add_child(_cards_container)
	
	visible = false

const RARE_BLESSING_CHANCE = 0.15  # Вероятность что один из слотов — рарное благословение

func show_cards():
	_current_offers.clear()
	for c in _cards_container.get_children():
		c.queue_free()
	
	var two_bless = CardsData.pick_random_blessings(2)
	var one_curse = CardsData.pick_random_curse()
	var curse_index = randi() % 3
	var use_rare = randf() < RARE_BLESSING_CHANCE
	var rare_slot = randi() % 3
	if rare_slot == curse_index:
		rare_slot = (curse_index + 1) % 3
	var bless_idx = 0
	for i in range(3):
		var card_data: Dictionary
		var is_curse: bool
		var is_rare: bool = false
		if i == curse_index:
			card_data = one_curse
			is_curse = true
		else:
			if use_rare and i == rare_slot:
				card_data = CardsData.pick_random_rare_blessing()
				is_rare = not card_data.is_empty()
			if not is_rare:
				card_data = two_bless[bless_idx]
				bless_idx += 1
			is_curse = false
		_current_offers.append({"card": card_data, "is_curse": is_curse, "is_rare": is_rare})
		_add_card_panel(card_data, is_curse, i, is_rare)
	
	visible = true

func _add_card_panel(card_data: Dictionary, is_curse: bool, index: int, is_rare: bool = false):
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 280)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.18, 0.22, 0.98)
	style.border_width_left = 4
	style.border_width_top = 4
	style.border_width_right = 4
	style.border_width_bottom = 4
	if is_curse:
		style.border_color = Color(0.9, 0.2, 0.2, 1)
	elif is_rare:
		style.border_color = Color(0.95, 0.85, 0.2, 1)
		style.border_width_left = 6
		style.border_width_top = 6
		style.border_width_right = 6
		style.border_width_bottom = 6
	else:
		style.border_color = Color(0.3, 0.5, 0.3, 1)
	panel.add_theme_stylebox_override("panel", style)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	
	var title = Label.new()
	title.text = card_data.get("name", "?")
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var desc = Label.new()
	desc.text = card_data.get("desc", "")
	desc.add_theme_font_size_override("font_size", 14)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(176, 0)
	vbox.add_child(desc)
	
	panel.gui_input.connect(_on_card_gui_input.bind(index))
	_cards_container.add_child(panel)

func _on_card_gui_input(event: InputEvent, index: int):
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if index >= 0 and index < _current_offers.size():
				var offer = _current_offers[index]
				var card_id = offer.card.get("id", "")
				GameManager.apply_boss_card(card_id, offer.is_curse)
			GameManager.clear_pending_boss_cards()
			GameManager.resume_game()
			visible = false

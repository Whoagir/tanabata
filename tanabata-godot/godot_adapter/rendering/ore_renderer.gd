# ore_renderer.gd
# Визуализация руды (пульсирующие круги). Текст запаса только в дебаг-режиме.
extends Node2D

var ecs: ECSWorld
var ore_visuals: Dictionary = {}  # ore_id -> {circle: Polygon2D, label: Label}

func _init(ecs_: ECSWorld):
	ecs = ecs_

func _process(delta: float):
	_render_ores(delta)

func _render_ores(_delta: float):
	var game_time = Time.get_ticks_msec() / 1000.0
	
	# Обновляем существующую руду
	for ore_id in ecs.ores.keys():
		if not ecs.has_component(ore_id, "ore"):
			continue
		
		var ore = ecs.ores[ore_id]
		var pos = ecs.positions.get(ore_id, Vector2.ZERO)
		
		# Создаём визуал если нет
		if not ore_visuals.has(ore_id):
			_create_ore_visual(ore_id, ore, pos)
		
		# Пульсация; подпись с числом только в дебаг-режиме
		_update_ore_pulse(ore_id, ore, game_time)
		_update_ore_label(ore_id, ore)
	
	# Удаляем визуалы удалённой руды
	var to_remove = []
	for ore_id in ore_visuals.keys():
		if not ecs.ores.has(ore_id):
			to_remove.append(ore_id)
	
	for ore_id in to_remove:
		_remove_ore_visual(ore_id)

func _create_ore_visual(ore_id: int, ore: Dictionary, pos: Vector2):
	# Круг руды — полигон создаётся один раз с базовым радиусом, пульсация через scale
	var circle = Polygon2D.new()
	circle.polygon = _generate_circle_polygon(ore["radius"], 32)
	circle.position = pos
	circle.color = Config.COLOR_ORE_BRIGHT.darkened(0.2)
	circle.color.a = 0.5
	add_child(circle)
	
	# Текст запаса — показывается только в дебаг-режиме
	var label = Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = pos - Vector2(20, 10)
	label.custom_minimum_size = Vector2(40, 20)
	add_child(label)
	
	ore_visuals[ore_id] = {
		"circle": circle,
		"label": label
	}

func _update_ore_pulse(ore_id: int, ore: Dictionary, game_time: float):
	if not ore_visuals.has(ore_id):
		return
	
	var visuals = ore_visuals[ore_id]
	var circle = visuals["circle"]
	
	var pulse_rate = ore.get("pulse_rate", 2.0)
	var sin_val = sin(game_time * pulse_rate * PI / 5.0)
	
	# Пульсация через scale (±10%) вместо пересоздания полигона каждый кадр
	var scale_factor = 1.0 + 0.1 * sin_val
	circle.scale = Vector2(scale_factor, scale_factor)
	
	circle.color.a = 0.4 + 0.2 * sin_val

func _update_ore_label(ore_id: int, ore: Dictionary):
	if not ore_visuals.has(ore_id):
		return
	var lbl = ore_visuals[ore_id]["label"]
	var cur_r = ore.get("current_reserve", 0.0)
	var max_r = ore.get("max_reserve", 1.0)
	lbl.visible = Config.visual_debug_mode
	if Config.visual_debug_mode:
		lbl.text = "%.0f" % cur_r

func _remove_ore_visual(ore_id: int):
	if ore_visuals.has(ore_id):
		var visuals = ore_visuals[ore_id]
		visuals["circle"].queue_free()
		visuals["label"].queue_free()
		ore_visuals.erase(ore_id)

func _generate_circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(segments):
		var angle = i * TAU / segments
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

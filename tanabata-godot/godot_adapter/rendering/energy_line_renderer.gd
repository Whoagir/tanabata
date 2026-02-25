# energy_line_renderer.gd
# Визуализация линий энергосети между башнями
extends Node2D

var ecs: ECSWorld
var line_visuals: Dictionary = {}  # line_id -> Line2D
var dragging_line: Line2D  # Линия при перетаскивании (source -> mouse)

func _init(ecs_: ECSWorld):
	ecs = ecs_
	dragging_line = Line2D.new()
	dragging_line.width = 5.0
	dragging_line.default_color = Color(1.0, 0.9, 0.2, 0.9)  # Жёлтая как в Go
	dragging_line.antialiased = true
	dragging_line.z_index = 101  # Поверх обычных линий

func _enter_tree():
	add_child(dragging_line)
	dragging_line.visible = false

func _process(_delta: float):
	_render_lines()
	_render_dragging_line()

func _render_dragging_line():
	var source_id = ecs.game_state.get("drag_source_tower_id", 0)
	if source_id == 0 or not ecs.towers.has(source_id):
		dragging_line.visible = false
		return
	var tower = ecs.towers[source_id]
	var hex = tower.get("hex")
	if not hex:
		dragging_line.visible = false
		return
	var start_pos = hex.to_pixel(Config.HEX_SIZE)
	var camera = get_viewport().get_camera_2d()
	var end_pos = start_pos
	if camera:
		var mouse_pos = get_viewport().get_mouse_position()
		end_pos = camera.get_screen_center_position() + (mouse_pos - camera.get_viewport_rect().size / 2) / camera.zoom
	dragging_line.points = PackedVector2Array([start_pos, end_pos])
	dragging_line.visible = true

func _render_lines():
	# Создаём/обновляем линии
	for line_id in ecs.energy_lines.keys():
		var line_data = ecs.energy_lines[line_id]
		var tower1_id = line_data.get("tower1_id")
		var tower2_id = line_data.get("tower2_id")
		
		# Проверяем что обе башни существуют
		if not ecs.towers.has(tower1_id) or not ecs.towers.has(tower2_id):
			continue
		
		var tower1 = ecs.towers[tower1_id]
		var tower2 = ecs.towers[tower2_id]
		var hex1 = tower1.get("hex")
		var hex2 = tower2.get("hex")
		
		if not hex1 or not hex2:
			continue
		
		var pos1 = hex1.to_pixel(Config.HEX_SIZE)
		var pos2 = hex2.to_pixel(Config.HEX_SIZE)
		
		# Создаём Line2D если нет
		if not line_visuals.has(line_id):
			var line_node = Line2D.new()
			line_node.width = 4.0
			line_node.default_color = line_data.get("color", Config.COLOR_ENERGY_LINE)
			line_node.antialiased = true
			line_node.z_index = 100  # ПОВЕРХ ВСЕГО!
			add_child(line_node)
			line_visuals[line_id] = line_node
		
		# Обновляем позиции
		var ln = line_visuals[line_id]
		ln.points = PackedVector2Array([pos1, pos2])
		ln.visible = not line_data.get("is_hidden", false)
	
	# Удаляем визуалы удалённых линий
	var to_remove = []
	for line_id in line_visuals.keys():
		if not ecs.energy_lines.has(line_id):
			to_remove.append(line_id)
	
	for line_id in to_remove:
		line_visuals[line_id].queue_free()
		line_visuals.erase(line_id)

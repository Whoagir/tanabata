# godot_adapter/rendering/wall_renderer.gd
extends Node2D

var ecs: ECSWorld
var hex_map

# Preview lines
var preview_layer: Node2D = null
# Слой для обводок (поверх всего)
var outline_layer: Node2D = null

# Визуал
const WALL_SIZE_PERCENT = 0.70
const CONNECTION_WIDTH = 0.5
const WALL_COLOR = Color(0.51, 0.55, 0.57, 0.85)
const WALL_EDGE_COLOR = Color(0.57, 0.59, 0.6, 1.0)
const WALL_EDGE_WIDTH = 2.0

# Анимация
const INSTANT_SPAWN = false
const SPAWN_DURATION = 0.05
const SPAWN_SCALE_BOUNCE = 1.03

var wall_nodes = {}

func _ready():
	ecs = GameManager.ecs
	hex_map = GameManager.hex_map
	_init_preview_layer()
	_init_outline_layer()

func _process(_delta):
	_update_walls()
	_update_outlines()
	_update_preview_lines()

func force_immediate_update():
	_update_walls()

func _update_walls():
	var newly_added = []
	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		var def_id = tower.get("def_id", "")
		var tower_def = GameManager.get_tower_def(def_id)
		
		if tower_def.get("type") != "WALL":
			continue
		
		if not wall_nodes.has(tower_id):
			_create_wall_visual(tower_id, tower)
			newly_added.append(tower_id)
	
	var to_remove = []
	var removed_positions = {}
	for tower_id in wall_nodes.keys():
		if not ecs.towers.has(tower_id):
			var wall_data = wall_nodes[tower_id]
			var container = wall_data.get("container")
			if container:
				removed_positions[tower_id] = container.position
			to_remove.append(tower_id)
	
	if newly_added.size() > 0 or to_remove.size() > 0:
		var to_update = {}
		
		for tower_id in newly_added:
			to_update[tower_id] = true
			_mark_neighbors(tower_id, to_update)
		
		for tower_id in to_remove:
			var hex_pos = removed_positions.get(tower_id)
			if hex_pos:
				var hex = Hex.from_pixel(hex_pos, Config.HEX_SIZE)
				_mark_neighbors_by_hex(hex, to_update)
		
		for tower_id in to_update.keys():
			if ecs.towers.has(tower_id) and wall_nodes.has(tower_id):
				_update_connections(tower_id)
	
	for tower_id in to_remove:
		_remove_wall_visual(tower_id)

func _mark_neighbors(tower_id: int, to_update: Dictionary):
	if not ecs.towers.has(tower_id):
		return
	var tower = ecs.towers[tower_id]
	var hex = tower.get("hex")
	if hex:
		_mark_neighbors_by_hex(hex, to_update)

func _mark_neighbors_by_hex(hex: Hex, to_update: Dictionary):
	for neighbor_hex in hex.get_neighbors():
		var neighbor_id = hex_map.get_tower_id(neighbor_hex)
		if neighbor_id != GameTypes.INVALID_ENTITY_ID:
			var neighbor_tower = ecs.towers.get(neighbor_id)
			if neighbor_tower:
				var neighbor_def = GameManager.get_tower_def(neighbor_tower.get("def_id", ""))
				if neighbor_def.get("type") == "WALL":
					to_update[neighbor_id] = true

func _create_wall_visual(tower_id: int, tower: Dictionary):
	var hex = tower.get("hex")
	if not hex:
		return
	
	var pixel_pos = hex.to_pixel(Config.HEX_SIZE)
	
	var wall_container = Node2D.new()
	wall_container.position = pixel_pos
	wall_container.z_index = 25
	add_child(wall_container)
	
	var hex_polygon = Polygon2D.new()
	var radius = Config.HEX_SIZE * WALL_SIZE_PERCENT
	hex_polygon.polygon = _make_hexagon(radius)
	hex_polygon.color = WALL_COLOR
	wall_container.add_child(hex_polygon)
	
	# Обводка добавится в _update_connections
	
	var connections_container = Node2D.new()
	connections_container.z_index = 1
	wall_container.add_child(connections_container)
	
	wall_nodes[tower_id] = {
		"container": wall_container,
		"hex_polygon": hex_polygon,
		"connections": connections_container
	}
	
	_animate_spawn(wall_container)

func _remove_wall_visual(tower_id: int):
	if not wall_nodes.has(tower_id):
		return
	
	var wall_data = wall_nodes[tower_id]
	var container = wall_data["container"]
	
	var tween = create_tween()
	tween.tween_property(container, "scale", Vector2.ZERO, 0.2)
	tween.tween_property(container, "modulate:a", 0.0, 0.2)
	tween.tween_callback(container.queue_free)
	
	wall_nodes.erase(tower_id)

func _update_connections(tower_id: int):
	if not wall_nodes.has(tower_id):
		return
	
	var tower = ecs.towers[tower_id]
	var hex = tower.get("hex")
	var wall_data = wall_nodes[tower_id]
	var connections_container = wall_data["connections"]
	
	for child in connections_container.get_children():
		child.queue_free()
	
	# Проверяем каждое направление напрямую
	var wall_neighbor_directions = {}
	var wall_neighbors = []
	
	for dir in range(6):
		var neighbor_hex = hex.neighbor(dir)
		var neighbor_id = hex_map.get_tower_id(neighbor_hex)
		if neighbor_id != GameTypes.INVALID_ENTITY_ID:
			var neighbor_tower = ecs.towers.get(neighbor_id)
			if neighbor_tower:
				var neighbor_def = GameManager.get_tower_def(neighbor_tower.get("def_id", ""))
				if neighbor_def.get("type") == "WALL":
					wall_neighbors.append(neighbor_hex)
					wall_neighbor_directions[dir] = true
	
	if wall_neighbors.size() == 6:
		_create_full_fill(connections_container)
		return
	
	# Рисуем линии к соседям
	for neighbor_hex in wall_neighbors:
		_create_connection_line(connections_container, hex, neighbor_hex)

func _create_connection_line(parent: Node2D, from_hex: Hex, to_hex: Hex):
	var from_pos = Vector2.ZERO
	var to_pos = to_hex.to_pixel(Config.HEX_SIZE) - from_hex.to_pixel(Config.HEX_SIZE)
	
	# Только линия БЕЗ обводки
	var line = Line2D.new()
	line.add_point(from_pos)
	line.add_point(to_pos)
	line.default_color = WALL_COLOR
	line.width = Config.HEX_SIZE * CONNECTION_WIDTH
	line.antialiased = true
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	parent.add_child(line)

func _update_outlines():
	if not outline_layer:
		return
	
	# Очищаем старые обводки
	for child in outline_layer.get_children():
		child.queue_free()
	
	# Ярче на 10%
	var brighter_color = Color(
		WALL_EDGE_COLOR.r * 1.1,
		WALL_EDGE_COLOR.g * 1.1,
		WALL_EDGE_COLOR.b * 1.1,
		WALL_EDGE_COLOR.a
	)
	
	var radius = Config.HEX_SIZE * WALL_SIZE_PERCENT - 2.0
	
	# Собираем все соединения для обводки линий
	var connection_lines = {}
	
	# Рисуем НЕВИДИМЫЕ стены с ОБВОДКОЙ поверх настоящих
	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		var def = GameManager.get_tower_def(tower.get("def_id", ""))
		if def.get("type") != "WALL":
			continue
		
		var hex = tower.get("hex")
		if not hex:
			continue
		
		var center = hex.to_pixel(Config.HEX_SIZE)
		var hex_points = _make_hexagon(radius)
		
		# Невидимый шестиугольник (прозрачный)
		var invisible_hex = Polygon2D.new()
		invisible_hex.polygon = hex_points
		invisible_hex.color = Color(0, 0, 0, 0)  # Прозрачный
		invisible_hex.position = center
		invisible_hex.z_index = 3
		outline_layer.add_child(invisible_hex)
		
		# Обводка вокруг него (полная)
		var outline = Line2D.new()
		for i in range(6):
			outline.add_point(center + hex_points[i])
		outline.add_point(center + hex_points[0])  # Замыкаем
		outline.default_color = brighter_color
		outline.width = WALL_EDGE_WIDTH
		outline.antialiased = true
		outline.z_index = 4
		outline_layer.add_child(outline)
	
	# Собираем соединения для обводки линий
	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		var def = GameManager.get_tower_def(tower.get("def_id", ""))
		if def.get("type") != "WALL":
			continue
		
		var hex = tower.get("hex")
		if not hex:
			continue
		
		var center = hex.to_pixel(Config.HEX_SIZE)
		
		for dir in range(6):
			var neighbor_hex = hex.neighbor(dir)
			var neighbor_id = hex_map.get_tower_id(neighbor_hex)
			if neighbor_id != GameTypes.INVALID_ENTITY_ID:
				var neighbor_tower = ecs.towers.get(neighbor_id)
				if neighbor_tower:
					var neighbor_def = GameManager.get_tower_def(neighbor_tower.get("def_id", ""))
					if neighbor_def.get("type") == "WALL":
						var pair_key = str(min(tower_id, neighbor_id)) + "_" + str(max(tower_id, neighbor_id))
						connection_lines[pair_key] = [center, neighbor_hex.to_pixel(Config.HEX_SIZE)]
	
	# Обводка линий (широкая линия цвета обводки)
	for points in connection_lines.values():
		var line_outline = Line2D.new()
		line_outline.add_point(points[0])
		line_outline.add_point(points[1])
		line_outline.default_color = brighter_color
		line_outline.width = Config.HEX_SIZE * CONNECTION_WIDTH + WALL_EDGE_WIDTH * 2
		line_outline.antialiased = true
		line_outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line_outline.end_cap_mode = Line2D.LINE_CAP_ROUND
		line_outline.z_index = 0
		outline_layer.add_child(line_outline)
	
	# Линия цвета стены поверх обводки (закрывает середину)
	for points in connection_lines.values():
		var line_fill = Line2D.new()
		line_fill.add_point(points[0])
		line_fill.add_point(points[1])
		line_fill.default_color = WALL_COLOR
		line_fill.width = Config.HEX_SIZE * CONNECTION_WIDTH
		line_fill.antialiased = true
		line_fill.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line_fill.end_cap_mode = Line2D.LINE_CAP_ROUND
		line_fill.z_index = 1
		outline_layer.add_child(line_fill)
	

func _create_full_fill(parent: Node2D):
	var fill_circle = Polygon2D.new()
	var radius = Config.HEX_SIZE * 1.1
	var points = []
	for i in range(32):
		var angle = i * TAU / 32
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	fill_circle.polygon = PackedVector2Array(points)
	fill_circle.color = WALL_COLOR
	fill_circle.z_index = -2
	parent.add_child(fill_circle)

func _make_hexagon(radius: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(6):
		var angle = PI / 6.0 + i * PI / 3.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func _animate_spawn(node: Node2D):
	if INSTANT_SPAWN:
		node.scale = Vector2.ONE
		node.modulate = Color(1, 1, 1, 1)
		return
	
	node.scale = Vector2(0.7, 0.7)
	node.modulate = Color(1, 1, 1, 0.5)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	
	tween.tween_property(node, "scale", Vector2.ONE * SPAWN_SCALE_BOUNCE, SPAWN_DURATION * 0.7)
	tween.chain().tween_property(node, "scale", Vector2.ONE, SPAWN_DURATION * 0.3)
	tween.tween_property(node, "modulate:a", 1.0, SPAWN_DURATION)

func _init_preview_layer():
	preview_layer = Node2D.new()
	preview_layer.z_index = 24
	add_child(preview_layer)

func _init_outline_layer():
	outline_layer = Node2D.new()
	outline_layer.z_index = 30  # ПОВЕРХ всех стен (которые на z=25)
	add_child(outline_layer)


func _update_preview_lines():
	if not preview_layer:
		return
	
	# Очищаем старые линии
	for child in preview_layer.get_children():
		child.queue_free()
	
	var has_preview = false
	var preview_pos = Vector2.ZERO
	var preview_hex = null
	
	var phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	if phase == GameTypes.GamePhase.BUILD_STATE:
		var mouse_pos = get_viewport().get_mouse_position()
		var camera = get_parent().get_parent().get_node_or_null("Camera2D")
		if camera:
			var world_pos = camera.get_screen_center_position() + (mouse_pos - camera.get_viewport_rect().size / 2) / camera.zoom
			var hex = Hex.from_pixel(world_pos, Config.HEX_SIZE)
			if hex_map.has_tile(hex):
				var preview_type = _get_preview_tower_type()
				if preview_type == "TOWER_WALL":
					preview_pos = hex.to_pixel(Config.HEX_SIZE)
					preview_hex = hex
					has_preview = true
	
	if not has_preview:
		return
	
	# Рисуем линии к соседним стенам
	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		var def = GameManager.get_tower_def(tower.get("def_id", ""))
		if def.get("type") == "WALL":
			var hex = tower.get("hex")
			if hex:
				var distance = preview_hex.distance_to(hex)
				if distance == 1:
					var wall_pos = hex.to_pixel(Config.HEX_SIZE)
					_draw_preview_line(preview_pos, wall_pos)

func _draw_preview_line(from_pos: Vector2, to_pos: Vector2):
	var line = Line2D.new()
	line.add_point(from_pos)
	line.add_point(to_pos)
	line.default_color = Color(WALL_COLOR.r, WALL_COLOR.g, WALL_COLOR.b, 0.35)
	line.width = Config.HEX_SIZE * CONNECTION_WIDTH
	line.antialiased = true
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	preview_layer.add_child(line)

func _get_preview_tower_type() -> String:
	if ecs.game_state.has("debug_tower_type"):
		return ecs.game_state["debug_tower_type"]
	
	var towers_built = ecs.game_state.get("towers_built_this_phase", 0)
	if towers_built >= Config.MAX_TOWERS_IN_BUILD_PHASE:
		return "NONE"
	
	# Обучение уровень 0: первая фаза — превью А; вторая фаза (после волны) — первая постановка майнер
	if ecs.game_state.get("is_tutorial", false) and ecs.game_state.get("tutorial_index", -1) == 0:
		var cw = ecs.game_state.get("current_wave", 0)
		var placements = ecs.game_state.get("placements_made_this_phase", 0)
		if cw >= 1 and placements == 0:
			return "TOWER_MINER"
		return "TA1"
	
	# Первая башня в волнах 1–4 = майнер
	var current_wave = ecs.game_state.get("current_wave", 0)
	var wave_mod_10 = (current_wave - 1) % 10
	
	if wave_mod_10 < 4 and towers_built == 0:
		return "TOWER_MINER"
	
	return "TA1"

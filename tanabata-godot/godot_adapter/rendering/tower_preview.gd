# godot_adapter/rendering/tower_preview.gd
# Preview башни на курсоре
extends Node2D

var ecs: ECSWorld
var hex_map: HexMap
var camera: Camera2D
var input_system

# Preview визуал
var preview_node: Node2D = null
var current_preview_type: String = ""
var ore_label: Label = null  # Для майнера: запас руды на гексе (белый текст на жёлтом)

# Визуальные параметры
const PREVIEW_ALPHA = 0.3  # 30% прозрачность
const PREVIEW_COLOR_VALID = Color(1.0, 1.0, 1.0, PREVIEW_ALPHA)
const PREVIEW_COLOR_INVALID = Color(1.0, 0.3, 0.3, PREVIEW_ALPHA)  # Красноватый если нельзя поставить

func _ready():
	ecs = GameManager.ecs
	hex_map = GameManager.hex_map
	camera = get_parent().get_parent().get_node("Camera2D")
	z_index = 100  # Поверх всего

func _process(_delta):
	_update_preview()

func _update_preview():
	var current_phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	
	# Preview только в BUILD фазе
	if current_phase != GameTypes.GamePhase.BUILD_STATE:
		_hide_preview()
		return
	
	# Получаем позицию мыши
	var mouse_pos = get_viewport().get_mouse_position()
	var world_pos = camera.get_screen_center_position() + (mouse_pos - camera.get_viewport_rect().size / 2) / camera.zoom
	var hex = Hex.from_pixel(world_pos, Config.HEX_SIZE)
	
	if not hex_map.has_tile(hex):
		_hide_preview()
		return
	
	# Определяем что будем ставить
	var tower_type = _determine_preview_tower_type()
	
	# Проверяем можно ли поставить
	var can_place = _can_place_at(hex)
	
	# Показываем preview
	_show_preview(hex, tower_type, can_place)

func _determine_preview_tower_type() -> String:
	# Дебаг режим
	if ecs.game_state.has("debug_tower_type"):
		var debug_type = ecs.game_state["debug_tower_type"]
		var def = GameManager.get_tower_def(debug_type)
		return def.get("type", "ATTACK")
	
	# Проверяем лимит
	var towers_built = ecs.game_state.get("towers_built_this_phase", 0)
	if towers_built >= Config.MAX_TOWERS_IN_BUILD_PHASE:
		return "NONE"
	
	# Обучение уровень 0: первая фаза — только атакующие (превью А); вторая фаза (после волны) — первая постановка майнер (превью майнера)
	if ecs.game_state.get("is_tutorial", false) and ecs.game_state.get("tutorial_index", -1) == 0:
		var cw = ecs.game_state.get("current_wave", 0)
		var placements = ecs.game_state.get("placements_made_this_phase", 0)
		if cw >= 1 and placements == 0:
			return "MINER"
		return "ATTACK"
	
	# Определяем как в input_system: первая башня в волнах 1–4 = майнер
	var current_wave = ecs.game_state.get("current_wave", 0)
	var wave_mod_10 = (current_wave - 1) % 10
	
	if wave_mod_10 < 4 and towers_built == 0:
		return "MINER"
	
	return "ATTACK"  # По умолчанию атакующая

func _can_place_at(hex: Hex) -> bool:
	var tile = hex_map.get_tile(hex)
	if not tile:
		return false
	
	return tile.passable and tile.can_place_tower and not tile.has_tower

func _show_preview(hex: Hex, tower_type: String, can_place: bool):
	if tower_type == "NONE":
		_hide_preview()
		return
	
	var pixel_pos = hex.to_pixel(Config.HEX_SIZE)
	
	# Создаем preview если нужно
	if not preview_node or current_preview_type != tower_type:
		_create_preview(tower_type)
		current_preview_type = tower_type
	
	if preview_node:
		preview_node.position = pixel_pos
		preview_node.visible = true
		preview_node.modulate = PREVIEW_COLOR_VALID if can_place else PREVIEW_COLOR_INVALID
		
		# Майнер: на жёлтом превью показываем запас руды белым шрифтом
		if tower_type == "MINER" and ore_label:
			var ore_reserve = _get_ore_reserve_at_hex(hex)
			if ore_reserve >= 0:
				ore_label.visible = true
				ore_label.text = "%.0f" % ore_reserve
			else:
				ore_label.visible = false

func _hide_preview():
	if preview_node:
		preview_node.visible = false
	if ore_label:
		ore_label.visible = false

func _get_ore_reserve_at_hex(hex: Hex) -> float:
	"""Запас руды на гексе (current_reserve). Если руды нет, возвращает -1."""
	for ore_id in ecs.ores.keys():
		var ore = ecs.ores[ore_id]
		var oh = ore.get("hex")
		if oh != null and oh.equals(hex):
			return ore.get("current_reserve", 0.0)
	return -1.0

func _create_preview(tower_type: String):
	if preview_node:
		preview_node.queue_free()
	ore_label = null
	
	preview_node = Node2D.new()
	add_child(preview_node)
	
	var radius = Config.HEX_SIZE * 0.6
	var polygon: Polygon2D
	
	# Формы как в Go версии (entity_renderer)
	match tower_type:
		"MINER":
			# Майнер — шестиугольник (жёлтый) + подпись запаса руды (яркий белый)
			polygon = _create_hexagon_polygon(radius)
			polygon.color = Color(1.0, 0.84, 0.0, 0.6)  # Золотой полупрозрачный
			ore_label = Label.new()
			ore_label.add_theme_font_size_override("font_size", 14)
			ore_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
			ore_label.modulate = Color(5.0, 5.0, 5.0)  # Очень яркий белый текст на превью
			ore_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ore_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			ore_label.position = Vector2(-22, -10)
			ore_label.custom_minimum_size = Vector2(44, 22)
			ore_label.visible = false
			preview_node.add_child(ore_label)
		"ATTACK":
			# Атакующая - КРУГ (оранжевый)
			polygon = _create_circle_polygon(radius)
			polygon.color = Color(1.0, 0.4, 0.0, 0.6)  # Оранжевый полупрозрачный
		"WALL":
			# Шестиугольник
			polygon = _create_hexagon_polygon(radius)
			polygon.color = Color(0.5, 0.5, 0.5)
		_:
			polygon = _create_circle_polygon(radius)
			polygon.color = Color(1.0, 1.0, 1.0)
	
	preview_node.add_child(polygon)

func _create_circle_polygon(radius: float) -> Polygon2D:
	var polygon = Polygon2D.new()
	var points = PackedVector2Array()
	var segments = 32
	for i in range(segments):
		var angle = i * TAU / segments
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	polygon.polygon = points
	return polygon

func _create_triangle_polygon(radius: float) -> Polygon2D:
	var polygon = Polygon2D.new()
	var points = PackedVector2Array()
	for i in range(3):
		var angle = -PI / 2 + i * TAU / 3
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	polygon.polygon = points
	return polygon

func _create_hexagon_polygon(radius: float) -> Polygon2D:
	var polygon = Polygon2D.new()
	var points = PackedVector2Array()
	for i in range(6):
		var angle = PI / 6.0 + i * PI / 3.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	polygon.polygon = points
	return polygon

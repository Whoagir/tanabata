# attack_link_renderer.gd
# Визуализация линий между соседними атакующими башнями
# Оптимизация: пары пересчитываются только при изменении набора башен; градиенты кэшируются по паре типов.
extends Node2D

var ecs: ECSWorld
var hex_map: HexMap
var link_visuals: Dictionary = {}  # "id1-id2" -> Line2D

# Кэш: пересчёт только при изменении башен
var _cached_link_list: Array = []  # [{link_key, hex1, hex2, def1, def2, type1, type2}, ...]
var _last_tower_count: int = -1
var _last_tower_keys_sorted: String = ""  # для детекции изменения набора башен

# Кэш градиентов по паре def_id (порядок id1, id2 = направление линии, чтобы цвета совпадали)
var _gradient_cache: Dictionary = {}

func _init(ecs_: ECSWorld, hex_map_: HexMap):
	ecs = ecs_
	hex_map = hex_map_

func _process(_delta: float):
	# Быстрая проверка: изменился ли набор башен?
	var ids: Array = ecs.towers.keys()
	ids.sort()
	var count = ids.size()
	var keys_sorted = ""
	for id in ids:
		keys_sorted += str(id) + ","
	if count != _last_tower_count or keys_sorted != _last_tower_keys_sorted:
		_rebuild_link_cache(ids, count, keys_sorted)
	# Всегда обновляем только позиции линий из кэша (без O(n²) и без создания Gradient)
	_apply_cached_links()

func _rebuild_link_cache(ids: Array, count: int, keys_sorted: String):
	_last_tower_count = count
	_last_tower_keys_sorted = keys_sorted
	_cached_link_list.clear()
	# O(n²) только при изменении башен
	for i in range(ids.size()):
		var tower1_id: int = ids[i]
		var tower1 = ecs.towers.get(tower1_id)
		if not tower1:
			continue
		var def1 = DataRepository.get_tower_def(tower1.get("def_id", ""))
		if not def1:
			continue
		var type1 = def1.get("type")
		if type1 != "ATTACK" and type1 != "WALL":
			continue
		var hex1 = tower1.get("hex")
		if not hex1:
			continue
		for j in range(i + 1, ids.size()):
			var tower2_id: int = ids[j]
			var tower2 = ecs.towers.get(tower2_id)
			if not tower2:
				continue
			var def2 = DataRepository.get_tower_def(tower2.get("def_id", ""))
			if not def2:
				continue
			var type2 = def2.get("type")
			if type2 != "ATTACK" and type2 != "WALL":
				continue
			if type1 != "ATTACK" and type2 != "ATTACK":
				continue
			var hex2 = tower2.get("hex")
			if not hex2:
				continue
			if hex1.distance_to(hex2) != 1:
				continue
			var link_key = "%d-%d" % [tower1_id, tower2_id]
			_cached_link_list.append({
				"link_key": link_key,
				"hex1": hex1,
				"hex2": hex2,
				"def1": def1,
				"def2": def2,
				"type1": type1,
				"type2": type2
			})

func _apply_cached_links():
	var active_keys: Dictionary = {}
	for link_data in _cached_link_list:
		var link_key: String = link_data["link_key"]
		active_keys[link_key] = true
		var pos1 = link_data["hex1"].to_pixel(Config.HEX_SIZE)
		var pos2 = link_data["hex2"].to_pixel(Config.HEX_SIZE)
		var def1 = link_data["def1"]
		var def2 = link_data["def2"]
		var type1 = link_data["type1"]
		var type2 = link_data["type2"]
		var color1 = _get_tower_color(def1, type1)
		var color2 = _get_tower_color(def2, type2)

		# Обводка
		var outline_key = link_key + "_outline"
		if not link_visuals.has(outline_key):
			var outline_line = Line2D.new()
			outline_line.width = 11.0
			outline_line.antialiased = true
			outline_line.z_index = 94
			outline_line.default_color = Color(0.0, 0.0, 0.0, 0.3)
			add_child(outline_line)
			link_visuals[outline_key] = outline_line
		link_visuals[outline_key].points = PackedVector2Array([pos1, pos2])

		# Основная линия
		if not link_visuals.has(link_key):
			var line_node = Line2D.new()
			line_node.width = 7.0
			line_node.antialiased = true
			line_node.z_index = 95
			add_child(line_node)
			link_visuals[link_key] = line_node
		var main_line = link_visuals[link_key]
		main_line.points = PackedVector2Array([pos1, pos2])

		# Градиент: одинаковые типы — один цвет; разные — из кэша по паре def_id (порядок = направление линии)
		if def1.get("id") == def2.get("id"):
			var bright_color = color1
			bright_color.a = 0.7
			main_line.default_color = bright_color
			main_line.gradient = null
		else:
			var grad_key = _gradient_cache_key(def1.get("id", ""), def2.get("id", ""))
			if not _gradient_cache.has(grad_key):
				var bright_color1 = color1
				bright_color1.a = 0.7
				var bright_color2 = color2
				bright_color2.a = 0.7
				var g = Gradient.new()
				g.set_color(0, bright_color1)
				g.set_color(1, bright_color2)
				_gradient_cache[grad_key] = g
			main_line.gradient = _gradient_cache[grad_key]
			main_line.default_color = Color.WHITE

	# Удаляем линии, которых нет в актуальном списке
	var to_remove = []
	for link_key in link_visuals.keys():
		if link_key.ends_with("_outline"):
			var base_key = link_key.replace("_outline", "")
			if not active_keys.has(base_key):
				to_remove.append(link_key)
		elif not active_keys.has(link_key):
			to_remove.append(link_key)
	for link_key in to_remove:
		link_visuals[link_key].queue_free()
		link_visuals.erase(link_key)

func _gradient_cache_key(id1: String, id2: String) -> String:
	# Порядок id1, id2 сохраняем — градиент 0 = начало линии, 1 = конец
	return id1 + "|" + id2

func _get_tower_color(tower_def: Dictionary, tower_type: String) -> Color:
	if tower_type == "WALL":
		return Color(0.6, 0.6, 0.6)
	var visuals = tower_def.get("visuals", {})
	var color_value = visuals.get("color", "#FF8C00")
	if typeof(color_value) == TYPE_STRING:
		return Color.html(color_value)
	elif typeof(color_value) == TYPE_DICTIONARY:
		return Color(
			color_value.get("r", 255) / 255.0,
			color_value.get("g", 140) / 255.0,
			color_value.get("b", 0) / 255.0,
			color_value.get("a", 255) / 255.0
		)
	return Color.ORANGE

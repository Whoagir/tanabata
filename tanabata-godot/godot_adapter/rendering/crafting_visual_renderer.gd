# crafting_visual_renderer.gd
# Визуализация возможностей крафта (подсветка башен + линии + шарики сверху)
extends Node2D

var ecs: ECSWorld
var hex_map: HexMap

# Визуалы
var highlight_nodes: Dictionary = {}  # tower_id -> Polygon2D (подсветка на земле)
var combinable_markers: Dictionary = {}  # tower_id -> Node2D (яркий шарик сверху башни, как в Go)
var link_lines: Dictionary = {}  # "id1-id2-..." -> Line2D (линии между ингредиентами)

# Текущая выбранная комбинация для preview
var selected_combination: Array = []
var selected_recipe: Dictionary = {}
var all_combinable_ids: Array = []
var clicked_tower_id: int = -1

# Родитель для маркеров (должен быть выше башен)
var _markers_layer: Node2D

func _init(ecs_: ECSWorld, hex_map_: HexMap):
	ecs = ecs_
	hex_map = hex_map_

func _ready():
	# Слой для шариков — поверх башен (hex_layer.parent = GameRoot)
	var root = get_parent().get_parent() if get_parent() else null
	if root and root.has_node("TowerLayer"):
		var tower_layer = root.get_node("TowerLayer")
		_markers_layer = Node2D.new()
		_markers_layer.name = "CombinableMarkersLayer"
		_markers_layer.z_index = 50  # Поверх башен
		tower_layer.add_child(_markers_layer)

func _process(_delta: float):
	var phase = ecs.game_state.get("phase", 0)
	var is_tutorial = ecs.game_state.get("is_tutorial", false)
	# В обучении не показываем визуал крафта (чёрные линии, бело-чёрные кружки)
	var show_craft_visual = (phase == GameTypes.GamePhase.WAVE_STATE or phase == GameTypes.GamePhase.TOWER_SELECTION_STATE) and not is_tutorial
	if show_craft_visual:
		_render_highlights()  # только очистка старых кругов, новых не создаём
		_render_combinable_markers()
		_render_combination_links()
	else:
		_clear_all()

# Удаляем старые подсветки под башнями (золотой круг больше не используем)
func _render_highlights():
	for tower_id in highlight_nodes.keys():
		highlight_nodes[tower_id].queue_free()
	highlight_nodes.clear()

# Яркий шарик сверху башни (как в Go: gold cylinder / white-black ball)
func _render_combinable_markers():
	if not _markers_layer:
		return
	
	var towers_to_mark: Dictionary = {}
	for tower_id in ecs.combinables.keys():
		if ecs.towers.has(tower_id):
			towers_to_mark[tower_id] = true
	
	for tower_id in towers_to_mark.keys():
		var tower = ecs.towers[tower_id]
		var hex = tower.get("hex")
		if not hex:
			continue
		var pos = hex.to_pixel(Config.HEX_SIZE)  # По центру башни
		var all_crafts_have_early_curse = _tower_all_crafts_have_early_curse(tower_id)
		if not combinable_markers.has(tower_id):
			var marker = _create_marker_ball(all_crafts_have_early_curse)
			_markers_layer.add_child(marker)
			combinable_markers[tower_id] = marker
		else:
			var marker_node = combinable_markers[tower_id]
			var fill = marker_node.get_child(0) if marker_node.get_child_count() > 0 else null
			if fill is Polygon2D:
				fill.color = Color(0.85, 0.25, 0.25, 0.95) if all_crafts_have_early_curse else Color(1.0, 1.0, 1.0, 0.95)
		var marker_node = combinable_markers[tower_id]
		marker_node.position = pos
		marker_node.visible = true
	
	# Удаляем лишние
	var to_remove = []
	for tower_id in combinable_markers.keys():
		if not towers_to_mark.has(tower_id):
			to_remove.append(tower_id)
	for tower_id in to_remove:
		combinable_markers[tower_id].queue_free()
		combinable_markers.erase(tower_id)

func _tower_all_crafts_have_early_curse(tower_id: int) -> bool:
	"""True если все крафты, в которых участвует эта башня, дают проклятие раннего крафта."""
	if not ecs.combinables.has(tower_id):
		return false
	var crafts = ecs.combinables[tower_id].get("possible_crafts", [])
	if crafts.is_empty():
		return false
	if not GameManager:
		return false
	for c in crafts:
		var out_id = c.get("recipe", {}).get("output_id", "")
		if not GameManager.would_craft_have_early_curse(out_id):
			return false
	return true

func _create_marker_ball(red_curse: bool = false) -> Node2D:
	"""Создаёт шарик: бело-чёрный (крафт без проклятия) или красно-чёрный (все крафты с проклятием раннего крафта)."""
	var container = Node2D.new()
	var radius = Config.HEX_SIZE * 0.35
	var points = PackedVector2Array()
	for i in range(16):
		var angle = (PI * 2 * i) / 16
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	var fill_color = Color(0.85, 0.25, 0.25, 0.95) if red_curse else Color(1.0, 1.0, 1.0, 0.95)
	var fill = Polygon2D.new()
	fill.polygon = points
	fill.color = fill_color
	fill.z_index = 1
	container.add_child(fill)
	var outline = Line2D.new()
	var outline_points = points.duplicate()
	outline_points.append(points[0])
	outline.points = outline_points
	outline.width = 2.0
	outline.default_color = Color(0.0, 0.0, 0.0, 1.0)
	outline.z_index = 2
	container.add_child(outline)
	return container

func _clear_all():
	"""Скрыть всё когда не волна"""
	for tower_id in highlight_nodes.keys():
		highlight_nodes[tower_id].visible = false
	for tower_id in combinable_markers.keys():
		combinable_markers[tower_id].visible = false
	for line_key in link_lines.keys():
		link_lines[line_key].visible = false

# Рисует линии между башнями в выбранной комбинации (только треугольник одного рецепта при 4+ башнях)
func _render_combination_links():
	var link_set: Array = []
	if all_combinable_ids.size() > 3 and clicked_tower_id >= 0 and clicked_tower_id in all_combinable_ids:
		# Показываем только треугольник рецепта, в котором участвует кликнутая башня
		if selected_combination.size() == 3 and selected_combination.has(clicked_tower_id):
			link_set = selected_combination.duplicate()
		else:
			var crafts = ecs.combinables.get(clicked_tower_id, {}).get("possible_crafts", [])
			for c in crafts:
				var comb = c.get("combination", [])
				if comb.size() == 3 and comb.has(clicked_tower_id):
					link_set = comb.duplicate()
					break
			if link_set.is_empty():
				link_set = selected_combination.duplicate() if selected_combination.size() == 3 else []
	elif not selected_combination.is_empty():
		link_set = selected_combination.duplicate()
	
	if link_set.is_empty():
		for line_key in link_lines.keys():
			link_lines[line_key].queue_free()
		link_lines.clear()
		return
	
	var active_links: Dictionary = {}
	for i in range(link_set.size()):
		for j in range(i + 1, link_set.size()):
			var tower1_id = link_set[i]
			var tower2_id = link_set[j]
			var tower1 = ecs.towers.get(tower1_id)
			var tower2 = ecs.towers.get(tower2_id)
			if not tower1 or not tower2:
				continue
			var hex1 = tower1.get("hex")
			var hex2 = tower2.get("hex")
			if not hex1 or not hex2:
				continue
			var pos1 = hex1.to_pixel(Config.HEX_SIZE)
			var pos2 = hex2.to_pixel(Config.HEX_SIZE)
			var link_key = "%d-%d" % [tower1_id, tower2_id]
			active_links[link_key] = [pos1, pos2]
	
	# Создаём/обновляем линии
	for link_key in active_links.keys():
		var positions = active_links[link_key]
		
		if not link_lines.has(link_key):
			var line = Line2D.new()
			line.width = 3.0
			line.default_color = Color(0.0, 0.0, 0.0, 1.0)  # Чёрные линии
			line.antialiased = true
			line.z_index = 96  # Между атак линиями и энергосетью
			add_child(line)
			link_lines[link_key] = line
		
		var line_node = link_lines[link_key]
		line_node.points = PackedVector2Array(positions)
	
	# Удаляем неактуальные линии
	var to_remove = []
	for link_key in link_lines.keys():
		if not active_links.has(link_key):
			to_remove.append(link_key)
	
	for link_key in to_remove:
		link_lines[link_key].queue_free()
		link_lines.erase(link_key)

# Выбрать комбинацию для preview. all_combinable = все башни в ecs.combinables, clicked = на какой кликнули (для 4+ вышек: все со всеми или только треугольник).
func set_selected_combination(combination: Array, recipe: Dictionary, all_combinable: Array = [], clicked: int = -1):
	selected_combination = combination
	selected_recipe = recipe
	all_combinable_ids = all_combinable.duplicate() if all_combinable.size() > 0 else []
	clicked_tower_id = clicked

# Очистить выбор
func clear_selection():
	selected_combination = []
	selected_recipe = {}
	all_combinable_ids = []
	clicked_tower_id = -1

# ============================================================================
# АНИМАЦИЯ КРАФТА
# ============================================================================

# Проигрывает анимацию крафта
func play_craft_animation(combination: Array, result_hex: Hex):
	"""Красивая анимация: вспышка + частицы из ингредиентов к результату"""
	var result_pos = result_hex.to_pixel(Config.HEX_SIZE)
	
	# Собираем позиции ингредиентов
	var ingredient_positions = []
	for tower_id in combination:
		if ecs.towers.has(tower_id):
			var tower = ecs.towers[tower_id]
			var hex = tower.get("hex")
			if hex:
				ingredient_positions.append(hex.to_pixel(Config.HEX_SIZE))
	
	# Создаем вспышку в центре результата
	var flash = ColorRect.new()
	flash.color = Color(1.0, 0.84, 0.0, 0.8)  # Золотой
	flash.position = result_pos - Vector2(50, 50)
	flash.size = Vector2(100, 100)
	flash.z_index = 200  # Поверх всего
	add_child(flash)
	
	# Анимация вспышки: появление + исчезновение
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "modulate:a", 0.0, 0.5).from(0.8)
	tween.tween_property(flash, "scale", Vector2(3.0, 3.0), 0.5).from(Vector2(0.1, 0.1))
	tween.tween_callback(func(): flash.queue_free()).set_delay(0.5)
	
	# Создаем летящие частицы от ингредиентов к результату
	for start_pos in ingredient_positions:
		for i in range(3):  # 3 частицы на каждый ингредиент
			await get_tree().create_timer(i * 0.05).timeout  # Небольшая задержка
			_create_flying_particle(start_pos, result_pos)

func _create_flying_particle(start_pos: Vector2, end_pos: Vector2):
	"""Создает летящую частицу"""
	var particle = ColorRect.new()
	particle.color = Color(1.0, 0.84, 0.0, 0.9)  # Золотой
	particle.size = Vector2(8, 8)
	particle.position = start_pos - Vector2(4, 4)
	particle.z_index = 199
	add_child(particle)
	
	# Анимация полета
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(particle, "position", end_pos - Vector2(4, 4), 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(particle, "modulate:a", 0.0, 0.4).from(0.9)
	tween.tween_callback(func(): particle.queue_free()).set_delay(0.4)

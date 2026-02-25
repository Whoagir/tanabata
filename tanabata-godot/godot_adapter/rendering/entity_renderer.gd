# entity_renderer.gd
# Рендеринг сущностей (башни, враги, снаряды)
extends Node2D

var ecs: ECSWorld
var tower_nodes: Dictionary = {}  # entity_id -> Node2D
var enemy_nodes: Dictionary = {}  # entity_id -> Node2D
var projectile_nodes: Dictionary = {}  # entity_id -> Node2D
var laser_nodes: Dictionary = {}  # laser_id -> Line2D
var volcano_effect_nodes: Dictionary = {}  # effect_id -> Polygon2D
var beacon_sector_nodes: Dictionary = {}  # tower_id -> Polygon2D

# Слои
var tower_layer: Node2D
var enemy_layer: Node2D
var projectile_layer: Node2D
var effect_layer: Node2D
var laser_layer: Node2D  # Лазеры рисуем здесь (гарантированно видимый слой)

# Object Pools
var enemy_pool: NodePool
var projectile_pool: NodePool

# Оптимизация: кэш состояния башен (для избежания лишних обновлений)
var tower_state_cache: Dictionary = {}  # tower_id -> {is_active, is_highlighted, is_selected}

# Соединения майнеров
var miner_connections_layer: Node2D  # Слой для соединений между майнерами и стенами
var miner_connection_lines: Dictionary = {}  # "id1_id2" -> Line2D

# Подсветка гексов
var hex_highlight_layer: Node2D  # Слой для подсветки гексов (под башнями)
var hex_highlights: Dictionary = {}  # entity_id -> {fill: Polygon2D, outline: Line2D}

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================================

func _ready():
	ecs = GameManager.ecs
	
	# Получаем слои из parent (GameRoot)
	tower_layer = get_parent().get_node("TowerLayer")
	enemy_layer = get_parent().get_node("EnemyLayer")
	projectile_layer = get_parent().get_node("ProjectileLayer")
	effect_layer = get_parent().get_node("EffectLayer")
	# Лазеры — на своём слое внутри рендерера, чтобы точно рисовались поверх всего
	laser_layer = Node2D.new()
	laser_layer.name = "LaserLayer"
	laser_layer.z_index = 100
	add_child(laser_layer)
	
	# Создаем слой для соединений майнеров (под башнями, но над стенами)
	miner_connections_layer = Node2D.new()
	miner_connections_layer.name = "MinerConnectionsLayer"
	miner_connections_layer.z_index = 24  # Чуть ниже башен (25), но выше стен
	tower_layer.add_child(miner_connections_layer)
	
	# Создаем слой для подсветки гексов (под всем)
	hex_highlight_layer = Node2D.new()
	hex_highlight_layer.name = "HexHighlightLayer"
	hex_highlight_layer.z_index = -10  # Под всеми остальными слоями
	tower_layer.add_child(hex_highlight_layer)
	
	# Создаем Object Pools
	enemy_pool = NodePool.new(
		enemy_layer,
		_create_pooled_enemy,
		_reset_enemy,
		20  # Предсоздаем 20 врагов
	)
	
	projectile_pool = NodePool.new(
		projectile_layer,
		_create_pooled_projectile,
		_reset_projectile,
		50  # Предсоздаем 50 снарядов
	)

# ============================================================================
# ОБНОВЛЕНИЕ
# ============================================================================

func _process(_delta):
	_render_hex_highlights()  # Рендерим подсветку гексов ПЕРВОЙ (под всем)
	
	Profiler.start("render_towers")
	_render_towers()
	Profiler.end("render_towers")
	
	Profiler.start("render_enemies")
	_render_enemies()
	Profiler.end("render_enemies")
	
	Profiler.start("render_projectiles")
	_render_projectiles()
	Profiler.end("render_projectiles")
	
	_render_lasers()
	_render_volcano_effects()
	_render_beacon_sectors()
	_render_miner_connections()
	

# ============================================================================
# РЕНДЕРИНГ БАШЕН
# ============================================================================

func _render_towers():
	# Удаляем башни, которых больше нет в ECS (один get_tower_def на удаляемую башню)
	var to_remove = []
	for tower_id in tower_nodes.keys():
		if not ecs.has_component(tower_id, "tower"):
			tower_nodes[tower_id].queue_free()
			to_remove.append(tower_id)
		else:
			var tower = ecs.towers[tower_id]
			var tower_def = GameManager.get_tower_def(tower.get("def_id", ""))
			if tower_def.get("type") == "WALL":
				tower_nodes[tower_id].queue_free()
				to_remove.append(tower_id)
	for tower_id in to_remove:
		tower_nodes.erase(tower_id)
		tower_state_cache.erase(tower_id)
	
	# Обновляем/создаем башни — один get_tower_def на башню за кадр, передаём в _update_*
	for tower_id in ecs.towers.keys():
		if not ecs.has_component(tower_id, "position"):
			continue
		if not ecs.has_component(tower_id, "renderable"):
			continue
		var tower = ecs.towers[tower_id]
		var tower_def = GameManager.get_tower_def(tower.get("def_id", ""))
		if tower_def.get("type") == "WALL":
			if tower_id in tower_nodes:
				tower_nodes[tower_id].queue_free()
				tower_nodes.erase(tower_id)
				tower_state_cache.erase(tower_id)
			continue
		var pos = ecs.positions[tower_id]
		var renderable = ecs.renderables[tower_id]
		var cached_state = tower_state_cache.get(tower_id, {})
		var def_changed = (cached_state.get("def_id", "") != tower.get("def_id", "") or
			cached_state.get("crafting_level", -1) != tower.get("crafting_level", 0))
		if def_changed and tower_id in tower_nodes:
			tower_nodes[tower_id].queue_free()
			tower_nodes.erase(tower_id)
			tower_state_cache.erase(tower_id)
		if not tower_id in tower_nodes:
			var tower_node = _create_tower_visual(renderable, tower_id)
			tower_layer.add_child(tower_node)
			tower_nodes[tower_id] = tower_node
		var tower_node = tower_nodes[tower_id]
		tower_node.position = pos
		if tower_def.get("type") == "MINER":
			var is_on_ore = _is_miner_on_ore(tower_id)
			tower_node.scale = Vector2(1.1, 1.1) if is_on_ore else Vector2.ONE
		var current_state = {
			"def_id": tower.get("def_id", ""),
			"crafting_level": tower.get("crafting_level", 0),
			"is_active": tower.get("is_active", false),
			"is_highlighted": tower.get("is_highlighted", false),
			"is_selected": tower.get("is_selected", false),
			"is_manually_selected": tower.get("is_manually_selected", false)
		}
		cached_state = tower_state_cache.get(tower_id, {})
		var state_changed = (
			cached_state.get("is_active") != current_state["is_active"] or
			cached_state.get("is_highlighted") != current_state["is_highlighted"] or
			cached_state.get("is_selected") != current_state["is_selected"] or
			cached_state.get("is_manually_selected") != current_state["is_manually_selected"]
		)
		if state_changed:
			_update_tower_color(tower_node, tower, tower_def)
			_update_tower_highlight(tower_node, tower, tower_def)
			tower_state_cache[tower_id] = current_state

# ============================================================================
# РЕНДЕРИНГ ВРАГОВ
# ============================================================================

func _render_enemies():
	# Возвращаем в пул врагов, которых больше нет в ECS
	var to_remove = []
	for enemy_id in enemy_nodes.keys():
		if not ecs.has_component(enemy_id, "enemy"):
			enemy_pool.release(enemy_nodes[enemy_id])
			to_remove.append(enemy_id)
	for enemy_id in to_remove:
		enemy_nodes.erase(enemy_id)
	
	# Обновляем/создаем врагов
	for enemy_id in ecs.enemies.keys():
		if not ecs.has_component(enemy_id, "position"):
			continue
		if not ecs.has_component(enemy_id, "renderable"):
			continue
		
		var pos = ecs.positions[enemy_id]
		var renderable = ecs.renderables[enemy_id]
		
		# Берем из пула если ещё нет
		if not enemy_id in enemy_nodes:
			var enemy_node = enemy_pool.acquire()
			_update_enemy_visual(enemy_node, renderable)
			enemy_nodes[enemy_id] = enemy_node
		
		# Обновляем позицию
		var enemy_node = enemy_nodes[enemy_id]
		enemy_node.position = pos
		
		# Летающие — поверх всего (стены, башни, обычных врагов)
		var enemy_data = ecs.enemies.get(enemy_id, {})
		var def_id = enemy_data.get("def_id", "")
		var enemy_def = DataRepository.get_enemy_def(def_id) if def_id else {}
		var flying = enemy_def.get("flying", false)
		enemy_node.z_index = 50 if flying else 0
		
		# Обновляем здоровье (масштаб)
		if ecs.has_component(enemy_id, "health"):
			var health = ecs.healths[enemy_id]
			var health_percent = float(health["current"]) / float(health["max"])
			var scale_factor = 0.6 + 0.4 * health_percent  # От 60% до 100%
			enemy_node.scale = Vector2(scale_factor, scale_factor)
		
		# Визуализация статус-эффектов (приоритет: damage_flash > jade_poison > poison > slow)
		var body = enemy_node.get_node_or_null("Body")
		if body:
			if ecs.damage_flashes.has(enemy_id):
				# Красная вспышка при уроне
				body.modulate = Config.ENEMY_DAMAGE_COLOR
			elif ecs.jade_poisons.has(enemy_id):
				# Зелёный оттенок от Jade — чем больше стаков, тем очень зеленее (4 стака = макс)
				var jade = ecs.jade_poisons[enemy_id]
				var instances = jade.get("instances", [])
				var stacks = instances.size()
				var strength = clamp(0.15 + float(stacks) * 0.25, 0.0, 1.0)  # 4 стака ≈ 1.0
				body.modulate = Color.WHITE.lerp(Config.ENEMY_JADE_POISON_COLOR, strength)
			elif ecs.poison_effects.has(enemy_id):
				# Зеленоватый оттенок при обычном яде
				body.modulate = Config.ENEMY_POISON_COLOR
			elif ecs.mag_armor_debuffs.has(enemy_id):
				# Фиолетовый оттенок при снижении маг. брони (NE)
				body.modulate = Config.ENEMY_MAG_ARMOR_DEBUFF_COLOR
			elif ecs.phys_armor_debuffs.has(enemy_id):
				# Рыже-медный оттенок при снижении физ. брони (NA)
				body.modulate = Config.ENEMY_PHYS_ARMOR_DEBUFF_COLOR
			elif ecs.slow_effects.has(enemy_id):
				# Голубоватый оттенок при замедлении
				body.modulate = Config.ENEMY_SLOW_COLOR
			else:
				# Нормальный цвет
				body.modulate = Color(1.0, 1.0, 1.0)
		
		# Обводка для выделенных врагов (движущиеся сущности)
		var outline = enemy_node.get_node_or_null("Outline")
		if outline:
			var enemy = ecs.enemies.get(enemy_id, {})
			var is_highlighted = enemy.get("is_highlighted", false)
			outline.visible = is_highlighted

# ============================================================================
# РЕНДЕРИНГ СНАРЯДОВ
# ============================================================================

func _render_projectiles():
	# Возвращаем в пул снаряды, которых больше нет в ECS
	var to_remove = []
	for proj_id in projectile_nodes.keys():
		if not ecs.has_component(proj_id, "projectile"):
			projectile_pool.release(projectile_nodes[proj_id])
			to_remove.append(proj_id)
	for proj_id in to_remove:
		projectile_nodes.erase(proj_id)
	
	# Обновляем/создаем снаряды
	for proj_id in ecs.projectiles.keys():
		if not ecs.has_component(proj_id, "position"):
			continue
		if not ecs.has_component(proj_id, "renderable"):
			continue
		
		var pos = ecs.positions[proj_id]
		var renderable = ecs.renderables[proj_id]
		
		# Берем из пула если ещё нет
		if not proj_id in projectile_nodes:
			var proj_node = projectile_pool.acquire()
			_update_projectile_visual(proj_node, renderable)
			projectile_nodes[proj_id] = proj_node
		
		# Обновляем позицию
		var proj_node = projectile_nodes[proj_id]
		proj_node.position = pos

# ============================================================================
# РЕНДЕРИНГ ЛАЗЕРОВ
# ============================================================================

func _render_lasers():
	var to_remove = []
	for lid in laser_nodes.keys():
		if not ecs.lasers.has(lid):
			laser_nodes[lid].queue_free()
			to_remove.append(lid)
	for lid in to_remove:
		laser_nodes.erase(lid)
	
	for laser_id in ecs.lasers.keys():
		var laser = ecs.lasers[laser_id]
		var start_pos = _to_vector2(laser.get("start_pos"))
		var target_pos = _to_vector2(laser.get("target_pos"))
		var color = laser.get("color", Color.WHITE)
		
		if start_pos != null and target_pos != null:
			var line: Line2D
			if laser_nodes.has(laser_id):
				line = laser_nodes[laser_id]
				line.clear_points()
			else:
				line = Line2D.new()
				line.width = 5.0
				line.z_index = 0
				laser_layer.add_child(line)
				laser_nodes[laser_id] = line
			line.add_point(start_pos)
			line.add_point(target_pos)
			line.default_color = color

# Приведение к Vector2 (на случай если из ECS пришёл dict с x,y)
func _to_vector2(v) -> Variant:
	if v == null:
		return null
	if v is Vector2:
		return v
	if v is Dictionary and v.has("x") and v.has("y"):
		return Vector2(float(v.x), float(v.y))
	return null

# ============================================================================
# РЕНДЕРИНГ VOLCANO EFFECTS (огненные круги при попадании)
# ============================================================================

func _render_volcano_effects():
	var to_remove = []
	for eid in volcano_effect_nodes.keys():
		if not ecs.volcano_effects.has(eid):
			volcano_effect_nodes[eid].queue_free()
			to_remove.append(eid)
	for eid in to_remove:
		volcano_effect_nodes.erase(eid)
	
	for effect_id in ecs.volcano_effects.keys():
		var eff = ecs.volcano_effects[effect_id]
		var pos = eff.get("pos", Vector2.ZERO)
		var timer = eff.get("timer", 0.25)
		var max_r = eff.get("max_radius", 15.0)
		var col = eff.get("color", Color(1.0, 0.27, 0.0))
		var progress = 1.0 - timer / 0.25
		var alpha = 0.6 * (1.0 - progress)
		col.a = alpha
		
		var node: Polygon2D
		if volcano_effect_nodes.has(effect_id):
			node = volcano_effect_nodes[effect_id]
		else:
			node = Polygon2D.new()
			effect_layer.add_child(node)
			volcano_effect_nodes[effect_id] = node
		
		node.position = pos
		var radius = max_r * progress
		node.scale = Vector2(radius, radius)
		if not node.has_meta("_unit_circle"):
			var points = PackedVector2Array()
			for i in range(24):
				var a = TAU * i / 24
				points.append(Vector2(cos(a), sin(a)))
			node.polygon = points
			node.set_meta("_unit_circle", true)
		node.color = col

# ============================================================================
# РЕНДЕРИНГ BEACON SECTORS (сектор урона Маяка)
# ============================================================================

func _render_beacon_sectors():
	var to_remove = []
	for tid in beacon_sector_nodes.keys():
		var sector = ecs.beacon_sectors.get(tid)
		if not sector or not sector.get("is_visible", false):
			beacon_sector_nodes[tid].queue_free()
			to_remove.append(tid)
	for tid in to_remove:
		beacon_sector_nodes.erase(tid)
	
	for tower_id in ecs.beacon_sectors.keys():
		var sector = ecs.beacon_sectors[tower_id]
		if not sector.get("is_visible", false):
			continue
		var pos = ecs.positions.get(tower_id, Vector2.ZERO)
		var angle = sector.get("angle", 0.0)
		var arc = sector.get("arc", PI / 2)
		var range_hex = sector.get("range", 4)
		var radius = range_hex * Config.HEX_SIZE
		var start_a = angle - arc / 2
		var end_a = angle + arc / 2
		
		var node: Polygon2D
		if beacon_sector_nodes.has(tower_id):
			node = beacon_sector_nodes[tower_id]
		else:
			node = Polygon2D.new()
			node.color = Color(1.0, 1.0, 0.7, 0.25)
			node.z_index = 5
			effect_layer.add_child(node)
			beacon_sector_nodes[tower_id] = node
		
		node.position = pos
		var points = PackedVector2Array()
		points.append(Vector2.ZERO)
		for i in range(25):
			var t = float(i) / 24.0
			var a = lerp_angle(start_a, end_a, t)
			points.append(Vector2(cos(a), sin(a)) * radius)
		node.polygon = points

# ============================================================================
# СОЗДАНИЕ ВИЗУАЛА
# ============================================================================

func _create_tower_visual(renderable: Dictionary, tower_id: int) -> Node2D:
	var container = Node2D.new()
	container.set_meta("entity_id", tower_id)
	
	# Получаем тип башни
	var tower = ecs.towers.get(tower_id, {})
	var tower_def_id = tower.get("def_id", "")
	var tower_def = GameManager.get_tower_def(tower_def_id)
	var tower_type = tower_def.get("type", "ATTACK")
	
	var radius = renderable.get("radius", 10.0)
	var color = renderable.get("color", Color.WHITE)
	
	# Создаем форму в зависимости от типа (как в Go версии)
	var body: Node2D
	if tower_type == "MINER":
		# Майнер - ЖЕЛТЫЙ ШЕСТИУГОЛЬНИК (простой и чистый)
		body = _create_hexagon(radius, color)
		body.z_index = 1
		
		# Обводка шестиугольника (небольшая)
		var miner_outline = Line2D.new()
		miner_outline.name = "MinerOutline"
		miner_outline.width = 2.0
		miner_outline.default_color = Color(0.8, 0.7, 0.0, 0.9)  # Темнее желтая обводка
		miner_outline.z_index = 2
		miner_outline.antialiased = true
		_add_hexagon_outline(miner_outline, radius)
		container.add_child(miner_outline)
		
		# Синий кружок в центре (для активных майнеров на руде) - УВЕЛИЧЕННЫЙ И ЯРКИЙ
		var energy_dot = Polygon2D.new()
		energy_dot.name = "EnergyDot"
		var dot_radius = 6.0
		var dot_points = PackedVector2Array()
		var segments = 32
		for i in range(segments):
			var angle = (PI * 2 * i) / segments
			dot_points.append(Vector2(cos(angle), sin(angle)) * dot_radius)
		energy_dot.polygon = dot_points
		energy_dot.color = Color(0.2, 0.6, 1.0, 1.0)  # Более яркий синий
		energy_dot.position = Vector2(0, 0)
		energy_dot.z_index = 100  # ПОВЕРХ ВСЕГО!
		energy_dot.visible = false
		container.add_child(energy_dot)
		
		# Маленький кружок сети (когда в сети но НЕ на руде)
		var network_dot = _create_network_dot()
		container.add_child(network_dot)
	elif tower_type == "WALL":
		# Стена - ШЕСТИУГОЛЬНИК (серый)
		body = _create_hexagon(radius, color)
	else:
		# Атакующая (ATTACK): крафт 1 = квадрат, крафт 2 = треугольник, иначе круг
		var crafting_level = tower.get("crafting_level", 0)
		if crafting_level >= 2:
			body = _create_triangle(radius, color)
		elif crafting_level == 1:
			body = _create_square(radius, color)
		else:
			body = _create_circle(radius, color)
		
		# Маленький кружок сети (когда в энергосети)
		var network_dot = _create_network_dot()
		container.add_child(network_dot)
	
	body.name = "Body"
	container.add_child(body)
	
	# Обводка для подсветки выбора
	var outline = Line2D.new()
	outline.name = "Outline"
	outline.z_index = 10  # Поверх всего
	outline.antialiased = true
	
	# Обводка в зависимости от формы
	if tower_type == "MINER":
		# Майнеры: базовая ЖЕЛТАЯ обводка (всегда видна, 40% прозрачность)
		outline.width = 2.0
		outline.default_color = Color(1.0, 1.0, 0.0, 0.4)  # ЖЕЛТАЯ, 40% прозрачность
		outline.visible = true  # Всегда видна для майнеров
		_add_hexagon_outline(outline, radius)
	elif tower_type == "WALL":
		# Стены: НЕТ обводки (стены не выделяются)
		outline.width = 0.0
		outline.visible = false
		_add_hexagon_outline(outline, radius)
	else:
		# Атакующие: крафт 1–2 — золотистая обводка, иначе белая
		var crafting_level = tower.get("crafting_level", 0)
		outline.width = 2.5 if crafting_level >= 1 else 2.0
		outline.default_color = Color(1.0, 0.84, 0.2, 0.6) if crafting_level >= 1 else Color(1.0, 1.0, 1.0, 0.4)
		outline.visible = true
		if crafting_level >= 2:
			_add_triangle_outline(outline, radius)
		elif crafting_level == 1:
			_add_square_outline(outline, radius)
		else:
			_add_circle_outline(outline, radius)
	
	container.add_child(outline)
	
	return container

# Создание круга (для добывающих)
func _create_circle(radius: float, color: Color) -> Polygon2D:
	var polygon = Polygon2D.new()
	var points = PackedVector2Array()
	var segments = 16
	for i in range(segments):
		var angle = (PI * 2 * i) / segments
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	polygon.polygon = points
	polygon.color = color
	return polygon

# Создание треугольника (для атакующих)
func _create_triangle(radius: float, color: Color) -> Polygon2D:
	var polygon = Polygon2D.new()
	var points = PackedVector2Array()
	# Треугольник смотрит вверх
	points.append(Vector2(0, -radius * 1.2))  # Верх
	points.append(Vector2(radius, radius * 0.7))  # Право
	points.append(Vector2(-radius, radius * 0.7))  # Лево
	polygon.polygon = points
	polygon.color = color
	return polygon

# Создание перевернутого треугольника (для нижней части майнера)
func _create_inverted_triangle(radius: float, color: Color) -> Polygon2D:
	var polygon = Polygon2D.new()
	var points = PackedVector2Array()
	# Треугольник смотрит вниз
	points.append(Vector2(0, radius * 1.2))  # Низ
	points.append(Vector2(-radius, -radius * 0.7))  # Лево-верх
	points.append(Vector2(radius, -radius * 0.7))  # Право-верх
	polygon.polygon = points
	polygon.color = color
	return polygon

# Квадрат (крафт уровень 1)
func _create_square(radius: float, color: Color) -> Polygon2D:
	var polygon = Polygon2D.new()
	var r = radius * 0.9
	var points = PackedVector2Array([Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)])
	polygon.polygon = points
	polygon.color = color
	return polygon

# Создание шестиугольника (для стен)
func _create_hexagon(radius: float, color: Color) -> Polygon2D:
	var polygon = Polygon2D.new()
	var points = PackedVector2Array()
	for i in range(6):
		var angle = (PI * 2 * i) / 6 - PI / 6
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	polygon.polygon = points
	polygon.color = color
	return polygon

# Обводки
func _add_circle_outline(line: Line2D, radius: float):
	var segments = 16
	for i in range(segments + 1):
		var angle = (PI * 2 * i) / segments
		line.add_point(Vector2(cos(angle), sin(angle)) * radius)

func _add_square_outline(line: Line2D, radius: float):
	var r = radius * 0.9
	line.add_point(Vector2(-r, -r))
	line.add_point(Vector2(r, -r))
	line.add_point(Vector2(r, r))
	line.add_point(Vector2(-r, r))
	line.add_point(Vector2(-r, -r))

func _add_triangle_outline(line: Line2D, radius: float):
	line.add_point(Vector2(0, -radius * 1.2))
	line.add_point(Vector2(radius, radius * 0.7))
	line.add_point(Vector2(-radius, radius * 0.7))
	line.add_point(Vector2(0, -radius * 1.2))

func _add_inverted_triangle_outline(line: Line2D, radius: float):
	line.add_point(Vector2(0, radius * 1.2))
	line.add_point(Vector2(radius, -radius * 0.7))
	line.add_point(Vector2(-radius, -radius * 0.7))
	line.add_point(Vector2(0, radius * 1.2))

# Обводка для гексаграммы (звезда из двух треугольников)
func _add_hexagram_outline(line: Line2D, radius: float):
	# Обводим всю звезду по внешнему контуру (6 лучей)
	# Верхняя точка верхнего треугольника
	line.add_point(Vector2(0, -radius * 1.2))
	# Правая точка нижнего треугольника
	line.add_point(Vector2(radius, -radius * 0.7))
	# Правая нижняя точка верхнего треугольника
	line.add_point(Vector2(radius, radius * 0.7))
	# Нижняя точка нижнего треугольника
	line.add_point(Vector2(0, radius * 1.2))
	# Левая нижняя точка верхнего треугольника
	line.add_point(Vector2(-radius, radius * 0.7))
	# Левая точка нижнего треугольника
	line.add_point(Vector2(-radius, -radius * 0.7))
	# Замыкаем
	line.add_point(Vector2(0, -radius * 1.2))

func _add_hexagon_outline(line: Line2D, radius: float):
	for i in range(7):
		var angle = (PI * 2 * i) / 6 - PI / 6
		line.add_point(Vector2(cos(angle), sin(angle)) * radius)

func _create_entity_visual(renderable: Dictionary) -> Node2D:
	var container = Node2D.new()
	
	var rect = ColorRect.new()
	var radius = renderable.get("radius", 10.0)
	rect.size = Vector2(radius * 2, radius * 2)
	rect.position = Vector2(-radius, -radius)
	rect.color = renderable.get("color", Color.WHITE)
	container.add_child(rect)
	
	return container

func _update_tower_color(tower_node: Node2D, tower: Dictionary, tower_def: Dictionary = {}):
	var body = tower_node.get_node_or_null("Body")
	if not body:
		return
	if tower_def.is_empty():
		tower_def = GameManager.get_tower_def(tower.get("def_id", ""))
	if not tower_def:
		return
	var tower_type = tower_def.get("type", "ATTACK")
	var is_active = tower.get("is_active", false)
	
	# Базовый цвет из visuals
	var base_color = Color.WHITE
	if tower_def.has("visuals") and tower_def["visuals"].has("color"):
		var color_dict = tower_def["visuals"]["color"]
		base_color = Color(
			color_dict.get("r", 255) / 255.0,
			color_dict.get("g", 255) / 255.0,
			color_dict.get("b", 255) / 255.0,
			color_dict.get("a", 255) / 255.0
		)
	else:
		# Цвета по умолчанию (если нет в JSON)
		match tower_type:
			"MINER":
				base_color = Color(1.0, 0.84, 0.0)  # Золотой
			"WALL":
				base_color = Color(0.41, 0.41, 0.41)  # Темно-серый
			_:
				base_color = Color(1.0, 0.31, 0.0)  # Оранжевый
	
	# Неактивные башни (кроме стен) затемняются
	if tower_type != "WALL" and not is_active:
		# Майнеры неактивные тоже затемняются + 15%
		if tower_type == "MINER":
			body.color = base_color.darkened(0.15).darkened(0.5)
		else:
			body.color = base_color.darkened(0.5)
	else:
		# Майнеры на 15% тусклее (даже когда активны)
		if tower_type == "MINER":
			body.color = base_color.darkened(0.15)
		else:
			body.color = base_color
	
	# Для майнера обновляем обводку и синий кружок
	if tower_type == "MINER":
		# Обновляем обводку шестиугольника
		var miner_outline = tower_node.get_node_or_null("MinerOutline")
		if miner_outline:
			var outline_color = Color(0.8, 0.7, 0.0, 0.9)  # Темнее желтая
			if not is_active:
				miner_outline.default_color = outline_color.darkened(0.5)
			else:
				miner_outline.default_color = outline_color
		
		# Показываем/скрываем синий кружок ТОЛЬКО если майнер стоит на руде
		var energy_dot = tower_node.get_node_or_null("EnergyDot")
		if energy_dot:
			# Получаем tower_id из метаданных ноды
			var tower_id = tower_node.get_meta("entity_id")
			var is_on_ore = _is_miner_on_ore(tower_id)
			energy_dot.visible = is_active and is_on_ore
		
		# Маленький кружок: когда в сети но НЕ на руде
		var network_dot = tower_node.get_node_or_null("NetworkDot")
		if network_dot:
			var tower_id = tower_node.get_meta("entity_id")
			var is_on_ore = _is_miner_on_ore(tower_id)
			network_dot.visible = is_active and not is_on_ore
	
	# Для атакующих: маленький кружок когда в сети
	if tower_type == "ATTACK":
		var network_dot = tower_node.get_node_or_null("NetworkDot")
		if network_dot:
			network_dot.visible = is_active

func _create_network_dot() -> Polygon2D:
	"""Маленький синий кружок (половина линии ~4px) для башен в энергосети"""
	var dot = Polygon2D.new()
	dot.name = "NetworkDot"
	dot.z_index = 99
	dot.visible = false
	var dot_radius = 3.0  # Маленький кружок в центре линии
	var pts = PackedVector2Array()
	for i in range(16):
		var a = (PI * 2 * i) / 16
		pts.append(Vector2(cos(a), sin(a)) * dot_radius)
	dot.polygon = pts
	dot.color = Color(0.2, 0.6, 1.0, 1.0)
	return dot

func _update_tower_highlight(tower_node: Node2D, tower: Dictionary, tower_def: Dictionary = {}):
	var outline = tower_node.get_node_or_null("Outline")
	if not outline or not outline is Line2D:
		return
	if tower_def.is_empty():
		tower_def = GameManager.get_tower_def(tower.get("def_id", ""))
	var is_highlighted = tower.get("is_highlighted", false)
	var is_selected = tower.get("is_selected", false)
	var is_manually_selected = tower.get("is_manually_selected", false)
	var tower_type = tower_def.get("type", "ATTACK") if tower_def else "ATTACK"
	
	var any_selection = is_highlighted or is_selected or is_manually_selected
	
	# Обновляем обводку в зависимости от типа башни
	if tower_type == "MINER":
		# Майнеры: базовая ЖЕЛТАЯ обводка всегда видна
		# При выборе - ЖЕЛТАЯ но чуть толще
		if any_selection:
			outline.default_color = Color(1.0, 1.0, 0.0, 0.7)  # ЖЕЛТАЯ 70% при выборе
			outline.width = 2.5
		else:
			outline.default_color = Color(1.0, 1.0, 0.0, 0.4)  # ЖЕЛТАЯ 40% базово
			outline.width = 2.0
	elif tower_type == "WALL":
		# Стены: НИКОГДА не показываем обводку
		outline.visible = false
	else:
		# Атакующие: пассивная БЕЛАЯ обводка всегда видна
		# При выборе - ЖЕЛТАЯ и толще
		outline.visible = true  # Всегда видна!
		
		if any_selection:
			outline.width = 2.5
			outline.default_color = Color(1.0, 1.0, 0.0, 0.7)  # ЖЕЛТАЯ при выборе
		else:
			outline.width = 2.0
			outline.default_color = Color(1.0, 1.0, 1.0, 0.4)  # БЕЛАЯ 40% базово

# ============================================================================
# OBJECT POOL ФУНКЦИИ
# ============================================================================

func _create_pooled_enemy() -> Node2D:
	var container = Node2D.new()
	# Враги - квадратики (Polygon2D для modulate)
	var polygon = Polygon2D.new()
	polygon.name = "Body"
	# Создаем квадрат 20x20
	polygon.polygon = PackedVector2Array([
		Vector2(-10, -10),
		Vector2(10, -10),
		Vector2(10, 10),
		Vector2(-10, 10)
	])
	polygon.color = Color.WHITE  # Будет перекрашен через modulate
	container.add_child(polygon)
	
	# Обводка для выделения врагов
	var outline = Line2D.new()
	outline.name = "Outline"
	outline.width = 2.0
	outline.default_color = Color(1.0, 1.0, 0.0, 0.8)  # Желтая обводка
	outline.visible = false
	outline.z_index = 10
	outline.antialiased = true
	# Обводка квадрата
	outline.add_point(Vector2(-10, -10))
	outline.add_point(Vector2(10, -10))
	outline.add_point(Vector2(10, 10))
	outline.add_point(Vector2(-10, 10))
	outline.add_point(Vector2(-10, -10))
	container.add_child(outline)
	
	return container

func _create_pooled_projectile() -> Node2D:
	var container = Node2D.new()
	var circle = Polygon2D.new()
	circle.name = "Body"
	# Создаем круг из 16 точек
	var points = PackedVector2Array()
	var segments = 16
	for i in range(segments):
		var angle = (i / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * 5.0)
	circle.polygon = points
	container.add_child(circle)
	return container

func _reset_enemy(node: Node2D):
	node.position = Vector2.ZERO
	node.scale = Vector2.ONE
	node.rotation = 0.0
	node.z_index = 0  # чтобы при переиспользовании не тянуть «летающий» z

func _reset_projectile(node: Node2D):
	node.position = Vector2.ZERO
	node.scale = Vector2.ONE
	node.rotation = 0.0

func _update_enemy_visual(node: Node2D, renderable: Dictionary):
	var body = node.get_node("Body") as Polygon2D
	if not body:
		return
	
	var radius = renderable.get("radius", 10.0)
	# Обновляем размер квадрата
	body.polygon = PackedVector2Array([
		Vector2(-radius, -radius),
		Vector2(radius, -radius),
		Vector2(radius, radius),
		Vector2(-radius, radius)
	])
	body.color = renderable.get("color", Color.WHITE)

func _update_projectile_visual(node: Node2D, renderable: Dictionary):
	var circle = node.get_node("Body") as Polygon2D
	var radius = renderable.get("radius", 5.0)
	
	# Обновляем размер круга
	var points = PackedVector2Array()
	var segments = 16
	for i in range(segments):
		var angle = (i / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	circle.polygon = points
	circle.color = renderable.get("color", Color.WHITE)

# ============================================================================
# РЕНДЕРИНГ СОЕДИНЕНИЙ МАЙНЕРОВ
# ============================================================================

func _render_miner_connections():
	if not miner_connections_layer:
		return
	
	# Собираем все майнеры и стены
	var hex_map = GameManager.hex_map
	var miners = []
	var miners_set = {}  # tower_id -> true
	var walls_and_miners = {}  # "q_r" -> {id, type}
	
	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		var tower_def = GameManager.get_tower_def(tower.get("def_id", ""))
		if not tower_def:
			continue
		
		var tower_type = tower_def.get("type", "")
		var hex = tower.get("hex")
		if not hex:
			continue
		
		var hex_key = str(hex.q) + "_" + str(hex.r)
		
		if tower_type == "MINER":
			miners.append(tower_id)
			miners_set[tower_id] = true
			walls_and_miners[hex_key] = {"id": tower_id, "type": "MINER", "hex": hex}
		elif tower_type == "WALL":
			walls_and_miners[hex_key] = {"id": tower_id, "type": "WALL", "hex": hex}
	
	# Собираем необходимые соединения
	var needed_connections = {}
	
	for miner_id in miners:
		var tower = ecs.towers[miner_id]
		var hex = tower.get("hex")
		if not hex:
			continue
		
		var pos = hex.to_pixel(Config.HEX_SIZE)
		
		# Проверяем всех 6 соседей
		for dir in range(6):
			var neighbor_hex = hex.neighbor(dir)
			var neighbor_hex_key = str(neighbor_hex.q) + "_" + str(neighbor_hex.r)
			
			if walls_and_miners.has(neighbor_hex_key):
				var neighbor_data = walls_and_miners[neighbor_hex_key]
				var neighbor_id = neighbor_data["id"]
				var neighbor_type = neighbor_data["type"]
				var neighbor_pos = neighbor_hex.to_pixel(Config.HEX_SIZE)
				
				# Создаем ключ (меньший id первый, чтобы не дублировать)
				var key = ""
				if miner_id < neighbor_id:
					key = str(miner_id) + "_" + str(neighbor_id)
				else:
					key = str(neighbor_id) + "_" + str(miner_id)
				
				# Определяем тип соединения и цвет
				var connection_type = ""
				var line_color = Color.WHITE
				var line_width = 0.0
				var outline_width = 0.0
				var outline_color = Color.WHITE
				
				if neighbor_type == "MINER":
					# Майнер-Майнер: более серая и заметная линия с желтой обводкой (ЕЩЁ ЯРЧЕ)
					connection_type = "miner_miner"
					line_color = Color(0.7, 0.7, 0.5, 0.5)  # Серо-желтая, ещё ярче (0.35 -> 0.5)
					line_width = 7.0  # Чуть шире чем энергия (5.0)
					outline_width = 9.0  # Желтая обводка
					outline_color = Color(1.0, 0.9, 0.0, 0.55)  # Яркая желтая обводка (0.4 -> 0.55)
				else:
					# Майнер-Стена: более серая и заметная (с желтой обводкой, ЕЩЁ ЯРЧЕ)
					connection_type = "miner_wall"
					line_color = Color(0.65, 0.65, 0.55, 0.5)  # Серо-желтоватая, ярче (0.4 -> 0.5)
					line_width = Config.HEX_SIZE * 0.5
					outline_width = Config.HEX_SIZE * 0.5 + 2.0  # Желтая обводка
					outline_color = Color(1.0, 0.9, 0.0, 0.45)  # Яркая желтая обводка (0.35 -> 0.45)
				
				needed_connections[key] = {
					"pos1": pos,
					"pos2": neighbor_pos,
					"color": line_color,
					"width": line_width,
					"outline_width": outline_width,
					"outline_color": outline_color,
					"type": connection_type
				}
	
	# Удаляем ненужные линии
	var to_remove = []
	for key in miner_connection_lines.keys():
		if not needed_connections.has(key):
			var line_data = miner_connection_lines[key]
			if line_data.has("outline"):
				line_data["outline"].queue_free()
			if line_data.has("line"):
				line_data["line"].queue_free()
			to_remove.append(key)
	for key in to_remove:
		miner_connection_lines.erase(key)
	
	# Создаем/обновляем линии
	for key in needed_connections.keys():
		var conn = needed_connections[key]
		
		if not miner_connection_lines.has(key):
			var line_data = {}
			
			# Создаем обводку если нужна
			if conn["outline_width"] > 0:
				var outline = Line2D.new()
				outline.width = conn["outline_width"]
				outline.default_color = conn["outline_color"]
				outline.antialiased = true
				outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
				outline.end_cap_mode = Line2D.LINE_CAP_ROUND
				outline.z_index = 0
				miner_connections_layer.add_child(outline)
				line_data["outline"] = outline
			
			# Основная линия
			var line = Line2D.new()
			line.width = conn["width"]
			line.default_color = conn["color"]
			line.antialiased = true
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
			line.z_index = 1
			miner_connections_layer.add_child(line)
			line_data["line"] = line
			
			miner_connection_lines[key] = line_data
		
		var line_data = miner_connection_lines[key]
		
		# Обновляем позиции обводки
		if line_data.has("outline"):
			var outline = line_data["outline"]
			outline.clear_points()
			outline.add_point(conn["pos1"])
			outline.add_point(conn["pos2"])
		
		# Обновляем позиции линии
		var line = line_data["line"]
		line.clear_points()
		line.add_point(conn["pos1"])
		line.add_point(conn["pos2"])

# ============================================================================
# РЕНДЕРИНГ ПОДСВЕТКИ ГЕКСОВ
# ============================================================================

func _render_hex_highlights():
	if not hex_highlight_layer:
		return
	
	# Собираем сущности, которые нужно подсветить (башни, руда)
	var entities_to_highlight = {}  # entity_id -> {pos, radius, color}
	
	# Башни
	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		var tower_def_id = tower.get("def_id", "")
		var tower_def = GameManager.get_tower_def(tower_def_id)
		var tower_type = tower_def.get("type", "ATTACK") if tower_def else "ATTACK"
		
		# СТЕНЫ НЕ ПОДСВЕЧИВАЕМ НИКОГДА
		if tower_type == "WALL":
			continue
		
		var is_highlighted = tower.get("is_highlighted", false)
		var is_selected = tower.get("is_selected", false)
		var is_manually_selected = tower.get("is_manually_selected", false)
		var is_temporary = tower.get("is_temporary", false)
		var phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
		var show_phase_built_blue = (phase == GameTypes.GamePhase.BUILD_STATE or phase == GameTypes.GamePhase.TOWER_SELECTION_STATE) and is_temporary
		
		# Подсвечиваем если есть выделение ИЛИ башня построена в этой фазе (голубой гекс)
		if not (is_highlighted or is_selected or is_manually_selected or show_phase_built_blue):
			continue
		
		# Получаем позицию и радиус
		if not ecs.has_component(tower_id, "position"):
			continue
		if not ecs.has_component(tower_id, "renderable"):
			continue
		
		var pos = ecs.positions[tower_id]
		var radius = Config.HEX_SIZE * 0.95  # РАЗМЕР ГЕКСА НА КАРТЕ
		
		# Определяем цвет подсветки в зависимости от приоритета
		var highlight_color = Color(0.7, 0.7, 0.7, 0.25)  # СЕРЫЙ по умолчанию
		
		# Приоритет: is_selected > is_manually_selected > is_highlighted > построена в этой фазе (голубой)
		if is_selected:
			# СОХРАНЕНО (кнопка "Сохранить") - ГОЛУБОЙ гекс
			highlight_color = Color(0.3, 0.8, 1.0, 0.35)
		elif is_manually_selected:
			# Выделено для крафта (Shift+клик) - ФИОЛЕТОВЫЙ гекс
			highlight_color = Color(0.8, 0.3, 1.0, 0.3)
		elif is_highlighted:
			# Просто выбрано (обычный клик) - СЕРЫЙ гекс
			highlight_color = Color(0.7, 0.7, 0.7, 0.25)
		elif show_phase_built_blue:
			# Построена в этой фазе (BUILD/SELECTION) - голубой гекс
			highlight_color = Color(0.35, 0.7, 1.0, 0.28)
		else:
			# Не должно сюда попасть
			continue
		
		entities_to_highlight[tower_id] = {
			"pos": pos,
			"radius": radius,
			"color": highlight_color
		}
	
	# Руда (неподвижная, поэтому hex highlight)
	for ore_id in ecs.ores.keys():
		var ore = ecs.ores[ore_id]
		var is_highlighted = ore.get("is_highlighted", false)
		
		if not is_highlighted:
			continue
		
		# Получаем позицию
		if not ecs.has_component(ore_id, "position"):
			continue
		
		var pos = ecs.positions[ore_id]
		var radius = Config.HEX_SIZE * 0.95  # РАЗМЕР ГЕКСА НА КАРТЕ
		
		# Руда - ЖЕЛТЫЙ гекс
		var highlight_color = Color(1.0, 1.0, 0.0, 0.2)
		
		entities_to_highlight[ore_id] = {
			"pos": pos,
			"radius": radius,
			"color": highlight_color
		}
	
	# Удаляем лишние подсветки
	var to_remove = []
	for entity_id in hex_highlights.keys():
		if not entities_to_highlight.has(entity_id):
			var highlight_data = hex_highlights[entity_id]
			if highlight_data.has("fill"):
				highlight_data["fill"].queue_free()
			if highlight_data.has("outline"):
				highlight_data["outline"].queue_free()
			to_remove.append(entity_id)
	for entity_id in to_remove:
		hex_highlights.erase(entity_id)
	
	# Создаем/обновляем подсветки
	for entity_id in entities_to_highlight.keys():
		var data = entities_to_highlight[entity_id]
		
		if not hex_highlights.has(entity_id):
			# Создаем новую подсветку
			var highlight_data = {}
			
			# Заливка (полупрозрачный шестиугольник)
			var fill = Polygon2D.new()
			fill.name = "HexFill_%d" % entity_id
			var hex_points = PackedVector2Array()
			for i in range(6):
				var angle = (PI * 2 * i) / 6 - PI / 6
				hex_points.append(Vector2(cos(angle), sin(angle)) * data["radius"])
			fill.polygon = hex_points
			fill.color = data["color"]
			fill.z_index = 0
			hex_highlight_layer.add_child(fill)
			highlight_data["fill"] = fill
			
			# Обводка гекса (более яркая)
			var outline = Line2D.new()
			outline.name = "HexOutline_%d" % entity_id
			outline.width = 2.0
			outline.default_color = Color(data["color"].r, data["color"].g, data["color"].b, data["color"].a * 2.5)  # Ярче в 2.5 раза
			outline.antialiased = true
			outline.z_index = 1
			for i in range(7):  # 7 точек чтобы замкнуть
				var angle = (PI * 2 * i) / 6 - PI / 6
				outline.add_point(Vector2(cos(angle), sin(angle)) * data["radius"])
			hex_highlight_layer.add_child(outline)
			highlight_data["outline"] = outline
			
			hex_highlights[entity_id] = highlight_data
		
		# Обновляем позицию и цвет
		var highlight_data = hex_highlights[entity_id]
		if highlight_data.has("fill"):
			highlight_data["fill"].position = data["pos"]
			highlight_data["fill"].color = data["color"]
		if highlight_data.has("outline"):
			highlight_data["outline"].position = data["pos"]
			var outline_color = Color(data["color"].r, data["color"].g, data["color"].b, data["color"].a * 2.5)
			highlight_data["outline"].default_color = outline_color

# Проверяет, стоит ли майнер на руде — O(1) через ore_hex_index
func _is_miner_on_ore(tower_id: int) -> bool:
	if not ecs.towers.has(tower_id):
		return false
	var tower = ecs.towers[tower_id]
	var hex = tower.get("hex")
	if not hex:
		return false
	var ore_id = ecs.ore_hex_index.get(hex.to_key(), -1)
	if ore_id < 0:
		return false
	var ore = ecs.ores.get(ore_id)
	if not ore:
		return false
	return ore.get("current_reserve", 0.0) >= Config.ORE_DEPLETION_THRESHOLD

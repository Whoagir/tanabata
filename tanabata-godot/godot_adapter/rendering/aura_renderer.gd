# aura_renderer.gd
# Рендеринг аур башен
extends Node2D

var ecs: ECSWorld
var hex_map: HexMap

var aura_circles: Dictionary = {}  # tower_id -> Line2D
# Кэш состояния: tower_id -> {is_active, radius, hex_key} — обновляем визуал только при изменении
var _aura_state_cache: Dictionary = {}

func _ready():
	ecs = GameManager.ecs
	hex_map = GameManager.hex_map
	z_index = 15

func _process(_delta):
	_render_auras()

func _render_auras():
	var to_remove = []
	for tower_id in aura_circles.keys():
		if not ecs.auras.has(tower_id) or not ecs.towers.has(tower_id):
			aura_circles[tower_id].queue_free()
			to_remove.append(tower_id)
	for tower_id in to_remove:
		aura_circles.erase(tower_id)
		_aura_state_cache.erase(tower_id)
	
	for tower_id in ecs.auras.keys():
		var tower = ecs.towers.get(tower_id)
		if not tower:
			continue
		
		var is_active = tower.get("is_active", false)
		if not is_active:
			if aura_circles.has(tower_id):
				aura_circles[tower_id].queue_free()
				aura_circles.erase(tower_id)
				_aura_state_cache.erase(tower_id)
			continue
		
		var aura_data = ecs.auras[tower_id]
		var radius = aura_data.get("radius", 2)
		var hex = tower.get("hex")
		var hex_key = hex.to_key() if hex else ""
		
		var cached = _aura_state_cache.get(tower_id, {})
		var state_changed = (
			cached.get("is_active") != is_active or
			cached.get("radius") != radius or
			cached.get("hex_key") != hex_key
		)
		
		if not state_changed and aura_circles.has(tower_id):
			continue
		
		var pos = hex.to_pixel(Config.HEX_SIZE)
		var pixel_radius = radius * Config.HEX_SIZE * 1.8
		
		var circle: Line2D
		if aura_circles.has(tower_id):
			circle = aura_circles[tower_id]
		else:
			circle = Line2D.new()
			circle.width = 2.0
			circle.default_color = Color(0.2, 0.8, 0.2, 0.5)
			add_child(circle)
			aura_circles[tower_id] = circle
		
		circle.clear_points()
		for i in range(33):
			var angle = (i / 32.0) * TAU
			circle.add_point(pos + Vector2(cos(angle), sin(angle)) * pixel_radius)
		
		_aura_state_cache[tower_id] = {"is_active": is_active, "radius": radius, "hex_key": hex_key}

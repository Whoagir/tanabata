# entity_factory.gd
# Фабрика для создания сущностей (башни, враги, снаряды, стены)
# Единая точка истины для создания - избегаем дублирования
class_name EntityFactory

# ============================================================================
# БАШНИ
# ============================================================================

# Создать башню по определению
static func create_tower(ecs: ECSWorld, hex_map: HexMap, hex: Hex, def_id: String) -> int:
	var tower_def = DataRepository.get_tower_def(def_id)
	if tower_def.is_empty():
		push_error("Cannot create tower: definition not found for %s" % def_id)
		return GameTypes.INVALID_ENTITY_ID
	
	var entity_id = ecs.create_entity()
	var pixel_pos = hex.to_pixel(Config.HEX_SIZE)
	
	# Position (прямое присвоение, не через add_component)
	ecs.positions[entity_id] = pixel_pos
	
	# Все компоненты башни (tower, renderable, combat, aura) — одна подфункция
	_apply_tower_components(ecs, entity_id, hex, def_id, tower_def)
	
	# Обновляем карту
	hex_map.place_tower(hex, entity_id)
	
	return entity_id


# Внутренний «рецепт»: навешивает tower, renderable, combat (если есть в def), aura (если есть).
# Вызов только из create_tower. Не трогает карту (hex_map).
static func _apply_tower_components(ecs: ECSWorld, entity_id: int, hex: Hex, def_id: String, tower_def: Dictionary) -> void:
	var tower_type = tower_def.get("type", "ATTACK")
	ecs.add_component(entity_id, "tower", {
		"def_id": def_id,
		"level": tower_def.get("level", 1),
		"hex_q": hex.q,
		"hex_r": hex.r,
		"hex": hex,
		"is_active": false,
		"type": tower_type,
		"is_temporary": true,
		"is_permanent": false,
		"is_selected": false,
		"is_manually_selected": false,
		"is_highlighted": false,
		"crafting_level": 0,
		"mvp_level": 0
	})
	
	# Renderable компонент (размер по уровню: Lv.1 меньше, Lv.6 близок к гексу)
	var visuals = tower_def.get("visuals", {})
	var level = tower_def.get("level", 1)
	var radius_factor = visuals.get("radius_factor", 0.6)
	if level >= 1 and level <= 6:
		radius_factor = Config.get_tower_radius_factor_for_level(level)
	var color_value = visuals.get("color", "#FF8C00")
	var color: Color
	if typeof(color_value) == TYPE_STRING:
		color = Color.html(color_value)  # Парсим hex-строку
	elif typeof(color_value) == TYPE_DICTIONARY:
		# Формат {r: 255, g: 140, b: 0, a: 255}
		color = Color(
			color_value.get("r", 255) / 255.0,
			color_value.get("g", 140) / 255.0,
			color_value.get("b", 0) / 255.0,
			color_value.get("a", 255) / 255.0
		)
	else:
		color = Color.ORANGE  # Fallback
	
	ecs.add_component(entity_id, "renderable", {
		"color": color,
		"radius": Config.HEX_SIZE * radius_factor
	})
	
	# Combat — только если в def есть ключ "combat" (не смотрим на type)
	if tower_def.has("combat"):
		var combat_data = tower_def.get("combat", {})
		var attack_def = combat_data.get("attack", {})
		var params = attack_def.get("params", {})
		
		var combat_comp = {
			"damage": combat_data.get("damage", 10),
			"fire_rate": combat_data.get("fire_rate", 1.0),
			"range": combat_data.get("range", 3),
			"fire_cooldown": 0.0,  # ← ВАЖНО: fire_cooldown, НЕ cooldown!
			"shot_cost": combat_data.get("shot_cost", 1.0),
			"attack_type": attack_def.get("damage_type", "PHYSICAL"),
			"split_count": params.get("split_count", 1) if typeof(params) == TYPE_DICTIONARY else 1,
			"attack_type_data": attack_def  # ← КРИТИЧНО: полные данные атаки!
		}
		ecs.add_component(entity_id, "combat", combat_comp)
	
	# Aura — только если в def есть непустой "aura"
	var aura_data = tower_def.get("aura", {})
	if not aura_data.is_empty():
		var aura_comp = {
			"radius": aura_data.get("radius", 2),
			"speed_multiplier": aura_data.get("speed_multiplier", 1.0),
			"damage_bonus": aura_data.get("damage_bonus", 0)
		}
		if aura_data.get("flying_only", false):
			aura_comp["flying_only"] = true
			aura_comp["slow_factor"] = aura_data.get("slow_factor", 0.0)
		ecs.add_component(entity_id, "aura", aura_comp)

# Создать стену
static func create_wall(ecs: ECSWorld, hex_map: HexMap, hex: Hex) -> int:
	var entity_id = ecs.create_entity()
	var pixel_pos = hex.to_pixel(Config.HEX_SIZE)
	
	# Position (прямое присвоение)
	ecs.positions[entity_id] = pixel_pos
	
	# Получаем определение стены из DataRepository (если есть)
	var wall_def = DataRepository.get_tower_def("TOWER_WALL")
	if wall_def.is_empty():
		wall_def = {"visuals": {"color": "#8B4513", "radius_factor": 0.5}}
	
	# Tower компонент (стена это особый тип башни)
	ecs.add_component(entity_id, "tower", {
		"def_id": "TOWER_WALL",
		"level": 1,
		"hex_q": hex.q,
		"hex_r": hex.r,
		"hex": hex,
		"is_active": false,
		"type": "WALL",
		"is_temporary": false,
		"is_permanent": true,
		"is_selected": false,
		"is_manually_selected": false,
		"is_highlighted": false,
		"crafting_level": 0,
		"mvp_level": 0
	})
	
	# Renderable (используем визуалы из определения)
	var visuals = wall_def.get("visuals", {})
	var color_value = visuals.get("color", "#8B4513")
	var color: Color
	if typeof(color_value) == TYPE_STRING:
		color = Color.html(color_value)
	elif typeof(color_value) == TYPE_DICTIONARY:
		color = Color(
			color_value.get("r", 139) / 255.0,
			color_value.get("g", 69) / 255.0,
			color_value.get("b", 19) / 255.0,
			color_value.get("a", 255) / 255.0
		)
	else:
		color = Color.SADDLE_BROWN
	
	ecs.add_component(entity_id, "renderable", {
		"color": color,
		"radius": Config.HEX_SIZE * visuals.get("radius_factor", 0.6),
		"visible": true
	})
	
	# Обновляем карту
	hex_map.place_tower(hex, entity_id)
	
	# Тайл непроходимый
	var tile = hex_map.get_tile(hex)
	if tile:
		tile.passable = false
		hex_map.set_tile(hex, tile)
	
	return entity_id

# ============================================================================
# ВРАГИ
# ============================================================================

# Создать врага
static func create_enemy(ecs: ECSWorld, def_id: String, path_hexes: Array) -> int:
	var enemy_def = DataRepository.get_enemy_def(def_id)
	if enemy_def.is_empty():
		push_error("Cannot create enemy: definition not found for %s" % def_id)
		return GameTypes.INVALID_ENTITY_ID
	
	var entity_id = ecs.create_entity()
	
	# Стартовая позиция на первом гексе пути
	if path_hexes.is_empty():
		push_error("Cannot create enemy: empty path")
		ecs.destroy_entity(entity_id)
		return GameTypes.INVALID_ENTITY_ID
	
	var start_hex: Hex = path_hexes[0]
	var start_pos = start_hex.to_pixel(Config.HEX_SIZE)
	
	# Position (прямое присвоение)
	ecs.positions[entity_id] = start_pos
	
	# Velocity (прямое присвоение)
	ecs.velocities[entity_id] = Vector2.ZERO
	
	# Health
	var max_health = enemy_def.get("health", 100)
	ecs.add_component(entity_id, "health", {
		"current": max_health,
		"max": max_health
	})
	
	# Enemy
	ecs.add_component(entity_id, "enemy", {
		"def_id": def_id,
		"physical_armor": enemy_def.get("physical_armor", 0),
		"magical_armor": enemy_def.get("magical_armor", 0),
		"base_speed": enemy_def.get("speed", 80.0),
		"current_speed": enemy_def.get("speed", 80.0),
		"is_highlighted": false  # Для выделения при клике
	})
	
	# Path
	ecs.add_component(entity_id, "path", {
		"hexes": path_hexes,
		"current_index": 0
	})
	
	# Renderable
	var enemy_color_value = enemy_def.get("color", "#FF0000")
	var enemy_color: Color
	if typeof(enemy_color_value) == TYPE_STRING:
		enemy_color = Color.html(enemy_color_value)
	else:
		enemy_color = Color.RED
	
	ecs.add_component(entity_id, "renderable", {
		"color": enemy_color,
		"radius": Config.HEX_SIZE * 0.4
	})
	
	return entity_id

# ============================================================================
# СНАРЯДЫ
# ============================================================================

# Создать снаряд
static func create_projectile(
	ecs: ECSWorld,
	source_id: int,
	target_id: int,
	damage: int,
	damage_type: String,
	start_pos: Vector2
) -> int:
	var entity_id = ecs.create_entity()
	
	# Position (прямое присвоение)
	ecs.positions[entity_id] = start_pos
	
	# Projectile
	ecs.add_component(entity_id, "projectile", {
		"source_id": source_id,
		"target_id": target_id,
		"damage": damage,
		"speed": Config.PROJECTILE_SPEED,
		"damage_type": damage_type
	})
	
	# Renderable (цвет зависит от типа урона)
	var proj_color = _get_damage_type_color(damage_type)
	ecs.add_component(entity_id, "renderable", {
		"color": proj_color,
		"radius": Config.HEX_SIZE * 0.2
	})
	
	return entity_id

# Создать лазер (визуальный эффект)
static func create_laser(
	ecs: ECSWorld,
	source_pos: Vector2,
	target_pos: Vector2,
	damage_type: String
) -> int:
	var entity_id = ecs.create_entity()
	
	# Position (начальная точка - прямое присвоение)
	ecs.positions[entity_id] = source_pos
	
	# Laser
	ecs.add_component(entity_id, "laser", {
		"target_pos": target_pos,
		"timer": Config.LASER_DURATION,
		"damage_type": damage_type
	})
	
	return entity_id

# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
# ============================================================================

# Получить цвет для типа урона
static func _get_damage_type_color(damage_type: String) -> Color:
	match damage_type.to_upper():
		"PHYSICAL":
			return Config.PHYSICAL_COLOR
		"MAGICAL":
			return Config.MAGICAL_COLOR
		"PURE":
			return Config.PURE_COLOR
		"SLOW":
			return Config.SLOW_COLOR
		"POISON":
			return Config.POISON_COLOR
		_:
			return Color.WHITE

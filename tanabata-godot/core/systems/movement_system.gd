# movement_system.gd
# Система движения врагов по пути
class_name MovementSystem

var ecs: ECSWorld
var hex_map: HexMap

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================================

func _init(ecs_: ECSWorld, hex_map_: HexMap):
	ecs = ecs_
	hex_map = hex_map_

# ============================================================================
# ОБНОВЛЕНИЕ
# ============================================================================

func update(delta: float):
	Profiler.start("movement_system")
	
	_update_flying_aura_slows()
	
	# Обрабатываем всех врагов с Path компонентом
	var enemies_to_remove = []
	
	
	for enemy_id in ecs.enemies.keys():
		if not ecs.has_component(enemy_id, "path"):
			continue
		if not ecs.has_component(enemy_id, "position"):
			continue
		
		var enemy = ecs.enemies[enemy_id]
		_update_rush_state(enemy_id, enemy, delta)
		_update_blink(enemy_id, enemy, delta)
		_update_aggro(enemy_id, enemy, delta)
		var path = ecs.paths[enemy_id]
		var pos = ecs.positions[enemy_id]
		
		var speed = enemy.get("speed", enemy.get("base_speed", 80.0))
		var effective_speed = _calculate_effective_speed(enemy_id, speed)
		
		# Текущая цель
		if path["current_index"] >= path["hexes"].size():
			# Достигли конца пути - наносим урон игроку
			_damage_player(enemy_id)
			enemies_to_remove.append(enemy_id)
			continue
		
		var target_hex = path["hexes"][path["current_index"]]
		var target_pos = target_hex.to_pixel(Config.HEX_SIZE)
		
		# Двигаемся к цели
		var direction = (target_pos - pos).normalized()
		var distance = pos.distance_to(target_pos)
		var move_distance = effective_speed * delta
		
		if move_distance >= distance:
			# Достигли текущего гекса
			ecs.positions[enemy_id] = target_pos
			path["current_index"] += 1
			
			# Урон от окружения (руда и энерголинии)
			_apply_environmental_damage(enemy_id, target_hex)
			if not ecs.enemies.has(enemy_id):
				continue  # Враг погиб от окружения
			
			# Проверяем чекпоинты
			_check_checkpoint(enemy_id, target_hex)
		else:
			# Продолжаем движение
			ecs.positions[enemy_id] = pos + direction * move_distance
	
	# Удаляем врагов, которые дошли до конца
	for enemy_id in enemies_to_remove:
		ecs.destroy_entity(enemy_id)
	
	Profiler.end("movement_system")

# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ============================================================================

func _update_blink(enemy_id: int, enemy: Dictionary, delta: float) -> void:
	if not enemy.get("abilities", []).has("blink"):
		return
	if ecs.bash_effects.has(enemy_id):
		return
	var cd = enemy.get("blink_cooldown_left", 0.0)
	if cd > 0:
		enemy["blink_cooldown_left"] = cd - delta
		return
	var path = ecs.paths.get(enemy_id)
	if not path or path["current_index"] >= path["hexes"].size():
		return
	var advance = mini(Config.BLINK_HEXES, path["hexes"].size() - path["current_index"])
	if advance <= 0:
		return
	path["current_index"] += advance
	var dest_hex = path["hexes"][path["current_index"] - 1]
	ecs.positions[enemy_id] = dest_hex.to_pixel(Config.HEX_SIZE)
	_apply_environmental_damage(enemy_id, dest_hex)
	if not ecs.enemies.has(enemy_id):
		return
	_check_checkpoint(enemy_id, dest_hex)
	enemy["blink_cooldown_left"] = Config.BLINK_COOLDOWN

func _update_rush_state(enemy_id: int, enemy: Dictionary, delta: float) -> void:
	if not enemy.get("abilities", []).has("rush"):
		return
	# Баш: не может применять активные скиллы (rush), только тикает кулдаун
	if ecs.bash_effects.has(enemy_id):
		enemy["rush_duration_left"] = 0.0
		var rush_cd = enemy.get("rush_cooldown_left", 0.0)
		if rush_cd > 0:
			enemy["rush_cooldown_left"] = rush_cd - delta
		return
	var rush_dur = enemy.get("rush_duration_left", 0.0)
	var rush_cd = enemy.get("rush_cooldown_left", 0.0)
	if rush_dur > 0:
		enemy["rush_duration_left"] = rush_dur - delta
		return
	if rush_cd > 0:
		enemy["rush_cooldown_left"] = rush_cd - delta
		return
	enemy["rush_duration_left"] = Config.RUSH_DURATION
	enemy["rush_cooldown_left"] = Config.RUSH_COOLDOWN

func _update_aggro(enemy_id: int, enemy: Dictionary, delta: float) -> void:
	if not enemy.get("abilities", []).has("aggro"):
		return
	var dur = enemy.get("aggro_duration_left", 0.0)
	var cd = enemy.get("aggro_cooldown_left", 0.0)
	if dur > 0:
		enemy["aggro_duration_left"] = dur - delta
		return
	if cd > 0:
		enemy["aggro_cooldown_left"] = cd - delta
		return
	enemy["aggro_duration_left"] = Config.AGGRO_DURATION
	enemy["aggro_cooldown_left"] = Config.AGGRO_COOLDOWN

func _update_flying_aura_slows():
	"""Заполняет flying_aura_slows: летающие враги в радиусе аур с flying_only получают замедление."""
	ecs.flying_aura_slows.clear()
	for tower_id in ecs.auras.keys():
		var aura = ecs.auras[tower_id]
		if not aura.get("flying_only", false):
			continue
		var slow_factor = aura.get("slow_factor", 0.0)
		if slow_factor <= 0:
			continue
		var tower = ecs.towers.get(tower_id, {})
		if not tower.get("is_active", false):
			continue
		var tower_hex = tower.get("hex")
		if tower_hex == null:
			continue
		var radius = int(aura.get("radius", 2))
		for enemy_id in ecs.enemies.keys():
			var enemy = ecs.enemies[enemy_id]
			if not enemy.get("flying", false):
				continue
			var pos = ecs.positions.get(enemy_id)
			if pos == null:
				continue
			var enemy_hex = Hex.from_pixel(pos, Config.HEX_SIZE)
			if tower_hex.distance_to(enemy_hex) <= radius:
				var cur = ecs.flying_aura_slows.get(enemy_id, 0.0)
				ecs.flying_aura_slows[enemy_id] = max(cur, slow_factor)

func _calculate_effective_speed(enemy_id: int, base_speed: float) -> float:
	if ecs.bash_effects.has(enemy_id):
		return 0.0
	var speed = base_speed
	
	if ecs.slow_effects.has(enemy_id):
		var slow = ecs.slow_effects[enemy_id]
		speed *= slow.get("slow_factor", 1.0)
	
	if ecs.jade_poisons.has(enemy_id):
		var jade = ecs.jade_poisons[enemy_id]
		var instances = jade.get("instances", [])
		var stacks = instances.size()
		var slow_per_stack = jade.get("slow_factor_per_stack", 0.05)
		var total_slow = slow_per_stack * stacks
		var speed_mult = max(1.0 - total_slow, 0.1)
		speed *= speed_mult
	
	# Кварц: аура замедления только для летающих
	var flying_slow = ecs.flying_aura_slows.get(enemy_id, 0.0)
	if flying_slow > 0:
		speed *= (1.0 - flying_slow)
	
	# Раш: +250% скорости на 2 сек, кулдаун 5 сек
	var enemy = ecs.enemies.get(enemy_id, {})
	if enemy.get("rush_duration_left", 0.0) > 0:
		speed *= Config.RUSH_SPEED_MULT
	
	return speed

func _apply_environmental_damage(enemy_id: int, hex: Hex) -> void:
	var total_damage = 0
	var hex_key = hex.to_key()
	# O(1) проверка руды через ore_hex_index
	var ore_id = ecs.ore_hex_index.get(hex_key, -1)
	if ore_id >= 0:
		var ore = ecs.ores.get(ore_id)
		if ore and ore.get("current_reserve", 0.0) >= Config.ORE_DEPLETION_THRESHOLD:
			total_damage += Config.ENV_DAMAGE_ORE_PER_TICK
	# O(1) проверка энерголинии через предвычисленный line_hex_set
	if GameManager.energy_network and GameManager.energy_network.line_hex_set.has(hex_key):
		total_damage += Config.ENV_DAMAGE_LINE_PER_TICK
	if total_damage <= 0:
		return
	var health = ecs.healths.get(enemy_id)
	if not health:
		return
	health["current"] = max(0, health["current"] - total_damage)
	ecs.damage_flashes[enemy_id] = {"timer": 0.2}
	if health["current"] <= 0:
		ecs.kill_enemy(enemy_id)

func _check_checkpoint(enemy_id: int, hex: Hex):
	var enemy = ecs.enemies[enemy_id]
	
	# Проверяем, является ли текущий гекс чекпоинтом
	for i in range(hex_map.checkpoints.size()):
		var cp = hex_map.checkpoints[i]
		if hex.equals(cp):
			if i > enemy.get("last_checkpoint_index", -1):
				enemy["last_checkpoint_index"] = i
			break

func _damage_player(enemy_id: int):
	var enemy = ecs.enemies[enemy_id]
	var base_damage = enemy.get("damage_to_player", 10)
	# Обучение уровень 0 (Основы): враги наносят 5 урона игроку, чтобы было наглядно
	if ecs.game_state.get("is_tutorial", false) and ecs.game_state.get("tutorial_index", -1) == 0:
		base_damage = 5
	# Босс наносит урон пропорционально оставшемуся HP (50% HP = 50% урона)
	var damage = base_damage
	if enemy.get("def_id", "") == "ENEMY_BOSS":
		var health = ecs.healths.get(enemy_id)
		if health:
			var cur = health.get("current", 1)
			var mx = health.get("max", 1)
			if mx > 0:
				damage = max(1, int(base_damage * float(cur) / float(mx)))
	
	for player_id in ecs.player_states.keys():
		var player = ecs.player_states[player_id]
		player["health"] -= damage
		if player["health"] <= 0 and not Config.god_mode:
			pass  # TODO: game over
		return

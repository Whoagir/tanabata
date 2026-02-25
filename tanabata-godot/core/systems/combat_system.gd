# core/systems/combat_system.gd
# Система атаки башен
extends RefCounted

var ecs: ECSWorld
var hex_map

# Кэш для оптимизации (не трогаем логику энергосети, только кэшируем результаты)
var power_source_cache: Dictionary = {}  # tower_id -> {sources: Array, timestamp: float}
var cache_lifetime: float = 0.25  # Обновляем кэш раз в 0.25 сек
# В начале волны не используем кэш 0.5 сек — избегаем бага "первая башня не стреляет" (майнер + две вышки, сохраняем вторую)
var _wave_start_time: float = -999.0
var _last_seen_wave: int = -1
const WAVE_START_CACHE_GRACE: float = 0.5
# Один раз за волну логируем причину пропуска (для отладки)
var _debug_skip_logged: Dictionary = {}  # key "w{wave}_t{tower_id}_{reason}" -> true

func _init(ecs_world: ECSWorld, map):
	ecs = ecs_world
	hex_map = map

func clear_power_cache() -> void:
	"""Сбрасывает кэш источников питания. Вызывать после rebuild_energy_network()."""
	power_source_cache.clear()

func _update_disarm_timers(delta: float) -> void:
	"""Уменьшаем таймеры дизарма башен."""
	var to_erase = []
	for tid in ecs.tower_disarm.keys():
		var entry = ecs.tower_disarm[tid]
		if typeof(entry) == TYPE_DICTIONARY:
			entry["timer"] = entry.get("timer", 0) - delta
			if entry["timer"] <= 0:
				to_erase.append(tid)
		else:
			to_erase.append(tid)
	for tid in to_erase:
		ecs.tower_disarm.erase(tid)

func _update_attack_slow_timers(delta: float) -> void:
	var to_erase = []
	for tid in ecs.tower_attack_slow.keys():
		var entry = ecs.tower_attack_slow[tid]
		entry["timer"] = entry.get("timer", 0) - delta
		if entry["timer"] <= 0:
			to_erase.append(tid)
	for tid in to_erase:
		ecs.tower_attack_slow.erase(tid)

func _apply_untouchable_to_tower(tower_id: int, target_enemy_id: int) -> void:
	if not ecs.enemies.has(target_enemy_id):
		return
	var abilities = ecs.enemies[target_enemy_id].get("abilities", [])
	if not abilities.has("untouchable"):
		return
	if not ecs.combat.has(tower_id):
		return
	var attack_type = str(ecs.combat[tower_id].get("attack_type_data", {}).get("type", "PROJECTILE")).to_upper()
	if attack_type == "NONE" or attack_type == "AREA_OF_EFFECT":
		return
	ecs.tower_attack_slow[tower_id] = {
		"timer": Config.UNTOUCHABLE_DURATION,
		"multiplier": Config.UNTOUCHABLE_SLOW_MULTIPLIER
	}

func _apply_disarm_from_enemies() -> void:
	"""Враги с способностью disarm накладывают дизарм на атакующие башни в радиусе."""
	var range_hex = Config.DISARM_RANGE_HEX
	var duration = Config.DISARM_DURATION
	for enemy_id in ecs.enemies.keys():
		var enemy = ecs.enemies[enemy_id]
		if not enemy:
			continue
		var abilities = enemy.get("abilities", [])
		if not abilities.has("disarm"):
			continue
		var pos = ecs.positions.get(enemy_id)
		if not pos:
			continue
		var enemy_hex = Hex.from_pixel(pos, Config.HEX_SIZE)
		for tid in ecs.combat.keys():
			var t = ecs.towers.get(tid)
			if not t:
				continue
			var tower_hex = t.get("hex")
			if tower_hex == null:
				continue
			if enemy_hex.distance_to(tower_hex) <= range_hex:
				ecs.tower_disarm[tid] = { "timer": duration }

func update(delta: float):
	var current_phase = ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	if current_phase != GameTypes.GamePhase.WAVE_STATE:
		_last_seen_wave = -1  # сброс при выходе из WAVE, чтобы новая волна снова получила grace period
		return
	
	# Проверяем есть ли вообще враги (оптимизация)
	if ecs.enemies.size() == 0:
		return
	
	# Дизарм и антачибл: обновляем таймеры
	_update_disarm_timers(delta)
	_update_attack_slow_timers(delta)
	_apply_disarm_from_enemies()
	
	var current_wave = ecs.game_state.get("current_wave", 0)
	# Запомнить время старта волны (для отключения кэша в начале волны)
	if current_wave != _last_seen_wave:
		_last_seen_wave = current_wave
		_wave_start_time = Time.get_ticks_msec() / 1000.0
	# Один раз за волну: список атакующих башен и их is_active (для отладки "первая не стреляет")
	if Config.COMBAT_DEBUG:
		var key = "w%d_started" % current_wave
		if not _debug_skip_logged.get(key, false):
			_debug_skip_logged[key] = true
			var lines: Array[String] = []
			for tid in ecs.combat.keys():
				var t = ecs.towers.get(tid, {})
				var active = t.get("is_active", false)
				var def_id = t.get("def_id", "?")
				lines.append("%d(%s active=%s)" % [tid, def_id, active])
			print("[CombatDebug] Wave %d started, enemies=%d. Combat towers: %s" % [current_wave, ecs.enemies.size(), ", ".join(lines)])
	for tower_id in ecs.combat.keys():
		var tower = ecs.towers.get(tower_id)
		if not tower:
			continue
		# Дизарм: башня не стреляет пока под эффектом
		if ecs.tower_disarm.get(tower_id, {}).get("timer", 0) > 0:
			continue
		
		var is_active = tower.get("is_active", false)
		if not is_active:
			if Config.COMBAT_DEBUG:
				var key = "w%d_t%d_not_active" % [current_wave, tower_id]
				if not _debug_skip_logged.get(key, false):
					_debug_skip_logged[key] = true
					print("[CombatDebug] Tower %d (def=%s) SKIP: not active (no power in network)" % [tower_id, tower.get("def_id", "?")])
			continue
		
		var combat_data = ecs.combat[tower_id]
		
		# Обновляем cooldown (с учетом aura и антачибла)
		var cooldown = combat_data.get("fire_cooldown", 0.0)
		if cooldown > 0:
			var cooldown_reduction = delta
			if ecs.aura_effects.has(tower_id):
				var aura_mult = ecs.aura_effects[tower_id].get("speed_multiplier", 1.0)
				cooldown_reduction *= aura_mult
			# Антачибл: башня атакует в 6 раз медленнее
			var slow_entry = ecs.tower_attack_slow.get(tower_id, {})
			if slow_entry.get("timer", 0) > 0:
				cooldown_reduction /= slow_entry.get("multiplier", 6.0)
			combat_data["fire_cooldown"] = cooldown - cooldown_reduction
			continue
		
		# Проверяем энергию (с кэшированием результатов)
		var power_sources = _get_power_sources_cached(tower_id)
		if power_sources.size() == 0:
			if Config.COMBAT_DEBUG:
				var key = "w%d_t%d_no_power" % [current_wave, tower_id]
				if not _debug_skip_logged.get(key, false):
					_debug_skip_logged[key] = true
					print("[CombatDebug] Tower %d (def=%s) SKIP: no power sources (is_active=true but _find_power_sources returned 0)" % [tower_id, tower.get("def_id", "?")])
			continue
		
		var total_reserve = 0.0
		for source_id in power_sources:
			if ecs.ores.has(source_id):
				total_reserve += ecs.ores[source_id].get("current_reserve", 0.0)
		
		var shot_cost = combat_data.get("shot_cost", 0.0)
		# Ауры тратят меньше руды (Config.AURA_ORE_COST_FACTOR); под аурой скорости — ещё AURA_SPEED_ORE_COST_FACTOR
		var effective_cost = shot_cost
		if ecs.auras.has(tower_id):
			effective_cost = shot_cost * Config.AURA_ORE_COST_FACTOR
			if ecs.auras[tower_id].get("speed_multiplier", 1.0) > 1.0:
				effective_cost *= Config.AURA_SPEED_ORE_COST_FACTOR
		else:
			effective_cost = shot_cost
		# Башни второго яруса крафта (crafting_level >= 1): расход руды на 70% больше
		if tower.get("crafting_level", 0) >= 1:
			effective_cost *= Config.ORE_COST_TIER2_MULTIPLIER
		# Башни под аурой скорости: стоимость выстрела / speed_mult, чтобы руда/сек не росла
		if ecs.aura_effects.has(tower_id):
			var speed_mult = ecs.aura_effects[tower_id].get("speed_multiplier", 1.0)
			if speed_mult > 1.0:
				effective_cost = effective_cost / speed_mult
		# Небольшая толерантность к float, чтобы сплит-башни (PA и др. с большим shot_cost) не молчали
		if total_reserve < effective_cost - 1e-5:
			if Config.COMBAT_DEBUG:
				var key = "w%d_t%d_low_reserve" % [current_wave, tower_id]
				if not _debug_skip_logged.get(key, false):
					_debug_skip_logged[key] = true
					print("[CombatDebug] Tower %d (def=%s) SKIP: low reserve (total=%.3f < cost=%.3f)" % [tower_id, tower.get("def_id", "?"), total_reserve, effective_cost])
			continue
		
		# Пропускаем башни с типом NONE/AREA (Volcano, Ruby, Lighthouse — спецмеханики)
		var attack_type_data = combat_data.get("attack_type_data", {})
		if typeof(attack_type_data) != TYPE_DICTIONARY:
			attack_type_data = {}
		var attack_method = str(attack_type_data.get("type", "PROJECTILE")).to_upper()
		if attack_method == "NONE" or attack_method == "AREA_OF_EFFECT":
			continue
		# Кварц и подобные: только аура (flying_only), без атаки
		if attack_method == "PROJECTILE" and combat_data.get("damage", 0) == 0 and ecs.auras.has(tower_id) and ecs.auras[tower_id].get("flying_only", false):
			continue

		# Ищем цели
		var targets = _find_targets(tower, combat_data)
		if targets.size() == 0:
			continue

		# Создаем атаку (снаряды или лазер)
		
		var attack_performed = false
		if attack_method == "LASER":
			attack_performed = _create_laser_attack(tower_id, tower, combat_data, targets)
		else:
			attack_performed = _create_projectiles(tower_id, tower, combat_data, targets, power_sources)
		
		if attack_performed and Config.COMBAT_DEBUG:
			print("[CombatDebug] Tower %d (%s) fired %s at %d targets" % [tower_id, tower.get("def_id", "?"), attack_method, targets.size()])
		
		if attack_performed:
			# Списываем энергию
			_consume_energy(power_sources, effective_cost)
			# Устанавливаем cooldown
			var fire_rate = combat_data.get("fire_rate", 1.0)
			combat_data["fire_cooldown"] = 1.0 / fire_rate

func _get_power_sources_cached(tower_id: int) -> Array:
	var current_time = Time.get_ticks_msec() / 1000.0
	# В начале волны не используем кэш — всегда свежий запрос к энергосети (фикс "первая башня не стреляет")
	var use_cache = (current_time - _wave_start_time) >= WAVE_START_CACHE_GRACE
	if use_cache:
		var cache_entry = power_source_cache.get(tower_id)
		if cache_entry and (current_time - cache_entry.get("timestamp", 0.0)) < cache_lifetime:
			return cache_entry.get("sources", [])
	
	var sources = _find_power_sources(tower_id)
	power_source_cache[tower_id] = {
		"sources": sources,
		"timestamp": current_time
	}
	return sources

func _find_power_sources(tower_id: int) -> Array:
	# Используем ОРИГИНАЛЬНУЮ логику энергосети (не трогаем!)
	if GameManager.energy_network:
		return GameManager.energy_network._find_power_sources(tower_id)
	return []

func _find_targets(tower: Dictionary, combat_data: Dictionary) -> Array:
	var tower_hex = tower.get("hex")
	if not tower_hex:
		return []
	
	var range_radius = combat_data.get("range", 3)
	var split_count = combat_data.get("split_count", 1)
	
	# Агрро: если танк с активным агрро в радиусе 4 гекса от вышки — бьём только его
	var aggro_enemy_id = -1
	for enemy_id in ecs.enemies.keys():
		var enemy = ecs.enemies.get(enemy_id)
		if not enemy or not enemy.get("abilities", []).has("aggro"):
			continue
		if enemy.get("aggro_duration_left", 0) <= 0:
			continue
		var enemy_pos = ecs.positions.get(enemy_id)
		if not enemy_pos:
			continue
		var enemy_hex = Hex.from_pixel(enemy_pos, Config.HEX_SIZE)
		if tower_hex.distance_to(enemy_hex) <= Config.AGGRO_RADIUS_HEX:
			aggro_enemy_id = enemy_id
			break
	
	var total_enemies = ecs.enemies.keys().size()
	var _enemies_with_pos = 0
	var _enemies_with_health = 0
	var enemies_in_range = 0
	
	# Собираем всех врагов в радиусе
	var candidates = []
	for enemy_id in ecs.enemies.keys():
		var enemy_pos = ecs.positions.get(enemy_id)
		if not enemy_pos:
			continue
		_enemies_with_pos += 1
		
		var health = ecs.healths.get(enemy_id)
		if not health or health.get("current", 0) <= 0:
			continue
		_enemies_with_health += 1
		
		var enemy_hex = Hex.from_pixel(enemy_pos, Config.HEX_SIZE)
		var distance = tower_hex.distance_to(enemy_hex)
		
		if distance <= range_radius:
			enemies_in_range += 1
			candidates.append({"id": enemy_id, "dist": distance})
	
	if aggro_enemy_id >= 0:
		var only_aggro = []
		for c in candidates:
			if c.id == aggro_enemy_id:
				only_aggro.append(c)
		if only_aggro.size() > 0:
			return [aggro_enemy_id]
		return []
	
	# Сортируем по расстоянию
	candidates.sort_custom(func(a, b): return a.dist < b.dist)
	
	# Берем ближайших
	var targets = []
	for i in range(min(split_count, candidates.size())):
		targets.append(candidates[i].id)
	
	return targets

func _create_projectiles(tower_id: int, tower: Dictionary, combat_data: Dictionary, targets: Array, power_sources: Array) -> bool:
	var tower_hex = tower.get("hex")
	if not tower_hex:
		return false
	
	var tower_pos = tower_hex.to_pixel(Config.HEX_SIZE)
	
	# Рассчитываем урон с бустом от руды
	var chosen_source = power_sources[randi() % power_sources.size()]
	var ore = ecs.ores.get(chosen_source)
	var boost_multiplier = _calculate_ore_boost(ore.get("current_reserve", 0.0))
	
	var network_mult = 1.0
	if GameManager.energy_network:
		network_mult = GameManager.energy_network.get_network_ore_damage_mult(tower_id)
	var mvp_mult = GameManager.get_mvp_damage_mult(tower_id)
	var base_damage = combat_data.get("damage", 10)
	var final_damage = int(base_damage * boost_multiplier * network_mult * mvp_mult)
	var damage_bonus = ecs.aura_effects.get(tower_id, {}).get("damage_bonus", 0)
	final_damage += damage_bonus
	
	var attack_type = combat_data.get("attack_type", "physical")
	var projectile_color = _get_projectile_color(attack_type)
	
	# Создаем снаряды для каждой цели
	for target_id in targets:
		var proj_id = ecs.create_entity()
		if Config.COMBAT_DEBUG:
			var cw = ecs.game_state.get("current_wave", 0)
			var key = "w%d_created_%d" % [cw, proj_id]
			if not _debug_skip_logged.get(key, false):
				_debug_skip_logged[key] = true
				print("[CombatDebug] Created projectile proj_id=%d target_id=%d tower_pos=%s" % [proj_id, target_id, tower_pos])
		
		# Предсказываем позицию цели для прямого полета
		var target_pos_predict = _predict_target_position(target_id, tower_pos)
		var direction = tower_pos.direction_to(target_pos_predict).angle()
		
		
		# Запоминаем текущий slow_factor для умной донаводки
		var current_slow_factor = 1.0
		if ecs.slow_effects.has(target_id):
			current_slow_factor = ecs.slow_effects[target_id].get("slow_factor", 1.0)
		
		# Impact burst (Malachite и т.п.) — данные для взрыва при попадании
		var proj_data = {
			"source_id": tower_id,
			"target_id": target_id,
			"target_pos": target_pos_predict,
			"direction": direction,
			"last_slow_factor": current_slow_factor,
			"damage": final_damage,
			"speed": Config.PROJECTILE_SPEED,
			"attack_type": attack_type
		}
		var params = combat_data.get("attack_type_data", {}).get("params", {})
		if typeof(params) == TYPE_DICTIONARY:
			var ib = params.get("impact_burst", {})
			if not ib.is_empty():
				proj_data["impact_burst_radius"] = ib.get("radius", 1.5)
				proj_data["impact_burst_target_count"] = ib.get("target_count", 4)
				proj_data["impact_burst_damage_factor"] = ib.get("damage_factor", 0.4)
				proj_data["direct_damage_multiplier"] = ib.get("direct_hit_multiplier", 1.0)
			if params.get("effect", "") == "JADE_POISON":
				proj_data["effect"] = "JADE_POISON"
		# Пишем в тот же ECS, что читает projectile_system (явно GameManager.ecs)
		var world = GameManager.ecs
		world.positions[proj_id] = tower_pos
		world.projectiles[proj_id] = proj_data
		world.renderables[proj_id] = {
			"color": projectile_color,
			"radius": Config.PROJECTILE_RADIUS
		}
	
	return true

func _calculate_ore_boost(current_reserve: float) -> float:
	# Логика из Go: чем меньше руды, тем больше урон
	var low_t = 10.0
	var high_t = 100.0
	var max_mult = 2.0
	var min_mult = 0.8
	
	if current_reserve <= low_t:
		return max_mult
	if current_reserve >= high_t:
		return min_mult
	
	return (current_reserve - low_t) * (min_mult - max_mult) / (high_t - low_t) + max_mult

func _get_projectile_color(attack_type: String) -> Color:
	match attack_type.to_upper():
		"PHYSICAL": return Config.PROJECTILE_COLOR_PHYSICAL
		"MAGICAL": return Config.PROJECTILE_COLOR_MAGICAL
		"PURE": return Config.PROJECTILE_COLOR_PURE
		"SLOW": return Config.PROJECTILE_COLOR_SLOW
		"POISON": return Config.PROJECTILE_COLOR_POISON
		_: return Config.PROJECTILE_COLOR_PURE

func _create_laser_attack(tower_id: int, tower: Dictionary, combat_data: Dictionary, targets: Array) -> bool:
	var tower_hex = tower.get("hex")
	if not tower_hex:
		return false
	
	var tower_pos = tower_hex.to_pixel(Config.HEX_SIZE)
	var network_mult = 1.0
	if GameManager.energy_network:
		network_mult = GameManager.energy_network.get_network_ore_damage_mult(tower_id)
	var mvp_mult = GameManager.get_mvp_damage_mult(tower_id)
	var base_damage = combat_data.get("damage", 10)
	var damage_bonus = ecs.aura_effects.get(tower_id, {}).get("damage_bonus", 0)
	var laser_damage = int((base_damage + damage_bonus) * network_mult * mvp_mult)
	var attack_type = combat_data.get("attack_type", "PHYSICAL")
	
	# Мгновенный урон для каждой цели
	for target_id in targets:
		var target_pos = ecs.positions.get(target_id)
		if not target_pos:
			continue
		
		# Создаем визуальный эффект лазера
		var laser_id = ecs.create_entity()
		ecs.add_component(laser_id, "laser", {
			"start_pos": tower_pos,
			"target_pos": target_pos,
			"timer": Config.LASER_DURATION,
			"color": _get_laser_color(attack_type)
		})
		
		if GameManager.roll_evasion(target_id):
			continue
		# Наносим урон
		_apply_laser_damage(target_id, laser_damage, attack_type, tower_id)
		_apply_untouchable_to_tower(tower_id, target_id)
		# Замедление (если есть в params) — только если враг не имеет неуязвимости к эффектам
		var params = combat_data.get("attack_type_data", {}).get("params", {})
		if typeof(params) == TYPE_DICTIONARY:
			var slow_mult = params.get("slow_multiplier", 0.0)
			var slow_dur = params.get("slow_duration", 0.0)
			if slow_mult > 0 and slow_dur > 0:
				var enemy_data = ecs.enemies.get(target_id)
				var abilities = enemy_data.get("abilities", []) if enemy_data else []
				if not abilities.has("effect_immunity"):
					ecs.slow_effects[target_id] = {
						"timer": slow_dur,
						"slow_factor": 1.0 - slow_mult
					}

	return true

func _apply_laser_damage(entity_id: int, damage: int, attack_type: String, source_tower_id: int = -1):
	var health = ecs.healths.get(entity_id)
	if not health:
		return
	var enemy = ecs.enemies.get(entity_id)
	if enemy and enemy.get("abilities", []).has("reflection"):
		var stacks = enemy.get("reflection_stacks", 0)
		if stacks > 0:
			enemy["reflection_stacks"] = stacks - 1
			ecs.damage_flashes[entity_id] = {"timer": 0.2}
			return
	var final_damage = damage
	
	# Учитываем броню по формуле Dota: урон × фактор(броня)
	if enemy:
		match attack_type.to_upper():
			"PHYSICAL":
				var arm = GameManager.get_effective_physical_armor(entity_id)
				final_damage = int(damage * GameManager.armor_to_damage_factor(float(arm)))
			"MAGICAL":
				var arm = GameManager.get_effective_magical_armor(entity_id)
				final_damage = int(damage * GameManager.armor_to_damage_factor(float(arm)))
			"PURE":
				pass
	
	# Минимум 1 урон при любом положительном входящем
	if final_damage < 1 and damage > 0:
		final_damage = 1
	elif final_damage < 0:
		final_damage = 0
	
	health["current"] = max(0, health["current"] - final_damage)
	
	GameManager.on_enemy_took_damage(entity_id, final_damage, source_tower_id)
	
	ecs.damage_flashes[entity_id] = {"timer": 0.2}
	
	if health["current"] <= 0:
		ecs.kill_enemy(entity_id)

func _get_laser_color(attack_type: String) -> Color:
	match attack_type.to_upper():
		"PHYSICAL": return Color(1.0, 0.3, 0.0, 0.8)  # Красно-оранжевый
		"MAGICAL": return Color(0.5, 0.3, 1.0, 0.8)   # Фиолетовый
		"PURE": return Color(0.7, 0.95, 1.0, 0.8)     # Голубовато-белый
		_: return Color(1.0, 1.0, 1.0, 0.8)

func _consume_energy(power_sources: Array, amount: float):
	if power_sources.size() == 0:
		return
	
	var chosen_source = power_sources[randi() % power_sources.size()]
	var ore = ecs.ores.get(chosen_source)
	if ore:
		var mult = 1.0
		if GameManager.energy_network:
			mult = GameManager.energy_network.get_miner_efficiency_for_ore(chosen_source)
		var deduct = amount / mult
		# Обучение уровень 1: гиперболизированная трата руды (в 3–5 раз), чтобы было наглядно
		deduct *= GameManager.get_ore_consumption_multiplier()
		ore["current_reserve"] = max(0.0, ore["current_reserve"] - deduct)
		
		if ore["current_reserve"] < 0.1:
			if GameManager.energy_network:
				GameManager.energy_network.rebuild_energy_network()

func _predict_target_position(target_id: int, start_pos: Vector2) -> Vector2:
	"""Предсказывает где будет цель когда снаряд долетит (учёт замедления и раша)"""
	var target_pos = ecs.positions.get(target_id)
	if not target_pos:
		return start_pos
	
	var enemy = ecs.enemies.get(target_id)
	if not enemy:
		return target_pos
	
	var path = ecs.paths.get(target_id)
	if not path or path["current_index"] >= path["hexes"].size():
		return target_pos
	
	var effective_speed = enemy.get("speed", 80.0)
	if ecs.bash_effects.has(target_id):
		effective_speed = 0.0
	if ecs.slow_effects.has(target_id):
		effective_speed *= ecs.slow_effects[target_id].get("slow_factor", 1.0)
	if ecs.jade_poisons.has(target_id):
		var jade = ecs.jade_poisons[target_id]
		var stacks = jade.get("instances", []).size()
		var slow_per = jade.get("slow_factor_per_stack", 0.05)
		effective_speed *= max(0.1, 1.0 - slow_per * stacks)
	if enemy.get("rush_duration_left", 0.0) > 0:
		effective_speed *= Config.RUSH_SPEED_MULT
	
	var current_hex = path["hexes"][path["current_index"]]
	var next_pos = current_hex.to_pixel(Config.HEX_SIZE)
	var to_next = (next_pos - target_pos)
	if to_next.length_squared() > 1.0:
		to_next = to_next.normalized()
	else:
		to_next = Vector2(1, 0)
	var distance = start_pos.distance_to(target_pos)
	var time_to_hit = distance / Config.PROJECTILE_SPEED
	var predicted_offset = to_next * effective_speed * time_to_hit
	return target_pos + predicted_offset

# core/systems/projectile_system.gd
# Система движения снарядов и нанесения урона
extends RefCounted

var ecs: ECSWorld
# Дебаг: один раз за волну логируем причины удаления снарядов
var _proj_debug_logged: Dictionary = {}
var _last_proj_debug_wave: int = -1

func _init(ecs_world: ECSWorld):
	ecs = ecs_world

func update(delta: float):
	# Обновляем эффекты
	_update_damage_flashes(delta)
	_update_lasers(delta)
	_update_volcano_effects(delta)
	
	var to_remove = []
	var current_wave = ecs.game_state.get("current_wave", 0) if ecs.game_state else 0
	if current_wave != _last_proj_debug_wave:
		_last_proj_debug_wave = current_wave
		_proj_debug_logged.clear()
	
	# Читаем из того же ECS, в который combat_system пишет (GameManager.ecs)
	var world = GameManager.ecs
	for proj_id in world.projectiles.keys():
		var proj = world.projectiles[proj_id]
		# По ключу, не по truthiness: Vector2(0,0) в GDScript falsy, башня на Hex(0,0) даёт (0,0)
		if not world.positions.has(proj_id):
			if Config.COMBAT_DEBUG:
				var key = "w%d_no_pos_%d" % [current_wave, proj_id]
				if not _proj_debug_logged.get(key, false):
					_proj_debug_logged[key] = true
					print("[ProjectileDebug] proj_id %d REMOVED: no position in ECS" % proj_id)
			to_remove.append(proj_id)
			continue
		var pos = world.positions.get(proj_id)
		
		var target_id = proj.get("target_id")
		if not world.positions.has(target_id):
			if Config.COMBAT_DEBUG:
				var key = "w%d_no_target_%d" % [current_wave, proj_id]
				if not _proj_debug_logged.get(key, false):
					_proj_debug_logged[key] = true
					print("[ProjectileDebug] proj_id %d REMOVED: target_id %d has no position" % [proj_id, target_id])
			to_remove.append(proj_id)
			continue
		var target_pos = world.positions.get(target_id)
		
		# Цель мертва?
		var target_health = world.healths.get(target_id)
		if target_health and target_health.get("current", 0) <= 0:
			to_remove.append(proj_id)
			continue
		
		# --- САМОНАВЕДЕНИЕ ---
		# Осколки малахита (homing): всегда летят к текущей позиции цели (каждый кадр)
		if proj.get("homing", false):
			proj["direction"] = pos.direction_to(target_pos).angle()
			proj["last_slow_factor"] = 1.0
		else:
			# Обычные снаряды: пересчитываем курс только при изменении slow_factor цели
			var current_slow_factor = 1.0
			if world.slow_effects.has(target_id):
				current_slow_factor = world.slow_effects[target_id].get("slow_factor", 1.0)
			var last_slow_factor = proj.get("last_slow_factor", 1.0)
			if abs(current_slow_factor - last_slow_factor) > 0.001:
				var new_predicted_pos = _recalculate_target_position(target_id, pos, target_pos)
				proj["direction"] = pos.direction_to(new_predicted_pos).angle()
				proj["last_slow_factor"] = current_slow_factor
		
		# Расстояние до цели (нужно для попадания и потиковой донаводки)
		var dx = target_pos.x - pos.x
		var dy = target_pos.y - pos.y
		var dist_to_target = sqrt(dx * dx + dy * dy)
		
		# --- ПОТИКОВАЯ ДОНАВОДКА (оптимизировано: не каждый кадр) ---
		# Раз в HOMING_TICK_INTERVAL сек плавно подкручиваем направление к текущей позиции цели
		if not proj.get("homing", false):
			if not proj.has("_homing_t"):
				proj["_homing_t"] = Config.HOMING_TICK_INTERVAL
			proj["_homing_t"] -= delta
			if proj["_homing_t"] <= 0.0:
				proj["_homing_t"] = Config.HOMING_TICK_INTERVAL
				if dist_to_target < Config.HOMING_ACTIVATE_DISTANCE and dist_to_target > Config.PROJECTILE_HIT_RADIUS:
					var ideal_angle = pos.direction_to(target_pos).angle()
					var cur_dir = proj.get("direction", 0.0)
					proj["direction"] = lerp_angle(cur_dir, ideal_angle, Config.HOMING_CORRECTION_STRENGTH)
		
		var speed = proj.get("speed", Config.PROJECTILE_SPEED)
		var direction = proj.get("direction", 0.0)
		
		# ПОПАДАНИЕ: если цель в радиусе (увеличенный радиус — меньше промахов)
		if dist_to_target <= speed * delta or dist_to_target < Config.PROJECTILE_HIT_RADIUS:
			if Config.COMBAT_DEBUG:
				var key = "w%d_hit_%d" % [current_wave, proj_id]
				if not _proj_debug_logged.get(key, false):
					_proj_debug_logged[key] = true
					print("[ProjectileDebug] proj_id %d HIT target %d, damage %d" % [proj_id, proj.get("target_id"), proj.get("damage", 0)])
			_hit_target(proj_id, proj)
			to_remove.append(proj_id)
		else:
			# ДВИЖЕНИЕ: по текущему направлению (донаводка уже учтена по тикам выше)
			pos.x += cos(direction) * speed * delta
			pos.y += sin(direction) * speed * delta
			world.positions[proj_id] = pos
	
	# Удаляем снаряды
	for proj_id in to_remove:
		world.destroy_entity(proj_id)

func _hit_target(proj_id: int, proj: Dictionary):
	var target_id = proj.get("target_id")
	var damage = proj.get("damage", 0)
	var attack_type = proj.get("attack_type", "physical")

	# Impact burst (Malachite) — осколки разлетаются к соседям
	if proj.has("impact_burst_radius"):
		var impact_pos = ecs.positions.get(proj_id)
		if impact_pos:
			_handle_impact_burst(proj, impact_pos)

	# Уклонение: визуально снаряд попал, урона и эффектов нет
	if GameManager.roll_evasion(target_id):
		return

	var source_id = proj.get("source_id", -1)
	# JADE_POISON — стакающийся яд (Jade башня); не применяем если у врага неуязвимость к эффектам
	if proj.get("effect", "") == "JADE_POISON":
		var enemy_data = ecs.enemies.get(target_id)
		var abilities = enemy_data.get("abilities", []) if enemy_data else []
		if not abilities.has("effect_immunity"):
			_apply_jade_poison(target_id, source_id)

	# Наносим урон по главной цели (у Малахита первая тычка сильнее, осколки — из proj.damage)
	var main_damage = int(damage * proj.get("direct_damage_multiplier", 1.0))
	_apply_damage(target_id, main_damage, attack_type, source_id)

	# Антачибл: башня, попавшая по этому врагу, замедляется (не для Volcano/Mayak)
	if source_id >= 0 and ecs.enemies.has(target_id):
		var ab = ecs.enemies[target_id].get("abilities", [])
		if ab.has("untouchable") and ecs.combat.has(source_id):
			var at = str(ecs.combat[source_id].get("attack_type_data", {}).get("type", "PROJECTILE")).to_upper()
			if at != "NONE" and at != "AREA_OF_EFFECT":
				ecs.tower_attack_slow[source_id] = {
					"timer": Config.UNTOUCHABLE_DURATION,
					"multiplier": Config.UNTOUCHABLE_SLOW_MULTIPLIER
				}

	# Применяем статус-эффекты (замедление, яд, дебаффы брони) — только если нет неуязвимости к эффектам
	var enemy_data = ecs.enemies.get(target_id)
	var abilities = enemy_data.get("abilities", []) if enemy_data else []
	if not abilities.has("effect_immunity"):
		_apply_status_effects(target_id, attack_type, source_id)
		_apply_bash_if_any(target_id, source_id)
		_apply_gold_armor_debuff_if_any(target_id, source_id)
	else:
		_apply_armor_debuffs_only(target_id, attack_type, source_id)
		_apply_gold_armor_debuff_if_any(target_id, source_id)

func _apply_damage(entity_id: int, damage: int, attack_type: String, source_tower_id: int = -1):
	var health = ecs.healths.get(entity_id)
	if not health:
		return
	var enemy = ecs.enemies.get(entity_id)
	# Рефлекшн: один слой щита снимает удар без урона
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
			"PHYSICAL", "PHYS_ARMOR_DEBUFF":
				var arm = GameManager.get_effective_physical_armor(entity_id)
				final_damage = int(damage * GameManager.armor_to_damage_factor(float(arm)))
			"MAGICAL", "MAG_ARMOR_DEBUFF":
				var arm = GameManager.get_effective_magical_armor(entity_id)
				final_damage = int(damage * GameManager.armor_to_damage_factor(float(arm)))
			"PURE", "SLOW", "POISON":
				pass  # Чистый урон
	
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

func _update_damage_flashes(delta: float):
	var to_remove = []
	for entity_id in ecs.damage_flashes.keys():
		var flash = ecs.damage_flashes[entity_id]
		flash["timer"] -= delta
		if flash["timer"] <= 0:
			to_remove.append(entity_id)
	
	for entity_id in to_remove:
		ecs.damage_flashes.erase(entity_id)

func _update_lasers(delta: float):
	# Ограничиваем вычитание, чтобы лазер успел отрисоваться хотя бы в одном кадре (даже при большом delta после паузы)
	var step = min(delta, 0.06)
	var to_remove = []
	for laser_id in ecs.lasers.keys():
		var laser = ecs.lasers[laser_id]
		laser["timer"] -= step
		if laser["timer"] <= 0:
			to_remove.append(laser_id)
	
	for laser_id in to_remove:
		ecs.destroy_entity(laser_id)

func _update_volcano_effects(delta: float):
	var to_remove = []
	for effect_id in ecs.volcano_effects.keys():
		var eff = ecs.volcano_effects[effect_id]
		eff["timer"] = eff.get("timer", 0.25) - delta
		if eff["timer"] <= 0:
			to_remove.append(effect_id)
	for effect_id in to_remove:
		ecs.destroy_entity(effect_id)

# ============================================================================
# СТАТУС-ЭФФЕКТЫ
# ============================================================================

func _recalculate_target_position(target_id: int, proj_pos: Vector2, target_pos: Vector2) -> Vector2:
	"""Пересчитывает предсказанную позицию при изменении состояния цели"""
	var enemy = ecs.enemies.get(target_id)
	if not enemy:
		return target_pos
	
	var path = ecs.paths.get(target_id)
	if not path or path["current_index"] >= path["hexes"].size():
		return target_pos
	
	var base_speed = enemy.get("speed", 80.0)
	var effective_speed = base_speed
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
	var distance = proj_pos.distance_to(target_pos)
	var time_to_hit = distance / Config.PROJECTILE_SPEED
	var predicted_offset = to_next * effective_speed * time_to_hit
	return target_pos + predicted_offset

func _handle_impact_burst(proj: Dictionary, impact_pos: Vector2):
	"""Impact burst (Malachite): осколки к врагам в радиусе 3 гексов (~105 px)"""
	var radius_hex = proj.get("impact_burst_radius", 3)
	var target_count = int(proj.get("impact_burst_target_count", 6))
	var damage_factor = proj.get("impact_burst_damage_factor", 0.4)
	var source_id = proj.get("source_id", -1)
	var main_target_id = proj.get("target_id", -1)
	var attack_type = proj.get("attack_type", "MAGICAL")
	var base_damage = proj.get("damage", 0)
	var burst_damage = max(1, int(base_damage * damage_factor))
	# 1 гекс ≈ 35 px (center-to-center), 3 гекса = 105
	var radius_px = radius_hex * Config.HEX_SIZE * 1.75

	var candidates = []
	for enemy_id in ecs.enemies.keys():
		if enemy_id == main_target_id:
			continue
		var enemy_pos = ecs.positions.get(enemy_id)
		if not enemy_pos:
			continue
		var health = ecs.healths.get(enemy_id)
		if not health or health.get("current", 0) <= 0:
			continue
		var dist = impact_pos.distance_to(enemy_pos)
		if dist <= radius_px:
			candidates.append({"id": enemy_id, "dist": dist})
	candidates.sort_custom(func(a, b): return a.dist < b.dist)

	var burst_count = min(target_count, candidates.size())
	for i in range(burst_count):
		var enemy_id = candidates[i].id
		var enemy_pos = ecs.positions.get(enemy_id)
		var direction = impact_pos.direction_to(enemy_pos).angle()
		var new_proj_id = ecs.create_entity()
		ecs.positions[new_proj_id] = Vector2(impact_pos.x, impact_pos.y)
		ecs.projectiles[new_proj_id] = {
			"source_id": source_id,
			"target_id": enemy_id,
			"target_pos": enemy_pos,
			"direction": direction,
			"last_slow_factor": 1.0,
			"damage": burst_damage,
			"speed": Config.PROJECTILE_SPEED * 0.8,
			"attack_type": attack_type,
			"homing": true
		}
		var proj_color = _get_projectile_color(attack_type)
		ecs.renderables[new_proj_id] = {"color": proj_color, "radius": Config.PROJECTILE_RADIUS * 0.6}

func _get_projectile_color(attack_type: String) -> Color:
	match attack_type.to_upper():
		"PHYSICAL": return Config.PROJECTILE_COLOR_PHYSICAL
		"MAGICAL": return Config.PROJECTILE_COLOR_MAGICAL
		"PURE": return Config.PROJECTILE_COLOR_PURE
		"SLOW": return Config.PROJECTILE_COLOR_SLOW
		"POISON": return Config.PROJECTILE_COLOR_POISON
		_: return Config.PROJECTILE_COLOR_PURE

func _apply_jade_poison(entity_id: int, source_tower_id: int = -1):
	"""Добавляет стак Jade Poison (как в Go). source_tower_id — для учёта урона в статистике вышек."""
	if not ecs.jade_poisons.has(entity_id):
		ecs.jade_poisons[entity_id] = {
			"target_id": entity_id,
			"instances": [],
			"damage_per_stack": 10,
			"slow_factor_per_stack": 0.05,
			"source_tower_id": source_tower_id
		}
	var container = ecs.jade_poisons[entity_id]
	container["instances"] = container.get("instances", [])
	container["instances"].append({
		"duration": 5.0,
		"tick_timer": 1.0
	})

func _get_attack_params_from_tower(source_tower_id: int) -> Dictionary:
	"""Возвращает combat.attack.params из def башни, если source_tower_id валиден."""
	if source_tower_id < 0 or not ecs.towers.has(source_tower_id):
		return {}
	var tower = ecs.towers[source_tower_id]
	var def_id = tower.get("def_id", "")
	if def_id.is_empty():
		return {}
	var def = DataRepository.get_tower_def(def_id) if def_id else {}
	return def.get("combat", {}).get("attack", {}).get("params", {})

func _apply_status_effects(entity_id: int, attack_type: String, source_tower_id: int = -1):
	"""Применяет статус-эффекты к врагу. Параметры берутся из def башни (params), иначе из Config."""
	var params = _get_attack_params_from_tower(source_tower_id)
	match attack_type.to_upper():
		"SLOW":
			var slow_factor = params.get("slow_factor", Config.SLOW_FACTOR)
			ecs.slow_effects[entity_id] = {
				"timer": params.get("slow_duration", Config.SLOW_DURATION),
				"slow_factor": slow_factor
			}
		
		"POISON":
			var dps = params.get("poison_dps", Config.POISON_DPS)
			ecs.poison_effects[entity_id] = {
				"timer": params.get("poison_duration", Config.POISON_DURATION),
				"damage_per_sec": dps,
				"tick_timer": 1.0,
				"source_tower_id": source_tower_id
			}
		"PHYS_ARMOR_DEBUFF":
			_add_phys_armor_debuff(entity_id, params.get("armor_debuff_amount", Config.PHYS_ARMOR_DEBUFF_AMOUNT), params.get("armor_debuff_duration", Config.PHYS_ARMOR_DEBUFF_DURATION))
		"MAG_ARMOR_DEBUFF":
			_add_mag_armor_debuff(entity_id, params.get("armor_debuff_amount", Config.MAG_ARMOR_DEBUFF_AMOUNT), params.get("armor_debuff_duration", Config.MAG_ARMOR_DEBUFF_DURATION))
	# Либра: яд из params (poison_dps) даже при damage_type MAGICAL
	var poison_dps = params.get("poison_dps", 0)
	if poison_dps > 0:
		var poison_dur = params.get("poison_duration", Config.POISON_DURATION)
		ecs.poison_effects[entity_id] = {
			"timer": poison_dur,
			"damage_per_sec": poison_dps,
			"tick_timer": 1.0,
			"source_tower_id": source_tower_id
		}

func _apply_armor_debuffs_only(entity_id: int, attack_type: String, source_tower_id: int = -1):
	"""Только дебаффы брони (для врагов с effect_immunity). Стакаются с другими источниками."""
	var params = _get_attack_params_from_tower(source_tower_id)
	match attack_type.to_upper():
		"PHYS_ARMOR_DEBUFF":
			_add_phys_armor_debuff(entity_id, params.get("armor_debuff_amount", Config.PHYS_ARMOR_DEBUFF_AMOUNT), params.get("armor_debuff_duration", Config.PHYS_ARMOR_DEBUFF_DURATION))
		"MAG_ARMOR_DEBUFF":
			_add_mag_armor_debuff(entity_id, params.get("armor_debuff_amount", Config.MAG_ARMOR_DEBUFF_AMOUNT), params.get("armor_debuff_duration", Config.MAG_ARMOR_DEBUFF_DURATION))

func _add_phys_armor_debuff(entity_id: int, amount, duration: float):
	var current = ecs.phys_armor_debuffs.get(entity_id, [])
	var list: Array = current.duplicate() if current is Array else [current] if current is Dictionary and current.size() > 0 else []
	list.append({"amount": amount, "timer": duration})
	ecs.phys_armor_debuffs[entity_id] = list

func _add_mag_armor_debuff(entity_id: int, amount, duration: float):
	var current = ecs.mag_armor_debuffs.get(entity_id, [])
	var list: Array = current.duplicate() if current is Array else [current] if current is Dictionary and current.size() > 0 else []
	list.append({"amount": amount, "timer": duration})
	ecs.mag_armor_debuffs[entity_id] = list

func _apply_bash_if_any(entity_id: int, source_tower_id: int):
	"""С вероятностью bash_chance из params накладывает баш (огонь стоит, не использует скиллы) на bash_duration сек."""
	if source_tower_id < 0:
		return
	var params = _get_attack_params_from_tower(source_tower_id)
	var chance = params.get("bash_chance", 0.0)
	var duration = params.get("bash_duration", 0.0)
	if chance <= 0 or duration <= 0:
		return
	if randf() >= chance:
		return
	ecs.bash_effects[entity_id] = { "timer": duration }

func _apply_gold_armor_debuff_if_any(entity_id: int, source_tower_id: int):
	"""Голд: по хиту накладывает -30 физ и -30 маг брони на 5 сек (стакается)."""
	if source_tower_id < 0:
		return
	var params = _get_attack_params_from_tower(source_tower_id)
	var phys_amt = params.get("armor_debuff_phys", 0)
	var mag_amt = params.get("armor_debuff_mag", 0)
	var dur = params.get("armor_debuff_duration", 5.0)
	if phys_amt > 0:
		_add_phys_armor_debuff(entity_id, phys_amt, dur)
	if mag_amt > 0:
		_add_mag_armor_debuff(entity_id, mag_amt, dur)

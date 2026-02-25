# status_effect_system.gd
# Система обработки статус-эффектов (замедление, яд, и т.д.)
# Портировано из Go: internal/system/status_effect.go
class_name StatusEffectSystem

var ecs: ECSWorld

func _init(ecs_: ECSWorld):
	ecs = ecs_

# ============================================================================
# UPDATE
# ============================================================================

func update(delta: float):
	_update_slow_effects(delta)
	_update_bash_effects(delta)
	_update_reflection(delta)
	_update_poison_effects(delta)
	_update_phys_armor_debuffs(delta)
	_update_mag_armor_debuffs(delta)
	_update_jade_poison(delta)
	_update_reactive_armor_timers(delta)
	_update_enemy_regen(delta)

# ============================================================================
# SLOW EFFECTS
# ============================================================================

func _update_slow_effects(delta: float):
	var to_remove = []
	
	for entity_id in ecs.slow_effects.keys():
		var effect = ecs.slow_effects[entity_id]
		effect["timer"] -= delta
		
		if effect["timer"] <= 0:
			to_remove.append(entity_id)
	
	for entity_id in to_remove:
		ecs.slow_effects.erase(entity_id)

# ============================================================================
# BASH EFFECTS (оглушение: враг стоит, не использует скиллы)
# ============================================================================

func _update_bash_effects(delta: float):
	var to_remove = []
	for entity_id in ecs.bash_effects.keys():
		var effect = ecs.bash_effects[entity_id]
		effect["timer"] -= delta
		if effect["timer"] <= 0:
			to_remove.append(entity_id)
	for entity_id in to_remove:
		ecs.bash_effects.erase(entity_id)

# ============================================================================
# REFLECTION (рефлекшн: 4 слоя щита, кулдаун 5 с)
# ============================================================================

func _update_reflection(delta: float):
	for enemy_id in ecs.enemies.keys():
		var enemy = ecs.enemies[enemy_id]
		if not enemy.get("abilities", []).has("reflection"):
			continue
		var stacks = enemy.get("reflection_stacks", 0)
		if stacks > 0:
			continue
		var cd = enemy.get("reflection_cooldown_left", 0.0)
		cd -= delta
		enemy["reflection_cooldown_left"] = cd
		if cd <= 0:
			enemy["reflection_stacks"] = Config.REFLECTION_STACKS
			enemy["reflection_cooldown_left"] = Config.REFLECTION_COOLDOWN

# ============================================================================
# POISON EFFECTS
# ============================================================================

func _update_poison_effects(delta: float):
	var to_remove = []
	
	for entity_id in ecs.poison_effects.keys():
		var effect = ecs.poison_effects[entity_id]
		effect["timer"] -= delta
		
		if effect["timer"] <= 0:
			to_remove.append(entity_id)
			continue
		
		# Tick damage (каждую секунду)
		effect["tick_timer"] -= delta
		if effect["tick_timer"] <= 0:
			_apply_poison_damage(entity_id, effect["damage_per_sec"], effect.get("source_tower_id", -1))
			effect["tick_timer"] = 1.0  # Сброс таймера
	
	for entity_id in to_remove:
		ecs.poison_effects.erase(entity_id)

# ============================================================================
# ARMOR DEBUFFS (NA / NE)
# ============================================================================

func _update_phys_armor_debuffs(delta: float):
	var to_remove = []
	for entity_id in ecs.phys_armor_debuffs.keys():
		var data = ecs.phys_armor_debuffs[entity_id]
		if data is Array:
			var active = []
			for entry in data:
				entry["timer"] = entry.get("timer", 0.0) - delta
				if entry["timer"] > 0:
					active.append(entry)
			if active.is_empty():
				to_remove.append(entity_id)
			else:
				ecs.phys_armor_debuffs[entity_id] = active
		else:
			data["timer"] = data.get("timer", 0.0) - delta
			if data["timer"] <= 0:
				to_remove.append(entity_id)
	for entity_id in to_remove:
		ecs.phys_armor_debuffs.erase(entity_id)

func _update_mag_armor_debuffs(delta: float):
	var to_remove = []
	for entity_id in ecs.mag_armor_debuffs.keys():
		var data = ecs.mag_armor_debuffs[entity_id]
		if data is Array:
			var active = []
			for entry in data:
				entry["timer"] = entry.get("timer", 0.0) - delta
				if entry["timer"] > 0:
					active.append(entry)
			if active.is_empty():
				to_remove.append(entity_id)
			else:
				ecs.mag_armor_debuffs[entity_id] = active
		else:
			data["timer"] = data.get("timer", 0.0) - delta
			if data["timer"] <= 0:
				to_remove.append(entity_id)
	for entity_id in to_remove:
		ecs.mag_armor_debuffs.erase(entity_id)

# ============================================================================
# JADE POISON (стакающийся яд)
# ============================================================================

func _update_jade_poison(delta: float):
	var to_remove = []
	for entity_id in ecs.jade_poisons.keys():
		var container = ecs.jade_poisons[entity_id]
		var instances = container.get("instances", [])
		var active = []
		for inst in instances:
			inst["duration"] = inst.get("duration", 5.0) - delta
			if inst["duration"] > 0:
				inst["tick_timer"] = inst.get("tick_timer", 1.0) - delta
				if inst["tick_timer"] <= 0:
					var stacks = len(instances)
					var dmg_per = container.get("damage_per_stack", 10)
					var damage = int(float(dmg_per * stacks) * pow(1.1, stacks - 1))
					damage = max(1, int(float(damage) / 3.0 * 1.4))  # Джейд: базово /3, +40% урона с тычки
					var src_id = container.get("source_tower_id", -1)
					if src_id >= 0 and ecs.towers.has(src_id):
						var def_id = ecs.towers[src_id].get("def_id", "")
						var tdef = DataRepository.get_tower_def(def_id) if def_id else {}
						var mult = tdef.get("combat", {}).get("attack", {}).get("params", {}).get("poison_damage_multiplier", 1.0)
						damage = max(1, int(damage * mult))
					# +250% урона летающим (не боссам)
					if ecs.enemies.has(entity_id):
						var ed = ecs.enemies[entity_id]
						if ed.get("flying", false) and ed.get("def_id", "") != "ENEMY_BOSS":
							damage = max(1, int(damage * 2.5))
					_apply_poison_damage(entity_id, damage, src_id)
					inst["tick_timer"] = 1.0
				active.append(inst)
		container["instances"] = active
		if active.is_empty():
			to_remove.append(entity_id)
	for entity_id in to_remove:
		ecs.jade_poisons.erase(entity_id)

# ============================================================================
# РЕГЕН ВРАГОВ (с 15+ волны и реактивная броня)
# ============================================================================

func _update_enemy_regen(delta: float):
	for enemy_id in ecs.enemies.keys():
		var health = ecs.healths.get(enemy_id)
		if not health or health.get("current", 0) <= 0:
			continue
		var enemy = ecs.enemies[enemy_id]
		var regen = enemy.get("regen", 0)
		if ecs.reactive_armor_stacks.has(enemy_id):
			var ra = ecs.reactive_armor_stacks[enemy_id]
			regen += ra.get("stacks", 0)
		# Аура хиллера: +20 регена врагам в радиусе 4 гекса
		var enemy_pos = ecs.positions.get(enemy_id)
		if enemy_pos:
			var enemy_hex = Hex.from_pixel(enemy_pos, Config.HEX_SIZE)
			for other_id in ecs.enemies.keys():
				if other_id == enemy_id:
					continue
				var other = ecs.enemies[other_id]
				if not other.get("abilities", []).has("healer_aura"):
					continue
				var other_pos = ecs.positions.get(other_id)
				if not other_pos:
					continue
				var other_hex = Hex.from_pixel(other_pos, Config.HEX_SIZE)
				if enemy_hex.distance_to(other_hex) <= Config.HEALER_AURA_RADIUS:
					regen += Config.HEALER_AURA_REGEN_BONUS
		# Хус: чем меньше HP, тем больше реген (до 250% от базы)
		if enemy.get("abilities", []).has("hus"):
			var ratio = float(health["current"]) / float(max(1, health["max"]))
			var mult = clampf(2.5 - 1.5 * ratio, 1.0, Config.HUS_REGEN_MAX_MULT)
			regen = regen * mult
		# Джейд: яд режет реген врага (Config.JADE_POISON_REGEN_FACTOR)
		if ecs.jade_poisons.has(enemy_id):
			regen = regen * Config.JADE_POISON_REGEN_FACTOR
		if regen <= 0:
			continue
		var acc = ecs.enemy_regen_accumulator.get(enemy_id, 0.0) + regen * delta
		ecs.enemy_regen_accumulator[enemy_id] = acc
		var heal = int(acc)
		if heal >= 1:
			ecs.enemy_regen_accumulator[enemy_id] = acc - heal
			health["current"] = min(health["max"], health["current"] + heal)
		elif regen >= 1.0:
			# Целый реген >= 1: хотя бы 1 HP за тик при наличии регена
			heal = 1
			health["current"] = min(health["max"], health["current"] + heal)

# ============================================================================
# ТАЙМЕРЫ РЕАКТИВНОЙ БРОНИ (стаки сбрасываются через 4 сек без тычков)
# ============================================================================

func _update_reactive_armor_timers(delta: float):
	var to_remove = []
	for enemy_id in ecs.reactive_armor_stacks.keys():
		var ra = ecs.reactive_armor_stacks[enemy_id]
		ra["timer"] = ra.get("timer", 0) - delta
		if ra["timer"] <= 0:
			to_remove.append(enemy_id)
	for enemy_id in to_remove:
		ecs.reactive_armor_stacks.erase(enemy_id)

# ============================================================================
# УРОН ОТ ЯДА
# ============================================================================

func _apply_poison_damage(entity_id: int, damage: int, source_tower_id: int = -1):
	"""Наносит урон от яда (чистый урон). source_tower_id — для статистики вышек (NU, Jade)."""
	# Либра: при одной отравленной цели (solo) урон яда x3
	if source_tower_id >= 0 and ecs.towers.has(source_tower_id):
		var tower = ecs.towers[source_tower_id]
		if tower.get("def_id", "") == "TOWER_LIBRA":
			var count = 0
			for eid in ecs.poison_effects:
				if ecs.poison_effects[eid].get("source_tower_id", -1) == source_tower_id:
					count += 1
			if count == 1:
				damage = damage * 3
	var health = ecs.healths.get(entity_id)
	if not health:
		return
	var enemy = ecs.enemies.get(entity_id)
	if enemy and enemy.get("abilities", []).has("reflection"):
		var stacks = enemy.get("reflection_stacks", 0)
		if stacks > 0:
			enemy["reflection_stacks"] = stacks - 1
			return
	health["current"] = max(0, health["current"] - damage)
	
	# Учёт урона в статистике вышек
	GameManager.on_enemy_took_damage(entity_id, damage, source_tower_id)
	
	# Добавляем damage flash
	ecs.damage_flashes[entity_id] = {"timer": 0.2}
	
	# Если враг умер
	if health["current"] <= 0:
		ecs.kill_enemy(entity_id)

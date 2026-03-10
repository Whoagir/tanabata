# movement_system.gd
# Система движения врагов по пути
class_name MovementSystem

var ecs: ECSWorld
var hex_map: HexMap
# Враги в ауре «замедление всех» (Парайба): для баффа при выходе
var _all_enemies_aura_slow_prev: Dictionary = {}  # enemy_id -> true

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
	_update_all_enemies_aura_slows()
	_update_scream_zones(delta)
	
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
		var path = ecs.paths.get(enemy_id)
		var pos = ecs.positions.get(enemy_id)
		if path == null or pos == null:
			continue
		
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
	
	# Удаляем врагов, которые дошли до конца (прогресс для аналитики + система успеха: штраф за выход)
	for enemy_id in enemies_to_remove:
		if GameManager:
			GameManager.record_enemy_wave_progress(enemy_id)
			GameManager.on_enemy_reached_exit(enemy_id)
		if ecs.game_state.has("alive_enemies_count"):
			var c = ecs.game_state["alive_enemies_count"]
			if c > 0:
				ecs.game_state["alive_enemies_count"] = c - 1
		ecs.destroy_entity(enemy_id)
	
	Profiler.end("movement_system")

# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ============================================================================

func _update_blink(enemy_id: int, enemy: Dictionary, delta: float) -> void:
	if not enemy.get("abilities", []).has("blink"):
		return
	if ecs.bash_effects.has(enemy_id) or ecs.scream_stun.has(enemy_id):
		return
	var cd = enemy.get("blink_cooldown_left", 0.0)
	if cd > 0:
		enemy["blink_cooldown_left"] = cd - delta
		return
	var path = ecs.paths.get(enemy_id)
	if not path or path["current_index"] >= path["hexes"].size():
		return
	var blink_hexes = enemy.get("blink_hexes", Config.BLINK_HEXES)
	var advance = mini(blink_hexes, path["hexes"].size() - path["current_index"])
	if advance <= 0:
		return
	path["current_index"] += advance
	var dest_hex = path["hexes"][path["current_index"] - 1]
	ecs.positions[enemy_id] = dest_hex.to_pixel(Config.HEX_SIZE)
	_apply_environmental_damage(enemy_id, dest_hex)
	if not ecs.enemies.has(enemy_id):
		return
	_check_checkpoint(enemy_id, dest_hex)
	enemy["blink_cooldown_left"] = enemy.get("blink_cooldown", Config.BLINK_COOLDOWN)

func _update_rush_state(enemy_id: int, enemy: Dictionary, delta: float) -> void:
	if not enemy.get("abilities", []).has("rush"):
		return
	# Баш / крик: не может применять активные скиллы (rush), только тикает кулдаун
	if ecs.bash_effects.has(enemy_id) or ecs.scream_stun.has(enemy_id):
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
	"""Заполняет flying_aura_slows (стакается с Кварц/Чарминг) и flying_damage_taken_bonus. Работает даже при иммунитете к спеллам (BKB/effect_immunity)."""
	ecs.flying_aura_slows.clear()
	ecs.flying_damage_taken_bonus.clear()
	for tower_id in ecs.auras.keys():
		var aura = ecs.auras[tower_id]
		if not aura.get("flying_only", false):
			continue
		var slow_factor = aura.get("slow_factor", 0.0)
		var damage_bonus = aura.get("flying_damage_taken_bonus", 0.0)
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
			if tower_hex.distance_to(enemy_hex) > radius:
				continue
			if slow_factor > 0:
				var cur_mult = ecs.flying_aura_slows.get(enemy_id, 1.0)
				ecs.flying_aura_slows[enemy_id] = cur_mult * (1.0 - slow_factor)
			if damage_bonus > 0:
				var cur_bonus = ecs.flying_damage_taken_bonus.get(enemy_id, 0.0)
				ecs.flying_damage_taken_bonus[enemy_id] = max(cur_bonus, damage_bonus)

func _update_all_enemies_aura_slows():
	"""Ауры с all_enemies_slow (Парайба): замедление в радиусе через slow_effects; при выходе из ауры — бафф exit_slow на 2 с; бонус получаемого урона в радиусе."""
	ecs.paraba_damage_taken_bonus.clear()
	var in_aura_now: Dictionary = {}
	for tower_id in ecs.auras.keys():
		var aura = ecs.auras[tower_id]
		if not aura.get("all_enemies_slow", false):
			continue
		var tower = ecs.towers.get(tower_id, {})
		if not tower.get("is_active", false):
			continue
		var tower_hex = tower.get("hex")
		if tower_hex == null:
			continue
		var radius = int(aura.get("radius", 2))
		var slow_factor = aura.get("slow_factor", 0.5)
		var exit_factor = aura.get("exit_slow_factor", 0.7)
		var exit_duration = aura.get("exit_slow_duration", 2.0)
		var def_id = tower.get("def_id", "TOWER_PARAIBA")
		var source_aura = def_id + "_aura"
		var source_exit = def_id + "_exit"
		var damage_bonus = aura.get("damage_taken_bonus", 0.0)
		for enemy_id in ecs.enemies.keys():
			var pos = ecs.positions.get(enemy_id)
			if pos == null:
				continue
			var enemy_hex = Hex.from_pixel(pos, Config.HEX_SIZE)
			if tower_hex.distance_to(enemy_hex) <= radius:
				in_aura_now[enemy_id] = true
				if not ecs.slow_effects.has(enemy_id):
					ecs.slow_effects[enemy_id] = {}
				ecs.slow_effects[enemy_id][source_aura] = {"timer": 0.2, "slow_factor": slow_factor}
				if damage_bonus > 0:
					var cur = ecs.paraba_damage_taken_bonus.get(enemy_id, 0.0)
					ecs.paraba_damage_taken_bonus[enemy_id] = maxf(cur, damage_bonus)
	for enemy_id in _all_enemies_aura_slow_prev.keys():
		if in_aura_now.has(enemy_id):
			continue
		var aura = null
		var exit_factor = 0.7
		var exit_duration = 2.0
		var source_exit = "TOWER_PARAIBA_exit"
		for tid in ecs.auras.keys():
			var a = ecs.auras[tid]
			if a.get("all_enemies_slow", false):
				aura = a
				source_exit = ecs.towers.get(tid, {}).get("def_id", "TOWER_PARAIBA") + "_exit"
				exit_factor = a.get("exit_slow_factor", 0.7)
				exit_duration = a.get("exit_slow_duration", 2.0)
				break
		if aura != null:
			if not ecs.slow_effects.has(enemy_id):
				ecs.slow_effects[enemy_id] = {}
			ecs.slow_effects[enemy_id][source_exit] = {"timer": exit_duration, "slow_factor": exit_factor}
	_all_enemies_aura_slow_prev = in_aura_now

const SCREAM_DEBUG = true  # логи крика в Output (отключить после отладки)
var _scream_stun_logged: Dictionary = {}  # enemy_id -> true, пока враг в стане (сбрасываем когда стан снят)

const SCREAM_ZONE_SLOW_FACTOR = 0.8  # в зоне крика ещё 20% замедление (speed *= 0.8)

func _update_scream_zones(delta: float):
	"""Зоны крика (Турнамент): обновляем таймеры, накапливаем время врагов в зоне; при 4 с в зоне — стан 6 с и +50% урона на 6 с. В зоне — доп. замедление 20%."""
	var now = ecs.game_state.get("wave_game_time", 0.0)
	var to_remove: Array = []
	var enemies_in_scream_zone: Dictionary = {}  # enemy_id -> true
	for i in range(ecs.scream_zones.size()):
		var z = ecs.scream_zones[i]
		if (now - z.get("created_at", 0.0)) >= z.get("duration", 7.5):
			to_remove.append(i)
			if SCREAM_DEBUG:
				print("[Scream] zone expired, removing (index %d)" % i)
			continue
		var zone_required_time = z.get("required_time", 2.0)
		var center_hex = Hex.from_pixel(z.center, Config.HEX_SIZE)
		var radius_hex = z.get("radius_hex", 4.0)
		if not z.has("enemy_time"):
			z["enemy_time"] = {}
		for enemy_id in ecs.enemies.keys():
			var pos = ecs.positions.get(enemy_id)
			if not pos:
				continue
			var enemy_hex = Hex.from_pixel(pos, Config.HEX_SIZE)
			if center_hex.distance_to(enemy_hex) > radius_hex:
				continue
			enemies_in_scream_zone[enemy_id] = true
			var acc = z.enemy_time.get(enemy_id, 0.0)
			if acc < 0:
				continue  # уже применили дебафф от этой зоны
			var acc_prev = acc
			acc += delta
			z.enemy_time[enemy_id] = acc
			if SCREAM_DEBUG:
				var sec_prev = int(acc_prev)
				var sec_now = int(acc)
				if sec_now > sec_prev and sec_now <= int(zone_required_time):
					print("[Scream] enemy %d in zone: %.1fs (need %.1fs to stun)" % [enemy_id, acc, zone_required_time])
			if acc >= zone_required_time:
				z.enemy_time[enemy_id] = -1.0
				var stun_dur = z.get("stun_duration", 6.0)
				var debuff_dur = z.get("debuff_duration", 6.0)
				var bonus = z.get("damage_bonus", 0.5)
				# Крик игнорирует иммунитет к заклинаниям (effect_immunity / BKB)
				ecs.scream_stun[enemy_id] = { "timer": stun_dur }
				ecs.scream_damage_bonus[enemy_id] = { "timer": debuff_dur, "bonus": bonus }
				if SCREAM_DEBUG:
					print("[Scream] STUN applied to enemy %d (stun %.1fs, bonus %.1fs)" % [enemy_id, stun_dur, debuff_dur])
	for i in range(to_remove.size() - 1, -1, -1):
		ecs.scream_zones.remove_at(to_remove[i])
	# Замедление 20% в зоне крика: ставим/обновляем slow_effects["scream_zone"], снимаем у вышедших
	for eid in ecs.slow_effects.keys():
		var data = ecs.slow_effects[eid]
		if data is Dictionary and data.has("scream_zone") and not enemies_in_scream_zone.get(eid, false):
			data.erase("scream_zone")
	for eid in enemies_in_scream_zone.keys():
		if not ecs.slow_effects.has(eid):
			ecs.slow_effects[eid] = {}
		ecs.slow_effects[eid]["scream_zone"] = { "timer": 0.2, "slow_factor": SCREAM_ZONE_SLOW_FACTOR }
	# Декремент таймеров стана и бонуса урона от крика
	var stun_to_erase: Array = []
	for eid in ecs.scream_stun.keys():
		ecs.scream_stun[eid]["timer"] -= delta
		if ecs.scream_stun[eid]["timer"] <= 0:
			stun_to_erase.append(eid)
	for eid in stun_to_erase:
		if SCREAM_DEBUG:
			print("[Scream] stun ended for enemy %d" % eid)
		_scream_stun_logged.erase(eid)
		ecs.scream_stun.erase(eid)
	var bonus_to_erase: Array = []
	for eid in ecs.scream_damage_bonus.keys():
		ecs.scream_damage_bonus[eid]["timer"] -= delta
		if ecs.scream_damage_bonus[eid]["timer"] <= 0:
			bonus_to_erase.append(eid)
	for eid in bonus_to_erase:
		ecs.scream_damage_bonus.erase(eid)

func _calculate_effective_speed(enemy_id: int, base_speed: float) -> float:
	if ecs.bash_effects.has(enemy_id):
		return 0.0
	if ecs.scream_stun.has(enemy_id):
		if SCREAM_DEBUG and not _scream_stun_logged.get(enemy_id, false):
			_scream_stun_logged[enemy_id] = true
			var t = ecs.scream_stun[enemy_id].get("timer", 0.0)
			print("[Scream] enemy %d speed=0 (stun timer %.2fs)" % [enemy_id, t])
		return 0.0
	var speed = base_speed
	
	speed *= ecs.get_combined_slow_factor(enemy_id)
	
	if ecs.jade_poisons.has(enemy_id):
		var jade = ecs.jade_poisons[enemy_id]
		var instances = jade.get("instances", [])
		var stacks = instances.size()
		var slow_per_stack = jade.get("slow_factor_per_stack", Config.JADE_SLOW_PER_STACK)
		var path_len = ecs.game_state.get("wave_path_length", 0)
		var jade_effect_mult = Config.get_path_length_effectiveness_mult(path_len)
		var total_slow = minf(0.9, slow_per_stack * stacks * jade_effect_mult)
		var speed_mult = max(1.0 - total_slow, 0.1)
		speed *= speed_mult
	
	# Кварц/Чарминг: аура замедления только для летающих (стакается между собой и с slow_effects)
	var flying_slow_mult = ecs.flying_aura_slows.get(enemy_id, 1.0)
	speed *= flying_slow_mult
	
	# Раш: +250% скорости на 2 сек, кулдаун 5 сек
	var enemy = ecs.enemies.get(enemy_id, {})
	if enemy.get("rush_duration_left", 0.0) > 0:
		speed *= Config.RUSH_SPEED_MULT
	
	speed *= GameManager.get_card_enemy_speed_mult()
	# Компенсация длинной волны: ускорение врагов при >120 с (2x) и >180 с (4x) игрового времени
	var wave_game_time = ecs.game_state.get("wave_game_time", 0.0)
	speed *= Config.get_wave_duration_speed_compensation(wave_game_time)
	return speed

func _apply_environmental_damage(enemy_id: int, hex: Hex) -> void:
	var total_damage = 0
	var line_damage = 0
	var hex_key = hex.to_key()
	# O(1) проверка руды через ore_hex_index
	var ore_id = ecs.ore_hex_index.get(hex_key, -1)
	if ore_id >= 0:
		var ore = ecs.ores.get(ore_id)
		if ore and ore.get("current_reserve", 0.0) >= Config.ORE_DEPLETION_THRESHOLD:
			total_damage += Config.ENV_DAMAGE_ORE_PER_TICK
	# Урон энерголинии: скейлится от руды в сети и уровня игрока (руда * лвл / 5)
	if GameManager.energy_network and GameManager.energy_network.line_hex_set.has(hex_key):
		var totals = GameManager.get_ore_network_totals()
		var ore_amount = totals.get("total_current", 0.0)
		var player_level = 1
		for pid in ecs.player_states.keys():
			player_level = ecs.player_states[pid].get("level", 1)
			break
		line_damage = max(1, int(ore_amount * player_level / 40.0))  # в 8 раз меньше, чем было (/5)
		total_damage += line_damage
	if total_damage <= 0:
		return
	var total_before_mult = total_damage
	var mult = GameManager.get_damage_to_enemy_multiplier(enemy_id)
	total_damage = int(total_damage * mult)
	if total_damage <= 0:
		return
	# Учёт урона линии между майнерами для топа (не MVP)
	if line_damage > 0 and total_before_mult > 0 and ecs.game_state.has("energy_line_damage_this_wave"):
		var line_portion = float(line_damage) / float(total_before_mult)
		ecs.game_state["energy_line_damage_this_wave"] = ecs.game_state.get("energy_line_damage_this_wave", 0) + int(total_damage * line_portion)
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
				# Система успеха: штраф за прохождение чекпоинта (по оставшемуся HP врага)
				if GameManager:
					GameManager.on_enemy_reached_checkpoint(enemy_id, i + 1)
				# Вторая половина пути: если сегмент прошли медленнее среднего — помечаем для +20% урона
				var num_cp = hex_map.checkpoints.size()
				if i >= 1 and i >= num_cp / 2:
					var times = ecs.game_state.get("wave_enemy_checkpoint_times", {})
					var prev_time = times.get(enemy_id, {}).get(i - 1, 0.0)
					var now = ecs.game_state.get("wave_game_time", 0.0)
					var segment_time = now - prev_time
					var segment_key = "%d->%d" % [i - 1, i]
					var avg_time = GameManager.get_segment_average_game_time(segment_key)
					if avg_time > 0.0 and segment_time > avg_time:
						enemy["takes_slow_second_half_extra_damage"] = true
				enemy["last_checkpoint_index"] = i
				# Аналитика: время прохождения чекпоинта в игровом времени (не зависит от time_speed)
				if ecs.game_state.get("phase", -1) == GameTypes.GamePhase.WAVE_STATE:
					var times = ecs.game_state.get("wave_enemy_checkpoint_times", {})
					if not times.has(enemy_id):
						times[enemy_id] = {}
					times[enemy_id][i] = ecs.game_state.get("wave_game_time", 0.0)
					ecs.game_state["wave_enemy_checkpoint_times"] = times
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
	# Длина лабиринта: при длинном пути враги наносят меньше урона игроку (100% до 400 гексов, спад до 60% к 900+)
	var path_len = ecs.game_state.get("wave_path_length", 0)
	damage = int(damage * Config.get_path_length_enemy_damage_to_player_mult(path_len))
	damage = int(damage * Config.ENEMY_DAMAGE_TO_PLAYER_GLOBAL_MULT)
	damage = max(1, damage) if base_damage > 0 else 0
	
	for player_id in ecs.player_states.keys():
		var player = ecs.player_states[player_id]
		player["health"] -= damage
		ecs.game_state["hud_refresh_requested"] = true
		if player["health"] <= 0 and not Config.god_mode:
			ecs.game_state["game_over"] = true
		return

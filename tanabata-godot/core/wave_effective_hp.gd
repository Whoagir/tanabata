# wave_effective_hp.gd
# Расчёт общего эффективного HP волны (как в scripts/wave_hp_table.py).
# Используется для баланса перемешивания волн по интервалам: сохраняем кривую EHP при смене порядка.
class_name WaveEffectiveHP

const PATH_LENGTH_START := 150.0
const PATH_LENGTH_END := 900.0
const REGEN_REF_SEC := 10.0
const FLYING_PATH := 150.0
const REFLECTION_SAVE := 0.95
const REACTIVE_ARMOR_BONUS := 12
const UNTOUCHABLE_REDUCTION := 0.6
const DISARM_REDUCTION := 0.9
const BLINK_SPEED_MULT := 1.2
const RUSH_SPEED_MULT := 1.4
const HUS_REGEN_MULT := 1.9

static func path_length_for_wave(wn: int) -> float:
	if wn <= 1:
		return PATH_LENGTH_START
	if wn >= 40:
		return PATH_LENGTH_END
	return PATH_LENGTH_START + (PATH_LENGTH_END - PATH_LENGTH_START) * float(wn - 1) / 39.0

static func _enemy_speed(enemy_id: String, base_speed: float, wave_def: Dictionary) -> float:
	var s = base_speed * wave_def.get("speed_multiplier", 1.0) * wave_def.get("speed_multiplier_modifier", 1.0)
	s *= Config.ENEMY_SPEED_GLOBAL_MULT
	if enemy_id == "ENEMY_TOUGH" or enemy_id == "ENEMY_TOUGH_2":
		s *= Config.ENEMY_SPEED_TOUGH_MULT
	elif enemy_id == "ENEMY_DARKNESS_1" or enemy_id == "ENEMY_DARKNESS_2":
		s *= Config.ENEMY_SPEED_DARKNESS_MULT
	elif enemy_id == "ENEMY_BOSS":
		s *= Config.ENEMY_SPEED_BOSS_MULT
	return s

static func armor_to_damage_factor(armor: float) -> float:
	if armor == 0.0:
		return 1.0
	return 1.0 - (0.06 * armor) / (1.0 + 0.06 * abs(armor))

static func _compute_wave_entries(wave_def: Dictionary, wn: int, is_tutorial: bool) -> Array:
	var entries: Array = []
	var code_mult = DataRepository.get_wave_health_code_multiplier(wn, is_tutorial)
	if wave_def.has("enemies") and wave_def["enemies"] is Array:
		for e in wave_def["enemies"]:
			var enemy_id: String = e.get("enemy_id", "")
			var count: int = int(e.get("count", 1))
			var enemy_def = DataRepository.get_enemy_def(enemy_id)
			if enemy_def.is_empty():
				continue
			var flying: bool = enemy_def.get("flying", false)
			var health_mult = wave_def.get("health_multiplier", 1.0)
			if wave_def.has("health_multiplier_flying") and wave_def.has("health_multiplier_ground"):
				health_mult = wave_def["health_multiplier_flying"] if flying else wave_def["health_multiplier_ground"]
			health_mult *= wave_def.get("health_multiplier_modifier", 1.0)
			var base_health = wave_def.get("health_override", enemy_def.get("health", 100))
			if base_health <= 0:
				base_health = enemy_def.get("health", 100)
			base_health = int(base_health * health_mult * 1.0)
			base_health = maxi(1, int(base_health * code_mult))
			var phys_bonus = wave_def.get("physical_armor_bonus", 0)
			var mag_bonus = wave_def.get("magical_armor_bonus", 0)
			var mag_armor = (enemy_def.get("magical_armor", 0) + mag_bonus) * wave_def.get("magical_armor_multiplier", 1.0)
			var pure_resist = wave_def.get("pure_damage_resistance", 0.0)
			var speed = _enemy_speed(enemy_id, float(enemy_def.get("speed", 80)), wave_def)
			var abilities: Array = []
			if e.get("abilities") != null:
				abilities.assign(e["abilities"] if e["abilities"] is Array else [])
			elif wave_def.get("abilities") != null:
				var ab = wave_def["abilities"]
				abilities.assign(ab if ab is Array else [])
			if enemy_id == "ENEMY_HEALER" and wn == 34:
				if not "bkb" in abilities:
					abilities.append("bkb")
			var evasion_chance = float(e.get("evasion_chance", wave_def.get("evasion_chance", 0.0)))
			var path_len_regen = Config.REGEN_FLYING_PATH if flying else Config.get_maze_length_for_regen(wn)
			var base_regen = Config.get_regen_base_for_wave(wn)
			var regen_scale = Config.get_regen_scale(path_len_regen, speed, abilities, flying)
			var regen = base_regen * regen_scale * wave_def.get("regen_multiplier_modifier", 1.0)
			entries.append({
				"enemy_id": enemy_id,
				"count": count,
				"base_health": base_health,
				"phys_armor": enemy_def.get("physical_armor", 0) + phys_bonus,
				"mag_armor": mag_armor,
				"pure_armor": enemy_def.get("pure_armor", 0),
				"pure_resist": pure_resist,
				"speed": speed,
				"flying": flying,
				"abilities": abilities,
				"evasion_chance": evasion_chance,
				"regen": regen
			})
	else:
		var enemy_id: String = wave_def.get("enemy_id", "")
		var count: int = int(wave_def.get("count", 0))
		var enemy_def = DataRepository.get_enemy_def(enemy_id)
		if enemy_def.is_empty():
			return entries
		var flying: bool = enemy_def.get("flying", false)
		var health_mult = wave_def.get("health_multiplier", 1.0)
		if wave_def.has("health_multiplier_flying") and wave_def.has("health_multiplier_ground"):
			health_mult = wave_def["health_multiplier_flying"] if flying else wave_def["health_multiplier_ground"]
		health_mult *= wave_def.get("health_multiplier_modifier", 1.0)
		var base_health = wave_def.get("health_override", enemy_def.get("health", 100))
		if base_health <= 0:
			base_health = enemy_def.get("health", 100)
		base_health = int(base_health * health_mult * 1.0)
		base_health = maxi(1, int(base_health * code_mult))
		var phys_bonus = wave_def.get("physical_armor_bonus", 0)
		var mag_bonus = wave_def.get("magical_armor_bonus", 0)
		var mag_armor = (enemy_def.get("magical_armor", 0) + mag_bonus) * wave_def.get("magical_armor_multiplier", 1.0)
		var pure_resist = wave_def.get("pure_damage_resistance", 0.0)
		var speed = _enemy_speed(enemy_id, float(enemy_def.get("speed", 80)), wave_def)
		var abilities: Array = []
		if wave_def.get("abilities") != null:
			var ab = wave_def["abilities"]
			abilities.assign(ab if ab is Array else [])
		if enemy_id == "ENEMY_HEALER" and wn == 34:
			if not "bkb" in abilities:
				abilities.append("bkb")
		var evasion_chance = float(wave_def.get("evasion_chance", 0.0))
		var path_len_regen = Config.REGEN_FLYING_PATH if flying else Config.get_maze_length_for_regen(wn)
		var base_regen = Config.get_regen_base_for_wave(wn)
		var regen_scale = Config.get_regen_scale(path_len_regen, speed, abilities, flying)
		var regen = base_regen * regen_scale * wave_def.get("regen_multiplier_modifier", 1.0)
		entries.append({
			"enemy_id": enemy_id,
			"count": count,
			"base_health": base_health,
			"phys_armor": enemy_def.get("physical_armor", 0) + phys_bonus,
			"mag_armor": mag_armor,
			"pure_armor": enemy_def.get("pure_armor", 0),
			"pure_resist": pure_resist,
			"speed": speed,
			"flying": flying,
			"abilities": abilities,
			"evasion_chance": evasion_chance,
			"regen": regen
		})
	return entries

static func compute_wave_effective_hp(wave_number: int, is_tutorial: bool) -> float:
	var wave_def = DataRepository.get_wave_def(wave_number)
	if wave_def.is_empty():
		return 0.0
	var entries = _compute_wave_entries(wave_def, wave_number, is_tutorial)
	var path_len = path_length_for_wave(wave_number)
	var effective_total_hp := 0.0
	for e in entries:
		var ab: Array = e.get("abilities", [])
		var regen_sec = e["regen"]
		if "hus" in ab:
			regen_sec *= HUS_REGEN_MULT
		var effective_hp_raw = float(e["base_health"]) + regen_sec * REGEN_REF_SEC
		var phys_a = float(e["phys_armor"])
		var mag_a = float(e["mag_armor"])
		if "reactive_armor" in ab:
			phys_a += REACTIVE_ARMOR_BONUS
			mag_a += REACTIVE_ARMOR_BONUS
		var f_phys := 0.0
		if not ("ivasion" in ab):
			f_phys = armor_to_damage_factor(phys_a)
		var f_mag := 0.0
		if not ("bkb" in ab):
			f_mag = armor_to_damage_factor(mag_a)
		var f_pure = armor_to_damage_factor(float(e["pure_armor"])) * (1.0 - e["pure_resist"])
		var f_sum = f_phys + f_mag + f_pure
		if f_sum <= 0.0:
			f_sum = 1.0
		var ability_mult := 1.0
		var ev = e.get("evasion_chance", 0.0)
		if ev > 0 and ev < 1.0:
			ability_mult *= 1.0 / (1.0 - ev)
		if "reflection" in ab:
			ability_mult *= 1.0 / REFLECTION_SAVE
		if "untouchable" in ab:
			ability_mult *= 1.0 / UNTOUCHABLE_REDUCTION
		if "disarm" in ab:
			ability_mult *= 1.0 / DISARM_REDUCTION
		var speed_eff = e["speed"]
		if "blink" in ab:
			speed_eff *= BLINK_SPEED_MULT
		if "rush" in ab:
			speed_eff *= RUSH_SPEED_MULT
		var path_eff = FLYING_PATH if e["flying"] else path_len
		var per_unit = (effective_hp_raw / f_sum) * ability_mult
		var count = int(e["count"])
		effective_total_hp += per_unit * (path_eff / speed_eff) * count
	return effective_total_hp

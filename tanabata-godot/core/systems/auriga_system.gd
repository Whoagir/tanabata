# auriga_system.gd
# Башня Аурига: стреляет линией до 4 гексов в одном из 6 направлений.
# Не стреляет через стены/вышки; один выстрел = один урон всем врагам на линии.
extends RefCounted

var ecs: ECSWorld
var hex_map: HexMap
var power_source_finder: Callable

const LINE_LENGTH = 5
const AURIGA_DAMAGE_MULT = 3.0  # база; итого ×0.6 обычно, ×2.5 к врагам «тьма»
const AURIGA_NERF_MULT = 0.6    # −40% урона всем
const AURIGA_VS_DARKNESS_MULT = 2.5  # +150% к врагам Тьма (ENEMY_DARKNESS_*)
const AURIGA_DEF_ID = "TOWER_AURIGA"
const ROTATION_DELAY_FRAMES = 3  # один шаг поворота раз в 3 кадра (скорость поворота в 3 раза ниже)

# Направления: 0=E, 1=NE, 2=NW, 3=W, 4=SW, 5=SE (как в Hex.DIRECTIONS)

func _init(ecs_world: ECSWorld, map: HexMap, finder: Callable):
	ecs = ecs_world
	hex_map = map
	power_source_finder = finder

func update(delta: float):
	if ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE) != GameTypes.GamePhase.WAVE_STATE:
		_hide_all_auriga_lines()
		return

	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		if tower.get("def_id", "") != AURIGA_DEF_ID or not tower.get("is_active", false) or tower.get("is_manually_disabled", false):
			if ecs.auriga_lines.has(tower_id):
				ecs.auriga_lines[tower_id]["is_visible"] = false
			continue

		var tower_hex = tower.get("hex")
		if not tower_hex:
			continue
		var combat = ecs.combat.get(tower_id)
		if not combat:
			continue

		# Допустимые направления: соседний гекс свободен (нет башни/стены)
		var allowed_dirs = []
		for d in range(6):
			var neighbor_hex = tower_hex.neighbor(d)
			if hex_map.get_tower_id(neighbor_hex) == GameTypes.INVALID_ENTITY_ID:
				allowed_dirs.append(d)

		if allowed_dirs.is_empty():
			ecs.auriga_lines[tower_id] = {"is_visible": false, "hexes": [], "current_direction": -1}
			continue

		# Линии по направлениям один раз (оптимизация: не вызывать _get_line_hexes повторно)
		var line_hexes_per_dir = {}
		for d in allowed_dirs:
			line_hexes_per_dir[d] = _get_line_hexes(tower_hex, d)
		var enemy_count_per_dir = {}
		for d in allowed_dirs:
			enemy_count_per_dir[d] = _count_enemies_on_hexes(line_hexes_per_dir[d])

		# Выбираем направление с макс. врагов; при равенстве — кратчайший поворот от текущего, при 180° — случайно
		var best_dirs = []
		var best_count = -1
		for d in allowed_dirs:
			var c = enemy_count_per_dir[d]
			if c > best_count:
				best_count = c
				best_dirs = [d]
			elif c == best_count:
				best_dirs.append(d)
		var prev = ecs.auriga_lines.get(tower_id, {}).get("current_direction", -1)
		var chosen_dir = allowed_dirs[0]
		if best_dirs.size() == 1:
			chosen_dir = best_dirs[0]
		elif best_dirs.size() > 1:
			if prev < 0:
				chosen_dir = best_dirs[randi() % best_dirs.size()]
			else:
				var best_step = 7
				var candidates = []
				for d in best_dirs:
					var step_cw = (d - prev + 6) % 6
					var step_ccw = (prev - d + 6) % 6
					var step = mini(step_cw, step_ccw)
					if step < best_step:
						best_step = step
						candidates = [d]
					elif step == best_step:
						candidates.append(d)
				chosen_dir = candidates[randi() % candidates.size()]

		# Текущее направление (куда смотрим): поворот в 3 раза медленнее — один шаг раз в ROTATION_DELAY_FRAMES кадров
		var stored = ecs.auriga_lines.get(tower_id, {})
		var current_dir = stored.get("current_direction", -1)
		var rotation_wait = stored.get("rotation_wait", 0)
		if current_dir < 0 or not (current_dir in allowed_dirs):
			current_dir = chosen_dir
			rotation_wait = 0
		elif current_dir != chosen_dir:
			if rotation_wait <= 0:
				var step_cw = (chosen_dir - current_dir + 6) % 6
				var step_ccw = (current_dir - chosen_dir + 6) % 6
				if step_ccw < step_cw:
					current_dir = (current_dir - 1 + 6) % 6
				else:
					current_dir = (current_dir + 1) % 6
				rotation_wait = ROTATION_DELAY_FRAMES
			else:
				rotation_wait -= 1
		# Линия и выстрел — по текущему направлению (куда реально смотрит башня)
		if not (current_dir in line_hexes_per_dir):
			line_hexes_per_dir[current_dir] = _get_line_hexes(tower_hex, current_dir)
		var line_hexes = line_hexes_per_dir[current_dir]
		var hex_keys = []
		for h in line_hexes:
			hex_keys.append(h.to_key())

		ecs.auriga_lines[tower_id] = {
			"is_visible": true,
			"hexes": hex_keys,
			"current_direction": current_dir,
			"rotation_wait": rotation_wait
		}

		# Кулдаун и выстрел
		var cooldown = combat.get("fire_cooldown", 0.0)
		var cooldown_reduction = delta * GameManager.get_card_attack_speed_mult()
		if ecs.aura_effects.has(tower_id):
			cooldown_reduction *= ecs.aura_effects[tower_id].get("speed_multiplier", 1.0)
		cooldown -= cooldown_reduction
		if cooldown <= 0:
			var sources = power_source_finder.call(tower_id)
			if sources.is_empty():
				combat["fire_cooldown"] = 0.0
				continue
			var total_reserve = 0.0
			if GameManager.energy_network:
				for s in sources:
					total_reserve += GameManager.energy_network.get_power_source_reserve(s)
			var shot_cost = combat.get("shot_cost", 0.045)
			if tower.get("crafting_level", 0) >= 1:
				shot_cost *= Config.ORE_COST_TIER2_MULTIPLIER
			shot_cost += GameManager.get_curse_extra_ore_per_shot()
			if ecs.aura_effects.has(tower_id) and ecs.aura_effects[tower_id].get("speed_multiplier", 1.0) > 1.0:
				shot_cost /= ecs.aura_effects[tower_id].get("speed_multiplier", 1.0)
			if total_reserve < shot_cost - 1e-5:
				combat["fire_cooldown"] = 0.0
				continue
			var chosen = sources[randi() % sources.size()]
			if GameManager.energy_network:
				GameManager.energy_network.consume_from_power_source(chosen, shot_cost, tower_id)
			# Урон всем на линии
			var base_damage = GameManager.get_tower_base_damage(tower_id)
			var network_mult = 1.0
			if GameManager.energy_network:
				network_mult = GameManager.energy_network.get_network_ore_damage_mult(tower_id)
			var mvp_mult = GameManager.get_mvp_damage_mult(tower_id)
			var resistance_mult = GameManager.get_resistance_mult(tower_id)
			var early_mult = GameManager.get_early_craft_curse_damage_multiplier(tower_id)
			var base_final = max(1, int(float(base_damage) * AURIGA_DAMAGE_MULT * AURIGA_NERF_MULT * network_mult * mvp_mult * resistance_mult * early_mult))
			var aura_eff = ecs.aura_effects.get(tower_id, {})
			var damage_bonus = aura_eff.get("damage_bonus", 0) + GameManager.get_card_damage_bonus_global()
			var damage_bonus_percent = aura_eff.get("damage_bonus_percent", 0.0)
			var damage_type = "PURE"
			var line_hex_set = {}
			for k in hex_keys:
				line_hex_set[k] = true
			for enemy_id in ecs.enemies.keys():
				var pos = ecs.positions.get(enemy_id)
				if not pos:
					continue
				var health = ecs.healths.get(enemy_id)
				if not health or health.get("current", 0) <= 0:
					continue
				var enemy_hex = Hex.from_pixel(pos, Config.HEX_SIZE)
				if not line_hex_set.has(enemy_hex.to_key()):
					continue
				var enemy = ecs.enemies.get(enemy_id, {})
				var def_id = enemy.get("def_id", "")
				var vs_darkness = 1.0
				if "DARKNESS" in def_id:
					vs_darkness = AURIGA_VS_DARKNESS_MULT
				var final_damage = max(1, int(float(base_final) * vs_darkness))
				if damage_bonus_percent > 0:
					final_damage = int(final_damage * (1.0 + damage_bonus_percent))
				final_damage += damage_bonus
				if not GameManager.roll_evasion(enemy_id):
					_apply_damage(enemy_id, final_damage, damage_type, tower_id)
			combat["fire_cooldown"] = 1.0 / combat.get("fire_rate", 1.0)
		else:
			combat["fire_cooldown"] = cooldown

func _hide_all_auriga_lines():
	for tid in ecs.auriga_lines.keys():
		ecs.auriga_lines[tid]["is_visible"] = false

func _get_line_hexes(start_hex: Hex, direction: int) -> Array:
	var result = []
	var h = start_hex
	for _i in range(LINE_LENGTH):
		h = h.neighbor(direction)
		if hex_map.get_tower_id(h) != GameTypes.INVALID_ENTITY_ID:
			break
		result.append(h)
	return result

func _count_enemies_on_hexes(hexes: Array) -> int:
	var keys = {}
	for h in hexes:
		keys[h.to_key()] = true
	var count = 0
	for enemy_id in ecs.enemies.keys():
		var pos = ecs.positions.get(enemy_id)
		if not pos:
			continue
		var health = ecs.healths.get(enemy_id)
		if not health or health.get("current", 0) <= 0:
			continue
		var enemy_hex = Hex.from_pixel(pos, Config.HEX_SIZE)
		if keys.has(enemy_hex.to_key()):
			count += 1
	return count

func _apply_damage(entity_id: int, damage: int, damage_type: String, source_tower_id: int = -1):
	var health = ecs.healths.get(entity_id)
	if not health:
		return
	if damage_type.to_upper() == "MAGICAL" and GameManager.is_magic_immune(entity_id):
		return
	var final_damage = damage
	match damage_type.to_upper():
		"PHYSICAL":
			if GameManager.is_physical_immune(entity_id):
				final_damage = 0
			else:
				var arm = GameManager.get_effective_physical_armor(entity_id)
				final_damage = max(1, int(damage * GameManager.armor_to_damage_factor(float(arm))))
		"MAGICAL":
			if GameManager.is_magic_immune(entity_id):
				final_damage = 0
			else:
				var arm = GameManager.get_effective_magical_armor(entity_id)
				final_damage = max(1, int(damage * GameManager.armor_to_damage_factor(float(arm))))
		"PURE", "SLOW", "POISON":
			var arm = GameManager.get_effective_pure_armor(entity_id)
			final_damage = int(damage * GameManager.armor_to_damage_factor(float(arm)))
			var pure_res = GameManager.get_pure_damage_resistance(entity_id)
			if pure_res > 0.0:
				final_damage = int(final_damage * (1.0 - pure_res))
	if GameManager.has_curse_hp_percent():
		var max_hp = health.get("max", 100)
		final_damage += int(max_hp * 0.004)
	final_damage = int(final_damage * GameManager.get_damage_to_enemy_multiplier(entity_id, source_tower_id))
	if final_damage < 1 and damage > 0:
		final_damage = 1
	health["current"] = max(0, health["current"] - final_damage)
	GameManager.on_enemy_took_damage(entity_id, final_damage, source_tower_id)
	ecs.damage_flashes[entity_id] = {"timer": 0.2}
	if health["current"] <= 0:
		ecs.kill_enemy(entity_id)

# volcano_system.gd
# Система атаки башни "Вулкан" — AoE урон по врагам в радиусе
# Портировано из Go: internal/system/volcano_system.go
extends RefCounted

var ecs: ECSWorld
var power_source_finder: Callable

const VOLCANO_TICK_RATE = 8.0  # 8 тиков в секунду (в 2 раза чаще)
const VOLCANO_DAMAGE_MULT = 0.85  # урон вулкана понижен на 15%

func _init(ecs_world: ECSWorld, finder: Callable):
	ecs = ecs_world
	power_source_finder = finder

func update(delta: float):
	if ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE) != GameTypes.GamePhase.WAVE_STATE:
		return
	var aura_ore_factor = Config.get_aura_ore_cost_factor(ecs.get_player_level())
	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		var def_id = tower.get("def_id", "")
		if (def_id != "TOWER_VOLCANO" and def_id != "TOWER_RUBY" and def_id != "TOWER_ANTIQUE") or not tower.get("is_active", false) or tower.get("is_manually_disabled", false):
			continue

		if not ecs.volcano_auras.has(tower_id):
			ecs.volcano_auras[tower_id] = {"tick_timer": 0.0}

		var aura = ecs.volcano_auras[tower_id]
		aura["tick_timer"] = aura.get("tick_timer", 0.0) - delta
		if aura["tick_timer"] > 0:
			continue
		aura["tick_timer"] = 1.0 / VOLCANO_TICK_RATE

		var combat = ecs.combat.get(tower_id)
		if not combat:
			continue

		var sources = power_source_finder.call(tower_id)
		if sources.is_empty():
			continue

		var total_reserve = 0.0
		if GameManager.energy_network:
			for s in sources:
				total_reserve += GameManager.energy_network.get_power_source_reserve(s)

		var tick_cost = (combat.get("shot_cost", 0.25) / VOLCANO_TICK_RATE) * aura_ore_factor
		tick_cost += GameManager.get_curse_extra_ore_per_shot() / VOLCANO_TICK_RATE
		if tower.get("crafting_level", 0) >= 1:
			tick_cost *= Config.ORE_COST_TIER2_MULTIPLIER
		if total_reserve < tick_cost:
			continue

		var tower_hex = tower.get("hex")
		if not tower_hex:
			continue

		var range_radius = combat.get("range", 2)
		var targets = []
		for enemy_id in ecs.enemies.keys():
			var enemy_pos = ecs.positions.get(enemy_id)
			if not enemy_pos:
				continue
			var health = ecs.healths.get(enemy_id)
			if not health or health.get("current", 0) <= 0:
				continue
			var enemy_hex = Hex.from_pixel(enemy_pos, Config.HEX_SIZE)
			if tower_hex.distance_to(enemy_hex) <= range_radius:
				targets.append(enemy_id)

		if targets.is_empty():
			continue

		# Списываем энергию
		var chosen = sources[randi() % sources.size()]
		if GameManager.energy_network:
			GameManager.energy_network.consume_from_power_source(chosen, tick_cost, tower_id)

		var base_damage = GameManager.get_tower_base_damage(tower_id)
		# Меньше целей — больше урона по каждой (1 цель = 3x, "размер волны" целей = 1x, линейно)
		var wave_size = ecs.game_state.get("current_wave_enemy_count", 20)
		var n = mini(targets.size(), wave_size)
		var denom = max(1, wave_size - 1)
		var mult = 1.0 if n >= wave_size else (3.0 - 2.0 * (n - 1) / float(denom))
		var network_mult = 1.0
		if GameManager.energy_network:
			network_mult = GameManager.energy_network.get_network_ore_damage_mult(tower_id)
		var mvp_mult = GameManager.get_mvp_damage_mult(tower_id)
		var resistance_mult = GameManager.get_resistance_mult(tower_id)
		var early_mult = GameManager.get_early_craft_curse_damage_multiplier(tower_id)
		var current_wave = ecs.game_state.get("current_wave", 0)
		var wave_mult = Config.get_tower_damage_mult_for_wave(def_id, current_wave)
		var tick_damage = max(1, int(float(max(1, base_damage)) * mult * network_mult * mvp_mult * resistance_mult * early_mult * VOLCANO_DAMAGE_MULT * wave_mult))
		tick_damage += GameManager.get_card_damage_bonus_global()
		var damage_type = combat.get("attack_type", "PHYSICAL")
		var dt_upper = damage_type.to_upper()
		if dt_upper == "PHYSICAL":
			tick_damage += GameManager.get_card_phys_damage_bonus()
		elif dt_upper == "MAGICAL":
			tick_damage += GameManager.get_card_mag_damage_bonus()

		for target_id in targets:
			if GameManager.roll_evasion(target_id):
				pass
			else:
				_apply_damage(target_id, tick_damage, dt_upper, tower_id)
				if def_id == "TOWER_RUBY" or def_id == "TOWER_ANTIQUE":
					_apply_mag_armor_debuff_from_def(target_id, def_id)
			# Визуальный эффект (volcano_effects как в Go)
			var enemy_pos = ecs.positions.get(target_id)
			if enemy_pos:
				var renderable = ecs.renderables.get(target_id, {})
				var radius = renderable.get("radius", 10.0)
				var effect_id = ecs.create_entity()
				ecs.volcano_effects[effect_id] = {
					"pos": enemy_pos,
					"timer": 0.25,
					"max_radius": radius * 1.5,
					"color": Color(1.0, 0.27, 0.0)
				}
		# Антик: 1/300 шанс за тик — цепная молния на 7 целей по 4000 маг. урона
		if def_id == "TOWER_ANTIQUE" and targets.size() > 0:
			var tower_def = DataRepository.get_tower_def(def_id)
			var params = tower_def.get("combat", {}).get("attack", {}).get("params", {})
			var chance = params.get("chain_lightning_chance_per_tick", 0.0)
			if chance > 0.0 and randf() < chance:
				_try_antique_chain_lightning(tower_id, tower_hex, combat, params, targets)

func _apply_damage(entity_id: int, damage: int, damage_type: String, source_tower_id: int = -1):
	var health = ecs.healths.get(entity_id)
	if not health:
		return
	if damage_type.to_upper() == "MAGICAL" and GameManager.is_magic_immune(entity_id):
		return
	var enemy = ecs.enemies.get(entity_id, {})
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

func _apply_mag_armor_debuff_from_def(entity_id: int, def_id: String):
	"""Рубин/Антик: каждое попадание добавляет маг. дебафф из params def (стакается)."""
	var tower_def = DataRepository.get_tower_def(def_id)
	if tower_def.is_empty():
		return
	var params = tower_def.get("combat", {}).get("attack", {}).get("params", {})
	var add_per_hit = params.get("mag_armor_debuff_per_hit", 0.2)
	var duration = params.get("mag_armor_debuff_duration", 7.0)
	var current = ecs.mag_armor_debuffs.get(entity_id, [])
	var list: Array = current.duplicate() if current is Array else ([current] if current is Dictionary and current.size() > 0 else [])
	list.append({"amount": add_per_hit, "timer": duration})
	ecs.mag_armor_debuffs[entity_id] = list

func _try_antique_chain_lightning(tower_id: int, tower_hex, combat: Dictionary, params: Dictionary, tick_targets: Array):
	"""Антик: молния по цепочке до 7 целей, урон из params."""
	var chain_count = min(7, max(1, params.get("chain_lightning_count", 7)))
	var chain_damage_base = params.get("chain_lightning_damage", 4000)
	var range_px = float(params.get("chain_lightning_range_px", 450))
	var network_mult = 1.0
	if GameManager.energy_network:
		network_mult = GameManager.energy_network.get_network_ore_damage_mult(tower_id)
	var mvp_mult = GameManager.get_mvp_damage_mult(tower_id)
	var resistance_mult = GameManager.get_resistance_mult(tower_id)
	var early_mult = GameManager.get_early_craft_curse_damage_multiplier(tower_id)
	var chain_damage = max(1, int(chain_damage_base * network_mult * mvp_mult * resistance_mult * early_mult))
	chain_damage += GameManager.get_card_damage_bonus_global()
	chain_damage += GameManager.get_card_mag_damage_bonus()
	var first_id = tick_targets[randi() % tick_targets.size()]
	var chain_ids: Array = [first_id]
	var current_pos = ecs.positions.get(first_id)
	if not current_pos:
		_apply_damage(first_id, chain_damage, "MAGICAL", tower_id)
		return
	for _i in range(chain_count - 1):
		var best_id = -1
		var best_dist = range_px + 1.0
		for eid in ecs.enemies.keys():
			if eid in chain_ids:
				continue
			var h = ecs.healths.get(eid)
			if not h or h.get("current", 0) <= 0:
				continue
			var pos = ecs.positions.get(eid)
			if not pos:
				continue
			var d = current_pos.distance_to(pos)
			if d <= range_px and d < best_dist:
				best_dist = d
				best_id = eid
		if best_id < 0:
			break
		chain_ids.append(best_id)
		current_pos = ecs.positions.get(best_id)
	var snapshot: Array = []
	for eid in chain_ids:
		var pos = ecs.positions.get(eid)
		snapshot.append(pos if pos != null else Vector2.ZERO)
		if not GameManager.roll_evasion(eid):
			_apply_damage(eid, chain_damage, "MAGICAL", tower_id)
	if chain_ids.size() >= 2:
		ecs.chain_lightning_effects.append({
			"chain_ids": chain_ids,
			"snapshot_positions": snapshot,
			"timer": 0.5,
			"dead_timer": 0.3,
			"width_offset": 2
		})

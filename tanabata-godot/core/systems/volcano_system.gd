# volcano_system.gd
# Система атаки башни "Вулкан" — AoE урон по врагам в радиусе
# Портировано из Go: internal/system/volcano_system.go
extends RefCounted

var ecs: ECSWorld
var power_source_finder: Callable

const VOLCANO_TICK_RATE = 8.0  # 8 тиков в секунду (в 2 раза чаще)

func _init(ecs_world: ECSWorld, finder: Callable):
	ecs = ecs_world
	power_source_finder = finder

func update(delta: float):
	if ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE) != GameTypes.GamePhase.WAVE_STATE:
		return

	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		var def_id = tower.get("def_id", "")
		if (def_id != "TOWER_VOLCANO" and def_id != "TOWER_RUBY") or not tower.get("is_active", false):
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
		for sid in sources:
			if ecs.ores.has(sid):
				total_reserve += ecs.ores[sid].get("current_reserve", 0.0)

		var tick_cost = (combat.get("shot_cost", 0.25) / VOLCANO_TICK_RATE) * Config.AURA_ORE_COST_FACTOR
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
		if ecs.ores.has(chosen):
			var ore = ecs.ores[chosen]
			var mult = 1.0
			if GameManager.energy_network:
				mult = GameManager.energy_network.get_miner_efficiency_for_ore(chosen)
			var deduct = tick_cost / mult * GameManager.get_ore_consumption_multiplier()
			ore["current_reserve"] = max(0.0, ore.get("current_reserve", 0.0) - deduct)

		var base_damage = combat.get("damage", 40)
		# Меньше целей — больше урона по каждой (1 цель = 3x, "размер волны" целей = 1x, линейно)
		var wave_size = ecs.game_state.get("current_wave_enemy_count", 20)
		var n = mini(targets.size(), wave_size)
		var denom = max(1, wave_size - 1)
		var mult = 1.0 if n >= wave_size else (3.0 - 2.0 * (n - 1) / float(denom))
		var network_mult = 1.0
		if GameManager.energy_network:
			network_mult = GameManager.energy_network.get_network_ore_damage_mult(tower_id)
		var mvp_mult = GameManager.get_mvp_damage_mult(tower_id)
		var tick_damage = max(1, int(float(max(1, base_damage)) * mult * network_mult * mvp_mult))
		var damage_type = combat.get("attack_type", "PHYSICAL")

		for target_id in targets:
			if GameManager.roll_evasion(target_id):
				pass
			else:
				_apply_damage(target_id, tick_damage, damage_type, tower_id)
				if def_id == "TOWER_RUBY":
					_apply_ruby_mag_debuff(target_id)
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

func _apply_damage(entity_id: int, damage: int, damage_type: String, source_tower_id: int = -1):
	var health = ecs.healths.get(entity_id)
	if not health:
		return
	var enemy = ecs.enemies.get(entity_id, {})
	var final_damage = damage
	match damage_type.to_upper():
		"PHYSICAL":
			var arm = GameManager.get_effective_physical_armor(entity_id)
			final_damage = max(1, int(damage * GameManager.armor_to_damage_factor(float(arm))))
		"MAGICAL":
			var arm = GameManager.get_effective_magical_armor(entity_id)
			final_damage = max(1, int(damage * GameManager.armor_to_damage_factor(float(arm))))
		"PURE", "SLOW", "POISON":
			pass
	health["current"] = max(0, health["current"] - final_damage)
	GameManager.on_enemy_took_damage(entity_id, final_damage, source_tower_id)
	ecs.damage_flashes[entity_id] = {"timer": 0.2}
	if health["current"] <= 0:
		ecs.kill_enemy(entity_id)

func _apply_ruby_mag_debuff(entity_id: int):
	"""Рубин: каждое попадание добавляет -0.2 маг. брони на 7 сек (стакается)."""
	var tower_def = DataRepository.get_tower_def("TOWER_RUBY")
	var params = tower_def.get("combat", {}).get("attack", {}).get("params", {})
	var add_per_hit = params.get("mag_armor_debuff_per_hit", 0.2)
	var duration = params.get("mag_armor_debuff_duration", 7.0)
	var current = ecs.mag_armor_debuffs.get(entity_id, [])
	var list: Array = current.duplicate() if current is Array else ([current] if current is Dictionary and current.size() > 0 else [])
	list.append({"amount": add_per_hit, "timer": duration})
	ecs.mag_armor_debuffs[entity_id] = list

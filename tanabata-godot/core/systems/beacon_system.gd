# beacon_system.gd
# Система атаки башни "Маяк" — вращающийся луч по сектору
# Портировано из Go: internal/system/beacon_system.go
extends RefCounted

var ecs: ECSWorld
var power_source_finder: Callable

const BEACON_TICK_RATE = 24.0  # 24 тика в секунду

func _init(ecs_world: ECSWorld, finder: Callable):
	ecs = ecs_world
	power_source_finder = finder

func update(delta: float):
	if ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE) != GameTypes.GamePhase.WAVE_STATE:
		return

	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		if tower.get("def_id", "") != "TOWER_LIGHTHOUSE" or not tower.get("is_active", false):
			if ecs.beacon_sectors.has(tower_id):
				ecs.beacon_sectors[tower_id]["is_visible"] = false
			continue

		var tower_def = DataRepository.get_tower_def("TOWER_LIGHTHOUSE")
		var combat = ecs.combat.get(tower_id)
		if not combat:
			continue

		var attack_params = tower_def.get("combat", {}).get("attack", {}).get("params", {})
		var rotation_speed = attack_params.get("rotation_speed", 1.5)
		var arc_angle_deg = attack_params.get("arc_angle", 90)
		var arc_angle_rad = deg_to_rad(arc_angle_deg)

		if not ecs.beacons.has(tower_id):
			ecs.beacons[tower_id] = {
				"current_angle": 0.0,
				"rotation_speed": rotation_speed,
				"arc_angle": arc_angle_rad,
				"tick_timer": 0.0
			}

		var beacon = ecs.beacons[tower_id]
		beacon["current_angle"] = beacon.get("current_angle", 0.0) + beacon.get("rotation_speed", 1.5) * delta
		if beacon["current_angle"] > TAU:
			beacon["current_angle"] -= TAU

		if not ecs.beacon_sectors.has(tower_id):
			ecs.beacon_sectors[tower_id] = {}
		var range_hex_base = combat.get("range", 4)
		var range_hex = range_hex_base * Config.BEACON_RANGE_MULTIPLIER
		ecs.beacon_sectors[tower_id]["is_visible"] = true
		ecs.beacon_sectors[tower_id]["angle"] = beacon["current_angle"]
		ecs.beacon_sectors[tower_id]["arc"] = arc_angle_rad
		ecs.beacon_sectors[tower_id]["range"] = range_hex

		beacon["tick_timer"] = beacon.get("tick_timer", 0.0) - delta
		if beacon["tick_timer"] > 0:
			continue
		beacon["tick_timer"] = 1.0 / BEACON_TICK_RATE

		var sources = power_source_finder.call(tower_id)
		if sources.is_empty():
			continue

		var total_reserve = 0.0
		for sid in sources:
			if ecs.ores.has(sid):
				total_reserve += ecs.ores[sid].get("current_reserve", 0.0)

		var tick_cost = (combat.get("shot_cost", 0.2) / BEACON_TICK_RATE) * Config.AURA_ORE_COST_FACTOR
		if tower.get("crafting_level", 0) >= 1:
			tick_cost *= Config.ORE_COST_TIER2_MULTIPLIER
		if total_reserve < tick_cost:
			continue

		var tower_hex = tower.get("hex")
		if not tower_hex:
			continue

		var tower_pos = tower_hex.to_pixel(Config.HEX_SIZE)
		var range_px = range_hex * Config.HEX_SIZE
		var start_angle = beacon["current_angle"] - arc_angle_rad / 2
		var end_angle = beacon["current_angle"] + arc_angle_rad / 2

		var targets = []
		for enemy_id in ecs.enemies.keys():
			var enemy_pos = ecs.positions.get(enemy_id)
			if not enemy_pos:
				continue
			var health = ecs.healths.get(enemy_id)
			if not health or health.get("current", 0) <= 0:
				continue
			if _point_in_sector(enemy_pos, tower_pos, range_px, start_angle, end_angle):
				targets.append(enemy_id)

		if targets.is_empty():
			continue

		var chosen = sources[randi() % sources.size()]
		if ecs.ores.has(chosen):
			var ore = ecs.ores[chosen]
			var mult = 1.0
			if GameManager.energy_network:
				mult = GameManager.energy_network.get_miner_efficiency_for_ore(chosen)
			var deduct = tick_cost / mult * GameManager.get_ore_consumption_multiplier()
			ore["current_reserve"] = max(0.0, ore.get("current_reserve", 0.0) - deduct)

		var base_damage = combat.get("damage", 35)
		# Маяк: +20% урона за тик; множитель от руды в сети (мало руды — до 1.5x); MVP
		var network_mult = 1.0
		if GameManager.energy_network:
			network_mult = GameManager.energy_network.get_network_ore_damage_mult(tower_id)
		var mvp_mult = GameManager.get_mvp_damage_mult(tower_id)
		var tick_damage = max(1, int(float(base_damage) * Config.BEACON_DAMAGE_BASE_MULT * Config.BEACON_DAMAGE_BONUS_MULT / BEACON_TICK_RATE * network_mult * mvp_mult))
		var damage_type = combat.get("attack_type", "PURE")

		for target_id in targets:
			if not GameManager.roll_evasion(target_id):
				_apply_damage(target_id, tick_damage, damage_type, tower_id)
			var enemy_pos = ecs.positions.get(target_id)
			if enemy_pos:
				var renderable = ecs.renderables.get(target_id, {})
				var radius = renderable.get("radius", 10.0)
				var effect_id = ecs.create_entity()
				ecs.volcano_effects[effect_id] = {
					"pos": enemy_pos,
					"timer": 0.25,
					"max_radius": radius * 1.5,
					"color": Color(1.0, 1.0, 0.88)  # бело-желтый маяк
				}

func _point_in_sector(point: Vector2, center: Vector2, range_px: float, start_angle: float, end_angle: float) -> bool:
	var dx = point.x - center.x
	var dy = point.y - center.y
	var dist = sqrt(dx * dx + dy * dy)
	if dist > range_px:
		return false
	if dist < 2.0:
		return true
	var angle = fmod(atan2(dy, dx) + TAU, TAU)
	var sa = fmod(start_angle + TAU, TAU)
	var ea = fmod(end_angle + TAU, TAU)
	if sa <= ea:
		return angle >= sa and angle <= ea
	return angle >= sa or angle <= ea

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

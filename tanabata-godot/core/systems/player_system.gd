# player_system.gd
# Система опыта и уровней игрока
# Вызывает grant_xp_for_kill() при каждом убийстве врага
class_name PlayerSystem
extends RefCounted

var ecs: ECSWorld

func _init(ecs_world: ECSWorld):
	ecs = ecs_world

# Вызывать при убийстве врага (из projectile_system, combat_system, beacon_system, volcano_system)
static func grant_xp_for_kill(xp_amount: int = -1) -> void:
	if xp_amount < 0:
		xp_amount = Config.XP_PER_KILL
	
	if not GameManager.ecs:
		return
	
	for player_id in GameManager.ecs.player_states.keys():
		var player = GameManager.ecs.player_states[player_id]
		player["current_xp"] = player.get("current_xp", 0) + xp_amount
		var xp_to_next = player.get("xp_to_next_level", 100)
		
		# Уровень ап, пока хватает XP
		while player["current_xp"] >= xp_to_next:
			player["current_xp"] -= xp_to_next
			var level = player.get("level", 1) + 1
			player["level"] = level
			player["xp_to_next_level"] = Config.calculate_xp_for_level(level)
			xp_to_next = player["xp_to_next_level"]
		return  # Один игрок

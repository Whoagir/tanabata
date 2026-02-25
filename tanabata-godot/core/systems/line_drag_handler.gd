# line_drag_handler.gd
# Режим перетаскивания энерголиний (как в Go: startLineDrag, finishLineDrag, CancelLineDrag)
# Позволяет перенаправить линию от одной башни к другой
class_name LineDragHandler
extends RefCounted

var ecs: ECSWorld
var hex_map: HexMap
var energy_network: EnergyNetworkSystem

# Порог угла для попадания в линию (радианы) — как в Go: π/3.5
const ANGLE_THRESHOLD = PI / 3.5

func _init(ecs_: ECSWorld, hex_map_: HexMap, energy_network_: EnergyNetworkSystem):
	ecs = ecs_
	hex_map = hex_map_
	energy_network = energy_network_

func is_in_line_drag_mode() -> bool:
	return ecs.game_state.get("line_edit_mode", false)

func is_dragging() -> bool:
	return ecs.game_state.get("drag_source_tower_id", 0) != 0

func get_drag_source_tower_id() -> int:
	return ecs.game_state.get("drag_source_tower_id", 0)

func cancel_line_drag(unhide_line: bool = true) -> void:
	var hidden_id = ecs.game_state.get("hidden_line_id", 0)
	if unhide_line and hidden_id != 0 and ecs.energy_lines.has(hidden_id):
		ecs.energy_lines[hidden_id]["is_hidden"] = false
	ecs.game_state["drag_source_tower_id"] = 0
	ecs.game_state["drag_original_parent_id"] = 0
	ecs.game_state["hidden_line_id"] = 0

func handle_line_drag_click(hex: Hex, world_pos: Vector2) -> void:
	var source_id = ecs.game_state.get("drag_source_tower_id", 0)
	if source_id == 0:
		_start_line_drag(hex, world_pos)
	else:
		_finish_line_drag(hex)

func _start_line_drag(hex: Hex, world_pos: Vector2) -> void:
	var source_id = _get_tower_at(hex)
	if source_id < 0:
		return
	var source_tower = ecs.towers.get(source_id)
	var adj = energy_network._build_adjacency_list()
	var connections = adj.get(source_id, [])
	if connections.is_empty():
		return
	var source_hex = source_tower.get("hex")
	var source_pos = source_hex.to_pixel(Config.HEX_SIZE)
	var click_angle = atan2(world_pos.y - source_pos.y, world_pos.x - source_pos.x)
	var best_match_id = -1
	var min_angle_diff = PI
	for neighbor_id in connections:
		var neighbor_tower = ecs.towers.get(neighbor_id)
		if not neighbor_tower:
			continue
		var neighbor_hex = neighbor_tower.get("hex")
		var neighbor_pos = neighbor_hex.to_pixel(Config.HEX_SIZE)
		var line_angle = atan2(neighbor_pos.y - source_pos.y, neighbor_pos.x - source_pos.x)
		var angle_diff = abs(wrapf(click_angle - line_angle, -PI, PI))
		if angle_diff < min_angle_diff:
			min_angle_diff = angle_diff
			best_match_id = neighbor_id
	if best_match_id >= 0 and min_angle_diff < ANGLE_THRESHOLD:
		var line_id = energy_network.get_line_between_towers(source_id, best_match_id)
		if line_id >= 0:
			ecs.game_state["drag_source_tower_id"] = best_match_id
			ecs.game_state["drag_original_parent_id"] = source_id
			ecs.game_state["hidden_line_id"] = line_id
			ecs.energy_lines[line_id]["is_hidden"] = true

func _finish_line_drag(target_hex: Hex) -> void:
	var source_id = ecs.game_state.get("drag_source_tower_id", 0)
	var original_id = ecs.game_state.get("drag_original_parent_id", 0)
	var hidden_id = ecs.game_state.get("hidden_line_id", 0)
	var target_id = _get_tower_at(target_hex)
	if target_id < 0:
		# Клик на пустой гекс — отмена, восстанавливаем линию
		cancel_line_drag(true)
		return
	if target_id == source_id or target_id == original_id:
		# Клик на ту же башню — отмена, восстанавливаем линию
		cancel_line_drag(true)
		return
	if energy_network.reconnect_line(source_id, target_id, original_id, hidden_id):
		cancel_line_drag(false)  # Очищаем состояние, линия уже удалена в reconnect
	else:
		# Reconnect не прошёл (цикл, потеря питания) — восстанавливаем линию
		cancel_line_drag(true)

func _get_tower_at(hex: Hex) -> int:
	return hex_map.get_tower_id(hex)

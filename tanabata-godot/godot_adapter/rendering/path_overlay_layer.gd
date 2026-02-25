# path_overlay_layer.gd
# Отрисовка будущего пути (Future Path) и пройденных чекпоинтов (Cleared Checkpoints), как в Go
extends Node2D

var _last_fp_hash: int = -1
var _last_cleared_count: int = -1
var _last_phase: int = -1

func _process(_delta: float) -> void:
	if not GameManager.ecs:
		return
	var gs = GameManager.ecs.game_state
	var fp: Array = gs.get("future_path", [])
	var fp_hash = hash(fp)
	var cleared_count = gs.get("cleared_checkpoints", {}).size()
	var phase = gs.get("phase", 0)
	if fp_hash != _last_fp_hash or cleared_count != _last_cleared_count or phase != _last_phase:
		_last_fp_hash = fp_hash
		_last_cleared_count = cleared_count
		_last_phase = phase
		queue_redraw()

func _draw() -> void:
	if not GameManager.ecs:
		return
	var phase = GameManager.ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	var size = Config.HEX_SIZE
	var future_path: Array = GameManager.ecs.game_state.get("future_path", [])
	for key in future_path:
		var hex = Hex.from_key(key)
		var pos = hex.to_pixel(size)
		draw_colored_polygon(_poly_at(pos, size), Config.COLOR_FUTURE_PATH)
	if phase == GameTypes.GamePhase.WAVE_STATE:
		var cleared: Dictionary = GameManager.ecs.game_state.get("cleared_checkpoints", {})
		for key in cleared.keys():
			if not cleared.get(key, false):
				continue
			var hex = Hex.from_key(key)
			var pos = hex.to_pixel(size)
			draw_colored_polygon(_poly_at(pos, size), Config.COLOR_CHECKPOINT_CLEARED)

func _poly_at(center: Vector2, size: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(6):
		var angle_deg = 60.0 * i - 30.0
		var angle_rad = deg_to_rad(angle_deg)
		points.append(center + Vector2(size * cos(angle_rad), size * sin(angle_rad)))
	return points

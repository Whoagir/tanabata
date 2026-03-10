# headless_runner.gd
# Headless simulation runner for batch wave testing.
# Usage:
#   godot --headless --path . -- --snapshot path/last_run.json --wave 1 --wave-max 15 --runs 100 --seed 0
#   godot --headless --path . -- --snapshot path/last_run.json --wave 5 --runs 100
#   godot --headless --path . -- --seed N
extends Node

# Fixed timestep for deterministic simulation (~60fps equivalent)
const HEADLESS_DT: float = 1.0 / 60.0
# Ticks per real frame -- each real frame simulates ~3.3 seconds of game time
const TICKS_PER_FRAME: int = 200

var wave_system: WaveSystem
var movement_system: MovementSystem
var combat_system
var projectile_system
var status_effect_system
var aura_system
var volcano_system
var beacon_system
var auriga_system
var battery_system
var input_system: InputSystem

var _start_wave_pending: bool = false
var _snapshot: Dictionary = {}
var _snapshot_array: Array = []
var _wave_number: int = 1
var _wave_start: int = 1
var _wave_max: int = -1
var _runs_total: int = 1
var _run_index: int = 0
var _base_seed: int = -1
var _batch_mode: bool = false
var _single_wave_only: bool = false
var _single_wave_phase_was_wave: bool = false
var _csv_path: String = ""
var _csv_output_dir: String = ""
var _csv_lines: Array = []
var _finished: bool = false

func _ready():
	var args = OS.get_cmdline_user_args()
	_parse_args(args)
	if _wave_max < 0:
		_wave_max = _wave_number
	_wave_start = _wave_number
	if _wave_max > _wave_number:
		_csv_path = ""
	if _snapshot.is_empty() and _runs_total <= 1:
		_start_normal_run()
		return
	if not _snapshot.is_empty() and _runs_total >= 1:
		_batch_mode = true
		_single_wave_only = (_runs_total > 1)
		_run_index = 0
		_csv_lines.append(_csv_header())
		print("[Headless] Batch: waves %d-%d, %d runs each, seed base %d" % [_wave_number, _wave_max, _runs_total, _base_seed])
		_start_next_batch_run()
		return
	_start_normal_run()

func _parse_args(args: Array) -> void:
	for i in range(args.size()):
		if args[i] == "--snapshot":
			var path: String
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				path = args[i + 1]
			else:
				path = Config.get_project_snapshots_dir().path_join("last_run.json")
			var file = FileAccess.open(path, FileAccess.READ)
			if file:
				var json_str = file.get_as_text()
				file.close()
				var json = JSON.new()
				var err = json.parse(json_str)
				if err == OK:
					var data = json.get_data()
					if data is Array:
						_snapshot_array = data
					elif data is Dictionary:
						_snapshot_array = [data]
				else:
					push_warning("[Headless] Invalid JSON in snapshot: %s" % path)
			else:
				push_warning("[Headless] Cannot open snapshot: %s" % path)
		elif args[i] == "--wave" and i + 1 < args.size() and args[i + 1].is_valid_int():
			_wave_number = clampi(args[i + 1].to_int(), 1, 40)
		elif args[i] == "--wave-max" and i + 1 < args.size() and args[i + 1].is_valid_int():
			_wave_max = clampi(args[i + 1].to_int(), 1, 40)
		elif args[i] == "--runs" and i + 1 < args.size() and args[i + 1].is_valid_int():
			_runs_total = maxi(1, args[i + 1].to_int())
		elif args[i] == "--seed" and i + 1 < args.size() and args[i + 1].is_valid_int():
			_base_seed = args[i + 1].to_int()
		elif args[i] == "--out" and i + 1 < args.size():
			_csv_path = args[i + 1]
		elif args[i] == "--out-dir" and i + 1 < args.size():
			_csv_output_dir = args[i + 1]
	_load_snapshot_for_wave(_wave_number)
	_resolve_base_seed()

func _load_snapshot_for_wave(wave: int) -> void:
	if _snapshot_array.is_empty():
		return
	var idx = clampi(wave - 1, 0, _snapshot_array.size() - 1)
	_snapshot = _snapshot_array[idx]
	if _snapshot.is_empty() and not _snapshot_array.is_empty():
		_snapshot = _snapshot_array[0]

func _resolve_base_seed() -> void:
	if _base_seed <= 0 and not _snapshot.is_empty():
		_base_seed = int(_snapshot.get("run_seed", 0))
	if _base_seed <= 0:
		_base_seed = Config.get_initial_run_seed()
	if _base_seed <= 0:
		_base_seed = randi()

func _csv_header() -> String:
	return "run_index,seed,wave_number,enemy_def_id,spawned,killed,passed,total_hp,duration_sec,success,game_over,success_lvl_before,success_lvl_after,player_hp_before,player_hp_after,ore_spent,enemy_abilities,enemy_base_speed,enemy_base_hp,enemy_regen_base,enemy_flying,source_wave"

func _start_normal_run() -> void:
	print("[Headless] Single run. Seed: %s" % Config.get_initial_run_seed())
	GameManager.reinit_game()
	GameManager.ecs.game_state["difficulty"] = GameManager.difficulty
	_create_systems()
	GameManager.update_future_path()
	_start_wave_pending = true

func _start_next_batch_run() -> void:
	var run_seed = _base_seed + _run_index
	if not GameManager.reinit_from_snapshot(_snapshot, run_seed):
		print("[Headless] reinit_from_snapshot failed at wave %d run %d, skipping" % [_wave_number, _run_index])
		_finish_wave()
		return
	GameManager.ecs.game_state["difficulty"] = GameManager.difficulty
	_create_systems()
	GameManager.update_future_path()
	_start_wave_pending = true
	_single_wave_phase_was_wave = false

func _create_systems() -> void:
	input_system = InputSystem.new(GameManager.ecs, GameManager.hex_map, null)
	wave_system = WaveSystem.new(GameManager.ecs, GameManager.hex_map)
	movement_system = MovementSystem.new(GameManager.ecs, GameManager.hex_map)
	var CombatSystemScript = preload("res://core/systems/combat_system.gd")
	var ProjectileSystemScript = preload("res://core/systems/projectile_system.gd")
	var StatusEffectSystemScript = preload("res://core/systems/status_effect_system.gd")
	var AuraSystemScript = preload("res://core/systems/aura_system.gd")
	var VolcanoSystemScript = preload("res://core/systems/volcano_system.gd")
	var BeaconSystemScript = preload("res://core/systems/beacon_system.gd")
	combat_system = CombatSystemScript.new(GameManager.ecs, GameManager.hex_map)
	projectile_system = ProjectileSystemScript.new(GameManager.ecs)
	status_effect_system = StatusEffectSystemScript.new(GameManager.ecs)
	aura_system = AuraSystemScript.new(GameManager.ecs, GameManager.hex_map)
	var power_finder = func(tid): return GameManager.energy_network._find_power_sources(tid) if GameManager.energy_network else []
	volcano_system = VolcanoSystemScript.new(GameManager.ecs, power_finder)
	beacon_system = BeaconSystemScript.new(GameManager.ecs, power_finder)
	var AurigaSystemScript = preload("res://core/systems/auriga_system.gd")
	auriga_system = AurigaSystemScript.new(GameManager.ecs, GameManager.hex_map, power_finder)
	var BatterySystemScript = preload("res://core/systems/battery_system.gd")
	battery_system = BatterySystemScript.new(GameManager.ecs, GameManager.energy_network)
	GameManager.input_system = input_system
	GameManager.wave_system = wave_system
	GameManager.movement_system = movement_system
	GameManager.combat_system = combat_system

# ---------------------------------------------------------------------------
# Main loop: batch uses fixed timestep with multi-tick speedup
# ---------------------------------------------------------------------------

func _process(_delta: float):
	if _finished:
		return
	if _batch_mode:
		for _tick in TICKS_PER_FRAME:
			_process_batch_tick()
			if _finished:
				return
		return
	_process_single(_delta)

func _process_batch_tick() -> void:
	if _run_index >= _runs_total:
		_finish_wave()
		return
	if GameManager.ecs.game_state.get("game_over", false):
		if _single_wave_only:
			_emit_batch_row(true)
			_run_index += 1
			if _run_index >= _runs_total:
				_finish_wave()
				return
			_start_next_batch_run()
		else:
			GameManager.log_snapshot_on_game_over()
			print("[Headless] Game over. Wave: %d. Exiting." % GameManager.ecs.game_state.get("current_wave", 0))
			_all_done()
		return
	if _start_wave_pending:
		_start_wave_pending = false
		if GameManager.phase_controller:
			GameManager.phase_controller.transition_to_wave()
		return
	var phase = GameManager.ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	if _single_wave_only and phase == GameTypes.GamePhase.BUILD_STATE and _single_wave_phase_was_wave:
		_emit_batch_row(false)
		_run_index += 1
		if _run_index >= _runs_total:
			_finish_wave()
			return
		_start_next_batch_run()
		return
	if not _single_wave_only and phase == GameTypes.GamePhase.BUILD_STATE:
		if GameManager.phase_controller:
			GameManager.phase_controller.transition_to_wave()
		return
	if phase == GameTypes.GamePhase.WAVE_STATE:
		_single_wave_phase_was_wave = true
	var scaled_dt = minf(HEADLESS_DT, Config.MAX_DELTA_TIME) * GameManager.ecs.game_state.get("time_speed", 1.0)
	if phase == GameTypes.GamePhase.WAVE_STATE:
		GameManager.ecs.game_state["wave_game_time"] = GameManager.ecs.game_state.get("wave_game_time", 0.0) + scaled_dt
	input_system.update(HEADLESS_DT)
	wave_system.update(scaled_dt)
	movement_system.update(scaled_dt)
	status_effect_system.update(scaled_dt)
	aura_system.update()
	combat_system.update(scaled_dt)
	volcano_system.update(scaled_dt)
	beacon_system.update(scaled_dt)
	auriga_system.update(scaled_dt)
	battery_system.update(scaled_dt)
	projectile_system.update(scaled_dt)

# ---------------------------------------------------------------------------
# CSV and batch result tracking
# ---------------------------------------------------------------------------

func _emit_batch_row(game_over: bool) -> void:
	var wa = GameManager.ecs.game_state.get("wave_analytics", {})
	var success = not game_over and wa.get("passed", 0) == 0
	var enemy_id = str(wa.get("enemy_def_id", ""))
	var line = "%d,%d,%d,%s,%d,%d,%d,%d,%.3f,%s,%s,%d,%d,%d,%d,%.1f,%s,%d,%d,%.2f,%d,%d" % [
		_run_index,
		_base_seed + _run_index,
		wa.get("wave_number", _wave_number),
		enemy_id,
		wa.get("spawned", 0),
		wa.get("killed", 0),
		wa.get("passed", 0),
		int(wa.get("total_hp", 0)),
		float(wa.get("duration_sec", 0.0)),
		"1" if success else "0",
		"1" if game_over else "0",
		int(wa.get("success_level_before", 10)),
		int(wa.get("success_level_after", 10)),
		int(wa.get("player_hp_before", 100)),
		int(wa.get("player_hp_after", 100)),
		float(wa.get("ore_spent", 0.0)),
		str(wa.get("enemy_abilities", "")),
		int(wa.get("enemy_base_speed", 80)),
		int(wa.get("enemy_base_hp", 100)),
		float(wa.get("enemy_regen_base", 0.0)),
		int(wa.get("enemy_flying", 0)),
		int(wa.get("source_wave", wa.get("wave_number", _wave_number))),
	]
	_csv_lines.append(line)

func _finish_wave() -> void:
	_write_csv_for_current_wave()
	if _wave_number >= _wave_max:
		_all_done()
		return
	_wave_number += 1
	_run_index = 0
	_csv_lines.clear()
	_csv_lines.append(_csv_header())
	_load_snapshot_for_wave(_wave_number)
	_start_next_batch_run()

func _write_csv_for_current_wave() -> void:
	var out_path = _csv_path
	if out_path.is_empty():
		var base_dir = _csv_output_dir if not _csv_output_dir.is_empty() else Config.get_project_snapshots_dir()
		base_dir = base_dir.replace("\\", "/")
		out_path = base_dir.path_join("wave_%d.csv" % _wave_number)
	out_path = out_path.replace("\\", "/")
	var dir_path = out_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var file = FileAccess.open(out_path, FileAccess.WRITE)
	if file:
		for line in _csv_lines:
			file.store_line(line)
		file.close()
		print("[Headless] Wave %d: %d runs -> %s" % [_wave_number, _csv_lines.size() - 1, out_path])
	else:
		print("[Headless] FAILED to write %s (error %s)" % [out_path, FileAccess.get_open_error()])

func _all_done() -> void:
	_finished = true
	var base_dir = _csv_output_dir if not _csv_output_dir.is_empty() else Config.get_project_snapshots_dir()
	base_dir = base_dir.replace("\\", "/")
	var marker = base_dir.path_join("batch_done.txt")
	var f = FileAccess.open(marker, FileAccess.WRITE)
	if f:
		f.store_string("done\n")
		f.close()
	print("[Headless] All done. Waves %d-%d, %d runs each." % [_wave_start, _wave_max, _runs_total])
	get_tree().quit()

# ---------------------------------------------------------------------------
# Single-run mode (no batch)
# ---------------------------------------------------------------------------

func _process_single(delta: float) -> void:
	if GameManager.ecs.game_state.get("game_over", false):
		GameManager.log_snapshot_on_game_over()
		print("[Headless] Game over. Wave: %d. Exiting." % GameManager.ecs.game_state.get("current_wave", 0))
		get_tree().quit()
		return
	if _start_wave_pending:
		_start_wave_pending = false
		if GameManager.phase_controller:
			GameManager.phase_controller.transition_to_wave()
		return
	var phase = GameManager.ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE)
	if phase == GameTypes.GamePhase.BUILD_STATE:
		if GameManager.phase_controller:
			GameManager.phase_controller.transition_to_wave()
		return
	var scaled_delta = minf(delta, Config.MAX_DELTA_TIME) * GameManager.ecs.game_state.get("time_speed", 1.0)
	if phase == GameTypes.GamePhase.WAVE_STATE:
		GameManager.ecs.game_state["wave_game_time"] = GameManager.ecs.game_state.get("wave_game_time", 0.0) + scaled_delta
	input_system.update(delta)
	wave_system.update(scaled_delta)
	movement_system.update(scaled_delta)
	status_effect_system.update(scaled_delta)
	aura_system.update()
	combat_system.update(scaled_delta)
	volcano_system.update(scaled_delta)
	beacon_system.update(scaled_delta)
	auriga_system.update(scaled_delta)
	battery_system.update(scaled_delta)
	projectile_system.update(scaled_delta)

# profiler.gd
# Простой профайлер для отслеживания производительности
extends Node

var enabled: bool = false
var timings: Dictionary = {}  # function_name -> Array[times]
var current_frames: Dictionary = {}  # function_name -> start_time
var frame_count: int = 0
var display_interval: int = 60  # Обновлять каждые 60 кадров

# ============================================================================
# API
# ============================================================================

func start(function_name: String):
	if not enabled:
		return
	current_frames[function_name] = Time.get_ticks_usec()

func end(function_name: String):
	if not enabled:
		return
	
	if not function_name in current_frames:
		return
	
	var start_time = current_frames[function_name]
	var elapsed = Time.get_ticks_usec() - start_time
	
	if not function_name in timings:
		timings[function_name] = []
	
	timings[function_name].append(elapsed)
	current_frames.erase(function_name)

# Обновление каждый кадр
func _process(_delta):
	if not enabled:
		return
	
	frame_count += 1
	
	# Каждые N кадров чистим старые данные
	if frame_count % display_interval == 0:
		_cleanup_old_data()

func _cleanup_old_data():
	# Оставляем только последние 60 замеров для каждой функции
	for func_name in timings.keys():
		var times = timings[func_name]
		if times.size() > 60:
			timings[func_name] = times.slice(-60)

# ============================================================================
# ПОЛУЧЕНИЕ СТАТИСТИКИ
# ============================================================================

func get_stats() -> Dictionary:
	var stats = {}
	
	for func_name in timings.keys():
		var times = timings[func_name]
		if times.size() == 0:
			continue
		
		var total = 0.0
		var max_time = 0
		var min_time = 999999999
		
		for t in times:
			total += t
			if t > max_time:
				max_time = t
			if t < min_time:
				min_time = t
		
		var avg = total / times.size()
		
		stats[func_name] = {
			"avg_us": avg,
			"avg_ms": avg / 1000.0,
			"min_us": min_time,
			"max_us": max_time,
			"calls": times.size()
		}
	
	return stats

func get_formatted_stats() -> String:
	var stats = get_stats()
	var lines = []
	
	# Сортируем по среднему времени (самые медленные сверху)
	var sorted_funcs = stats.keys()
	sorted_funcs.sort_custom(func(a, b): return stats[a]["avg_us"] > stats[b]["avg_us"])
	
	for func_name in sorted_funcs:
		var s = stats[func_name]
		var line = "%s: %.2f ms (min: %.2f, max: %.2f)" % [
			func_name,
			s["avg_ms"],
			s["min_us"] / 1000.0,
			s["max_us"] / 1000.0
		]
		lines.append(line)
	
	return "\n".join(lines)

func clear():
	timings.clear()
	current_frames.clear()
	frame_count = 0

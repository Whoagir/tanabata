# pathfinding.gd
# A* pathfinding для гексагональной карты
class_name Pathfinding

# Направления соседей (pointy-top hex) — инлайн для A* без аллокаций Hex
const _DIR_Q: Array[int] = [1, 1, 0, -1, -1, 0]
const _DIR_R: Array[int] = [0, -1, -1, 0, 1, 1]

# Инлайн hex distance по q,r (без создания Hex объекта)
static func _hex_dist(q1: int, r1: int, q2: int, r2: int) -> int:
	var dq = q1 - q2
	var dr = r1 - r2
	var ds = dq + dr  # s = -q - r, so ds = -(dq + dr) → abs(ds) = abs(dq + dr)
	return (abs(dq) + abs(dr) + abs(ds)) / 2

# ============================================================================
# A* — оптимизированная версия
# ============================================================================

# A* алгоритм: int ключи для внутренних Dictionary, инлайн-соседи, без лишних аллокаций.
static func find_path(start: Hex, goal: Hex, hex_map: HexMap, ignore_passable: bool = false) -> Array[Hex]:
	if not hex_map.has_tile(start) or not hex_map.has_tile(goal):
		return []
	
	if not ignore_passable:
		var goal_tile = hex_map.get_tile(goal)
		if not goal_tile or not goal_tile.passable:
			return []
	
	var sq = start.q
	var sr = start.r
	var gq = goal.q
	var gr = goal.r
	var start_key = Hex.int_key_from_qr(sq, sr)
	var goal_key = Hex.int_key_from_qr(gq, gr)
	
	if start_key == goal_key:
		return [start]
	
	var frontier: Array = []  # min-heap: [f, q, r]
	var closed: Dictionary = {}  # int_key -> true
	var came_from: Dictionary = {}  # int_key -> [parent_q, parent_r] or null
	var cost_so_far: Dictionary = {}  # int_key -> int
	
	came_from[start_key] = null
	cost_so_far[start_key] = 0
	_heap_push_qr(frontier, _hex_dist(sq, sr, gq, gr), sq, sr)
	
	while frontier.size() > 0:
		var item = _heap_pop_min_qr(frontier)
		var cq: int = item[1]
		var cr: int = item[2]
		var current_key = Hex.int_key_from_qr(cq, cr)
		
		if current_key in closed:
			continue
		closed[current_key] = true
		
		if cq == gq and cr == gr:
			return _reconstruct_path_int(came_from, start_key, sq, sr, goal_key, gq, gr)
		
		var current_cost: int = cost_so_far[current_key]
		
		for d in range(6):
			var nq = cq + _DIR_Q[d]
			var nr = cr + _DIR_R[d]
			
			if ignore_passable:
				if not hex_map.has_tile_qr(nq, nr):
					continue
			else:
				if not hex_map.is_passable_qr(nq, nr):
					continue
			
			var new_cost = current_cost + 1
			var neighbor_key = Hex.int_key_from_qr(nq, nr)
			
			if not neighbor_key in cost_so_far or new_cost < cost_so_far[neighbor_key]:
				cost_so_far[neighbor_key] = new_cost
				came_from[neighbor_key] = [cq, cr]
				var f = new_cost + _hex_dist(nq, nr, gq, gr)
				_heap_push_qr(frontier, f, nq, nr)
	
	return []

# ============================================================================
# path_exists — быстрая проверка существования пути (без реконструкции)
# ============================================================================

static func path_exists(start: Hex, goal: Hex, hex_map: HexMap, ignore_passable: bool = false) -> bool:
	if not hex_map.has_tile(start) or not hex_map.has_tile(goal):
		return false
	
	if not ignore_passable:
		var goal_tile = hex_map.get_tile(goal)
		if not goal_tile or not goal_tile.passable:
			return false
	
	var sq = start.q
	var sr = start.r
	var gq = goal.q
	var gr = goal.r
	
	if sq == gq and sr == gr:
		return true
	
	var frontier: Array = []
	var closed: Dictionary = {}
	var cost_so_far: Dictionary = {}
	var start_key = Hex.int_key_from_qr(sq, sr)
	
	cost_so_far[start_key] = 0
	_heap_push_qr(frontier, _hex_dist(sq, sr, gq, gr), sq, sr)
	
	while frontier.size() > 0:
		var item = _heap_pop_min_qr(frontier)
		var cq: int = item[1]
		var cr: int = item[2]
		var current_key = Hex.int_key_from_qr(cq, cr)
		
		if current_key in closed:
			continue
		closed[current_key] = true
		
		if cq == gq and cr == gr:
			return true
		
		var current_cost: int = cost_so_far[current_key]
		
		for d in range(6):
			var nq = cq + _DIR_Q[d]
			var nr = cr + _DIR_R[d]
			
			if ignore_passable:
				if not hex_map.has_tile_qr(nq, nr):
					continue
			else:
				if not hex_map.is_passable_qr(nq, nr):
					continue
			
			var new_cost = current_cost + 1
			var neighbor_key = Hex.int_key_from_qr(nq, nr)
			
			if not neighbor_key in cost_so_far or new_cost < cost_so_far[neighbor_key]:
				cost_so_far[neighbor_key] = new_cost
				var f = new_cost + _hex_dist(nq, nr, gq, gr)
				_heap_push_qr(frontier, f, nq, nr)
	
	return false

# Проверка существования пути через чекпоинты (без построения массива пути)
static func path_exists_through_checkpoints(start: Hex, checkpoints: Array[Hex], goal: Hex, hex_map: HexMap, ignore_passable: bool = false) -> bool:
	var current = start
	for checkpoint in checkpoints:
		if not path_exists(current, checkpoint, hex_map, ignore_passable):
			return false
		current = checkpoint
	return path_exists(current, goal, hex_map, ignore_passable)

# ============================================================================
# find_path_through_checkpoints — строит полный путь
# ============================================================================

static func find_path_through_checkpoints(start: Hex, checkpoints: Array[Hex], goal: Hex, hex_map: HexMap, ignore_passable: bool = false) -> Array[Hex]:
	var full_path: Array[Hex] = []
	var current = start
	
	for checkpoint in checkpoints:
		var segment = find_path(current, checkpoint, hex_map, ignore_passable)
		if segment.size() == 0:
			print("[Pathfinding] FAILED: No path from %s to %s" % [current, checkpoint])
			return []
		
		for i in range(1, segment.size()):
			full_path.append(segment[i])
		current = checkpoint
	
	var final_segment = find_path(current, goal, hex_map, ignore_passable)
	if final_segment.size() == 0:
		return []
	
	for i in range(1, final_segment.size()):
		full_path.append(final_segment[i])
	
	return full_path

# ============================================================================
# Min-heap (хранит [f, q, r] вместо [f, Hex] — без аллокации Hex)
# ============================================================================

static func _heap_push_qr(heap: Array, f: int, q: int, r: int) -> void:
	heap.append([f, q, r])
	var i = heap.size() - 1
	while i > 0:
		var parent_idx = (i - 1) / 2
		if heap[i][0] >= heap[parent_idx][0]:
			break
		var tmp = heap[i]
		heap[i] = heap[parent_idx]
		heap[parent_idx] = tmp
		i = parent_idx

static func _heap_pop_min_qr(heap: Array) -> Array:
	var result = heap[0]
	var last_idx = heap.size() - 1
	if last_idx == 0:
		heap.clear()
		return result
	heap[0] = heap[last_idx]
	heap.resize(last_idx)
	var i = 0
	var n = heap.size()
	while true:
		var left = 2 * i + 1
		var right = 2 * i + 2
		var smallest = i
		if left < n and heap[left][0] < heap[smallest][0]:
			smallest = left
		if right < n and heap[right][0] < heap[smallest][0]:
			smallest = right
		if smallest == i:
			break
		var tmp = heap[i]
		heap[i] = heap[smallest]
		heap[smallest] = tmp
		i = smallest
	return result

# ============================================================================
# Реконструкция пути из int-ключей
# ============================================================================

static func _reconstruct_path_int(came_from: Dictionary, start_key: int, sq: int, sr: int, goal_key: int, gq: int, gr: int) -> Array[Hex]:
	var path: Array[Hex] = []
	var cq = gq
	var cr = gr
	var current_key = goal_key
	
	while true:
		path.append(Hex.new(cq, cr))
		if current_key == start_key:
			break
		if not came_from.has(current_key):
			break
		var parent = came_from[current_key]
		if parent == null:
			break
		cq = parent[0]
		cr = parent[1]
		current_key = Hex.int_key_from_qr(cq, cr)
	
	path.reverse()
	return path

# ============================================================================
# Legacy heap (сохраняем для совместимости если используется где-то ещё)
# ============================================================================

static func _heap_push(heap: Array, f: float, hex: Hex) -> void:
	heap.append([f, hex])
	var i = heap.size() - 1
	while i > 0:
		var parent_idx = (i - 1) / 2
		if heap[i][0] >= heap[parent_idx][0]:
			break
		var tmp = heap[i]
		heap[i] = heap[parent_idx]
		heap[parent_idx] = tmp
		i = parent_idx

static func _heap_pop_min(heap: Array):
	if heap.is_empty():
		return null
	var result = heap[0]
	if heap.size() == 1:
		heap.clear()
		return result
	heap[0] = heap.pop_back()
	var i = 0
	var n = heap.size()
	while true:
		var left = 2 * i + 1
		var right = 2 * i + 2
		var smallest = i
		if left < n and heap[left][0] < heap[smallest][0]:
			smallest = left
		if right < n and heap[right][0] < heap[smallest][0]:
			smallest = right
		if smallest == i:
			break
		var tmp = heap[i]
		heap[i] = heap[smallest]
		heap[smallest] = tmp
		i = smallest
	return result

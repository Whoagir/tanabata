# energy_network_system.gd
# Система энергосети - управление соединениями между башнями
# Портирована из Go версии (energy_network.go)
class_name EnergyNetworkSystem

var ecs: ECSWorld
var hex_map: HexMap

# Кэш: tower_id -> массив ore_id в этой сети (инвалидируется при изменении графа)
var _network_ore_ids_cache: Dictionary = {}

# Предвычисленный набор гексов на энерголиниях (для env damage в movement_system)
var line_hex_set: Dictionary = {}  # hex_key -> true


# EnergyEdge - потенциальное соединение между башнями
class EnergyEdge:
	var tower1_id: int
	var tower2_id: int
	var type1: String  # "MINER", "ATTACK", "WALL"
	var type2: String
	var distance: float
	
	func _init(t1: int, t2: int, typ1: String, typ2: String, dist: float):
		tower1_id = t1
		tower2_id = t2
		type1 = typ1
		type2 = typ2
		distance = dist

func _init(ecs_: ECSWorld, hex_map_: HexMap):
	ecs = ecs_
	hex_map = hex_map_

# ============================================================================
# ПРИОРИТЕТЫ И СОРТИРОВКА
# ============================================================================

# Вычислить вес ребра (чем меньше, тем выше приоритет)
static func calculate_edge_weight(type1: String, type2: String, distance: float) -> float:
	var is_t1_miner = (type1 == "MINER")
	var is_t2_miner = (type2 == "MINER")
	
	# Майнер-Майнер: высший приоритет
	if is_t1_miner and is_t2_miner:
		return 100.0 + distance
	# Майнер-Атакер: средний приоритет
	if is_t1_miner or is_t2_miner:
		return 200.0 + distance
	# Атакер-Атакер: низший приоритет
	return 300.0 + distance

# Сортировка рёбер по приоритету (детерминированная)
static func sort_energy_edges(edges: Array) -> void:
	edges.sort_custom(func(a: EnergyEdge, b: EnergyEdge) -> bool:
		var weight_a = calculate_edge_weight(a.type1, a.type2, a.distance)
		var weight_b = calculate_edge_weight(b.type1, b.type2, b.distance)
		
		if weight_a != weight_b:
			return weight_a < weight_b
		
		# Tie-breaking: сортируем по ID для детерминизма
		var min_a = min(a.tower1_id, a.tower2_id)
		var max_a = max(a.tower1_id, a.tower2_id)
		var min_b = min(b.tower1_id, b.tower2_id)
		var max_b = max(b.tower1_id, b.tower2_id)
		
		if min_a != min_b:
			return min_a < min_b
		return max_a < max_b
	)

# ============================================================================
# ДОБАВЛЕНИЕ БАШНИ (ИНКРЕМЕНТАЛЬНОЕ)
# ============================================================================

# Добавить башню в энергосеть (вызывается при постановке башни)
func add_tower_to_network(new_tower_id: int) -> void:
	_network_ore_ids_cache.clear()
	if not ecs.towers.has(new_tower_id):
		return
	
	var new_tower = ecs.towers[new_tower_id]
	var tower_def_id = new_tower.get("def_id", "")
	var tower_def = DataRepository.get_tower_def(tower_def_id)
	
	if not tower_def or tower_def.get("type") == "WALL":
		return  # Стены не участвуют в сети
	
	var tower_type = tower_def.get("type", "ATTACK")
	
	if tower_type == "MINER":
		if _handle_miner_intercept(new_tower_id, new_tower):
			_expand_network_from(new_tower_id)
			rebuild_line_hex_set()
			return
	
	# 1. Найти возможные соединения с активными башнями
	var connections = _find_possible_connections(new_tower_id, new_tower)
	
	# 2. Проверить: может ли башня быть активной (майнер на руде = корень)
	var is_new_root = tower_type == "MINER" and _is_on_ore(new_tower.get("hex"))
	
	if connections.size() == 0 and not is_new_root:
		# Нет соединений и НЕ на руде → НЕАКТИВНА
		new_tower["is_active"] = false
		_update_tower_appearance(new_tower_id)
		return
	
	# 3. Активировать башню (либо на руде, либо есть соединения)
	new_tower["is_active"] = true
	_update_tower_appearance(new_tower_id)
	
	if connections.size() > 0:
		_connect_to_networks(new_tower_id, connections)
	
	_expand_network_from(new_tower_id)
	rebuild_line_hex_set()

# Перехват майнер-майнер линии (новый майнер встал на линию между двумя майнерами)
func _handle_miner_intercept(new_tower_id: int, new_tower: Dictionary) -> bool:
	var new_hex = new_tower.get("hex")
	var tower_def_id = new_tower.get("def_id", "")
	var tower_def = DataRepository.get_tower_def(tower_def_id)
	var new_type = tower_def.get("type", "ATTACK")
	
	for line_id in ecs.energy_lines.keys():
		var line = ecs.energy_lines[line_id]
		var t1 = ecs.towers.get(line.get("tower1_id"))
		var t2 = ecs.towers.get(line.get("tower2_id"))
		
		if not t1 or not t2:
			continue
		
		var def1 = DataRepository.get_tower_def(t1.get("def_id", ""))
		var def2 = DataRepository.get_tower_def(t2.get("def_id", ""))
		
		if not def1 or not def2:
			continue
		
		if def1.get("type") != "MINER" or def2.get("type") != "MINER":
			continue
		
		var hex1 = t1.get("hex")
		var hex2 = t2.get("hex")
		var dist12 = hex1.distance_to(hex2)
		var dist1_new = hex1.distance_to(new_hex)
		var dist_new2 = new_hex.distance_to(hex2)
		
		# Проверка перехвата: новый майнер на прямой между t1 и t2
		if dist1_new > 0 and dist_new2 > 0 and dist1_new + dist_new2 == dist12:
			# Перехват найден! Удаляем старую линию, создаём 2 новые
			ecs.destroy_entity(line_id)
			
			new_tower["is_active"] = true
			_update_tower_appearance(new_tower_id)
			
			# Создаём 2 новые линии
			_create_line(EnergyEdge.new(
				line.get("tower1_id"), new_tower_id,
				def1.get("type"), new_type,
				float(dist1_new)
			))
			_create_line(EnergyEdge.new(
				new_tower_id, line.get("tower2_id"),
				new_type, def2.get("type"),
				float(dist_new2)
			))
			return true
	
	return false

# Найти возможные соединения с активными башнями
func _find_possible_connections(new_tower_id: int, new_tower: Dictionary) -> Array:
	var connections: Array = []
	var new_hex = new_tower.get("hex")
	var new_def = DataRepository.get_tower_def(new_tower.get("def_id", ""))
	if not new_def:
		return connections
	
	var new_type = new_def.get("type", "ATTACK")
	
	for other_id in ecs.towers.keys():
		if other_id == new_tower_id:
			continue
		
		var other_tower = ecs.towers[other_id]
		if not other_tower.get("is_active", false):
			continue  # Только с активными башнями
		
		var other_def = DataRepository.get_tower_def(other_tower.get("def_id", ""))
		if not other_def:
			continue
		
		var other_type = other_def.get("type", "ATTACK")
		var other_hex = other_tower.get("hex")
		var distance = new_hex.distance_to(other_hex)
		
		# Правила соединения
		var is_neighbor = (distance == 1)
		var is_miner_connection = (
			new_type == "MINER" and 
			other_type == "MINER" and
			distance <= Config.ENERGY_TRANSFER_RADIUS and
			new_hex.is_on_same_line(other_hex)
		)
		
		if is_neighbor or is_miner_connection:
			connections.append(EnergyEdge.new(
				new_tower_id, other_id,
				new_type, other_type,
				float(distance)
			))
	
	sort_energy_edges(connections)
	return connections

# Подключиться к сетям (с предотвращением циклов)
func _connect_to_networks(tower_id: int, connections: Array) -> void:
	# Строим Union-Find для определения компонент
	var uf = UnionFind.new()
	for id in ecs.towers.keys():
		uf.find(id)
	
	for line in ecs.energy_lines.values():
		uf.union(line.get("tower1_id"), line.get("tower2_id"))
	
	var adj = _build_adjacency_list()
	var connection_made = false
	
	for edge in connections:
		var neighbor_id = edge.tower2_id
		
		# Предотвращение циклов: соединяем только если в разных компонентах
		if uf.find(tower_id) != uf.find(neighbor_id):
			# Эстетическая проверка: избегаем треугольников
			if not _forms_triangle(tower_id, neighbor_id, adj):
				_create_line(edge)
				uf.union(tower_id, neighbor_id)
				connection_made = true
				
				# Обновляем adj для последующих проверок
				if not adj.has(tower_id):
					adj[tower_id] = []
				if not adj.has(neighbor_id):
					adj[neighbor_id] = []
				adj[tower_id].append(neighbor_id)
				adj[neighbor_id].append(tower_id)
	
	# Fallback: если все соединения создают треугольники, делаем лучшее
	if not connection_made:
		for edge in connections:
			var neighbor_id = edge.tower2_id
			if uf.find(tower_id) != uf.find(neighbor_id):
				_create_line(edge)
				break

# Расширить сеть от башни (BFS)
func _expand_network_from(start_node: int) -> void:
	var queue = [start_node]
	var visited = {start_node: true}
	var adj = _build_adjacency_list()
	
	while queue.size() > 0:
		var current_id = queue.pop_front()
		var current_tower = ecs.towers.get(current_id)
		if not current_tower:
			continue
		
		var current_def = DataRepository.get_tower_def(current_tower.get("def_id", ""))
		if not current_def:
			continue
		
		var current_type = current_def.get("type", "ATTACK")
		var current_hex = current_tower.get("hex")
		
		# Ищем неактивных соседей
		for other_id in ecs.towers.keys():
			if visited.get(other_id, false):
				continue
			
			var other_tower = ecs.towers[other_id]
			if other_tower.get("is_active", false):
				continue
			
			var other_def = DataRepository.get_tower_def(other_tower.get("def_id", ""))
			if not other_def or other_def.get("type") == "WALL":
				continue
			
			var other_type = other_def.get("type", "ATTACK")
			var other_hex = other_tower.get("hex")
			var distance = current_hex.distance_to(other_hex)
			
			var is_neighbor = (distance == 1)
			var is_miner_connection = (
				current_type == "MINER" and
				other_type == "MINER" and
				distance <= Config.ENERGY_TRANSFER_RADIUS and
				current_hex.is_on_same_line(other_hex)
			)
			
			if is_neighbor or is_miner_connection:
				if not _forms_triangle(current_id, other_id, adj):
					# Активируем соседа
					other_tower["is_active"] = true
					_update_tower_appearance(other_id)
					
					# Создаём линию
					var edge = EnergyEdge.new(
						current_id, other_id,
						current_type, other_type,
						float(distance)
					)
					_create_line(edge)
					
					# Обновляем adj
					if not adj.has(current_id):
						adj[current_id] = []
					if not adj.has(other_id):
						adj[other_id] = []
					adj[current_id].append(other_id)
					adj[other_id].append(current_id)
					
					visited[other_id] = true
					queue.append(other_id)

# ============================================================================
# УДАЛЕНИЕ ЛИНИЙ К УДАЛЯЕМОЙ БАШНЕ
# ============================================================================

# Удалить все линии, подключённые к башне (вызывать ДО destroy_entity)
func remove_lines_connected_to_tower(tower_id: int) -> void:
	_network_ore_ids_cache.clear()
	var to_remove = []
	for line_id in ecs.energy_lines.keys():
		var line = ecs.energy_lines[line_id]
		if line.get("tower1_id") == tower_id or line.get("tower2_id") == tower_id:
			to_remove.append(line_id)
	for line_id in to_remove:
		ecs.destroy_entity(line_id)

# ============================================================================
# ИНКРЕМЕНТАЛЬНОЕ УДАЛЕНИЕ БАШНИ (сохраняет линии из режима U)
# ============================================================================

# Переподключить сеть после удаления башни (как handleTowerRemoval в Go).
# Сохраняет существующие линии и добавляет только недостающие "мосты".
func handle_tower_removal() -> void:
	_network_ore_ids_cache.clear()
	# 1. Определить какие башни питаются от источника
	var powered = _find_powered_towers_with_adj(_build_adjacency_list())
	for id in ecs.towers.keys():
		var tower = ecs.towers[id]
		var def = DataRepository.get_tower_def(tower.get("def_id", ""))
		if def and def.get("type") == "WALL":
			continue
		tower["is_active"] = powered.get(id, false)
	
	# 2. Объединить разъединённые активные компоненты (mergeActiveNetworks)
	_merge_active_networks()
	
	# 3. Итеративно подключать неактивные компоненты (добавлять по одному мосту)
	while true:
		var bridges = _find_all_possible_bridges()
		if bridges.is_empty():
			break
		
		var uf = UnionFind.new()
		for id in ecs.towers.keys():
			uf.find(id)
		for line in ecs.energy_lines.values():
			var t1 = line.get("tower1_id")
			var t2 = line.get("tower2_id")
			if ecs.towers.has(t1) and ecs.towers.has(t2):
				uf.union(t1, t2)
		
		var bridge_built = false
		for bridge in bridges:
			if uf.find(bridge.tower1_id) != uf.find(bridge.tower2_id):
				_create_line(bridge)
				bridge_built = true
				break
		
		if not bridge_built:
			break
		
		# Пересчитать питание после нового соединения
		powered = _find_powered_towers_with_adj(_build_adjacency_list())
		for id in ecs.towers.keys():
			var tower = ecs.towers[id]
			var def = DataRepository.get_tower_def(tower.get("def_id", ""))
			if def and def.get("type") == "WALL":
				continue
			tower["is_active"] = powered.get(id, false)
	
	# 4. Удалить линии к неактивным башням
	var to_remove = []
	for line_id in ecs.energy_lines.keys():
		var line = ecs.energy_lines[line_id]
		var t1 = ecs.towers.get(line.get("tower1_id"))
		var t2 = ecs.towers.get(line.get("tower2_id"))
		if not t1 or not t2 or not t1.get("is_active", false) or not t2.get("is_active", false):
			to_remove.append(line_id)
	for line_id in to_remove:
		ecs.destroy_entity(line_id)
	
	for id in ecs.towers.keys():
		_update_tower_appearance(id)
	
	rebuild_line_hex_set()
	if GameManager.combat_system:
		GameManager.combat_system.clear_power_cache()

func _merge_active_networks() -> void:
	var active_towers = {}
	for id in ecs.towers.keys():
		var tower = ecs.towers[id]
		if tower.get("is_active", false):
			active_towers[id] = tower
	
	if active_towers.size() <= 1:
		return
	
	var uf = UnionFind.new()
	for id in active_towers.keys():
		uf.find(id)
	for line in ecs.energy_lines.values():
		var t1 = line.get("tower1_id")
		var t2 = line.get("tower2_id")
		if active_towers.has(t1) and active_towers.has(t2):
			uf.union(t1, t2)
	
	var active_ids = active_towers.keys()
	var bridge_edges: Array = []
	for i in range(active_ids.size()):
		for j in range(i + 1, active_ids.size()):
			var id1 = active_ids[i]
			var id2 = active_ids[j]
			if uf.find(id1) == uf.find(id2):
				continue
			var t1 = active_towers[id1]
			var t2 = active_towers[id2]
			if _is_valid_connection(t1, t2):
				var def1 = DataRepository.get_tower_def(t1.get("def_id", ""))
				var def2 = DataRepository.get_tower_def(t2.get("def_id", ""))
				var dist = t1.get("hex").distance_to(t2.get("hex"))
				bridge_edges.append(EnergyEdge.new(
					id1, id2,
					def1.get("type", "ATTACK"), def2.get("type", "ATTACK"),
					float(dist)
				))
	
	sort_energy_edges(bridge_edges)
	for edge in bridge_edges:
		if uf.find(edge.tower1_id) != uf.find(edge.tower2_id):
			_create_line(edge)
			uf.union(edge.tower1_id, edge.tower2_id)

func _find_all_possible_bridges() -> Array:
	var active_ids = []
	var inactive_ids = []
	for id in ecs.towers.keys():
		var tower = ecs.towers[id]
		var def = DataRepository.get_tower_def(tower.get("def_id", ""))
		if not def or def.get("type") == "WALL":
			continue
		if tower.get("is_active", false):
			active_ids.append(id)
		else:
			inactive_ids.append(id)
	
	if active_ids.is_empty() or inactive_ids.is_empty():
		return []
	
	var bridges: Array = []
	for active_id in active_ids:
		var active_tower = ecs.towers[active_id]
		var active_def = DataRepository.get_tower_def(active_tower.get("def_id", ""))
		for inactive_id in inactive_ids:
			var inactive_tower = ecs.towers[inactive_id]
			var inactive_def = DataRepository.get_tower_def(inactive_tower.get("def_id", ""))
			if _is_valid_connection(active_tower, inactive_tower):
				var dist = active_tower.get("hex").distance_to(inactive_tower.get("hex"))
				bridges.append(EnergyEdge.new(
					active_id, inactive_id,
					active_def.get("type", "ATTACK"), inactive_def.get("type", "ATTACK"),
					float(dist)
				))
	
	sort_energy_edges(bridges)
	return bridges

# ============================================================================
# УДАЛЕНИЕ БАШНИ (ПОЛНЫЙ REBUILD)
# ============================================================================

# Удалить башню из сети (полная перестройка) - используется при FinalizeTowerSelection и т.п.
func rebuild_energy_network() -> void:
	_network_ore_ids_cache.clear()
	var all_towers = _collect_and_reset_towers()
	if all_towers.size() == 0:
		_clear_all_lines()
		return
	
	var potentially_active = _get_potentially_active_towers(all_towers)
	var possible_edges = _collect_possible_edges(all_towers, potentially_active)
	
	var result = _build_minimum_spanning_tree(possible_edges, potentially_active)
	var uf = result["uf"]
	var mst_edges = result["edges"]
	
	_activate_network_towers(all_towers, potentially_active, uf)
	_update_tower_appearances(all_towers)
	_rebuild_energy_lines(mst_edges)
	rebuild_line_hex_set()
	if GameManager.combat_system:
		GameManager.combat_system.clear_power_cache()

func _collect_and_reset_towers() -> Dictionary:
	var all_towers = {}
	for id in ecs.towers.keys():
		var tower = ecs.towers[id]
		var hex = tower.get("hex")
		all_towers[hex.to_key()] = id
		tower["is_active"] = false  # Сброс
	return all_towers

func _get_potentially_active_towers(all_towers: Dictionary) -> Dictionary:
	var potentially_active = {}
	for id in all_towers.values():
		var tower = ecs.towers.get(id)
		if not tower:
			continue
		var def = DataRepository.get_tower_def(tower.get("def_id", ""))
		if def and def.get("type") != "WALL":
			potentially_active[id] = true
	return potentially_active

func _collect_possible_edges(all_towers: Dictionary, potentially_active: Dictionary) -> Array:
	var edges: Array = []
	var active_hexes: Array[Hex] = []
	
	for hex_key in all_towers.keys():
		var id = all_towers[hex_key]
		if potentially_active.has(id):
			active_hexes.append(Hex.from_key(hex_key))
	
	for i in range(active_hexes.size()):
		for j in range(i + 1, active_hexes.size()):
			var hex_a = active_hexes[i]
			var hex_b = active_hexes[j]
			var id_a = all_towers[hex_a.to_key()]
			var id_b = all_towers[hex_b.to_key()]
			
			var tower_a = ecs.towers[id_a]
			var tower_b = ecs.towers[id_b]
			var def_a = DataRepository.get_tower_def(tower_a.get("def_id", ""))
			var def_b = DataRepository.get_tower_def(tower_b.get("def_id", ""))
			
			if not def_a or not def_b:
				continue
			
			var distance = hex_a.distance_to(hex_b)
			var is_neighbor = (distance == 1)
			var is_miner_connection = (
				def_a.get("type") == "MINER" and
				def_b.get("type") == "MINER" and
				distance <= Config.ENERGY_TRANSFER_RADIUS and
				hex_a.is_on_same_line(hex_b) and
				not _has_active_tower_between(hex_a, hex_b, all_towers, potentially_active)
			)
			
			if is_neighbor or is_miner_connection:
				edges.append(EnergyEdge.new(
					id_a, id_b,
					def_a.get("type"), def_b.get("type"),
					float(distance)
				))
	
	return edges

func _has_active_tower_between(hex_a: Hex, hex_b: Hex, all_towers: Dictionary, potentially_active: Dictionary) -> bool:
	var line = hex_a.line_to(hex_b)
	for i in range(1, line.size() - 1):  # Без концов
		var hex_key = line[i].to_key()
		if all_towers.has(hex_key):
			var id = all_towers[hex_key]
			if potentially_active.has(id):
				var tower = ecs.towers.get(id)
				if tower:
					var def = DataRepository.get_tower_def(tower.get("def_id", ""))
					# Блокируется только другим майнером
					if def and def.get("type") == "MINER":
						return true
	return false

func _build_minimum_spanning_tree(edges: Array, potentially_active: Dictionary) -> Dictionary:
	sort_energy_edges(edges)
	
	var uf = UnionFind.new()
	for id in potentially_active.keys():
		uf.find(id)
	
	var mst_edges: Array = []
	for edge in edges:
		if uf.find(edge.tower1_id) != uf.find(edge.tower2_id):
			uf.union(edge.tower1_id, edge.tower2_id)
			mst_edges.append(edge)
	
	return {"uf": uf, "edges": mst_edges}

func _activate_network_towers(all_towers: Dictionary, potentially_active: Dictionary, uf: UnionFind) -> void:
	# Найти корни (майнеры на руде)
	var energy_source_roots = {}
	for hex_key in all_towers.keys():
		var id = all_towers[hex_key]
		var tower = ecs.towers.get(id)
		if not tower:
			continue
		var def = DataRepository.get_tower_def(tower.get("def_id", ""))
		if def and def.get("type") == "MINER":
			var hex = Hex.from_key(hex_key)
			if _is_on_ore(hex):
				energy_source_roots[uf.find(id)] = true
	
	# Активировать ТОЛЬКО башни, подключенные к корням
	var activated_count = 0
	for id in potentially_active.keys():
		if energy_source_roots.has(uf.find(id)):
			ecs.towers[id]["is_active"] = true
			activated_count += 1
		else:
			# КРИТИЧНО: если башня НЕ подключена к руде, она НЕАКТИВНА
			ecs.towers[id]["is_active"] = false

func _update_tower_appearances(all_towers: Dictionary) -> void:
	for id in all_towers.values():
		_update_tower_appearance(id)

func _rebuild_energy_lines(mst_edges: Array) -> void:
	_clear_all_lines()
	for edge in mst_edges:
		var tower1 = ecs.towers.get(edge.tower1_id)
		var tower2 = ecs.towers.get(edge.tower2_id)
		if tower1 and tower2 and tower1.get("is_active") and tower2.get("is_active"):
			_create_line(edge)

# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ============================================================================

func _forms_triangle(id1: int, id2: int, adj: Dictionary) -> bool:
	var neighbors1 = adj.get(id1, [])
	var neighbors2 = adj.get(id2, [])
	
	if neighbors1.size() == 0 or neighbors2.size() == 0:
		return false
	
	var set1 = {}
	for n in neighbors1:
		set1[n] = true
	
	for n2 in neighbors2:
		if set1.has(n2):
			return true  # Общий сосед = треугольник
	
	return false

func _build_adjacency_list() -> Dictionary:
	var adj = {}
	for line in ecs.energy_lines.values():
		var t1 = line.get("tower1_id")
		var t2 = line.get("tower2_id")
		
		# Проверяем что обе башни существуют
		if not ecs.towers.has(t1) or not ecs.towers.has(t2):
			continue
		
		if not adj.has(t1):
			adj[t1] = []
		if not adj.has(t2):
			adj[t2] = []
		
		adj[t1].append(t2)
		adj[t2].append(t1)
	
	return adj

func _is_on_ore(hex: Hex) -> bool:
	var ore_id = ecs.ore_hex_index.get(hex.to_key(), -1)
	if ore_id < 0:
		return false
	var ore = ecs.ores.get(ore_id)
	if not ore:
		return false
	return ore.get("current_reserve", 0.0) >= Config.ORE_DEPLETION_THRESHOLD

# Сколько руды восстанавливается за волну (на жилу с майнером этого уровня).
# 1) Все майнеры × ORE_RESTORE_GLOBAL_MULT (0.7 = −30%).
# 2) Прогресс по уровню игрока (по опыту): майнер уровня L восстанавливает 0..100% в зависимости от прогресса XP в уровне L.
#    Прогресс = current_xp / xp_to_next_level. Если player_level > L — майнер L уже на 100%.
func get_ore_restore_per_round(ore_id: int) -> float:
	var ore = ecs.ores.get(ore_id)
	if not ore:
		return 0.8 * Config.ORE_RESTORE_GLOBAL_MULT
	var ore_hex = ore.get("hex")
	if not ore_hex:
		return 0.8 * Config.ORE_RESTORE_GLOBAL_MULT
	# O(1) через hex_map вместо перебора всех towers
	var tid = hex_map.get_tower_id(ore_hex)
	if tid == GameTypes.INVALID_ENTITY_ID:
		return 0.8 * Config.ORE_RESTORE_GLOBAL_MULT
	var t = ecs.towers.get(tid)
	if not t:
		return 0.8 * Config.ORE_RESTORE_GLOBAL_MULT
	var def = DataRepository.get_tower_def(t.get("def_id", ""))
	if def.get("type") != "MINER":
		return 0.8 * Config.ORE_RESTORE_GLOBAL_MULT
	var miner_lv = clampi(t.get("level", 1), 1, 5)
	var base: float
	match miner_lv:
		1: base = 0.8
		2: base = 1.9
		3: base = 4.1
		4: base = 6.6
		5: base = 10.0
		_: base = 0.8
	var player_level = 1
	var current_xp = 0
	var xp_to_next = 100
	for pid in ecs.player_states.keys():
		var ps = ecs.player_states[pid]
		player_level = ps.get("level", 1)
		current_xp = ps.get("current_xp", 0)
		xp_to_next = ps.get("xp_to_next_level", 100)
		break
	var progress = 1.0
	if xp_to_next > 0:
		progress = clampf(float(current_xp) / float(xp_to_next), 0.0, 1.0)
	var level_mult = 1.0
	if player_level > miner_lv:
		level_mult = 1.0
	elif player_level == miner_lv:
		level_mult = progress
	return base * Config.ORE_RESTORE_GLOBAL_MULT * level_mult

# Эффективность добычи: майнер лвл 2+ даёт +30% (списываем на 30% меньше руды за выстрел)
func get_miner_efficiency_for_ore(ore_id: int) -> float:
	var ore = ecs.ores.get(ore_id)
	if not ore:
		return 1.0
	var ore_hex = ore.get("hex")
	if not ore_hex:
		return 1.0
	# O(1) через hex_map вместо перебора всех towers
	var tid = hex_map.get_tower_id(ore_hex)
	if tid == GameTypes.INVALID_ENTITY_ID:
		return 1.0
	var t = ecs.towers.get(tid)
	if not t:
		return 1.0
	var def = DataRepository.get_tower_def(t.get("def_id", ""))
	if def.get("type") != "MINER":
		return 1.0
	var lv = t.get("level", 1)
	if lv >= 3:
		return 2.5
	if lv >= 2:
		return 1.7
	return 1.0

func _create_line(edge: EnergyEdge) -> void:
	var line_id = ecs.create_entity()
	ecs.add_component(line_id, "energy_line", {
		"tower1_id": edge.tower1_id,
		"tower2_id": edge.tower2_id,
		"color": Config.COLOR_ENERGY_LINE,
		"is_hidden": false
	})

# Найти линию между двумя башнями (для Line Drag)
func get_line_between_towers(tower1_id: int, tower2_id: int) -> int:
	for line_id in ecs.energy_lines.keys():
		var line = ecs.energy_lines[line_id]
		var t1 = line.get("tower1_id")
		var t2 = line.get("tower2_id")
		if (t1 == tower1_id and t2 == tower2_id) or (t1 == tower2_id and t2 == tower1_id):
			return line_id
	return -1

# Переподключить линию: удалить старую (original<->source), создать новую (source<->target)
func reconnect_line(source_id: int, target_id: int, original_parent_id: int, hidden_line_id: int) -> bool:
	if not _is_valid_new_connection(source_id, target_id, original_parent_id):
		return false
	_network_ore_ids_cache.clear()
	# Удаляем старую линию
	if hidden_line_id > 0 and ecs.energy_lines.has(hidden_line_id):
		ecs.destroy_entity(hidden_line_id)
	# Создаём новую
	var source_tower = ecs.towers.get(source_id)
	var target_tower = ecs.towers.get(target_id)
	if not source_tower or not target_tower:
		return false
	var def1 = DataRepository.get_tower_def(source_tower.get("def_id", ""))
	var def2 = DataRepository.get_tower_def(target_tower.get("def_id", ""))
	var type1 = def1.get("type", "ATTACK")
	var type2 = def2.get("type", "ATTACK")
	var dist = source_tower.get("hex").distance_to(target_tower.get("hex"))
	_create_line(EnergyEdge.new(source_id, target_id, type1, type2, float(dist)))
	_recalculate_powered_and_cleanup()
	rebuild_line_hex_set()
	if GameManager.combat_system:
		GameManager.combat_system.clear_power_cache()
	return true

func _is_valid_new_connection(source_id: int, target_id: int, original_parent_id: int) -> bool:
	var source_tower = ecs.towers.get(source_id)
	var target_tower = ecs.towers.get(target_id)
	if not source_tower or not target_tower:
		return false
	if not _is_valid_connection(source_tower, target_tower):
		return false
	var adj = _build_adjacency_list()
	# Нельзя убирать последнее соединение с башней (добытчик должен иметь >= 1 исходящей линии)
	var original_connections = adj.get(original_parent_id, [])
	if original_connections.size() < 2:
		return false  # У original только 1 связь — убирать её нельзя
	# Удаляем ребро source-original из adj (симулируем состояние после удаления линии)
	if adj.has(source_id):
		adj[source_id] = _array_without(adj[source_id], original_parent_id)
	if adj.has(original_parent_id):
		adj[original_parent_id] = _array_without(adj[original_parent_id], source_id)
	# BFS от target: если достигнем source — цикл, невалидно
	var queue = [target_id]
	var visited = {target_id: true}
	var head = 0
	while head < queue.size():
		var current = queue[head]
		head += 1
		if current == source_id:
			return false  # Цикл
		for neighbor in adj.get(current, []):
			if not visited.get(neighbor, false):
				visited[neighbor] = true
				queue.append(neighbor)
	# Добавляем новое ребро и проверяем что source остаётся powered
	adj[source_id] = adj.get(source_id, [])
	adj[source_id].append(target_id)
	adj[target_id] = adj.get(target_id, [])
	adj[target_id].append(source_id)
	var powered = _find_powered_towers_with_adj(adj)
	return powered.get(source_id, false)

func _array_without(arr: Array, elem) -> Array:
	var result = []
	for x in arr:
		if x != elem:
			result.append(x)
	return result

func _is_valid_connection(tower1: Dictionary, tower2: Dictionary) -> bool:
	var def1 = DataRepository.get_tower_def(tower1.get("def_id", ""))
	var def2 = DataRepository.get_tower_def(tower2.get("def_id", ""))
	if def1.is_empty() or def2.is_empty():
		return false
	if def1.get("type") == "WALL" or def2.get("type") == "WALL":
		return false
	var h1 = tower1.get("hex")
	var h2 = tower2.get("hex")
	if not h1 or not h2:
		return false
	var dist = h1.distance_to(h2)
	var is_adjacent = (dist == 1)
	var is_miner = def1.get("type") == "MINER" and def2.get("type") == "MINER"
	var miner_ok = is_miner and dist <= Config.ENERGY_TRANSFER_RADIUS and h1.is_on_same_line(h2)
	return is_adjacent or miner_ok

func _find_powered_towers_with_adj(adj: Dictionary) -> Dictionary:
	var powered = {}
	for id in ecs.towers.keys():
		var tower = ecs.towers[id]
		var def = DataRepository.get_tower_def(tower.get("def_id", ""))
		if def.get("type") == "MINER" and _is_on_ore(tower.get("hex")):
			powered[id] = true
	var queue = []
	for id in powered.keys():
		queue.append(id)
	var head = 0
	while head < queue.size():
		var current = queue[head]
		head += 1
		for neighbor in adj.get(current, []):
			if not powered.get(neighbor, false):
				powered[neighbor] = true
				queue.append(neighbor)
	return powered

func _recalculate_powered_and_cleanup() -> void:
	var powered = _find_powered_towers_with_adj(_build_adjacency_list())
	for id in ecs.towers.keys():
		var tower = ecs.towers[id]
		var def = DataRepository.get_tower_def(tower.get("def_id", ""))
		if def.get("type") == "WALL":
			continue
		tower["is_active"] = powered.get(id, false)
	for id in ecs.towers.keys():
		_update_tower_appearance(id)
	# Удаляем линии к неактивным башням
	var to_remove = []
	for line_id in ecs.energy_lines.keys():
		var line = ecs.energy_lines[line_id]
		var t1 = ecs.towers.get(line.get("tower1_id"))
		var t2 = ecs.towers.get(line.get("tower2_id"))
		if not t1 or not t2 or not t1.get("is_active", false) or not t2.get("is_active", false):
			to_remove.append(line_id)
	for line_id in to_remove:
		ecs.destroy_entity(line_id)
	# Обновляем визуалы оставшихся башен
	for id in ecs.towers.keys():
		_update_tower_appearance(id)

func _clear_all_lines() -> void:
	var to_remove = []
	for line_id in ecs.energy_lines.keys():
		to_remove.append(line_id)
	for line_id in to_remove:
		ecs.destroy_entity(line_id)

# Перестроить набор гексов, через которые проходят энерголинии (для env damage)
func rebuild_line_hex_set() -> void:
	line_hex_set.clear()
	for line_id in ecs.energy_lines.keys():
		var line = ecs.energy_lines[line_id]
		var t1 = ecs.towers.get(line.get("tower1_id"))
		var t2 = ecs.towers.get(line.get("tower2_id"))
		if not t1 or not t2:
			continue
		var h1 = t1.get("hex")
		var h2 = t2.get("hex")
		if not h1 or not h2:
			continue
		var hexes = h1.line_to(h2)
		for h in hexes:
			line_hex_set[h.to_key()] = true

func _update_tower_appearance(id: int) -> void:
	var tower = ecs.towers.get(id)
	if not tower:
		return
	
	var def = GameManager.get_tower_def(tower.get("def_id", ""))
	if not def:
		return
	
	var is_active = tower.get("is_active", false)
	var tower_type = def.get("type", "ATTACK")
	
	# Стены всегда с базовым цветом
	if tower_type == "WALL":
		tower["color"] = def.get("color", Color.GRAY)
	else:
		# Активные - цвет из дефа, неактивные - затемнённые
		if is_active:
			tower["color"] = def.get("color", Color.BLUE)
		else:
			tower["color"] = def.get("color", Color.BLUE).darkened(0.5)

# ============================================================================
# ПОИСК ИСТОЧНИКОВ ПИТАНИЯ
# ============================================================================

# Все башни, соединённые с данной линиями (одна компонента связности)
# Использует adjacency list: O(V+E) вместо O(V*E)
func _get_connected_tower_ids(tower_id: int) -> Array:
	var adj = _build_adjacency_list()
	var seen = {}
	var queue = [tower_id]
	seen[tower_id] = true
	var i = 0
	while i < queue.size():
		var tid = queue[i]
		i += 1
		for neighbor in adj.get(tid, []):
			if not seen.get(neighbor, false):
				seen[neighbor] = true
				queue.append(neighbor)
	return queue

# Статистика руды в сети этой башни: всего осталось, всего было, добыто (по руде под майнерами в компоненте)
# Кэш: список жил руды в сети (инвалидируется при добавлении/удалении башен, крафте, переподключении линии).
func get_network_ore_stats(tower_id: int) -> Dictionary:
	var ore_ids_arr: Array = []
	if _network_ore_ids_cache.has(tower_id):
		ore_ids_arr = _network_ore_ids_cache[tower_id]
	else:
		var connected = _get_connected_tower_ids(tower_id)
		var ore_ids = {}
		for tid in connected:
			var t = ecs.towers.get(tid)
			if not t:
				continue
			var def = DataRepository.get_tower_def(t.get("def_id", ""))
			if def.get("type") != "MINER":
				continue
			var mhex = t.get("hex")
			if not mhex:
				continue
			# O(1) через ore_hex_index вместо перебора всех ores
			var oid = ecs.ore_hex_index.get(mhex.to_key(), -1)
			if oid >= 0 and ecs.ores.has(oid):
				ore_ids[oid] = true
		ore_ids_arr = ore_ids.keys()
		for tid in connected:
			_network_ore_ids_cache[tid] = ore_ids_arr
	var total_current = 0.0
	var total_max = 0.0
	for oid in ore_ids_arr:
		var o = ecs.ores.get(oid)
		if o:
			total_current += o.get("current_reserve", 0.0)
			total_max += o.get("max_reserve", 0.0)
	return {"total_current": total_current, "total_max": total_max, "mined": total_max - total_current}

# Множитель урона от доли руды в сети: полная руда = 1.0, почти пусто = 1.5 (линейно).
func get_network_ore_damage_mult(tower_id: int) -> float:
	var st = get_network_ore_stats(tower_id)
	var total_max = st.get("total_max", 0.0)
	if total_max <= 0:
		return 1.0
	var ratio = st.get("total_current", 0.0) / total_max
	# ratio 1 (full) -> 1.0, ratio 0 (empty) -> 1.5
	return 1.5 - 0.5 * ratio

# Сумма руды по всем сетям (каждая связная компонента один раз). Для HUD — то же, что на майнере «в сети», но по всей карте.
func get_all_networks_ore_totals() -> Dictionary:
	var total_current := 0.0
	var total_max := 0.0
	var seen_components := {}  # key = sorted array id -> true
	for tid in ecs.towers.keys():
		var conn = _get_connected_tower_ids(tid)
		if conn.is_empty():
			continue
		conn.sort()
		var key = ""
		for c in conn:
			key += str(c) + ","
		if seen_components.get(key, false):
			continue
		seen_components[key] = true
		var st = get_network_ore_stats(tid)
		total_current += st.get("total_current", 0.0)
		total_max += st.get("total_max", 0.0)
	return {"total_current": total_current, "total_max": total_max}

# Поиск источников питания для башни
# Возвращает массив ore entity_id которые питают эту башню
func _find_power_sources(tower_id: int) -> Array:
	var sources = []
	
	var tower = ecs.towers.get(tower_id)
	if not tower:
		return sources
	
	if not tower.get("is_active", false):
		return sources
	
	for miner_id in ecs.towers.keys():
		var miner = ecs.towers[miner_id]
		var miner_def = DataRepository.get_tower_def(miner.get("def_id", ""))
		
		if miner_def.get("type") != "MINER":
			continue
		
		if not miner.get("is_active", false):
			continue
		
		var miner_hex = miner.get("hex")
		if not miner_hex:
			continue
		
		# O(1) lookup вместо перебора всех ores
		var ore_id = ecs.ore_hex_index.get(miner_hex.to_key(), -1)
		if ore_id < 0:
			continue
		var ore = ecs.ores.get(ore_id)
		if ore and ore.get("current_reserve", 0.0) > Config.ORE_DEPLETION_THRESHOLD:
			sources.append(ore_id)
	
	return sources

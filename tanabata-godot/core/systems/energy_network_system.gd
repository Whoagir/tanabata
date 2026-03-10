# energy_network_system.gd
# Система энергосети - управление соединениями между башнями
# Портирована из Go версии (energy_network.go)
class_name EnergyNetworkSystem

var ecs: ECSWorld
var hex_map: HexMap

# Кэш: tower_id -> массив ore_id в этой сети (инвалидируется при изменении графа)
var _network_ore_ids_cache: Dictionary = {}
# Кэш сглаженного восстановления руды по жилам (ore_id -> restore_per_round), инвалидируется в rebuild_energy_network
var _smoothed_restore_cache: Dictionary = {}

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

# Радиус передачи по типу башни (майнер 4, батарея 5)
static func get_transfer_radius(tower_def: Dictionary) -> int:
	var energy = tower_def.get("energy", {})
	if typeof(energy) == TYPE_DICTIONARY and energy.has("transfer_radius"):
		return int(energy["transfer_radius"])
	return Config.ENERGY_TRANSFER_RADIUS

# Вычислить вес ребра (чем меньше, тем выше приоритет)
static func calculate_edge_weight(type1: String, type2: String, distance: float) -> float:
	var is_t1_miner = (type1 == "MINER")
	var is_t2_miner = (type2 == "MINER")
	var is_t1_battery = (type1 == "BATTERY")
	var is_t2_battery = (type2 == "BATTERY")
	# Майнер-Майнер и Батарея-*: высший приоритет
	if (is_t1_miner and is_t2_miner) or (is_t1_battery or is_t2_battery):
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
	_smoothed_restore_cache.clear()
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
			var powered_after = _find_powered_towers_with_adj(_build_adjacency_list())
			_update_powered_tower_ids_for_renderer(powered_after)
			_update_all_towers_resistance()
			return
	
	# 1. Найти возможные соединения с активными башнями
	var connections = _find_possible_connections(new_tower_id, new_tower)
	
	# 2. Проверить: может ли башня быть активной (майнер или батарея на руде = корень)
	var new_hex = new_tower.get("hex")
	var is_new_root = (tower_type == "MINER" or tower_type == "BATTERY") and _is_on_ore(new_hex)
	
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
	var powered_after = _find_powered_towers_with_adj(_build_adjacency_list())
	_update_powered_tower_ids_for_renderer(powered_after)
	_update_all_towers_resistance()

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

# Есть ли у башни хотя бы одна линия (участвует в графе сети)
func _tower_has_any_line(tower_id: int) -> bool:
	for line in ecs.energy_lines.values():
		if line.get("tower1_id") == tower_id or line.get("tower2_id") == tower_id:
			return true
	return false

# Найти возможные соединения: с активными башнями и с башнями, уже входящими в граф (выключенные майнеры — передатчики, к ним тоже можно подключаться)
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
		var other_active = other_tower.get("is_active", false)
		var other_in_graph = _tower_has_any_line(other_id)
		if not other_active and not other_in_graph:
			continue  # Только активные или уже в сети (в т.ч. выключенные майнеры как передатчики)
		
		var other_def = DataRepository.get_tower_def(other_tower.get("def_id", ""))
		if not other_def:
			continue
		
		var other_type = other_def.get("type", "ATTACK")
		var other_hex = other_tower.get("hex")
		var distance = new_hex.distance_to(other_hex)
		var new_radius = get_transfer_radius(new_def)
		var other_radius = get_transfer_radius(other_def)
		var max_dist = mini(new_radius, other_radius)
		# Правила соединения
		var is_neighbor = (distance == 1)
		var is_miner_connection = (
			new_type == "MINER" and 
			other_type == "MINER" and
			distance <= max_dist and
			new_hex.is_on_same_line(other_hex)
		)
		var is_battery_connection = (
			(new_type == "BATTERY" or other_type == "BATTERY") and
			(new_type == "MINER" or new_type == "BATTERY") and
			(other_type == "MINER" or other_type == "BATTERY") and
			distance <= max_dist and
			new_hex.is_on_same_line(other_hex)
		)
		if is_neighbor or is_miner_connection or is_battery_connection:
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

# Расширить сеть от башни (BFS). Не создаём циклов: линия только если башни в разных компонентах связности.
func _expand_network_from(start_node: int) -> void:
	var queue = [start_node]
	var visited = {start_node: true}
	var adj = _build_adjacency_list()
	var uf = UnionFind.new()
	for id in ecs.towers.keys():
		uf.find(id)
	for line in ecs.energy_lines.values():
		var t1 = line.get("tower1_id")
		var t2 = line.get("tower2_id")
		if ecs.towers.has(t1) and ecs.towers.has(t2):
			uf.union(t1, t2)
	
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
		
		# Ищем соседей, с которыми ещё нет линии (чтобы не дублировать рёбра и не создавать циклы)
		for other_id in ecs.towers.keys():
			if visited.get(other_id, false):
				continue
			if adj.get(current_id, []).has(other_id):
				continue  # Уже соединены — не создаём дубликат линии
			
			var other_tower = ecs.towers[other_id]
			if other_tower.get("is_active", false):
				continue  # Активные уже в графе, линия к ним создана в _connect_to_networks
			
			var other_def = DataRepository.get_tower_def(other_tower.get("def_id", ""))
			if not other_def or other_def.get("type") == "WALL":
				continue
			
			var other_type = other_def.get("type", "ATTACK")
			var other_hex = other_tower.get("hex")
			var distance = current_hex.distance_to(other_hex)
			var current_radius = get_transfer_radius(current_def)
			var other_radius = get_transfer_radius(other_def)
			var max_dist = mini(current_radius, other_radius)
			var is_neighbor = (distance == 1)
			var is_miner_connection = (
				current_type == "MINER" and
				other_type == "MINER" and
				distance <= max_dist and
				current_hex.is_on_same_line(other_hex)
			)
			var is_battery_connection = (
				(current_type == "BATTERY" or other_type == "BATTERY") and
				(current_type == "MINER" or current_type == "BATTERY") and
				(other_type == "MINER" or other_type == "BATTERY") and
				distance <= max_dist and
				current_hex.is_on_same_line(other_hex)
			)
			if is_neighbor or is_miner_connection or is_battery_connection:
				if uf.find(current_id) == uf.find(other_id):
					continue  # Уже в одной компоненте — линия создаст цикл, не добавляем
				if not _forms_triangle(current_id, other_id, adj):
					# Активируем соседа только если он не выключен вручную (выключенный майнер остаётся передатчиком, не «включаем» его)
					if not other_tower.get("is_manually_disabled", false):
						other_tower["is_active"] = true
						_update_tower_appearance(other_id)
					
					# Создаём линию в любом случае (граф единый, выключенный — часть сети)
					var edge = EnergyEdge.new(
						current_id, other_id,
						current_type, other_type,
						float(distance)
					)
					_create_line(edge)
					uf.union(current_id, other_id)
					
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
	_smoothed_restore_cache.clear()
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
	_smoothed_restore_cache.clear()
	# 1. Определить какие башни питаются от источника
	var powered = _find_powered_towers_with_adj(_build_adjacency_list())
	for id in ecs.towers.keys():
		var tower = ecs.towers[id]
		var def = DataRepository.get_tower_def(tower.get("def_id", ""))
		if def and def.get("type") == "WALL":
			continue
		tower["is_active"] = powered.get(id, false) and not tower.get("is_manually_disabled", false)
	
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
			tower["is_active"] = powered.get(id, false) and not tower.get("is_manually_disabled", false)
	
	# Линии не удаляем по is_active: пустые майнеры остаются передатчиками, топология сохраняется (см. ENERGY_NETWORK_LINES_BUG_ANALYSIS.md).
	for id in ecs.towers.keys():
		_update_tower_appearance(id)
	
	rebuild_line_hex_set()
	var powered_after = _find_powered_towers_with_adj(_build_adjacency_list())
	_update_powered_tower_ids_for_renderer(powered_after)
	_update_all_towers_resistance()
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
	
	# Связность по всему графу (включая выключенные майнеры — передатчики). Иначе две активные башни,
	# соединённые только через выключенный майнер, считаются разными компонентами и между ними добавляется
	# мост -> цикл.
	var uf = UnionFind.new()
	for id in ecs.towers.keys():
		var tower = ecs.towers[id]
		var def = DataRepository.get_tower_def(tower.get("def_id", ""))
		if def and def.get("type") == "WALL":
			continue
		uf.find(id)
	for line in ecs.energy_lines.values():
		var t1 = line.get("tower1_id")
		var t2 = line.get("tower2_id")
		if ecs.towers.has(t1) and ecs.towers.has(t2):
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
	_smoothed_restore_cache.clear()
	var all_towers = _collect_and_reset_towers()
	if all_towers.size() == 0:
		_clear_all_lines()
		_update_powered_tower_ids_for_renderer({})
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
	var powered_after = _find_powered_towers_with_adj(_build_adjacency_list())
	_update_powered_tower_ids_for_renderer(powered_after)
	_update_all_towers_resistance()
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
			var type_a = def_a.get("type", "ATTACK")
			var type_b = def_b.get("type", "ATTACK")
			var r_a = get_transfer_radius(def_a)
			var r_b = get_transfer_radius(def_b)
			var max_dist = mini(r_a, r_b)
			var is_miner_connection = (
				type_a == "MINER" and
				type_b == "MINER" and
				distance <= max_dist and
				hex_a.is_on_same_line(hex_b) and
				not _has_active_tower_between(hex_a, hex_b, all_towers, potentially_active)
			)
			var is_battery_connection = (
				(type_a == "BATTERY" or type_b == "BATTERY") and
				(type_a == "MINER" or type_a == "BATTERY") and
				(type_b == "MINER" or type_b == "BATTERY") and
				distance <= max_dist and
				hex_a.is_on_same_line(hex_b) and
				not _has_active_tower_between(hex_a, hex_b, all_towers, potentially_active)
			)
			
			if is_neighbor or is_miner_connection or is_battery_connection:
				edges.append(EnergyEdge.new(
					id_a, id_b,
					type_a, type_b,
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
					# Блокируется майнером или батареей на линии (как у вышки типа Б)
					if def and (def.get("type") == "MINER" or def.get("type") == "BATTERY"):
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
	# Найти корни: майнеры на руде; батареи в режиме разряда (ручная трата или авто: сеть < 10 или батарея полная)
	var energy_source_roots = {}
	for hex_key in all_towers.keys():
		var id = all_towers[hex_key]
		var tower = ecs.towers.get(id)
		if not tower:
			continue
		var def = DataRepository.get_tower_def(tower.get("def_id", ""))
		if not def:
			continue
		if def.get("type") == "MINER":
			if tower.get("is_manually_disabled", false):
				continue
			var hex = Hex.from_key(hex_key)
			if _is_on_ore(hex):
				energy_source_roots[uf.find(id)] = true
		elif def.get("type") == "BATTERY":
			var hex = Hex.from_key(hex_key)
			if _is_on_ore(hex):
				energy_source_roots[uf.find(id)] = true
			else:
				var storage = tower.get("battery_storage", 0.0)
				if storage <= 0.0:
					continue
				var manual_discharge = tower.get("battery_manual_discharge", false)
				var storage_max = def.get("energy", {}).get("storage_max", 200.0)
				var net_ore = get_network_ore_total_for_activation(id)
				var auto_discharge = (net_ore < 10.0) or (storage >= storage_max)
				if manual_discharge or auto_discharge:
					energy_source_roots[uf.find(id)] = true
	
	# Активировать: подключены к корням и не выключены вручную (для батареи "выключено" = режим траты, всё равно источник)
	var activated_count = 0
	for id in potentially_active.keys():
		var tower = ecs.towers.get(id)
		var def = DataRepository.get_tower_def(tower.get("def_id", "")) if tower else null
		var is_battery = def and def.get("type") == "BATTERY"
		var not_manual_off = not (tower.get("is_manually_disabled", false) if tower else false)
		if energy_source_roots.has(uf.find(id)) and (not_manual_off or is_battery):
			ecs.towers[id]["is_active"] = true
			activated_count += 1
		else:
			ecs.towers[id]["is_active"] = false

func _update_tower_appearances(all_towers: Dictionary) -> void:
	for id in all_towers.values():
		_update_tower_appearance(id)

func _rebuild_energy_lines(mst_edges: Array) -> void:
	_clear_all_lines()
	# Линии по топологии MST (ручно выключенные башни остаются в сети — передают)
	for edge in mst_edges:
		var tower1 = ecs.towers.get(edge.tower1_id)
		var tower2 = ecs.towers.get(edge.tower2_id)
		if tower1 and tower2:
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

# Вес уровня майнера для сглаживания: лвл 1 = 1.0, каждый следующий +20% (лвл 2 = 1.2, 3 = 1.4, 4 = 1.6, 5 = 1.8).
func _miner_restore_weight(level: int) -> float:
	var lv = clampi(level, 1, 5)
	return 1.0 + (lv - 1) * Config.ORE_RESTORE_MINER_LEVEL_WEIGHT_BONUS

# Заполняет _smoothed_restore_cache: общее восстановление распределяется по жилам с весами по уровню майнера (лейт-польза низкоуровневых майнеров).
func _fill_smoothed_restore_cache() -> void:
	_smoothed_restore_cache.clear()
	var total_raw := 0.0
	var total_weight := 0.0
	var entries: Array = []  # { ore_id, raw, weight, disabled_mult, success_mult }
	var player_level = 1
	var current_xp = 0
	var xp_to_next = 100
	for pid in ecs.player_states.keys():
		var ps = ecs.player_states[pid]
		player_level = ps.get("level", 1)
		current_xp = ps.get("current_xp", 0)
		xp_to_next = ps.get("xp_to_next_level", 100)
		break
	var success_lv = ecs.game_state.get("success_level", Config.SUCCESS_LEVEL_DEFAULT)
	var success_mult = Config.get_success_ore_bonus_mult(success_lv)
	var card_bonus = GameManager.get_card_ore_restore_bonus() if GameManager else 0.0
	var progress = 1.0
	if xp_to_next > 0:
		progress = clampf(float(current_xp) / float(xp_to_next), 0.0, 1.0)
	for ore_id in ecs.ores.keys():
		var ore = ecs.ores.get(ore_id)
		if not ore:
			continue
		var ore_hex = ore.get("hex")
		if not ore_hex:
			continue
		var tid = hex_map.get_tower_id(ore_hex)
		if tid == GameTypes.INVALID_ENTITY_ID:
			continue
		var t = ecs.towers.get(tid)
		if not t:
			continue
		var def = DataRepository.get_tower_def(t.get("def_id", ""))
		if def.get("type") != "MINER":
			continue
		var miner_lv = clampi(t.get("level", 1), 1, 5)
		var base: float
		match miner_lv:
			1: base = 1.7 * Config.ORE_RESTORE_LEVEL_1_MULT
			2: base = 2.5
			3: base = 5.2
			4: base = 9.6
			5: base = 15.0
			_: base = 1.7
		var level_mult = 1.0
		if player_level > miner_lv:
			level_mult = 1.0
		elif player_level == miner_lv:
			level_mult = progress
		var raw = base * Config.ORE_RESTORE_GLOBAL_MULT * level_mult + card_bonus
		var weight = _miner_restore_weight(miner_lv)
		var disabled_mult = 1.3 if t.get("is_manually_disabled", false) else 1.0
		total_raw += raw
		total_weight += weight
		entries.append({"ore_id": ore_id, "raw": raw, "weight": weight, "disabled_mult": disabled_mult, "success_mult": success_mult})
	if total_weight <= 0.0:
		return
	var rate_per_weight = total_raw / total_weight
	for e in entries:
		var effective = rate_per_weight * e.weight * e.disabled_mult * e.success_mult
		_smoothed_restore_cache[e.ore_id] = effective

# Сколько руды восстанавливается за волну (на жилу с майнером).
# Сглаживание: суммарное восстановление по всем жилам распределяется по весам уровней (лвл 1 = 1.0, каждый следующий +20%), чтобы майнеры 1 лвл оставались полезны в лейте.
func get_ore_restore_per_round(ore_id: int) -> float:
	if _smoothed_restore_cache.is_empty():
		_fill_smoothed_restore_cache()
	if _smoothed_restore_cache.has(ore_id):
		return _smoothed_restore_cache[ore_id]
	return 0.0

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
	_update_all_towers_resistance()
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
	var t1 = def1.get("type", "ATTACK")
	var t2 = def2.get("type", "ATTACK")
	var r1 = get_transfer_radius(def1)
	var r2 = get_transfer_radius(def2)
	var max_dist = mini(r1, r2)
	var is_miner = t1 == "MINER" and t2 == "MINER"
	var miner_ok = is_miner and dist <= max_dist and h1.is_on_same_line(h2)
	var is_battery = (t1 == "BATTERY" or t2 == "BATTERY") and (t1 == "MINER" or t1 == "BATTERY") and (t2 == "MINER" or t2 == "BATTERY")
	var battery_ok = is_battery and dist <= max_dist and h1.is_on_same_line(h2)
	return is_adjacent or miner_ok or battery_ok

func _find_powered_towers_with_adj(adj: Dictionary) -> Dictionary:
	var powered = {}
	for id in ecs.towers.keys():
		var tower = ecs.towers[id]
		var def = DataRepository.get_tower_def(tower.get("def_id", ""))
		if not def:
			continue
		if def.get("type") == "MINER":
			if tower.get("is_manually_disabled", false):
				continue
			if _is_on_ore(tower.get("hex")):
				powered[id] = true
		elif def.get("type") == "BATTERY":
			if _is_on_ore(tower.get("hex")):
				powered[id] = true
			else:
				var storage = tower.get("battery_storage", 0.0)
				if storage <= 0.0:
					continue
				var manual = tower.get("battery_manual_discharge", false)
				var storage_max = def.get("energy", {}).get("storage_max", 200.0)
				if manual or storage >= storage_max:
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
	_network_ore_ids_cache.clear()
	var powered = _find_powered_towers_with_adj(_build_adjacency_list())
	for id in ecs.towers.keys():
		var tower = ecs.towers[id]
		var def = DataRepository.get_tower_def(tower.get("def_id", ""))
		if def.get("type") == "WALL":
			continue
		tower["is_active"] = powered.get(id, false) and not tower.get("is_manually_disabled", false)
	for id in ecs.towers.keys():
		_update_tower_appearance(id)
	# Линии не удаляем при вкл/выкл майнера: выключенный майнер остаётся передатчиком, топология сети сохраняется. Линии удаляются только при сносе башни (remove_lines_connected_to_tower / handle_tower_removal).
	_update_powered_tower_ids_for_renderer(powered)

# Сохранить множество ID башен, входящих в компоненты с корнями (есть питание). Рендерер рисует линии только между такими башнями — при 0 корней линии не показываются.
func _update_powered_tower_ids_for_renderer(powered: Dictionary) -> void:
	ecs.game_state["energy_network_powered_tower_ids"] = powered

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

# Сумма руды в компоненте по жилам под майнерами и батареями (без учёта is_active). Для решения «батарея — корень?» во время rebuild.
func get_network_ore_total_for_activation(tower_id: int) -> float:
	var connected = _get_connected_tower_ids(tower_id)
	var total = 0.0
	var seen_oid = {}
	for tid in connected:
		var t = ecs.towers.get(tid)
		if not t:
			continue
		var def = DataRepository.get_tower_def(t.get("def_id", ""))
		if not def:
			continue
		if def.get("type") != "MINER" and def.get("type") != "BATTERY":
			continue
		var mhex = t.get("hex")
		if not mhex:
			continue
		var oid = ecs.ore_hex_index.get(mhex.to_key(), -1)
		if oid >= 0 and ecs.ores.has(oid) and not seen_oid.get(oid, false):
			seen_oid[oid] = true
			var o = ecs.ores[oid]
			if o:
				total += o.get("current_reserve", 0.0)
	return total

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
			if not def:
				continue
			var mhex = t.get("hex")
			if not mhex:
				continue
			var oid = ecs.ore_hex_index.get(mhex.to_key(), -1)
			if oid < 0 or not ecs.ores.has(oid):
				continue
			if def.get("type") == "MINER":
				if not t.get("is_active", false):
					continue
				var ore = ecs.ores[oid]
				if ore.get("current_reserve", 0.0) >= Config.ORE_DEPLETION_THRESHOLD:
					ore_ids[oid] = true
			elif def.get("type") == "BATTERY":
				var ore = ecs.ores[oid]
				if ore.get("current_reserve", 0.0) >= Config.ORE_DEPLETION_THRESHOLD:
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
	var connected = _get_connected_tower_ids(tower_id)
	for tid in connected:
		var t = ecs.towers.get(tid)
		if not t:
			continue
		var def = DataRepository.get_tower_def(t.get("def_id", ""))
		if not def or def.get("type") != "BATTERY":
			continue
		var storage = t.get("battery_storage", 0.0)
		if storage <= 0.0:
			continue
		var manual = t.get("battery_manual_discharge", false)
		var storage_max = def.get("energy", {}).get("storage_max", 200.0)
		var net_ore = get_network_ore_total_for_activation(tid)
		var auto_discharge = (net_ore < 10.0) or (storage >= storage_max)
		if manual or auto_discharge:
			total_current += storage
			total_max += storage
	return {"total_current": total_current, "total_max": total_max, "mined": total_max - total_current, "ore_ids": ore_ids_arr}

# Все жилы руды в сетях (под майнерами) — для награды за голд-существо (равномерное распределение руды).
func get_all_network_ore_ids() -> Array:
	var seen: Dictionary = {}
	for tid in ecs.towers:
		var st = get_network_ore_stats(tid)
		for oid in st.get("ore_ids", []):
			seen[oid] = true
	return seen.keys()

# Множитель урона от доли руды в сети: полная руда = 1.0, почти пусто = 1.5 (линейно).
func get_network_ore_damage_mult(tower_id: int) -> float:
	var st = get_network_ore_stats(tower_id)
	var total_max = st.get("total_max", 0.0)
	if total_max <= 0:
		return 1.0
	var ratio = st.get("total_current", 0.0) / total_max
	# ratio 1 (full) -> 1.0, ratio 0 (empty) -> 1.5
	return 1.5 - 0.5 * ratio

# ============================================================================
# СОПРОТИВЛЕНИЕ СЕТИ (резистор)
# ============================================================================
# Вышки типа Б (MINER, BATTERY) — 0 сопротивления. Вышки типа А (ATTACK) — 0.2 за каждую на пути до ближайшей типа Б. Сумма капается на 1. Множитель урона и силы ауры = max(0, 1 - resistance).

func _compute_tower_resistance(tower_id: int) -> float:
	var adj = _build_adjacency_list()
	if not adj.has(tower_id):
		return 0.0
	var queue = [tower_id]
	var visited = {tower_id: true}
	var hops = {tower_id: 0}
	var head = 0
	while head < queue.size():
		var current = queue[head]
		head += 1
		var current_hops = hops.get(current, 0)
		var t = ecs.towers.get(current)
		if not t:
			continue
		var def = DataRepository.get_tower_def(t.get("def_id", ""))
		if not def:
			continue
		var tt = def.get("type", "ATTACK")
		if tt == "MINER" or tt == "BATTERY":
			if current == tower_id:
				return 0.0
			var resistance = current_hops * Config.RESISTANCE_PER_ATTACK_TOWER
			return minf(resistance, Config.RESISTANCE_CAP)
		for neighbor in adj.get(current, []):
			if not visited.get(neighbor, false):
				visited[neighbor] = true
				hops[neighbor] = current_hops + 1
				queue.append(neighbor)
	return Config.RESISTANCE_CAP

func _update_all_towers_resistance() -> void:
	var adj = _build_adjacency_list()
	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		var def = DataRepository.get_tower_def(tower.get("def_id", ""))
		if not def or def.get("type") == "WALL":
			tower["resistance"] = 0.0
			continue
		if not adj.has(tower_id):
			tower["resistance"] = 0.0
			continue
		tower["resistance"] = _compute_tower_resistance(tower_id)

func get_resistance_mult(tower_id: int) -> float:
	var t = ecs.towers.get(tower_id)
	if not t:
		return 1.0
	var r = t.get("resistance", 0.0)
	return maxf(0.0, 1.0 - r)

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

# Список сетей с рудой и числом атакующих вышек (не MINER, не WALL). Для лога «основная сеть» = с макс. числом атакующих.
func get_networks_ore_and_attack_count() -> Array:
	var result: Array = []
	var seen_components := {}
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
		var attack_count = 0
		for t_id in conn:
			var t = ecs.towers.get(t_id)
			if not t:
				continue
			var def = DataRepository.get_tower_def(t.get("def_id", ""))
			var ttype = def.get("type", "")
			if ttype != "MINER" and ttype != "WALL":
				attack_count += 1
		result.append({
			"tower_id": tid,
			"total_current": st.get("total_current", 0.0),
			"total_max": st.get("total_max", 0.0),
			"attack_count": attack_count
		})
	return result

# Поиск источников питания для башни (в той же сети).
# Возвращает массив {"type": "ore", "id": ore_id} или {"type": "battery", "id": tower_id}.
func _find_power_sources(tower_id: int) -> Array:
	var sources = []
	var tower = ecs.towers.get(tower_id)
	if not tower or not tower.get("is_active", false):
		return sources
	var connected = _get_connected_tower_ids(tower_id)
	var seen_ore = {}
	for tid in connected:
		var t = ecs.towers.get(tid)
		if not t:
			continue
		var def = DataRepository.get_tower_def(t.get("def_id", ""))
		if not def:
			continue
		var mhex = t.get("hex")
		if not mhex:
			continue
		var ore_id = ecs.ore_hex_index.get(mhex.to_key(), -1)
		if ore_id >= 0 and ecs.ores.has(ore_id) and not seen_ore.get(ore_id, false):
			var ore = ecs.ores[ore_id]
			if ore.get("current_reserve", 0.0) >= Config.ORE_DEPLETION_THRESHOLD:
				if def.get("type") == "MINER":
					if not t.get("is_active", false):
						continue
				seen_ore[ore_id] = true
				sources.append({"type": "ore", "id": ore_id})
		if def.get("type") == "BATTERY":
			var storage = t.get("battery_storage", 0.0)
			if storage <= 0.0:
				continue
			var manual = t.get("battery_manual_discharge", false)
			var storage_max = def.get("energy", {}).get("storage_max", 200.0)
			var net_ore = get_network_ore_total_for_activation(tid)
			var auto_discharge = (net_ore < 10.0) or (storage >= storage_max)
			if manual or auto_discharge:
				sources.append({"type": "battery", "id": tid})
	return sources

func get_power_source_reserve(source: Dictionary) -> float:
	if source.get("type") == "ore":
		var o = ecs.ores.get(source.get("id", -1))
		return o.get("current_reserve", 0.0) if o else 0.0
	if source.get("type") == "battery":
		var t = ecs.towers.get(source.get("id", -1))
		return t.get("battery_storage", 0.0) if t else 0.0
	return 0.0

func consume_from_power_source(source: Dictionary, amount: float, tower_id: int = -1) -> void:
	if source.get("type") == "ore":
		var ore_id = source.get("id", -1)
		var ore = ecs.ores.get(ore_id)
		if not ore:
			return
		var sector = ore.get("sector", 0)
		var mult = get_miner_efficiency_for_ore(ore_id)
		var deduct = amount / mult * GameManager.get_ore_consumption_multiplier()
		var cur = ore.get("current_reserve", 0.0)
		ore["current_reserve"] = maxf(0.0, cur - deduct)
		GameManager.record_ore_spent(deduct, sector, tower_id)
		if ore["current_reserve"] < Config.ORE_DEPLETION_THRESHOLD:
			ecs.destroy_entity(ore_id)
			rebuild_energy_network()
	elif source.get("type") == "battery":
		var bid = source.get("id", -1)
		var t = ecs.towers.get(bid)
		if not t:
			return
		var cur = t.get("battery_storage", 0.0)
		var deduct = minf(amount, cur)
		t["battery_storage"] = maxf(0.0, cur - deduct)
		GameManager.record_ore_spent(deduct, 0, tower_id)

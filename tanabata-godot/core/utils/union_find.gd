# union_find.gd
# Union-Find (Disjoint Set Union) для энергосети
# Используется для MST (Minimum Spanning Tree) и предотвращения циклов
class_name UnionFind

var parent: Dictionary = {}  # id -> parent_id
var rank: Dictionary = {}    # id -> rank (для оптимизации)

# Найти корень компоненты (с path compression)
func find(x: int) -> int:
	if not parent.has(x):
		parent[x] = x
		rank[x] = 0
		return x
	
	# Path compression: сжимаем путь к корню
	if parent[x] != x:
		parent[x] = find(parent[x])
	
	return parent[x]

# Объединить две компоненты (union by rank)
func union(x: int, y: int) -> void:
	var root_x = find(x)
	var root_y = find(y)
	
	if root_x == root_y:
		return  # Уже в одной компоненте
	
	# Union by rank: присоединяем меньшее дерево к большему
	if rank[root_x] < rank[root_y]:
		parent[root_x] = root_y
	elif rank[root_x] > rank[root_y]:
		parent[root_y] = root_x
	else:
		parent[root_y] = root_x
		rank[root_x] += 1

# Проверить: находятся ли x и y в одной компоненте
func connected(x: int, y: int) -> bool:
	return find(x) == find(y)

# Сбросить всю структуру
func clear() -> void:
	parent.clear()
	rank.clear()

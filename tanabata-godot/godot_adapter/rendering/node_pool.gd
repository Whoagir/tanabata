# node_pool.gd
# Object Pool для переиспользования Node2D (снаряды, враги, эффекты)
class_name NodePool

var pool: Array = []
var pool_size: int = 0
var create_func: Callable
var reset_func: Callable
var parent_node: Node

func _init(parent: Node, create_callback: Callable, reset_callback: Callable, initial_size: int = 10):
	parent_node = parent
	create_func = create_callback
	reset_func = reset_callback
	
	# Предсоздаем объекты
	for i in range(initial_size):
		var node = create_func.call()
		node.visible = false
		parent_node.add_child(node)
		pool.append(node)
		pool_size += 1

# Взять объект из пула
func acquire() -> Node2D:
	var node: Node2D
	
	if pool.size() > 0:
		# Берем из пула
		node = pool.pop_back()
	else:
		# Пул пуст - создаем новый
		node = create_func.call()
		parent_node.add_child(node)
		pool_size += 1
	
	node.visible = true
	return node

# Вернуть объект в пул
func release(node: Node2D):
	if node == null:
		return
	
	# Сбрасываем состояние
	reset_func.call(node)
	node.visible = false
	pool.append(node)

# Получить статистику
func get_stats() -> Dictionary:
	return {
		"total": pool_size,
		"active": pool_size - pool.size(),
		"pooled": pool.size()
	}

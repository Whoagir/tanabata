# godot_adapter/rendering/metaball_wall_renderer.gd
# Liquid glass стены через metaballs
extends Node2D

var ecs: ECSWorld
var hex_map: HexMap

# Shader material
var shader_material: ShaderMaterial
var metaball_canvas: ColorRect

# Визуальные параметры
const WALL_SIZE_PERCENT = 0.70
const METABALL_RADIUS = 20.0  # Радиус влияния каждой стены
const METABALL_THRESHOLD = 1.0

# Оптимизация
var needs_update = false
var wall_positions: PackedVector2Array = PackedVector2Array()

func _ready():
	ecs = GameManager.ecs
	hex_map = GameManager.hex_map
	
	# Создаем canvas для shader
	metaball_canvas = ColorRect.new()
	metaball_canvas.size = Vector2(2000, 2000)  # Большой canvas
	metaball_canvas.position = Vector2(-1000, -1000)
	metaball_canvas.z_index = 25
	add_child(metaball_canvas)
	
	# Загружаем shader
	var shader = load("res://godot_adapter/rendering/metaball_wall.gdshader")
	shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	metaball_canvas.material = shader_material
	

func _process(_delta):
	_update_walls()

func _update_walls():
	# Собираем позиции всех стен
	var positions = []
	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		var def_id = tower.get("def_id", "")
		var tower_def = GameManager.get_tower_def(def_id)
		
		if tower_def.get("type") != "WALL":
			continue
		
		var hex = tower.get("hex")
		if hex:
			var pixel_pos = hex.to_pixel(Config.HEX_SIZE)
			positions.append(pixel_pos)
	
	# Обновляем shader uniform
	if positions.size() > 0:
		_update_shader_positions(positions)
		metaball_canvas.visible = true
	else:
		metaball_canvas.visible = false

func _update_shader_positions(positions: Array):
	# Ограничиваем до 100 (max_balls в shader)
	var count = min(positions.size(), 100)
	
	# Создаем массив для shader
	var shader_positions = []
	for i in range(100):
		if i < count:
			shader_positions.append(positions[i])
		else:
			shader_positions.append(Vector2.ZERO)  # Пустая позиция
	
	# Передаем в shader
	shader_material.set_shader_parameter("ball_positions", shader_positions)
	shader_material.set_shader_parameter("ball_radius", Config.HEX_SIZE * WALL_SIZE_PERCENT)
	shader_material.set_shader_parameter("threshold", METABALL_THRESHOLD)

func force_immediate_update():
	_update_walls()

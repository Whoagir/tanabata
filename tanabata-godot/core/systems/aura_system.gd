# aura_system.gd
# Система обработки аур (буст скорострельности башен)
# Портировано из Go: internal/system/aura.go
class_name AuraSystem

var ecs: ECSWorld
var hex_map: HexMap

func _init(ecs_: ECSWorld, hex_map_: HexMap):
	ecs = ecs_
	hex_map = hex_map_

# ============================================================================
# UPDATE
# ============================================================================

func update():
	"""Обновляет ауры башен (без дельта-времени, т.к. это проверка состояния)"""
	# Сначала очищаем все aura_effects
	ecs.aura_effects.clear()
	
	# Находим все башни с аурами
	var aura_towers = []
	for tower_id in ecs.towers.keys():
		if ecs.auras.has(tower_id):
			var tower = ecs.towers[tower_id]
			# Проверяем что башня активна (подключена к энергосети)
			if tower.get("is_active", false):
				aura_towers.append(tower_id)
	
	# Для каждой башни с аурой проверяем кто в радиусе
	for aura_tower_id in aura_towers:
		var aura_tower = ecs.towers[aura_tower_id]
		var aura_data = ecs.auras[aura_tower_id]
		var aura_hex = aura_tower.get("hex")
		var aura_radius = aura_data.get("radius", 2)
		var speed_mult = aura_data.get("speed_multiplier", 1.0)
		var damage_bonus = aura_data.get("damage_bonus", 0)
		
		# Находим все гексы в радиусе ауры
		var hexes_in_range = hex_map.get_hexes_in_range(aura_hex, aura_radius)
		
		# Для каждого гекса проверяем есть ли на нем башня
		for hex in hexes_in_range:
			var tower_id = hex_map.get_tower_id(hex)
			if tower_id == GameTypes.INVALID_ENTITY_ID:
				continue
			
			# Башня не может баффать сама себя
			if tower_id == aura_tower_id:
				continue
			
			# Проверяем что это атакующая башня (имеет combat компонент)
			if not ecs.combat.has(tower_id):
				continue
			
			# Применяем buff: скорость атаки стакается (перемножается), бонус урона — максимум
			if ecs.aura_effects.has(tower_id):
				var cur = ecs.aura_effects[tower_id]
				if speed_mult > 1.0:
					cur["speed_multiplier"] = cur.get("speed_multiplier", 1.0) * speed_mult
				if damage_bonus > 0:
					cur["damage_bonus"] = max(cur.get("damage_bonus", 0), damage_bonus)
			else:
				var eff = {}
				if speed_mult > 1.0:
					eff["speed_multiplier"] = speed_mult
				if damage_bonus > 0:
					eff["damage_bonus"] = damage_bonus
				if not eff.is_empty():
					ecs.aura_effects[tower_id] = eff

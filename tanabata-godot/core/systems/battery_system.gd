# battery_system.gd
# Башня «Батарея»: накопление/разряд. Тик раз в секунду.
# Режим «добыча»: из сети забирается 0.05/с, в хранилище за тик всегда добавляется 0.1 (копит больше чем тратит). Жила под батареей — как у вышки типа Б, руда идёт в сеть, батарея из неё в себя не забирает.
# Режим «трата»: батарея становится источником, отдаёт в сеть до 0.1/с из буфера; жила под ней по-прежнему питает сеть.
extends RefCounted

var ecs: ECSWorld
var energy_network: EnergyNetworkSystem

var _accumulated: float = 0.0
const TICK_INTERVAL: float = 1.0

func _init(ecs_world: ECSWorld, energy_net: EnergyNetworkSystem):
	ecs = ecs_world
	energy_network = energy_net

func update(delta: float) -> void:
	if ecs.game_state.get("phase", GameTypes.GamePhase.BUILD_STATE) != GameTypes.GamePhase.WAVE_STATE:
		return
	_accumulated += delta
	if _accumulated < TICK_INTERVAL:
		return
	_accumulated -= TICK_INTERVAL
	_tick_batteries()

func _tick_batteries() -> void:
	var need_rebuild = false
	for tower_id in ecs.towers.keys():
		var tower = ecs.towers[tower_id]
		var def = DataRepository.get_tower_def(tower.get("def_id", ""))
		if not def or def.get("type") != "BATTERY":
			continue
		var energy = def.get("energy", {})
		var storage_max = float(energy.get("storage_max", 200))
		var charge_rate = float(energy.get("charge_rate", 0.1))
		var discharge_rate = float(energy.get("discharge_rate", 0.1))
		var consume_rate = float(energy.get("consume_rate", 0.05))
		var storage = tower.get("battery_storage", 0.0)
		var manual_discharge = tower.get("battery_manual_discharge", false)
		var net_ore = 0.0
		if energy_network and energy_network.has_method("get_network_ore_stats"):
			var st = energy_network.get_network_ore_stats(tower_id)
			net_ore = st.get("total_current", 0.0)
		# Режим трата: батарея не «выдаёт» руду по скорости — её хранилище доступно сети как источник, потребители списывают сами
		var effective_discharge = manual_discharge or (net_ore < 10.0) or (storage >= storage_max)
		if effective_discharge:
			pass  # Ничего не делаем за тик; списание идёт через consume_from_power_source в combat/volcano/beacon/auriga
		else:
			# Режим добыча: из сети забираем 0.05, в хранилище всегда добавляем 0.1 за тик (остальное — бонус накопителя)
			var from_network = 0.0
			if consume_rate > 0.0 and energy_network and energy_network.has_method("get_network_ore_stats"):
				var st = energy_network.get_network_ore_stats(tower_id)
				var ore_ids = st.get("ore_ids", [])
				if ore_ids.size() > 0:
					var remaining = consume_rate
					ore_ids.sort_custom(func(a, b):
						var ra = ecs.ores.get(a, {}).get("current_reserve", 0.0)
						var rb = ecs.ores.get(b, {}).get("current_reserve", 0.0)
						return ra > rb
					)
					var depleted_ore_ids: Array = []
					for oid in ore_ids:
						if remaining <= 0.0:
							break
						var o = ecs.ores.get(oid)
						if not o:
							continue
						var cur = o.get("current_reserve", 0.0)
						if cur < Config.ORE_DEPLETION_THRESHOLD:
							continue
						var deduct = minf(remaining, cur)
						o["current_reserve"] = maxf(0.0, cur - deduct)
						from_network += deduct
						remaining -= deduct
						GameManager.record_ore_spent(deduct, o.get("sector", 0))
						if o["current_reserve"] < Config.ORE_DEPLETION_THRESHOLD:
							depleted_ore_ids.append(oid)
							need_rebuild = true
					for oid in depleted_ore_ids:
						if ecs.ores.has(oid):
							ecs.destroy_entity(oid)
			var success_lv = ecs.game_state.get("success_level", Config.SUCCESS_LEVEL_DEFAULT)
			var charge_mult = Config.get_success_ore_bonus_mult(success_lv)
			tower["battery_storage"] = minf(storage_max, storage + charge_rate * charge_mult)
	if need_rebuild and energy_network and energy_network.has_method("rebuild_energy_network"):
		energy_network.rebuild_energy_network()

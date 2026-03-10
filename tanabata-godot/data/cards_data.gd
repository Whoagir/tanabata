# cards_data.gd
# Определения карт награды за босса (благословения и проклятия)
class_name CardsData
extends RefCounted

const BLESSINGS = [
	{"id": "bless_damage9", "name": "+9 урона", "desc": "Каждая вышка наносит +9 урона"},
	{"id": "bless_attack_speed3", "name": "+3% скорость атаки", "desc": "+3% к скорости атаки всех вышек"},
	{"id": "bless_ore1", "name": "+1 руда майнерам", "desc": "+1 к восстановлению руды у каждого майнера"},
	{"id": "bless_enemy_slow10", "name": "Враги медленнее", "desc": "Враги на 10% медленнее"},
	{"id": "bless_phys20", "name": "+20 физ урона", "desc": "+20 урона вышкам с физической атакой"},
	{"id": "bless_mag20", "name": "+20 маг урона", "desc": "+20 урона вышкам с магической атакой"},
]

# Рарные благословения (отдельный пул, выпадают реже, ярче подсвечиваются)
const RARE_BLESSINGS = [
	{"id": "bless_remove_early_curses", "name": "Снять проклятия", "desc": "Снимает все проклятия с вышек (раннего крафта и касания)"},
]

const CURSES = [
	{"id": "curse_hp_percent", "name": "Кровопускание", "desc": "Вышки наносят 0.4% от макс. HP врага, но тратят +0.5 руды за выстрел"},
	{"id": "curse_split", "name": "Сплит+", "desc": "Сплит-вышки берут +1 цель, но тратят +2 руды за выстрел"},
	{"id": "curse_attack_speed15", "name": "Скорость", "desc": "+15% к скорости атаки вышек"},
]

static func get_blessing_pool() -> Array:
	return BLESSINGS.duplicate()

static func get_curse_pool() -> Array:
	return CURSES.duplicate()

static func get_rare_blessing_pool() -> Array:
	return RARE_BLESSINGS.duplicate()

static func pick_random_rare_blessing() -> Dictionary:
	var pool = get_rare_blessing_pool()
	if pool.is_empty():
		return {}
	return pool[randi() % pool.size()].duplicate()

static func pick_random_blessings(count: int) -> Array:
	var pool = get_blessing_pool()
	var out: Array = []
	for i in range(mini(count, pool.size())):
		var idx = randi() % pool.size()
		out.append(pool[idx])
		pool.remove_at(idx)
	return out

static func pick_random_curse() -> Dictionary:
	var pool = get_curse_pool()
	return pool[randi() % pool.size()].duplicate()

static func get_card_name(card_id: String) -> String:
	for c in BLESSINGS:
		if c.get("id", "") == card_id:
			return c.get("name", card_id)
	for c in RARE_BLESSINGS:
		if c.get("id", "") == card_id:
			return c.get("name", card_id)
	for c in CURSES:
		if c.get("id", "") == card_id:
			return c.get("name", card_id)
	return card_id

static func get_card_desc(card_id: String) -> String:
	for c in BLESSINGS:
		if c.get("id", "") == card_id:
			return c.get("desc", "")
	for c in RARE_BLESSINGS:
		if c.get("id", "") == card_id:
			return c.get("desc", "")
	for c in CURSES:
		if c.get("id", "") == card_id:
			return c.get("desc", "")
	return ""

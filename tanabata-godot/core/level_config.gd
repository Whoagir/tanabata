# level_config.gd
# Конфигурация уровней: основная игра и обучение.
# Данные волн/башен/врагов — из DataRepository (waves.json и т.д.).
# Здесь только параметры карты, лимит волн, пошаговые подсказки (steps).

class_name LevelConfig

# Ключи конфига уровня (словарь)
const KEY_MAP_RADIUS = "map_radius"
const KEY_ORE_VEIN_COUNT = "ore_vein_count"
const KEY_WAVE_MAX = "wave_max"      # 0 = без лимита (основная игра)
const KEY_IS_TUTORIAL = "is_tutorial"
const KEY_TUTORIAL_INDEX = "tutorial_index"
const KEY_TITLE = "title"
const KEY_HINTS = "hints"            # устаревшее, используем KEY_STEPS
const KEY_CHECKPOINT_COUNT = "checkpoint_count"  # -1 = 6, 0 = пустая карта (без чекпоинтов)
const KEY_STEPS = "steps"            # массив { "trigger": "id", "message": "текст" }
const KEY_ORE_CONSUMPTION_MULTIPLIER = "ore_consumption_multiplier"  # только для обучения (гиперболизация траты руды)

# Триггеры пошаговых подсказок
const TRIGGER_GAME_START = "game_start"
const TRIGGER_TOWERS_5 = "towers_5"
const TRIGGER_PHASE_SELECTION = "phase_selection"
const TRIGGER_TOWERS_SAVED_2 = "towers_saved_2"
const TRIGGER_PHASE_WAVE = "phase_wave"
const TRIGGER_WAVE_STARTED = "wave_started"
const TRIGGER_MINER_ON_ORE = "miner_on_ore"
const TRIGGER_MINERS_3_ON_ORE = "miners_3_on_ore"  # три майнера на руде
const TRIGGER_MINERS_2_ON_ORE = "miners_2_on_ore"  # два майнера на руде (уровень 1 — выдаётся Б А Б А А)
const TRIGGER_ATTACKER_CONNECTED = "attacker_connected"
const TRIGGER_ORE_DEPLETES = "ore_depletes"
const TRIGGER_PHASE_BUILD_AFTER_WAVE = "phase_build_after_wave"  # снова фаза строительства после волны (уровень 0)
const TRIGGER_NONE = "none"  # не переключать шаг (последнее сообщение остаётся)

# Радиус карты в основной игре (из Config)
static func get_default_map_radius() -> int:
	return Config.MAP_RADIUS

# Конфиг основной игры (текущее поведение)
static func get_main_config() -> Dictionary:
	return {
		KEY_MAP_RADIUS: get_default_map_radius(),
		KEY_ORE_VEIN_COUNT: 3,
		KEY_WAVE_MAX: 0,
		KEY_IS_TUTORIAL: false,
		KEY_CHECKPOINT_COUNT: -1,
		KEY_TITLE: "",
		KEY_HINTS: [],
		KEY_STEPS: []
	}

# Уровень 0 — Основы: пустая маленькая карта без чекпоинтов, «за руку»
# Цель этапа: рассказать про фазы и про существование майнеров. Только атакующие башни (тип А), без майнера первой постановкой.
static func _steps_level0() -> Array:
	return [
		{ "trigger": TRIGGER_TOWERS_5, "message": "Фаза СТРОИТЕЛЬСТВА. Поставь 5 башен на карту — кликай ЛКМ по пустому гексу. Сейчас появятся только атакующие башни (случайного типа)." },
		{ "trigger": TRIGGER_PHASE_SELECTION, "message": "Отлично! Поставил 5 башен. Переключи фазу: нажми на круг-индикатор фазы справа вверху. Фаза сменится на ВЫБОР." },
		{ "trigger": TRIGGER_TOWERS_SAVED_2, "message": "Фаза ВЫБОРА. Выбери 2 башни, которые хочешь сохранить — кликай по ним и нажимай «Сохранить». Остальные 3 превратятся в стены." },
		{ "trigger": TRIGGER_PHASE_WAVE, "message": "Выбрал 2 башни. Перейди к волне — нажми на индикатор фазы справа вверху. Невыбранные башни станут стенами, выбранные останутся." },
		{ "trigger": TRIGGER_NONE, "message": "Фаза ВОЛНЫ. В данной фазе враги бегут от старта к выходу, в предыдущих фазах твоя задача — построить сооружения так, чтобы они не дали врагам пройти." },
		{ "trigger": TRIGGER_NONE, "message": "Враги заспавнились. Следи за здоровьем вверху — если враг дойдёт до выхода, ты теряешь HP. После волны снова наступит фаза строительства." },
		# После первой волны — снова фаза строительства (четвёртая плашка). Триггер NONE — не переключать на шаг 7.
		{ "trigger": TRIGGER_NONE, "message": "Фаза СТРОИТЕЛЬСТВА. Твои вышки должны быть запитаны от руды, для этого есть майнеры, поставь его на руду (синий кружок) и поставь рядом атакующую вышку. Удалять вышки можно ПКМ." },
		{ "trigger": TRIGGER_NONE, "message": "Поставь майнер на руду и атакующие башни рядом. Удалять можно ПКМ. В фазе выбора сохрани нужные, затем перейди к волне и отбей врагов." },
		# Вторая фаза выбора (после второй постройки): майнер сохраняется сам, сохранить нужно атакующую с синей линией
		{ "trigger": TRIGGER_NONE, "message": "Фаза Выбора. Майнер сохраняется автоматически, сохрани вышку что стоит рядом с ним и имеет синюю линию (сеть)." }
	]

# Уровень 1 — Энергия и руда: без чекпоинтов, карта как на уровне 0. Три майнера на 3 руды, линии, передача энергии, трата руды (гиперболизирована).
# Шаги: 3 майнера на руду -> при смене фазы на волну показываем плашку -> волна началась -> конец.
static func _steps_level1() -> Array:
	return [
		{ "trigger": TRIGGER_MINERS_2_ON_ORE, "message": "Нет чекпоинтов — карта как в основах. Сначала тебе даются 2 майнера и 3 атакующие. Поставь майнеры на руду (синие кружки), рядом — атакующие вышки. ЛКМ по гексу с рудой для майнера." },
		{ "trigger": TRIGGER_PHASE_WAVE, "message": "Майнеры могут передавать энергию на расстояние — они и добытчики, и передатчики. Поставь атакующую башню рядом (или в цепочке с майнерами). Майнер питает сеть, каждый выстрел расходует руду. Перейди к волне — нажми на индикатор фазы справа вверху." },
		{ "trigger": TRIGGER_WAVE_STARTED, "message": "Фаза волны. Враги идут к выходу. Руда тратится при каждом выстреле — здесь расход усилен, следи за индикатором «Руда» вверху." },
		{ "trigger": TRIGGER_NONE, "message": "После волны запас руды частично восстановится. Используй это в следующих уровнях." }
	]

# Заглушки шагов для уровней 2–4 (можно расширить позже)
static func _steps_level2() -> Array:
	return [
		{ "trigger": TRIGGER_TOWERS_5, "message": "Поставь 5 башен. В фазе выбора сохрани 2 — остальные станут стенами и перекроют путь врагам. Продумай, где оставить башни." },
		{ "trigger": TRIGGER_WAVE_STARTED, "message": "Стены блокируют путь. Враги обходят их. Отбей волну." },
		{ "trigger": TRIGGER_NONE, "message": "Уровень «Стены и выбор» — невыбранные башни становятся стенами." }
	]

static func _steps_level3() -> Array:
	return [
		{ "trigger": TRIGGER_PHASE_WAVE, "message": "Три башни рядом по рецепту подсвечиваются — их можно скрафтить в одну. Нажми B — книга рецептов. Например: TA + PA + NI = Сильвер. Поставь башни, выбери 2 и перейди к волне." },
		{ "trigger": TRIGGER_NONE, "message": "Отбей волну, при необходимости используй крафт в следующих раундах." }
	]

static func _steps_level4() -> Array:
	return [
		{ "trigger": TRIGGER_NONE, "message": "Практика: первые 10 волн основной игры на уменьшенной карте. Применяй всё, чему научился." }
	]

# Уровни обучения
static func get_tutorial_levels() -> Array:
	return [
		# 0: Основы — пустая карта без чекпоинтов, пошагово: фаза строительства → 5 башен → смена фазы → выбор 2 → волна
		{
			KEY_MAP_RADIUS: 8,
			KEY_ORE_VEIN_COUNT: 3,
			KEY_WAVE_MAX: 2,
			KEY_IS_TUTORIAL: true,
			KEY_TUTORIAL_INDEX: 0,
			KEY_CHECKPOINT_COUNT: 0,
			KEY_TITLE: "Основы",
			KEY_HINTS: [],
			KEY_STEPS: _steps_level0()
		},
		# 1: Энергия и руда — без чекпоинтов, карта как уровень 0, 3 жилы руды, 3 майнера, гиперболизированная трата руды
		{
			KEY_MAP_RADIUS: 8,
			KEY_ORE_VEIN_COUNT: 3,
			KEY_WAVE_MAX: 2,
			KEY_IS_TUTORIAL: true,
			KEY_TUTORIAL_INDEX: 1,
			KEY_CHECKPOINT_COUNT: 0,
			KEY_TITLE: "Энергия и руда",
			KEY_ORE_CONSUMPTION_MULTIPLIER: 5,
			KEY_HINTS: [],
			KEY_STEPS: _steps_level1()
		},
		# 2: Стены и выбор
		{
			KEY_MAP_RADIUS: 11,
			KEY_ORE_VEIN_COUNT: 4,
			KEY_WAVE_MAX: 3,
			KEY_IS_TUTORIAL: true,
			KEY_TUTORIAL_INDEX: 2,
			KEY_CHECKPOINT_COUNT: -1,
			KEY_TITLE: "Стены и выбор",
			KEY_HINTS: [],
			KEY_STEPS: _steps_level2()
		},
		# 3: Крафт
		{
			KEY_MAP_RADIUS: 11,
			KEY_ORE_VEIN_COUNT: 4,
			KEY_WAVE_MAX: 3,
			KEY_IS_TUTORIAL: true,
			KEY_TUTORIAL_INDEX: 3,
			KEY_CHECKPOINT_COUNT: -1,
			KEY_TITLE: "Крафт",
			KEY_HINTS: [],
			KEY_STEPS: _steps_level3()
		},
		# 4: Практика
		{
			KEY_MAP_RADIUS: 9,
			KEY_ORE_VEIN_COUNT: 3,
			KEY_WAVE_MAX: 10,
			KEY_IS_TUTORIAL: true,
			KEY_TUTORIAL_INDEX: 4,
			KEY_CHECKPOINT_COUNT: -1,
			KEY_TITLE: "Практика",
			KEY_HINTS: [],
			KEY_STEPS: _steps_level4()
		}
	]

# Получить конфиг уровня обучения по индексу (0..4)
static func get_tutorial_level(index: int) -> Dictionary:
	var levels = get_tutorial_levels()
	if index < 0 or index >= levels.size():
		return get_main_config()
	return levels[index]

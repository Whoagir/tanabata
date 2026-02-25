# Слои архитектуры и паттерны проектирования

Аналогия с веб-приложением: есть «ручки» (ввод и отображение), слой приложения (сценарии использования), доменная логика и инфраструктура. Ниже — как это устроено в проекте и какие паттерны используются.

---

## Аналогия с веб-приложением

| Веб | Tanabata (Godot) |
|-----|------------------|
| **HTTP handlers / Controllers** | Точки ввода и UI: `game_root.gd` (_unhandled_input, _input), `game_hud.gd`, `info_panel.gd` — принимают клики/клавиши и решают, куда передать |
| **Application layer / Use cases** | Оркестрация: `GameManager` (загрузка данных, создание игрока, стен, руды), `InputSystem` (команды «поставить башню», «выбрать башню») — координируют домен и не содержат правил игры |
| **Domain / Business logic** | ECS + системы: `ecs_world.gd`, `*_system.gd` (wave, movement, combat, projectile, aura, status_effect, energy_network, ore_generation), `hexmap`, `game_types.gd` — правила игры, без Godot и без прямого I/O |
| **Data access / Config** | Конфиг и данные: `config.gd` (константы, `load_json`), JSON в `data/`, определения башен/врагов/волн в `GameManager` (tower_defs, get_tower_def, get_wave_def) |
| **Rendering / Adapters** | `godot_adapter/rendering/*` — читают состояние из ECS и рисуют в Godot (EntityRenderer, WallRenderer, OreRenderer и т.д.). Аналог «сериализации в ответ» — преобразование доменного состояния в картинку |

---

## Слои (сверху вниз)

### 1. Presentation (представление)

**Назначение:** принять ввод пользователя и отобразить состояние. Не содержит правил игры.

**Файлы и роли:**

- **scenes/game_root.gd**
  - Перехват ввода: `_unhandled_input` (клики мыши), `_input` (Space, P, I, 1–3, 0).
  - Фильтрация: «клик не в UI» (`_is_ui_area`), «не в InfoPanel».
  - Вызов: `input_system.handle_mouse_click(mouse_pos, button)` — передача в слой приложения.
  - Управление камерой (WASD, zoom) — чисто представление.
  - Хоткеи фазы (Space) и паузы (P) вызывают `_cycle_phase()` и `GameManager.toggle_pause()` — тонкая связка с приложением/доменом.
  - Хранение ссылок на слои (HexLayer, TowerLayer, …) и рендереры; создание систем и рендереров в `_ready()` — композиция корня сцены.
- **godot_adapter/ui/game_hud.gd**
  - Построение UI (здоровье, волна, счётчик башен, убийства, индикатор фазы, кнопки скорости и паузы).
  - Обновление текста из `ecs.game_state` и `ecs.player_states` (чтение — только отображение).
  - Обработчики кнопок: смена фазы, пауза, скорость — вызывают методы GameManager или напрямую меняют `ecs.game_state` и выполняют очистку сущностей/финализацию выбора. Здесь смешаны представление и сценарии перехода фаз (см. EXTENSION_RISKS.md).
- **godot_adapter/ui/info_panel.gd**
  - Показ информации о выбранной сущности (башня/враг) по данным из `ecs`.
  - Кнопки «Сохранить» / переход в WAVE при сохранении двух башен — снова логика перехода фазы и финализации выбора внутри UI.

**Граница:** слой не должен содержать формул урона, правил волн, условий победы/поражения. Сейчас часть логики переходов фаз и очистки сущностей живёт в game_root и game_hud/info_panel — её логично вынести в один оркестратор фаз (Application).

---

### 2. Application (приложение / use cases)

**Назначение:** сценарии использования: «поставить башню», «начать волну», «сменить фазу», «загрузить игру». Координирует домен и данные, но не реализует правила игры.

**Файлы и роли:**

- **autoload/game_manager.gd**
  - Старт игры: создание ECS, карты, игрока, начальных стен, генерация руды, создание EnergyNetworkSystem, загрузка JSON (load_game_data).
  - Данные: хранение tower_defs, enemy_defs, recipe_defs, loot_table_defs, wave_defs; методы get_tower_def, get_wave_def, get_loot_table_for_level — по сути «доступ к данным» для домена и UI.
  - Пауза/скорость: toggle_pause(), изменение game_state["paused"] и time_speed.
  - Сигнал event_dispatched — задел под события; подписчиков нет.
  - Fixed timestep (accumulator, update_simulation) объявлен, но **игровой цикл систем реально вызывается из GameRoot._process** (input_system.update, wave_system.update, …). Массив `systems` в GameManager не заполняется из game_root — дублирование концепции «цикла».
- **core/systems/input_system.gd**
  - Приём ввода: `handle_mouse_click` переводит клик в «команду» (place_tower, remove_tower, select_tower, toggle_selection, …) и кладёт в `command_queue`.
  - Выполнение: `update()` достаёт команды из очереди и вызывает `place_tower(hex)`, `select_tower(tower_id)` и т.д. — это уже вызов доменных операций (создание/удаление сущностей, изменение компонентов в ECS).
  - Явная зависимость от GameManager (get_tower_def, info_panel) и от ecs/hex_map — граница между Application и Domain здесь размыта: InputSystem и создаёт сущности в ECS, и знает фазы/лимиты. По идее «сценарий» только координирует, а «как создать башню» и «можно ли ставить» — домен или отдельный фасад.

**Граница:** слой не должен содержать формул боя, движения по гексам, расчёта MST энергосети. Логику «какая башня ставится» (RANDOM_ATTACK, дебаг-режим) и «сколько башен сохранять» лучше держать в одном месте (конфиг + фасад), а не размазывать по InputSystem и UI.

---

### 3. Domain (домен / бизнес-логика)

**Назначение:** правила игры: сущности, компоненты, симуляция волн, движения, боя, энергосети, руды. Без привязки к Godot и к конкретному способу ввода/вывода.

**Файлы и роли:**

- **core/ecs/ecs_world.gd**
  - Хранилище сущностей и компонентов (словари: positions, towers, enemies, projectiles, ores, healths, combat, …).
  - create_entity / destroy_entity, add_component.
  - game_state (phase, current_wave, towers_built_this_phase, total_enemies_killed, paused, time_speed) — глобальное состояние одной партии.
  - init_game_state() — инициализация ключей состояния.
- **core/systems/*.gd**
  - **wave_system:** спавн врагов по волнам (get_wave_def через GameManager), создание сущностей врагов с path, health, enemy def.
  - **movement_system:** движение по path, обновление positions, достижение чекпоинта/базы (урон игроку).
  - **combat_system:** поиск целей, создание снарядов/лазеров, нанесение урона, применение slow/poison, инкремент total_enemies_killed.
  - **projectile_system:** полёт снарядов, попадание по врагу, урон, уничтожение сущностей.
  - **status_effect_system:** таймеры slow/poison, урон по времени.
  - **aura_system:** расчёт aura_effects от башен с аурой (скорость врагов).
  - **energy_network_system:** построение графа башен, MST, энерголинии, активность майнеров на руде, деградация по цепям.
  - **ore_generation_system:** процедурная генерация руды на карте (вызывается при старте из GameManager).
- **core/hexmap/*.gd**
  - Hex, HexMap: геометрия гексов, соседи, путь, чекпоинты, get_tile, set_tile, get_tower_id, passable, генерация начальных стен.
- **core/types/game_types.gd**
  - Энумы и константы: GamePhase, TowerType, AttackType, DamageType, EventType; INVALID_ENTITY_ID — общий контракт для всех слоёв.
- **core/utils/union_find.gd**
  - Структура данных для объединения компонент связности (энергосеть).

**Граница:** слой не обращается к Node, SceneTree, файлам (кроме через переданные параметры). Загрузка определений (get_tower_def, get_wave_def) вызывается из систем через GameManager — зависимость «домен → приложение/данные» в одну сторону допустима; лучше бы фасад «данные для симуляции» с минимальным API.

---

### 4. Infrastructure (инфраструктура)

**Назначение:** константы, загрузка файлов, отрисовка состояния в движке.

**Файлы и роли:**

- **autoload/config.gd**
  - Константы: экран, гекс, карта, тик, здоровье, лимиты башен, энергосеть, руда, враги, снаряды, цвета, пути к JSON.
  - load_json(path) — чтение файлов.
  - Визуальные флаги (visual_debug_mode) — для отладки.
- **data/*.json**
  - Определения башен, врагов, рецептов, loot tables, волн — «сырые» данные, которые обрабатывает GameManager и отдаёт домену/UI через tower_defs, get_wave_def и т.д.
- **godot_adapter/rendering/*.gd**
  - **entity_renderer:** по ecs.towers, ecs.enemies, ecs.projectiles создаёт/обновляет Node2D (Polygon2D, Line2D), пулы врагов и снарядов, подсветка выбора и майнеров на руде.
  - **wall_renderer:** отрисовка стен по ecs.towers (type WALL) и карте.
  - **ore_renderer:** отрисовка руды по ecs.ores.
  - **energy_line_renderer:** линии энергосети по ecs.energy_lines и positions.
  - **aura_renderer:** визуал аур по ecs.auras и positions.
  - **tower_preview:** превью башни под курсором при размещении.
- **godot_adapter/utils (если есть)** — например Object Pool для нод (NodePool).

Рендереры только читают ECS и карту (GameManager.ecs, GameManager.hex_map), не меняют логическое состояние игры — это корректная односторонняя зависимость Infrastructure → Domain (чтение).

---

## Поток данных (упрощённо)

1. **Ввод:** мышь/клавиатура → `game_root` (_input / _unhandled_input) → проверка UI-зоны → `input_system.handle_mouse_click` (или хоткей фазы/паузы).
2. **Команда:** InputSystem кладёт в command_queue команду (place_tower, select_tower, …); в следующем кадре `input_system.update()` выполняет её, вызывая методы, которые меняют ECS (create_entity, add_component, hex_map.set_tile и т.д.).
3. **Симуляция:** в `game_root._process` по очереди вызываются wave_system.update, movement_system.update, status_effect_system.update, aura_system.update, combat_system.update, projectile_system.update. Energy network пересчитывается при изменении башен (из InputSystem при place_tower/remove_tower). Все системы читают/пишут только ECS и hex_map.
4. **Отрисовка:** каждый кадр entity_renderer, wall_renderer, ore_renderer, energy_line_renderer, aura_renderer, tower_preview в _process / _physics_process читают ecs и hex_map и обновляют ноды в сцене.
5. **UI:** game_hud и info_panel в _process или по сигналам читают ecs.game_state, ecs.player_states, ecs.towers и обновляют подписи/кнопки.

Итого: ввод → Presentation → Application (InputSystem, при необходимости GameManager) → Domain (ECS + системы) → состояние обновлено; Presentation и Infrastructure читают состояние и рисуют/показывают UI.

---

## Паттерны проектирования

| Паттерн | Где используется |
|--------|-------------------|
| **Singleton (Autoload)** | `GameManager`, `Config` — одна точка доступа к данным, конфигу и ECS/hex_map. |
| **ECS (Entity-Component-System)** | `ecs_world.gd` — сущности и компоненты; системы в `core/systems/` — логика без наследования, данные в словарях. |
| **Command / Очередь команд** | `InputSystem.command_queue`: клик превращается в команду (place_tower, select_tower, …), выполняется в update() — батчинг и отложенное выполнение. |
| **Object Pool** | `NodePool` в entity_renderer для врагов и снарядов — переиспользование нод вместо создания/удаления. |
| **Data-driven design** | Башни, враги, волны заданы в JSON; код обращается по id (get_tower_def, get_wave_def). Логика типов частично в данных (type, attack_type), частично в жёстких if по строке (см. EXTENSION_RISKS.md). |
| **Adapter** | Папка `godot_adapter/`: рендереры адаптируют доменное состояние (ECS, HexMap) к Godot (Node2D, Polygon2D, Line2D). Core не знает о Godot. |
| **State (простой)** | `game_state` в ECS — один словарь с phase, current_wave, paused, time_speed и т.д. Переходы фаз разбросаны по game_root, game_hud, info_panel (нет единого State Machine объекта). |
| **Repository-like** | Определения (tower_defs, enemy_defs, wave_defs) и методы get_tower_def, get_wave_def в GameManager — аналог доступа к данным без отдельного слоя репозиториев. |

---

## Зависимости между слоями (идеально)

- **Presentation** → Application (вызов handle_mouse_click, toggle_pause, смена фазы через будущий PhaseController).
- **Application** → Domain (вызов ECS и систем), Application → Infrastructure/Config (чтение констант и данных).
- **Domain** → только типы (GameTypes) и, при необходимости, фасад данных (get_tower_def и т.п. через интерфейс, а не напрямую GameManager).
- **Infrastructure** → Domain (чтение ECS/hex_map для рендера), Infrastructure → Config.

Сейчас: UI и game_root иногда напрямую пишут в `ecs.game_state` и вызывают очистку сущностей — это смещение логики приложения в слой представления. Рекомендация: вынести переходы фаз и связанные действия в один Application-модуль (PhaseController/GameManager), а из UI только вызывать его.

---

## Краткая таблица: файл → слой

| Слой | Файлы / папки |
|------|----------------|
| **Presentation** | scenes/game_root.gd (ввод, камера, композиция), godot_adapter/ui/game_hud.gd, godot_adapter/ui/info_panel.gd |
| **Application** | autoload/game_manager.gd (оркестрация старта, данные, пауза), core/systems/input_system.gd (команды от ввода) |
| **Domain** | core/ecs/ecs_world.gd, core/systems/ (wave, movement, combat, projectile, status_effect, aura, energy_network, ore_generation), core/hexmap/, core/types/game_types.gd, core/utils/union_find.gd |
| **Infrastructure** | autoload/config.gd, data/*.json, godot_adapter/rendering/*.gd, пулы и утилиты рендера |

Так можно ориентироваться при рефакторинге: не тащить доменные правила в UI и не размазывать сценарии использования по разным узлам сцены, а держать границы слоёв и зависимости направленными в одну сторону (вниз: от Presentation к Application к Domain; Infrastructure читает Domain).

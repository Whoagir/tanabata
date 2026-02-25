# Вся документация проекта Tanabata (Godot)

Один общий файл со всем содержимым из папки `docs/`. Исходные файлы не удалены.

---

## Содержание

1. [README (оглавление docs)](#1-readme-оглавление-docs)
1a. [IMPLEMENTED — Итог реализации](#1a-implemented--итог-реализации)
2. [00-overview — Обзор проекта](#2-00-overview--обзор-проекта)
3. [01-architecture — Архитектура](#3-01-architecture--архитектура)
4. [02-ecs — ECS](#4-02-ecs--ecs)
5. [03-game-phases — Фазы игры](#5-03-game-phases--фазы-игры)
6. [04-hexmap — Гексагональная карта](#6-04-hexmap--гексагональная-карта)
7. [05-pathfinding — Поиск пути](#7-05-pathfinding--поиск-пути)
8. [06-systems-input — InputSystem](#8-06-systems-input--inputsystem)
9. [07-systems-wave — WaveSystem](#9-07-systems-wave--wavesystem)
10. [08-systems-movement — MovementSystem](#10-08-systems-movement--movementsystem)
11. [09-systems-combat — CombatSystem](#11-09-systems-combat--combatsystem)
12. [10-systems-projectile — ProjectileSystem](#12-10-systems-projectile--projectilesystem)
13. [11-systems-energy-network — EnergyNetworkSystem](#13-11-systems-energy-network--energynetworksystem)
14. [12-systems-ore-generation — OreGenerationSystem](#14-12-systems-ore-generation--oregenerationsystem)
15. [13-rendering-overview — Рендеринг (обзор)](#15-13-rendering-overview--рендеринг-обзор)
16. [14-rendering-entity — EntityRenderer](#16-14-rendering-entity--entityrenderer)
17. [15-rendering-wall — WallRenderer](#17-15-rendering-wall--wallrenderer)
18. [16-rendering-energy-lines — EnergyLineRenderer](#18-16-rendering-energy-lines--energylinerenderer)
19. [17-rendering-ore — OreRenderer](#19-17-rendering-ore--orerenderer)
20. [18-rendering-tower-preview — TowerPreview](#20-18-rendering-tower-preview--towerpreview)
21. [19-ui-hud — UI и HUD](#21-19-ui-hud--ui-и-hud)
22. [20-game-root — GameRoot](#22-20-game-root--gameroot)
23. [21-data-json — Данные (JSON)](#23-21-data-json--данные-json)
24. [22-config — Config](#24-22-config--config)
25. [23-game-manager — GameManager](#25-23-game-manager--gamemanager)
26. [24-game-types — GameTypes](#26-24-game-types--gametypes)
27. [25-union-find — Union-Find](#27-25-union-find--union-find)
28. [26-node-pool — NodePool](#28-26-node-pool--nodepool)
29. [27-profiler — Profiler](#29-27-profiler--profiler)

---

## 1. README (оглавление docs)

**Файл:** `docs/README.md`

Документация проекта Tanabata (Godot). Описание всех систем и механик проекта. Только текст, без кода.

В корне проекта: **PROJECT_OVERVIEW.md** — краткое описание: о чём игра, что есть, что происходит по шагам.

**Содержание (ссылки на отдельные файлы):** общее (overview, IMPLEMENTED, architecture, ecs, game-phases, game-types), карта и путь (hexmap, pathfinding), системы, рендеринг, UI, данные и конфиг, утилиты.

---

## 1a. IMPLEMENTED — Итог реализации

**Файл:** `docs/IMPLEMENTED.md`

Краткий список реализованного: карта, фазы, энергосеть, руда, волны, движение, бой (PROJECTILE/LASER/AOE/BEACON), статус-эффекты (slow, poison, jade_poison), крафт, Recipe Book (B), Volcano, Lighthouse, Silver, Malachite, Jade. Путь: A* с min-heap, для летающих — условная вставка центра. Снаряды: потиковая донаводка. MVP (бафф урона башен 0–5, +1 за топ по урону за волну, не при пропуске). Уклонение врагов (evasion), способности из ability_definitions.json. DataRepository, баланс в towers.json/waves.json. HUD: топ-5 урона с MVP и подсветкой, руда.

---

## 2. 00-overview — Обзор проекта

**Файл:** `docs/00-overview.md`

### Что это

Tanabata — 2D Tower Defense игра на гексагональной карте. Портируется с версии на Go. Игрок строит башни, выбирает какие сохранить, затем отражает волны врагов.

### Главные идеи

- **Карта** — гексы с точкой входа, выходом и чекпоинтами.
- **Башни** — майнеры (дают энергию), атакующие (стреляют по врагам), стены (блокируют).
- **Энергосеть** — атакующие башни работают только при доступе к энергии от майнеров.
- **Фазы** — строительство → выбор башен → волна врагов → снова строительство.

### Структура проекта

- **core/** — логика, не зависящая от Godot.
- **godot_adapter/** — связка с Godot (рендер, UI, ввод).
- **autoload/** — синглтоны (Config, GameManager, Profiler).
- **data/** — JSON с определениями башен, врагов, волн.
- **scenes/** — главные сцены Godot.

### Поток работы

1. Запуск — загрузка данных, генерация карты и руды, создание энергосети.
2. BUILD — игрок ставит до 5 башен, майнеры должны быть на руде.
3. SELECTION — игрок отмечает 2 башни, остальные превращаются в стены.
4. WAVE — враги идут от входа к выходу, башни стреляют.
5. Когда все враги убиты — снова BUILD.

---

## 3. 01-architecture — Архитектура

**Файл:** `docs/01-architecture.md`

### Слои

#### 1. Core (ядро)

Содержит логику игры без привязки к Godot:

- ECS мир (сущности, компоненты)
- Гексагональная математика
- Генерация карты
- Поиск пути
- Системы: ввод, волны, бой, снаряды, движение, энергосеть, руда

#### 2. Godot Adapter (адаптер)

Связывает core с Godot:

- Рендеринг (башни, враги, снаряды, стены, линии, руда)
- UI (HUD, кнопки, индикаторы)
- Ввод (мышь, клавиатура)
- Пул объектов для оптимизации

#### 3. Autoload (синглтоны)

- **Config** — константы, настройки, формулы.
- **GameManager** — ECS, карта, системы, данные, загрузка.
- **Profiler** — замер времени выполнения (опционально).

### Порядок инициализации

1. Godot загружает autoload-скрипты.
2. GameManager создаёт ECS, карту, загружает JSON.
3. GameManager генерирует руду и создаёт энергосеть.
4. Главная сцена создаёт системы и рендереры.
5. Каждый кадр: ввод → системы → рендер.

### Главный цикл

- Обработка ввода (клики, клавиши).
- Обновление систем (волны, движение, бой, снаряды) с учётом скорости времени.
- Рендеринг (карта, сущности, эффекты).
- Обновление UI.

---

## 4. 02-ecs — ECS

**Файл:** `docs/02-ecs.md`

### Суть

Всё в игре — сущности (entities) с номерами. Свойства задаются компонентами. Логика живёт в системах, которые перебирают сущности по нужным компонентам.

### Сущности

У каждой сущности есть целочисленный ID. При создании ID растёт. Удаление — очистка всех компонентов и удаление из реестра сущностей.

### Основные компоненты

**Базовые:** position, velocity, health (current, max).

**Визуальные:** renderable (цвет, радиус, видимость).

**Башни:** tower (def_id, уровень, гекс, активность, временная/постоянная, выбор, mvp_level 0–5), combat (урон, скорострельность, дальность, перезарядка, тип атаки), turrets (угол поворота).

**Враги:** enemy (def_id, броня, abilities, evasion_chance), path (список гексов пути, текущий индекс).

**Снаряды и эффекты:** projectile (источник, цель, урон, скорость, тип урона), laser (начало, конец, таймер, цвет), damage_flash (таймер).

**Руда:** ore (мощность, текущий и максимальный запас, гекс).

**Энергосеть:** energy_line (ID двух башен, скрыта ли линия).

**Волны:** wave (номер волны, враги для спавна, интервал, таймер, путь).

**Игрок:** player_state (уровень, опыт, здоровье).

**Специальные (реализованы):** slow_effects, poison_effects, jade_poisons (стакающийся яд), aura_effects, beacons, beacon_sectors, volcano_effects.

### Состояние игры

game_state (синглтон): фаза, номер волны, счётчик башен, скорость времени, пауза, total_enemies_killed, debug_tower_type; tower_damage_this_wave, last_wave_tower_damage, last_wave_number, wave_skipped (для MVP только при непропущенной волне).

---

## 5. 03-game-phases — Фазы игры

**Файл:** `docs/03-game-phases.md`

### Три фазы

1. **BUILD** — строительство.
2. **TOWER_SELECTION** — выбор башен.
3. **WAVE** — волна врагов.

Переключение: BUILD → SELECTION → WAVE → BUILD.

### BUILD (строительство)

Игрок ставит башни ЛКМ, удаляет ПКМ. Максимум 5 обычных башен за фазу. Башня только на проходимый тайл с возможностью размещения. Стены не в энергосети. После 5 башен — авто-переход в SELECTION. Режим отладки: 1 — случайная атакующая, 2 — майнер, 3 — стена.

### TOWER_SELECTION (выбор башен)

Игрок кликает по башням, чтобы отметить для сохранения. Нужно выбрать 2 из 5. Клик по индикатору фазы — переход в WAVE. Невыбранные временные башни превращаются в стены, выбранные — постоянные. Майнеры считаются выбранными по умолчанию.

### WAVE (волна)

Спавнятся враги по таймеру. Враги идут по пути через чекпоинты (A*). Башни стреляют. Враги получают урон, умирают. Когда все заспавнены и убиты — волна завершена. Переход: волна завершена → BUILD, счётчик башен сбрасывается.

### Индикатор фазы

Круг справа сверху: синий — BUILD, жёлтый — SELECTION, красный — WAVE. Клик — переход на следующую фазу вручную.

---

## 6. 04-hexmap — Гексагональная карта

**Файл:** `docs/04-hexmap.md`

Осевые координаты (axial) Q, R. S = -(Q+R). Ориентация pointy-top.

**Операции:** гекс ↔ пиксели, расстояние, соседи, линия (для майнеров).

**Tile:** passable, can_place_tower, has_tower, tower_id.

**Генерация:** сетка в радиусе, Entry/Exit на краях, 6 чекпоинтов по кругу, береговые тайлы без размещения башен, выход непроходим, связность обходом.

**Особые гексы:** Entry (спавн), Exit (финиш, урон игроку), Checkpoints (промежуточные цели).

---

## 7. 05-pathfinding — Поиск пути

**Файл:** `docs/05-pathfinding.md`

A* между гексами с min-heap для frontier (O(log n) на шаг). Только проходимые тайлы, стоимость 1.

Путь: Entry → Checkpoint 1 → … → Exit. Собирается из отрезков A*. Башни непроходимы. Летающие: условная вставка центра (если отрезок длиннее следующего; при входе/выходе — если чекпоинт среди двух самых дальних).

Пересчёт: при старте — сразу update_future_path(); при постановке/снятии башни и смене фазы — _request_future_path_update() с дебаунсом 0.08 с.

---

## 8. 06-systems-input — InputSystem

**Файл:** `docs/06-systems-input.md`

Обрабатывает клики и клавиши. Определяет гекс/UI, ставит команды в очередь (place_tower, remove_tower, select_tower, toggle_selection). Команды выполняются по несколько за кадр.

ЛКМ: BUILD — по пустому гексу поставить башню, по башне подсветить; SELECTION — переключить выбор. ПКМ: BUILD — удалить башню.

Экранные координаты → мировые через камеру → гекс. Размещение: проверка фазы, лимита, гекса; тип по логике волн или отладке; создание сущности, тайл, энергосеть. Удаление: сущность из ECS, тайл проходим, сеть пересборка.

Выбор типа: первые 4 волны в блоке 10 — первая майнер, остальные атакующие; следующие 6 — все атакующие. Отладка: 1/2/3.

---

## 9. 07-systems-wave — WaveSystem

**Файл:** `docs/07-systems-wave.md`

Управляет волнами: старт, спавн по таймеру, завершение. Только в фазе WAVE.

Старт: определение волны из JSON, путь через чекпоинты (для летающих — с центром), сущность wave. Спавн: враг с здоровьем (health_multiplier или health_multiplier_flying/ground), abilities, evasion_chance из волны.

Завершение: все заспавнены и нет живых → log_wave_damage_report() (last_wave_tower_damage, +1 MVP первой по урону с mvp < 5, только если не wave_skipped), затем удаление wave и снарядов, фаза → BUILD.

---

## 10. 08-systems-movement — MovementSystem

**Файл:** `docs/08-systems-movement.md`

Передвигает врагов по пути. Только в WAVE.

Путь: path.hexes, path.current_index. Цель — гекс по индексу. Направление к цели, эффективная скорость с учётом slow. Близко к цели — current_index++. Конец пути — урон игроку, destroy_entity. Позиция: pos + direction * (effective_speed * delta). velocity не используется.

---

## 11. 09-systems-combat — CombatSystem

**Файл:** `docs/09-systems-combat.md`

Атака башен: поиск целей, снаряды/лазеры, энергия. Только WAVE, только combat + is_active.

Цели: враги в радиусе (range), живые, сортировка по расстоянию, до split_count. Энергия: майнеры на руде в сети, кэш 0.5 сек, запас >= shot_cost, списание с руды.

PROJECTILE — сущности снарядов, урон с MVP и сетью, roll_evasion перед уроном; split, impact_burst (Malachite), JADE_POISON (Jade). LASER — мгновенный урон с MVP и evasion. Стоимость выстрела для аур из Config (AURA_ORE_COST_FACTOR, AURA_SPEED_ORE_COST_FACTOR). NONE/AREA_OF_EFFECT — Volcano, Lighthouse. Cooldown: 1/fire_rate, учёт aura_effects.

---

## 12. 10-systems-projectile — ProjectileSystem

**Файл:** `docs/10-systems-projectile.md`

Движение снарядов к целям, урон при попадании, вспышки урона, лазеры.

Полный homing (каждый кадр) для осколков Малахита. Потиковая донаводка для остальных: раз в HOMING_TICK_INTERVAL (0.06 с) коррекция направления к цели при расстоянии < HOMING_ACTIVATE_DISTANCE. Попадание — урон с учётом брони. Impact burst (Malachite) — вторичные снаряды с homing. JADE_POISON — стак в jade_poisons. damage_flash 0.2 сек. laser — Line2D на LaserLayer, Config.LASER_DURATION 0.4 с.

---

## 13. 11-systems-energy-network — EnergyNetworkSystem

**Файл:** `docs/11-systems-energy-network.md`

Связывает башни линиями. MINER на руде — источник, ATTACK — потребитель, WALL — не в сети.

Соединения: майнер–майнер до 3 гексов на одной линии; соседи (1 гекс) — любые пары; атакующая–атакующая только соседи.

add_tower_to_network при постановке. Майнер на линии между двумя майнерами — перехват (старая линия удаляется, две новые). При удалении башни — полная пересборка MST по приоритетам (майнер–майнер > майнер–атакер > атакер–атакер), внутри по расстоянию. Поиск источников для атакующей — список ID руд для CombatSystem.

---

## 14. 12-systems-ore-generation — OreGenerationSystem

**Файл:** `docs/12-systems-ore-generation.md`

Процедурная генерация руды. 3 центра (исключая entry, exit, checkpoints). Общая мощность 240–270 распределяется (центральная жила, средняя, дальняя). Центральная — центр + до 3 соседей (4 гекса); остальные — радиус 2. Создаётся ore: power, max_reserve, current_reserve, hex, radius, pulse_rate, is_highlighted. Seed карты для воспроизводимости. Ниже порога 0.1 — истощена, майнер неактивен.

---

## 15. 13-rendering-overview — Рендеринг (обзор)

**Файл:** `docs/13-rendering-overview.md`

Слои: HexLayer, TowerLayer, EnemyLayer, ProjectileLayer, EffectLayer (z_index). Лазеры — на LaserLayer внутри EntityRenderer.

Рендереры: EntityRenderer (башни, враги, снаряды, лазеры, volcano_effects, пулы), WallRenderer, EnergyLineRenderer, OreRenderer, AuraRenderer, TowerPreview. Object pooling.

---

## 16. 14-rendering-entity — EntityRenderer

**Файл:** `docs/14-rendering-entity.md`

Башни: MINER — шестиугольник жёлтый, обводка, синий кружок на руде; ATTACK — круг (цвет из JSON); WALL — WallRenderer. Неактивные затемнены, обводка при выделении.

Враги: квадрат, масштаб по здоровью. Модуляция: damage_flash → jade_poisons (зелёный по стакам) → poison → slow.

Снаряды: круг 16 точек, цвет по типу урона, пул. Лазеры: Line2D на LaserLayer (дочерний узел рендерера), толщина 5 px, Config.LASER_DURATION 0.4 с, _to_vector2 для позиций.

---

## 17. 15-rendering-wall — WallRenderer

**Файл:** `docs/15-rendering-wall.md`

Стены и линии между соседними стенами. Слои: заливка шестиугольников, линии по рёбрам, обводка поверх. «Грязные» гексы при изменении, пересчёт стен и линий. Обводка по внешним рёбрам и линиям соединений.

---

## 18. 16-rendering-energy-lines — EnergyLineRenderer

**Файл:** `docs/16-rendering-energy-lines.md`

Линии из energy_lines (tower1_id, tower2_id, color, is_hidden). Позиции из hex башен. Line2D между центрами, цвет из Config. is_hidden — не рисуются или иначе.

---

## 19. 17-rendering-ore — OreRenderer

**Файл:** `docs/17-rendering-ore.md`

Руда из ECS (ores). Пульсирующая подсветка гексов. Альфа по синусоиде (примерно 20–60%). Позиция hex.to_pixel().

---

## 20. 18-rendering-tower-preview — TowerPreview

**Файл:** `docs/18-rendering-tower-preview.md`

Полупрозрачное превью под курсором. Только BUILD, мышь над картой. Тип из debug_tower_type или логика волн. MINER — треугольник жёлтый, ATTACK — круг оранжевый, WALL — шестиугольник серый. Зелёный — можно поставить, красноватый — нельзя.

---

## 21. 19-ui-hud — UI и HUD

**Файл:** `docs/19-ui-hud.md`

Верхняя панель: здоровье, волна, башни, убийства, кнопка «Рецепты (B)». Индикатор руды: прогресс-бар по оставшейся доле (get_ore_network_totals), подпись «Руда: X / Y»; при наведении на майнер — руда его сети. Индикатор фазы: круг (синий/жёлтый/красный), клик — следующая фаза. Кнопки: скорость (1x, 2x, 4x), пауза. Обновление каждый кадр из game_state и ECS. Переходы по клику: BUILD→SELECTION, SELECTION→WAVE (финализация выбора), WAVE→BUILD.

---

## 22. 20-game-root — GameRoot

**Файл:** `docs/20-game-root.md`

Инициализация: Input, Wave, Movement, Combat, Projectile, StatusEffect, Aura, Crafting, Volcano, Beacon; EntityRenderer, Ore, EnergyLine, Wall, Aura, TowerPreview, HUD, InfoPanel, RecipeBook.

Ввод: Space (фаза), P (пауза), I (дебаг), 1/2/3 (тип башни), 0 (выкл.), Shift+PageUp (профайлер). Мышь в InputSystem если не UI. _is_ui_area. Эффекты: hover гексов, след за курсором (~0.65 сек), дебаг-метки (I). Delta * time_speed для систем.

---

## 23. 21-data-json — Данные (JSON)

**Файл:** `docs/21-data-json.md`

**Правило баланса:** добавление/убавление вышке без явного «коэффициентом» — всегда правки в towers.json (и при необходимости waves.json, enemies.json), не множители в коде.

towers.json, enemies.json, waves.json, recipes.json, loot_tables.json, **ability_definitions.json** (id, name, type способностей). Волны: abilities, evasion_chance, health_multiplier_flying/ground. Загрузка через **DataRepository** (get_tower_def, get_enemy_def, get_wave_def, get_ability_def).

---

## 24. 22-config — Config

**Файл:** `docs/22-config.md`

Экран, гекс, карта, delta limit. Tick rate, здоровье, лимиты башен. **Баланс ауры и спецбашен:** AURA_ORE_COST_FACTOR, AURA_SPEED_ORE_COST_FACTOR, JADE_POISON_REGEN_FACTOR, BEACON_RANGE_MULTIPLIER, BEACON_DAMAGE_BASE_MULT, BEACON_DAMAGE_BONUS_MULT; PATH_ABILITY_DEFINITIONS. Энергосеть, руда, волны, снаряды (потиковая донаводка, LASER_DURATION), вспышки, маяк/вулкан. UI: цвета фаз, индикаторы, цвета снарядов.

---

## 25. 23-game-manager — GameManager

**Файл:** `docs/23-game-manager.md`

Создаёт ECS, HexMap; данные через DataRepository. Путь: update_future_path(), _request_future_path_update() (дебаунс 0.08 с). Руда: get_ore_network_totals(), get_ore_network_ratio(). **Урон и MVP:** on_enemy_took_damage (tower_damage_this_wave), get_mvp_damage_mult(tower_id), roll_evasion(entity_id), get_top5_tower_damage() (mvp_level, is_top1, has_max_mvp), log_wave_damage_report() (+1 MVP первой с mvp < 5 только если не wave_skipped). _deferred_recalculate_crafting(). Доступ к данным через DataRepository. event_dispatched — задел.

---

## 26. 24-game-types — GameTypes

**Файл:** `docs/24-game-types.md`

Фазы: BUILD_STATE, WAVE_STATE, TOWER_SELECTION_STATE. Башни: ATTACK, MINER, WALL. Атаки: PROJECTILE, LASER, AREA_OF_EFFECT (Volcano), BEACON (Lighthouse), NONE. Урон: PHYSICAL, MAGICAL, PURE, SLOW, POISON, INTERNAL. Утилиты: enum→строка, цвет по типу урона.

---

## 27. 25-union-find — Union-Find

**Файл:** `docs/25-union-find.md`

Система непересекающихся множеств для MST в EnergyNetworkSystem. MakeSet, Find, Union. Проверка цикла: оба конца в одном множестве — ребро пропустить.

---

## 28. 26-node-pool — NodePool

**Файл:** `docs/26-node-pool.md`

Пул узлов Godot: acquire (взять/создать), release (вернуть + reset). EntityRenderer — враги и снаряды. Меньше созданий/удалений.

---

## 29. 27-profiler — Profiler

**Файл:** `docs/27-profiler.md`

Автозагрузка: start("имя"), end("имя"), enabled, clear. Системы оборачивают update. has_singleton — если нет Profiler, вызовы пропускаются.

---

*Конец сводного файла. Исходные файлы: `docs/00-overview.md` … `docs/27-profiler.md`, `docs/README.md`.*

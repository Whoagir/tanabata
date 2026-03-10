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
30. [28-game-mechanics — Игровые механики](#30-28-game-mechanics--игровые-механики)
31. [29-logging-analytics — Логирование и аналитика](#31-29-logging-analytics--логирование-и-аналитика)
32. [30-level-config-tutorial — LevelConfig и туториал](#32-30-level-config-tutorial--levelconfig-и-туториал)
33. [31-systems-auriga — Auriga (башня и система)](#33-31-systems-auriga--auriga-башня-и-система)
34. [32-boss-reward-cards — Награда за босса (карты)](#34-32-boss-reward-cards--награда-за-босса-карты)

---

## 1. README (оглавление docs)

**Файл:** `docs/README.md`

Документация проекта Tanabata (Godot). Описание всех систем и механик проекта. Только текст, без кода.

В корне проекта: **PROJECT_OVERVIEW.md** — краткое описание: о чём игра, что есть, что происходит по шагам.

**Содержание (ссылки на отдельные файлы):** общее (overview, IMPLEMENTED, architecture, ecs, game-phases, game-types), карта и путь (hexmap, pathfinding), системы, рендеринг, UI, данные и конфиг, утилиты.

---

## 1a. IMPLEMENTED — Итог реализации

**Файл:** `docs/IMPLEMENTED.md`

Краткий список реализованного: карта, фазы, энергосеть (майнеры и батареи как источники, смешанные ore+battery, get_power_source_reserve/consume_from_power_source), руда, волны, движение, бой (PROJECTILE/LASER/AOE/BEACON), BatterySystem (заряд/разряд батарей), статус-эффекты (slow, poison, jade_poison), крафт, Recipe Book (B), Volcano, Lighthouse, Silver, Malachite, Jade, Battery (NA2+NU2+TOWER_MINER). Вкл/выкл башни вручную (ПКМ или слайдер в InfoPanel); у батареи — режим Добыча/Трата; выключенный майнер только передаёт сеть, не добывает; инкрементальное вкл/выкл без пересборки сети. Путь: A* с min-heap, для летающих — условная вставка центра. Снаряды: потиковая донаводка. MVP (бафф урона башен 0–5, +1 за топ по урону за волну, не при пропуске). Уклонение врагов (evasion), способности из ability_definitions.json. DataRepository, баланс в towers.json, waves.json, wave_balance.json; scripts/balance_tiers.py — урон по ярусу крафта (0: −15%, 1: +7%, 2: +10%); HP врагов: множители из wave_balance.json (волны 4–9, 11–12, 14–16, 21–22, 27, 37–39 и др.); быстрые на 6–9 дополнительно ×0.6 (Config). Реген: таблица Config + regen_scale; в waves.json regen_multiplier_modifier (напр. 12: 0.333, 14: 0.5, 15: 0.4). Завершение волны по alive_enemies_count. DEBUG_TEST_TOWER_IDS: TOWER_QUARTZ, NI3, TA2, TOWER_LAKICHINZ. Snapshot: в начале каждой волны record_wave_snapshot(); при проигрыше в лог выводится массив wave_snapshots (JSON). HUD: счётчики, топ-5, руда, длина пути, уровень успеха, блок батареи.

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
5. Когда все враги заспавнены и нет живых (убиты или дошли до выхода) — снова BUILD.

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
- Системы: ввод, волны, бой, снаряды, движение, энергосеть, руда, статус-эффекты, крафт, вулкан, маяк, аурига (Auriga), редактор энерголиний (LineDragHandler)

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

game_state (синглтон): фаза, номер волны, счётчик башен, скорость времени, пауза, total_enemies_killed, debug_tower_type; tower_damage_this_wave, last_wave_tower_damage, last_wave_number, wave_skipped (для MVP только при непропущенной волне); alive_enemies_count (для HUD и завершения волны; +1 при спавне, −1 в kill_enemy и при выходе врага); wave_snapshots (массив снимков по волнам для симуляций, при проигрыше выводится в лог); game_over (проигрыш при HP <= 0, меню конца игры); developer_mode (I — кликабельный индикатор фазы, HP <= 0 не завершает игру).

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

Игрок кликает по башням, чтобы отметить для сохранения. Нужно выбрать 2 из 5. В режиме разработчика (I) клик по индикатору фазы — переход в WAVE. Невыбранные временные башни превращаются в стены, выбранные — постоянные. Майнеры считаются выбранными по умолчанию.

### WAVE (волна)

Спавнятся враги по таймеру. Враги идут по пути через чекпоинты (A*). Башни стреляют. Враги получают урон, умирают. Когда все заспавнены и убиты — волна завершена. Переход: волна завершена → BUILD, счётчик башен сбрасывается.

### Индикатор фазы

Круг справа сверху: синий — BUILD, жёлтый — SELECTION, красный — WAVE. В режиме разработчика (I) клик — переход на следующую фазу вручную; в обычном режиме индикатор не кликабелен.

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

ЛКМ: BUILD — по пустому гексу поставить башню, по башне подсветить; SELECTION — переключить выбор. ПКМ: BUILD — удалить башню; WAVE/SELECTION — по башне (не стена) toggle_tower_enabled (вкл/выкл); у батареи переключатель Добыча/Трата в InfoPanel.

Экранные координаты → мировые через камеру → гекс. Размещение: проверка фазы, лимита, гекса; тип по логике волн или отладке; создание сущности, тайл, энергосеть. Удаление: сущность из ECS, тайл проходим, сеть пересборка.

Выбор типа: первые 4 волны в блоке 10 — первая майнер, остальные атакующие; следующие 6 — все атакующие. Отладка: 1/2/3; **6** — тестовая из Config.DEBUG_TEST_TOWER_IDS (TOWER_QUARTZ, NI3, TA2, TOWER_LAKICHINZ); 0 — выкл.

---

## 9. 07-systems-wave — WaveSystem

**Файл:** `docs/07-systems-wave.md`

Управляет волнами: старт, спавн по таймеру, завершение. Только в фазе WAVE.

Старт: record_wave_snapshot(), затем определение волны из JSON, путь через чекпоинты (для летающих — с центром), сущность wave; alive_enemies_count = 0. Спавн: враг с здоровьем (health_multiplier или health_multiplier_flying/ground), abilities, evasion_chance из волны; множители HP из wave_balance.json (волны 5–9, 14–16, 21–22, 27 и др.; быстрые на 6–9 ×0.6); реген из Config (таблица + regen_scale); в enemy — spawned_wave и pure_damage_resistance; alive_enemies_count += 1.

Завершение: все заспавнены и **alive_enemies_count == 0** (счётчик уменьшается в kill_enemy и при достижении выхода в MovementSystem) → log_wave_damage_report() (last_wave_tower_damage, +1 MVP первой по урону с mvp < 5, только если не wave_skipped), затем удаление wave и снарядов, фаза → BUILD.

---

## 10. 08-systems-movement — MovementSystem

**Файл:** `docs/08-systems-movement.md`

Передвигает врагов по пути. Только в WAVE.

Путь: path.hexes, path.current_index. Цель — гекс по индексу. Направление к цели, эффективная скорость с учётом slow. Близко к цели — current_index++. Конец пути — урон игроку, record_enemy_wave_progress/on_enemy_reached_exit, **уменьшение alive_enemies_count** (выход без kill_enemy), destroy_entity. Позиция: pos + direction * (effective_speed * delta). velocity не используется. Экологический урон: руда (ENV_DAMAGE_ORE_PER_TICK), энерголиния — max(1, ore_amount * player_level / 40) (в 8 раз ниже прежнего /5).

---

## 11. 09-systems-combat — CombatSystem

**Файл:** `docs/09-systems-combat.md`

Атака башен: поиск целей, снаряды/лазеры, энергия. Только WAVE, только combat + is_active.

Цели: враги в радиусе (range), живые, сортировка по расстоянию, до split_count. Энергия: источники — жилы (ore) и батареи в режиме разряда (battery); get_power_source_reserve/consume_from_power_source; кэш 0.5 сек, суммарный запас >= shot_cost. Множитель урона только get_network_ore_damage_mult (доля руды в сети), без буста от выбранной жилы.

PROJECTILE — сущности снарядов, урон с MVP и сетью, roll_evasion перед уроном; split, impact_burst (Malachite), JADE_POISON (Jade). LASER — мгновенный урон с MVP и evasion. Стоимость выстрела для аур из Config (AURA_ORE_COST_FACTOR, AURA_SPEED_ORE_COST_FACTOR). NONE/AREA_OF_EFFECT — Volcano, Lighthouse. Cooldown: 1/fire_rate, учёт aura_effects.

---

## 12. 10-systems-projectile — ProjectileSystem

**Файл:** `docs/10-systems-projectile.md`

Движение снарядов к целям, урон при попадании, вспышки урона, лазеры.

Полный homing (каждый кадр) для осколков Малахита. Потиковая донаводка для остальных: раз в HOMING_TICK_INTERVAL (0.06 с) коррекция направления к цели при расстоянии < HOMING_ACTIVATE_DISTANCE. Попадание — урон с учётом брони. Impact burst (Malachite) — вторичные снаряды с homing. JADE_POISON — стак в jade_poisons. damage_flash 0.2 сек. laser — Line2D на LaserLayer, Config.LASER_DURATION 0.4 с.

---

## 13. 11-systems-energy-network — EnergyNetworkSystem

**Файл:** `docs/11-systems-energy-network.md`

Связывает башни линиями. Типы: MINER, BATTERY (на руде или в режиме разряда — источник), ATTACK — потребитель, WALL — не в сети. Корни: майнер на руде; батарея на руде; батарея не на руде — только при разряде (ручная трата или авто: руда в сети < 10 или запас >= storage_max). Соединения майнер/батарея: до 4 (майнер) или 5 (батарея) гексов на одной линии, без другой вышки типа Б между ними. Вкл/выкл вручную (is_manually_disabled); у батареи — режим Добыча/Трата (battery_manual_discharge). get_network_ore_stats — жилы под майнерами и батареями + запас разряжающих батарей; total_max для батарей — текущий storage, не storage_max.

Источники питания _find_power_sources: массив dict {"type":"ore","id":ore_id} и {"type":"battery","id":tower_id}. get_power_source_reserve / consume_from_power_source для Combat, Volcano, Beacon, Auriga. Множитель урона get_network_ore_damage_mult (доля руды в сети). add_tower_to_network, перехват майнер–майнер, полная пересборка MST при удалении. Риски и неочевидное поведение: см. **ENERGY_NETWORK_RISKS_AND_EDGE_CASES.md**.

---

## 14. 12-systems-ore-generation — OreGenerationSystem

**Файл:** `docs/12-systems-ore-generation.md`

Процедурная генерация руды. 3 центра (исключая entry, exit, checkpoints). Общая мощность 240–270: центральная жила (до 4 гексов), средняя — строго 6–8 гексов (радиус 2…15 до набора 6+ без чекпоинтов), распределение по гексам напрямую, доля 28–32%, сумма в 2 раза больше (множитель), разброс внутри жилы 65%; крайняя — радиус 2, лимит 60 на гекс. Создаётся ore: power, max_reserve, current_reserve, hex, radius, pulse_rate, is_highlighted, sector. Seed карты для воспроизводимости. Ниже порога 0.1 — истощена, майнер неактивен.

---

## 15. 13-rendering-overview — Рендеринг (обзор)

**Файл:** `docs/13-rendering-overview.md`

Слои: HexLayer, TowerLayer, EnemyLayer, ProjectileLayer, EffectLayer (z_index). Лазеры — на LaserLayer внутри EntityRenderer.

Рендереры: EntityRenderer (башни, враги, снаряды, лазеры, volcano_effects, пулы), WallRenderer, EnergyLineRenderer, OreRenderer, AuraRenderer, TowerPreview. Object pooling.

---

## 16. 14-rendering-entity — EntityRenderer

**Файл:** `docs/14-rendering-entity.md`

Башни: MINER — шестиугольник жёлтый, обводка, синий кружок на руде; BATTERY — шестиугольник с красной обводкой (radius_factor 0.65), «вкл» = режим Добыча, «выкл» = режим Трата (is_visually_on = not battery_manual_discharge); ATTACK — круг (цвет из JSON); WALL — WallRenderer. Неактивные затемнены, обводка при выделении.

Враги: квадрат, масштаб по здоровью. Модуляция: damage_flash → jade_poisons (зелёный по стакам) → poison → slow.

Снаряды: круг 16 точек, цвет по типу урона, пул. Лазеры: Line2D на LaserLayer (дочерний узел рендерера), толщина 5 px, Config.LASER_DURATION 0.4 с, _to_vector2 для позиций.

---

## 17. 15-rendering-wall — WallRenderer

**Файл:** `docs/15-rendering-wall.md`

Стены и линии между соседними стенами. Слои: заливка шестиугольников, линии по рёбрам, обводка поверх. «Грязные» гексы при изменении, пересчёт стен и линий. Обводка по внешним рёбрам и линиям соединений.

---

## 18. 16-rendering-energy-lines — EnergyLineRenderer

**Файл:** `docs/16-rendering-energy-lines.md`

Линии из energy_lines (tower1_id, tower2_id, color, is_hidden). Позиции из hex башен. Line2D между центрами, цвет из Config. Батареи участвуют в линиях по тем же правилам, что и майнеры (та же линия, радиус из def). is_hidden — не рисуются при перетаскивании (режим U).

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

InfoPanel: при выборе башни/врага/руды — название, описание, скиллы, кнопки. В заголовке башни (кроме стены): переключатель вкл/выкл — 50 px правее названия, слайдер в стиле «замок в самолёте» (влево = выкл, вправо = вкл), приглушённые зелёный/красный; у **батареи** слайдер = Добыча/Трата (battery_manual_discharge), отдельный блок _add_battery_info (запас, режим); то же по ПКМ по башне в WAVE/SELECTION. Верхняя панель: здоровье, волна, башни, убийства, живые враги (alive_enemies_count), кнопка «Рецепты (B)». Индикатор руды: по одному прогресс-бару на каждую сеть с рудой (при старте без вышек баров нет), под каждым баром подпись «X / Y»; синий при руде >= 10, красный при < 10, мигание при < 3; при наведении на майнер — руда его сети. Индикатор фазы: круг (синий/жёлтый/красный); клик переключает фазу только в режиме разработчика (I). Кнопки: скорость (1x, 2x, 4x), пауза. Меню конца игры: при HP <= 0 — модальный Popup (очки, убийства, «Начать заново», «В меню»), фон тёмно-синий как в главном меню. Обновление счётчиков и топ-5 до 4 раз в секунду (троттл); FPS — каждый кадр. Переходы по клику (в режиме разработчика): BUILD→SELECTION, SELECTION→WAVE, WAVE→BUILD.

---

## 22. 20-game-root — GameRoot

**Файл:** `docs/20-game-root.md`

Инициализация: Input, Wave, Movement, Combat, Projectile, StatusEffect, Aura, Crafting, Volcano, Beacon, BatterySystem, AurigaSystem, LineDragHandler; EntityRenderer, Ore, EnergyLine, AttackLink, CraftingVisual, Wall, Aura, PathOverlay, TowerPreview, HUD, InfoPanel, RecipeBook, BossRewardOverlay, GameOverOverlay.

Ввод: P (пауза), I (режим разработчика: дебаг + кликабельный индикатор фазы + HP <= 0 не завершает игру), 1/2/3/6 (тип башни: 6 — тестовая из DEBUG_TEST_TOWER_IDS: TOWER_QUARTZ, NI3, TA2, TOWER_LAKICHINZ), 0 (выкл.), Shift+PageUp (профайлер). Мышь в InputSystem если не UI. _is_ui_area. Конец игры: при HP <= 0 (не в режиме I) — game_over, меню с очками и кнопками. Эффекты: hover гексов, след за курсором (~0.65 сек), дебаг-метки (I). Delta * time_speed для систем.

---

## 23. 21-data-json — Данные (JSON)

**Файл:** `docs/21-data-json.md`

**Правило баланса:** добавление/убавление вышке без явного «коэффициентом» — всегда правки в towers.json (и при необходимости waves.json, enemies.json), не множители в коде. **Баланс по ярусам:** скрипт scripts/balance_tiers.py — урон башен по crafting_level (0: −15%, 1: +7%, 2: +10%). HP врагов: в JSON база; множители из wave_balance.json (волны 5–9, 14–16, 21–22, 27 и др.; быстрые на 6–9 ×0.6). Реген — таблица по волнам в Config + regen_scale; в waves.json regen_multiplier_modifier (12, 14, 15 и др.).

towers.json, enemies.json, waves.json, recipes.json, loot_tables.json, **ability_definitions.json** (id, name, type способностей). Волны: abilities, evasion_chance, health_multiplier_flying/ground. Загрузка через **DataRepository** (get_tower_def, get_enemy_def, get_wave_def, get_ability_def).

---

## 24. 22-config — Config

**Файл:** `docs/22-config.md`

Экран, гекс, карта, delta limit. Tick rate, здоровье, лимиты башен. **Баланс ауры и спецбашен:** AURA_ORE_COST_FACTOR, AURA_SPEED_ORE_COST_FACTOR, JADE_POISON_REGEN_FACTOR, BEACON_RANGE_MULTIPLIER, BEACON_DAMAGE_BASE_MULT, BEACON_DAMAGE_BONUS_MULT; PATH_ABILITY_DEFINITIONS. Энергосеть, руда, волны, снаряды (потиковая донаводка, LASER_DURATION), вспышки, маяк/вулкан. **DEBUG_TEST_TOWER_IDS** — массив для клавиши 6 (TOWER_QUARTZ, NI3, TA2, TOWER_LAKICHINZ). UI: цвета фаз, индикаторы, цвета снарядов.

---

## 25. 23-game-manager — GameManager

**Файл:** `docs/23-game-manager.md`

Создаёт ECS, HexMap; данные через DataRepository. Путь: update_future_path(), _request_future_path_update() (дебаунс 0.08 с). Руда: get_ore_network_totals(), get_ore_network_ratio(). **Проклятия и PURE:** get_curse_extra_ore_per_shot() (0.5 при curse_hp_percent), get_pure_damage_resistance(entity_id) для снижения PURE-урона по врагу. **Урон и MVP:** on_enemy_took_damage (tower_damage_this_wave), get_mvp_damage_mult(tower_id), roll_evasion(entity_id), get_top5_tower_damage() (mvp_level, is_top1, has_max_mvp), log_wave_damage_report() (+1 MVP первой с mvp < 5 только если не wave_skipped). _deferred_recalculate_crafting(). Доступ к данным через DataRepository. event_dispatched — задел.

---

## 26. 24-game-types — GameTypes

**Файл:** `docs/24-game-types.md`

Фазы: BUILD_STATE, WAVE_STATE, TOWER_SELECTION_STATE. Башни: ATTACK, MINER, BATTERY, WALL. Атаки: PROJECTILE, LASER, AREA_OF_EFFECT (Volcano), BEACON (Lighthouse), NONE. Урон: PHYSICAL, MAGICAL, PURE, SLOW, POISON, INTERNAL. Утилиты: enum→строка, цвет по типу урона.

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

## 30. 28-game-mechanics — Игровые механики

**Файл:** `docs/28-game-mechanics.md`

Краткое описание игры и полный список механик: фазы, размещение/выбор башен, типы башен и атак, энергосеть, руда (в т.ч. фиксированное восстановление за волну, основная сеть), крафт (урон по ярусу: balance_tiers.py — 0: −15%, 1: +7%, 2: +10%; HP врагов: wave_balance.json (волны 5–9, 14–16, 21–22, 27 и др.; быстрые 6–9 ×0.6); реген из Config, в waves.json regen_multiplier_modifier), волны (модификаторы из JSON, pure_damage_resistance; завершение по alive_enemies_count == 0; snapshot в начале каждой волны, при проигрыше — лог wave_snapshots), враги и способности, путь и движение (экологический урон: руда и энерголиния ore×level/40; при выходе врага — alive_enemies_count −1), бой, снаряды, PURE-урон и get_pure_damage_resistance, проклятие curse_hp_percent (+0.5 руды за выстрел), статус-эффекты, Volcano/Beacon, MVP, UI (HUD троттл 4/с, счётчик врагов из game_state), дебаг. Уровни и обучение (LevelConfig, туториал 0–4). Логирование и аналитика (отчёт после волны, сводная таблица, plot_wave_logs.py).

---

## 31. 29-logging-analytics — Логирование и аналитика

**Файл:** `docs/29-logging-analytics.md`

После каждой завершённой волны GameManager выводит в консоль детальный отчёт и сводную таб-таблицу. Папка scripts/: plot_wave_logs.py (matplotlib, numpy) строит PNG по сводке; wave_log.txt — пример лога; balance_tiers.py — баланс по ярусам. docs/wave_charts.html — интерактивные графики (Chart.js), тот же формат данных. Цепочка: лог из игры → файл или вставка в скрипт/HTML → графики. Важно для баланса и анализа на будущее.

---

## 32. 30-level-config-tutorial — LevelConfig и туториал

**Файл:** `docs/30-level-config-tutorial.md`

LevelConfig (core/level_config.gd): ключи конфига уровня (map_radius, ore_vein_count, wave_max, checkpoint_count, steps), триггеры подсказок (towers_5, miner_on_ore, wave_started и др.). Основная игра — get_main_config(). Уровни обучения 0–4: Основы, Энергия и руда, Стены и выбор, Крафт, Практика. get_tutorial_level(index).

---

## 33. 31-systems-auriga — Auriga (башня и система)

**Файл:** `docs/31-systems-auriga.md`

Auriga — атакующая башня (TOWER_AURIGA): линия урона до 5 гексов в одном из 6 направлений. AurigaSystem обновляет направление по количеству врагов на линии, поворот замедлен. Данные в ecs.auriga_lines; отрисовка в EntityRenderer. Механика будет развиваться.

---

## 34. 32-boss-reward-cards — Награда за босса (карты)

**Файл:** `docs/32-boss-reward-cards.md`

После убийства босса (ENEMY_BOSS) показывается BossRewardOverlay: три карты (две благословения, одна проклятие). Данные в CardsData (data/cards_data.gd): BLESSINGS, RARE_BLESSINGS, CURSES. Выбор карты применяет эффект, затем clear_pending_boss_cards().

---

*Конец сводного файла. Исходные файлы: `docs/00-overview.md` … `docs/32-boss-reward-cards.md`, `docs/README.md`.*

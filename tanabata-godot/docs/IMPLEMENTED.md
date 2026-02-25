# Реализовано (итог)

Краткий список того, что уже работает в проекте.

## Основной геймплей

- **Карта** — гексы (pointy-top), процедурная генерация (Entry, Exit, 6 чекпоинтов).
- **Путь врагов** — A* через чекпоинты (frontier в min-heap для скорости); пересчёт с дебаунсом 0.08 с при постановке/снятии башни и смене фазы. Для летающих — условная вставка центра между чекпоинтами (если отрезок длиннее следующего) и при входе/выходе (если чекпоинт среди двух самых дальних от входа/выхода).
- **Фазы** — BUILD (5 башен) → TOWER_SELECTION (2 сохранить) → WAVE → BUILD. Пропуск волны (переход WAVE→BUILD вручную) не даёт MVP.
- **Энергосеть** — майнеры на руде = источники; атакующие только при подключении (MST). Множитель урона от доли руды в сети (мало руды — до 1.5×).
- **Руда** — 3 жилы, расход при выстрелах, истощение. HUD: прогресс-бар по оставшейся доле (current/max по всем жилам), подпись «Руда: X / Y»; при наведении на майнер — руда только его сети.
- **MVP** — у каждой башни уровень 0–5: +20% урона за уровень (5 = ×2). В конце волны (если волна не пропущена) +1 MVP получает первая по урону башня с mvp < 5. При крафте — среднее арифметическое по комбинации, округление вверх, макс 5.
- **UI** — HUD, InfoPanel, индикатор фазы, скорость (1x/2x/4x), пауза. Топ-5 урона вышек: отображение «Имя MVP N», красная подсветка для топа по урону и для MVP 5.

## Системы

- **InputSystem** — клики (размещение/удаление/выбор башен).
- **WaveSystem** — спавн врагов по таймеру.
- **MovementSystem** — движение по пути, учёт slow и jade_poison.
- **CombatSystem** — поиск целей, снаряды/лазеры, энергия; урон с учётом MVP (get_mvp_damage_mult); проверка уклонения (roll_evasion); стоимость выстрела для аур из Config (AURA_ORE_COST_FACTOR, AURA_SPEED_ORE_COST_FACTOR).
- **ProjectileSystem** — полёт снарядов, урон, потиковая донаводка (раз в 0.06 с при приближении к цели), impact burst (Malachite), JADE_POISON; осколки Малахита — полный homing каждый кадр; при попадании — проверка evasion (визуал есть, урона нет при успехе).
- **StatusEffectSystem** — slow, poison, jade_poison (стакающийся DoT); реген врага под ядом Джейда — множитель из Config (JADE_POISON_REGEN_FACTOR).
- **CraftingSystem** — обнаружение комбинаций соседних башен, крафт в новые типы; тяжёлый пересчёт откладывается при смене фазы.
- **VolcanoSystem** — AoE-урон вокруг башни (4 тика/сек).
- **BeaconSystem** — вращающийся луч Маяка (90°, 24 тика/сек).
- **AuraSystem** — ауры активных башен.

## Башни (уровень 1)

| ID | Тип | Механика |
|----|-----|----------|
| TA, TE, TO | PROJECTILE | Физ./маг./чистый урон |
| PA, PE, PO | PROJECTILE | Сплит (2 цели) |
| NI | PROJECTILE | Замедление |
| **Silver** | LASER | Урон + замедление (50%, 2 сек) |
| **Malachite** | PROJECTILE | Сплит + impact burst (радиус 3 гекса, 6 целей), осколки с homing |
| **Volcano** | AOE | Урон по площади каждые 0.25 сек |
| **Lighthouse** | BEACON | Вращающийся луч 90° |
| **Jade** | PROJECTILE | Стакающийся яд (DoT, замедление по стакам) |

## Крафт и рецепты

- **Recipe Book** — кнопка «Рецепты (B)» в HUD, панель со всеми рецептами (TA+PA+NI=Silver и т.д.).
- **recipes.json** — рецепты (Silver, Malachite, Volcano, Lighthouse, Jade и др.).
- CraftingSystem проверяет соседей (3 гекса), при совпадении заменяет на крафтованную башню.

## Визуал

- **Башни** — круг (базовые) или шестиугольник с золотой обводкой (крафтованные).
- **Враги** — квадрат, масштаб по здоровью; damage_flash (красный), slow (голубой), poison (зелёный).
- **Jade poison** — чем больше стаков, тем насыщеннее зелёный (ENEMY_JADE_POISON_COLOR).
- **Лазеры** — Line2D на LaserLayer (дочерний узел EntityRenderer), толщина 5 px, длительность из Config (0.4 с); позиции приводятся к Vector2 через _to_vector2.
- **Volcano** — огненные круги при тиках на EffectLayer.
- **Object pooling** — враги, снаряды.

## Враги и способности

- **Способности** — в waves.json: abilities (массив id), evasion_chance. В ability_definitions.json — метаданные (id, name, type: passive/active). Уклонение (evasion): при попадании снаряда/лазера/Volcano/Beacon проверяется roll_evasion; при успехе урона нет, визуал попадания есть.
- **Волны** — health_multiplier_flying / health_multiplier_ground для смешанных волн; regen, abilities, evasion_chance задаются в данных.

## Данные и конфиг

- **DataRepository** — автозагрузка: загрузка towers, enemies, waves, recipes, loot_tables, ability_definitions. Доступ: get_tower_def, get_enemy_def, get_wave_def, get_ability_def.
- **Config** — баланс ауры и маяка: AURA_ORE_COST_FACTOR, AURA_SPEED_ORE_COST_FACTOR, JADE_POISON_REGEN_FACTOR, BEACON_RANGE_MULTIPLIER, BEACON_DAMAGE_BASE_MULT, BEACON_DAMAGE_BONUS_MULT; PATH_ABILITY_DEFINITIONS.

## Компоненты ECS (активно используются)

- towers (в т.ч. mvp_level), combat, enemies (abilities, evasion_chance), healths, positions, paths, projectiles, lasers.
- slow_effects, jade_poisons, poison_effects.
- volcano_effects, beacons, beacon_sectors.
- damage_flashes, ores, energy_lines, wave.
- game_state: tower_damage_this_wave, last_wave_tower_damage, wave_skipped (для MVP только при непропущенной волне).

## Оптимизации производительности

### ECS

- **Реестр компонентов** (`_component_stores`) — массив ссылок на все хранилища. `destroy_entity()` очищает автоматически циклом вместо 38 ручных `.erase()`. Добавление нового компонента требует только одну строку в `_init()`.
- **`kill_enemy(entity_id)`** — единый метод убийства врага в ECSWorld. Заменяет 6 дублированных мест (projectile, combat, beacon, volcano, status_effect, movement системы).
- **`ore_hex_index`** — пространственный индекс `hex_key → ore_id` для O(1) поиска руды по гексу. Заполняется при генерации руды, используется в 6+ местах вместо линейного перебора всех ores.

### Pathfinding (A*)

- **Int-ключи** — `to_int_key()` / `int_key_from_qr()` для внутренних Dictionary в A* (came_from, cost_so_far, closed). ~3x быстрее String-ключей.
- **Инлайн-соседи** — итерация по `_DIR_Q`/`_DIR_R` массивам вместо `get_neighbors()` (0 аллокаций Hex/Array в основном цикле A*).
- **`is_passable_qr(q, r)`** — проверка проходимости тайла по координатам без создания Hex объекта.
- **`path_exists()`** — A* возвращающий bool без реконструкции пути (без came_from). Используется в `_would_block_path()`.
- **`path_exists_through_checkpoints()`** — проверка существования пути через все чекпоинты с early-exit.
- **Кэш путей в WaveSystem** — ground и flying пути считаются один раз за волну при `start_wave()`, при спавне берутся из кэша.

### Энергосеть

- **`_get_connected_tower_ids()`** — BFS через adjacency list O(V+E) вместо перебора всех energy_lines на каждом шаге O(V×E).
- **`get_miner_efficiency_for_ore()`** и **`get_ore_restore_per_round()`** — O(1) через `hex_map.get_tower_id()` вместо перебора всех towers.
- **`line_hex_set`** — предвычисленный набор гексов на энерголиниях. Пересчитывается при изменении сети. Используется в `_apply_environmental_damage()` для O(1) проверки вместо O(lines × line_length).

### Рендеринг

- **Dirty flags** — `aura_renderer` обновляет круги только при изменении `is_active`/`radius`/`hex`. `path_overlay_layer` перерисовывает только при изменении `hash(future_path)`, cleared_checkpoints или фазы.
- **Dictionary lookup** — лазеры, volcano effects, beacon sectors используют Dictionary (id → node) вместо `get_children()` + парсинг строковых имён.
- **Scale вместо polygon regen** — пульсация руды (ore_renderer) и volcano effects через `node.scale` вместо пересоздания PackedVector2Array каждый кадр.

### Профайлер

- Вызовы `Profiler.start()`/`end()` напрямую (Profiler — autoload с внутренней проверкой `enabled`). Ранее `Engine.has_singleton("Profiler")` всегда возвращал false — профайлер не работал.

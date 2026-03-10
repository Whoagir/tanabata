# Реализовано (итог)

Краткий список того, что уже работает в проекте.

## Основной геймплей

- **Карта** — гексы (pointy-top), процедурная генерация (Entry, Exit, 6 чекпоинтов).
- **Путь врагов** — A* через чекпоинты (frontier в min-heap для скорости); пересчёт с дебаунсом 0.08 с при постановке/снятии башни и смене фазы. Для летающих — условная вставка центра между чекпоинтами (если отрезок длиннее следующего) и при входе/выходе (если чекпоинт среди двух самых дальних от входа/выхода).
- **Фазы** — BUILD (5 башен) → TOWER_SELECTION (2 сохранить) → WAVE → BUILD. Пропуск волны (переход WAVE→BUILD вручную) не даёт MVP.
- **Энергосеть** — майнеры на руде и батареи (на руде или в режиме разряда) = источники; атакующие только при подключении (MST). **Сопротивление сети (resistance):** каждая атакующая вышка на пути до ближайшей типа Б (майнер/батарея) даёт +0.2, кап 1; множитель урона max(0, 1 - resistance); пересчёт при изменении сети. Батарея (TOWER_BATTERY): режим Добыча/Трата, заряд из сети (charge_rate 0.5/с в данных, умножается на get_success_ore_bonus_mult), отдача запаса в сеть; соединения как у майнеров (линия, радиус 5). Источники питания — смешанные (ore + battery), списание через get_power_source_reserve/consume_from_power_source. Множитель урона от доли руды в сети (get_network_ore_damage_mult), до 1.5×, и от сопротивления (get_resistance_mult). **Вкл/выкл майнера:** выключенный майнер перестаёт быть корнем (не добывает), но остаётся передатчиком; на жиле при выключенном майнере восстановление руды +30%. Линии при переключении и при удалении другой башни **не удаляются** по is_active (топология сохраняется; см. docs/ENERGY_NETWORK_LINES_BUG_ANALYSIS.md).
- **Руда** — жилы: центральная (до 4 гексов, множитель CENTRAL_VEIN_POWER_MULT), средняя (6–8 гексов, доля 28–32%, множитель 2×), крайняя (радиус 2, лимит 60); дополнительная точка на серединном перпендикуляре центр–середина, 3 гекса от середины, 15–20 руды. Расход при выстрелах, истощение. Урон от энерголинии при проходе врага: ore_amount × player_level / 40. Восстановление за волну **фиксированное**: до 20 тиков (1 тик/сек), база по уровню майнера 1–5 (1.7, 2.5, 5.2, 9.6, 15), × ORE_RESTORE_GLOBAL_MULT, × get_ore_restore_mult_for_wave, × get_success_ore_bonus_mult(success_level); выключенный майнер даёт на жиле +30%; при короткой волне остаток дополняется в конце. HUD: по одному прогресс-бару на каждую сеть с рудой; под баром «X / Y»; цвет: синий при руде >= 10, красный при < 10, мигание при < 3 (ORE_FLICKER_THRESHOLD). При наведении на майнер — руда его сети. **Основная сеть** — сеть с макс. числом атакующих вышек; в логе после волны — остаток руды в основной сети в %. Таблица EHP по волнам: data/WAVE_HP_TABLE.md (скрипт scripts/wave_hp_table.py).
- **MVP** — у каждой башни уровень 0–5: +20% урона за уровень (5 = ×2). В конце волны (если волна не пропущена) +1 MVP получает первая по урону башня с mvp < 5. При крафте — среднее арифметическое по комбинации, округление вверх, макс 5.
- **UI** — HUD, InfoPanel, индикатор фазы, скорость (1x/2x/4x), пауза. **Стеш (очередь слотов)** — в фазе BUILD слева снизу (y = SCREEN_HEIGHT − 40): отображается **game_state["stash_queue"]** (оставшиеся слоты Б/А); при постановке башни из очереди забирается один слот (pop_front), при снятии майнера/батареи (Б) слот возвращается в начало очереди, при снятии атакующей (А) — не возвращается. Шрифт 17 pt, жирный, увеличенные пробелы между буквами; Б — жёлтый, А — серый. Счётчики (здоровье, волна, башни, убийства, живые враги) и топ-5 урона обновляются до 4 раз в секунду (троттл); счётчик живых врагов из **game_state["alive_enemies_count"]**. Топ-5: «Имя MVP N», красная подсветка для топа и MVP 5. **Переключатель вкл/выкл башни** в InfoPanel: в заголовке, 50 px правее названия, двухпозиционный слайдер (тип замок в самолёте); ПКМ по башне в WAVE/SELECTION — то же действие. Выключенный майнер только передаёт сеть, не добывает; линии с выключенной башней не удаляются (инкрементальное вкл/выкл без пересборки всей сети). **Индикатор фазы** в обычном режиме не кликабелен; клик переключает фазу только в **режиме разработчика (I)**. **Меню конца игры**: при HP <= 0 (не в режиме разработчика) — модальный Popup с очками, убийствами, кнопками «Начать заново» и «В меню»; фон тёмно-синий как в главном меню.

## Системы

- **InputSystem** — клики (размещение/удаление/выбор башен).
- **WaveSystem** — спавн врагов по таймеру.
- **MovementSystem** — движение по пути, учёт slow и jade_poison.
- **CombatSystem** — поиск целей, снаряды/лазеры, энергия; урон с учётом MVP (get_mvp_damage_mult); проверка уклонения (roll_evasion); стоимость выстрела для аур из Config (AURA_ORE_COST_FACTOR, AURA_SPEED_ORE_COST_FACTOR).
- **ProjectileSystem** — полёт снарядов, урон, потиковая донаводка (раз в 0.06 с при приближении к цели), impact burst (Malachite, U235 и др.: fixed_damage, fragment_speed_multiplier), JADE_POISON; осколки Малахита — полный homing каждый кадр; при попадании — проверка evasion (визуал есть, урона нет при успехе). U235: бонус урона за повторные попадания по одной цели (repeat_hit_bonus_damage за стак, стаки в game_state["tower_hit_stacks"], длительность repeat_hit_stack_duration). **Lucky heal (Lakichinz):** при попадании снаряда проверяется `lucky_heal_chance` из attack.params башни; при успехе игроку восстанавливается `lucky_heal_amount` HP (макс. BASE_HEALTH).
- **StatusEffectSystem** — slow, poison, jade_poison (стакающийся DoT); реген врага под ядом Джейда — множитель из Config (JADE_POISON_REGEN_FACTOR). **Обычный яд (NU1, NU2, Либра):** стакается по источнику (def_id башни): на враге может быть одновременно яд от NU1, NU2 и Jade; повторное попадание от той же башни (тот же def_id) только обновляет таймер и dps, не добавляет стак. **tower_hit_stacks (U235):** декремент таймеров стаков повторных попаданий (game_state["tower_hit_stacks"]); при destroy_entity врага запись удаляется в ECS.
- **CraftingSystem** — обнаружение комбинаций соседних башен, крафт в новые типы; тяжёлый пересчёт откладывается при смене фазы. **Мимик:** при output_id == TOWER_MIMIC результат подменяется на случайную вышку уровня крафта 1 (ATTACK) по весам из DataRepository.mimic_weights (mimic_weights.json); при отсутствии веса — 1.0.
- **VolcanoSystem** — AoE-урон вокруг башни (4 тика/сек).
- **BeaconSystem** — вращающийся луч Маяка (90°, 24 тика/сек).
- **AuraSystem** — ауры активных башен.
- **BatterySystem** — тик раз в 1 с в WAVE: заряд батарей из сети (consume_rate из сети, charge_rate в storage), разряд только при потреблении сетью (без периодического пуша).
- **AurigaSystem** — башня Auriga: линия урона до 5 гексов, выбор направления по количеству врагов, замедленный поворот; данные в ecs.auriga_lines, отрисовка в EntityRenderer.
- **LineDragHandler** — редактор энерголиний (клавиша U): перенаправление линии от одной башни к другой (клик по башне с связью → клик по целевой башне); reconnect через EnergyNetworkSystem.

## Башни (уровень 1)

| ID | Тип | Механика |
|----|-----|----------|
| TA, TE, TO | PROJECTILE | Физ./маг./чистый урон |
| PA, PE, PO | PROJECTILE | Сплит (2 цели) |
| NI | PROJECTILE | Замедление |
| **Silver** | LASER | Урон + замедление (30%, 2 сек) |
| **Malachite** | PROJECTILE | Сплит + impact burst (радиус 3 гекса, 6 целей), осколки с homing |
| **Volcano** | AOE | Урон по площади каждые 0.25 сек |
| **Lighthouse** | BEACON | Вращающийся луч 90° |
| **Jade** | PROJECTILE | Стакающийся яд (DoT, замедление по стакам) |
| **Auriga** | (спец.) | Линия урона до 5 гексов, поворот по направлению с макс. врагов; механика развивается |
| **238** | PROJECTILE | Мультицель 11, MAGICAL, projectile_speed_multiplier. Рецепт PE5+PO3+NE4. |
| **U235** | PROJECTILE | Ярус 3. Мультицель 11, impact burst (осколки fixed_damage, fragment_speed_multiplier), стаки повторных попаданий (+урон за стак, длительность 7 с). Рецепт 238+Vivid Malachite+Malachite. |
| **Мимик** | (спец.) | Рецепт PE1+TE2+DE1: при крафте ставится случайная вышка уровня крафта 1 по весам (mimic_weights.json). |
| **Battery** | BATTERY | Накопитель: Добыча (жила питает сеть, заряд из сети) / Трата (запас отдаётся сети). Крафт NA2+NU2+TOWER_MINER. |
|| **Bloodstone** | PROJECTILE | Цепная молния 17%, 950 урона, до 5 целей. Рецепт NE3+PE4+PO5. |
|| **Antique** | AOE | Дебафф маг. брони, цепная молния (2%/тик, 4000 урона, 7 целей). Рецепт Ruby+Bloodstone+TO3. |
|| **Charming** | AURA | Аура по летающим: slow 70%, +20% получаемого урона. Ярус 2, радиус 4. Рецепт TOWER_QUARTZ+NE3+DA3. |
|| **Lakichinz** | PROJECTILE | Ярус 2, PURE, 90 урона, fire_rate 1.4. Lucky heal: при попадании 1/160 шанс отхилить игрока на 1 HP. Рецепт TOWER_QUARTZ+NI3+TA2. |

## Крафт и рецепты

- **Recipe Book** — кнопка «Рецепты (B)» в HUD, панель со всеми рецептами (TA+PA+NI=Silver и т.д.).
- **recipes.json** — рецепты (Silver, Malachite, Volcano, Lighthouse, Jade, 238, U235, Мимик, Paraba (Gruss+NE1+NI2) и др.).
- CraftingSystem проверяет соседей (3 гекса), при совпадении заменяет на крафтованную башню. **Мимик (PE1+TE2+DE1):** при крафте на гекс ставится случайная вышка уровня крафта 1 по весам из **mimic_weights.json** (DataRepository.mimic_weights).

## Визуал

- **Башни** — круг (базовые) или шестиугольник с золотой обводкой (крафтованные).
- **Враги** — квадрат, масштаб по здоровью; damage_flash (красный), slow (голубой), poison (зелёный).
- **Jade poison** — чем больше стаков, тем насыщеннее зелёный (ENEMY_JADE_POISON_COLOR).
- **Лазеры** — Line2D на LaserLayer (дочерний узел EntityRenderer), толщина 5 px, длительность из Config (0.4 с); позиции приводятся к Vector2 через _to_vector2.
- **Volcano** — огненные круги при тиках на EffectLayer.
- **Object pooling** — враги, снаряды.
- **Auriga** — линия гексов от башни (auriga_lines), отрисовка в EntityRenderer.

## Враги и способности

- **Способности** — в waves.json: abilities (массив id), evasion_chance. В ability_definitions.json — метаданные (id, name, type: passive/active). Уклонение (evasion): при попадании снаряда/лазера/Volcano/Beacon проверяется roll_evasion; при успехе урона нет, визуал попадания есть.
- **Волны** — health_multiplier_flying / health_multiplier_ground для смешанных волн; abilities, evasion_chance задаются в данных. Реген врагов не берётся из поля `regen` в waves.json (база из таблицы в Config), в волне используется только **regen_multiplier_modifier**. В waves.json опционально: **health_multiplier_modifier**, **speed_multiplier_modifier**, **regen_multiplier_modifier**, **pure_damage_resistance** (волна 11 и др.), **blink_hexes**, **blink_cooldown**, **blink_start_cooldown** (для волн с блинком) — применяются при спавне. Спецволны: 10 — босс -10% HP; 14 — враги -20% HP, блинк 4 гекса, кулдаун +1 с, случайный сдвиг старта 0-0.2 с; 15 — летающие слабые -15% скорость, -10% HP. Базовые HP/скорость в enemies.json (летающие и все враги приведены к -7% HP/скорость летающих от прежних значений).
- **Баланс HP по волнам (wave_balance.json)** — множители HP в `data/wave_balance.json` (wave_health). Применяются через DataRepository.get_wave_health_code_multiplier(). Текущие: волны 1–3 ×0.6; 4 +40%; 5 ×0.75; 6–7 +15%/ +25% (1.265, 1.1875); 8 ×1.03125 (−25% для ENEMY_FAST); 9 +20% (0.96); 11 ×0.76; 12 ×1.2; 14 ×0.8; 15 ×1.5; 16 ×1.7; 17–19, 21–22, 27, 29; 37–39 ×3/×3/×4; туториал ×0.3. Дополнительно: быстрые (ENEMY_FAST) на волнах 6–9 — Config.ENEMY_FAST_WAVES_6_9_HP_MULT (0.6). Реген по волнам: в waves.json regen_multiplier_modifier для волн 12 (0.333), 14 (0.5), 15 (0.4).
- **Реген врагов** — не зависит от health_scale и от поля `regen` в waves.json. База регена задаётся **таблицей по волнам** в Config (REGEN_TABLE_BY_WAVE): волны 1–10 = 0, 11+ из таблицы, боссы 20/30/40 — фиксированные значения. Итог: `база * regen_scale * сложность * regen_multiplier_modifier`. **regen_scale** считается от длины пути и скорости: (path/ref_path) * (ref_speed/effective_speed); способности rush/blink увеличивают эффективную скорость и уменьшают scale. Длина лабиринта для расчёта — по формуле от номера волны (get_maze_length_for_regen). Летающие: путь 200 гексов, множитель регена **REGEN_FLYING_SCALE_MULT** (0.5) — в два раза меньше регена. В waves.json только **regen_multiplier_modifier** для точечной подстройки волны. Хус/хиллер/реактивная броня/яд Джейда применяются к уже посчитанному регену в рантайме.
- **Золотые враги** — особый враг с увеличенным HP (x GOLD_CREATURE_HP_MULT) и наградой. Правила спавна: не спавнятся на волнах 1-5; после появления золотого врага следующий может появиться только через 5+ волн; не более одного за волну; не спавнится на боссах; минимальный success_level >= GOLD_MIN_SUCCESS_LEVEL; шанс GOLD_CREATURE_CHANCE за каждого врага. Отслеживание: `game_state["last_gold_spawned_wave"]`, `game_state["gold_spawned_this_wave"]`.

## Данные и конфиг

- **DataRepository** — автозагрузка: загрузка towers, enemies, waves, recipes, loot_tables, ability_definitions, mimic_weights. Доступ: get_tower_def, get_enemy_def, get_wave_def, get_ability_def; словарь mimic_weights для взвешенного выбора результата крафта Мимика.
- **Баланс по ярусам** — скрипт **scripts/balance_tiers.py**: урон башен в towers.json по crafting_level (0: −15%, 1: +7%, 2: +10%). Здоровье врагов: в JSON — база; в WaveSystem при спавне: волны 1–3 — ×0.6 (−40%), волны 5–6 — ×0.95 (−5%), волна 4 — +40% (wave_balance), волна 8 — ×1.03125 (−25% для быстрого врага), волна 11 — ×0.76, волны 37–39 — ×3/×3/×4; туториал — ×0.3.
- **Config** — баланс ауры и маяка: get_aura_ore_cost_factor, get_aura_speed_ore_cost_factor, JADE_POISON_REGEN_FACTOR, BEACON_*; PATH_ABILITY_DEFINITIONS. Руда: ORE_RESTORE_TICKS_PER_WAVE (20), ORE_RESTORE_GLOBAL_MULT, **ORE_RESTORE_LEVEL_1_MULT** (0.9025, −10% добычи майнеров 1 уровня), get_ore_restore_mult_for_wave(wave), get_success_ore_bonus_mult(success_level). Сопротивление сети: RESISTANCE_PER_ATTACK_TOWER (0.2), RESISTANCE_CAP (1). TOWER_DAMAGE_MULT_BY_WAVE / get_tower_damage_mult_for_wave для вулкана и др. Опыт: XP_PER_KILL (10), calculate_xp_for_level, get_total_xp. **Детерминированный сид:** GAME_SEED (0 = случайный прогон, в консоль выводится сид для воспроизведения); get_initial_run_seed() учитывает --seed N в командной строке; в начале игры вызывается seed(run_seed), карта и все randf/randi идут из одной ленты; game_state["run_seed"] хранит сид прогона. Полный список констант — config.gd и docs/22-config.md.
- **LevelConfig** — конфиг уровней и туториала: map_radius, ore_vein_count, wave_max, checkpoint_count, steps (триггер + сообщение). Уровни обучения 0–4: Основы, Энергия и руда, Стены и выбор, Крафт, Практика. Триггеры: towers_5, phase_selection, miner_on_ore, wave_started и др.
- **Логи после волны** — log_wave_damage_report: чекпоинты, путь, руда по секторам, основная сеть %, урон вышек, сводная таб-таблица для графиков, блок **[Руда по вышкам за раунд]** (вышка, def_id, руда_всего, руда_сек). Колонка **успех** — уровень успеха (6+, ср. 10). **Snapshot:** в начале каждой волны GameManager.record_wave_snapshot() добавляет снимок (seed, current_wave, towers) в game_state["wave_snapshots"]; при проигрыше log_snapshot_on_game_over() выводит в консоль полный массив wave_snapshots (JSON) для воспроизведения прогонов. См. раздел «Скрипты и визуализация» ниже.

## Награда за босса

- При убийстве босса (ENEMY_BOSS) выставляется **pending_boss_cards**; GameRoot показывает **BossRewardOverlay**: три карты (две благословения, одна проклятие). Данные карт в **CardsData** (data/cards_data.gd): BLESSINGS, RARE_BLESSINGS, CURSES. Выбор карты применяет эффект (напр. curse_hp_percent — +0.5 руды за выстрел, урон % от макс. HP врага), затем clear_pending_boss_cards(). Подробнее: [32-boss-reward-cards](32-boss-reward-cards.md).

## Скрипты и визуализация (важно для баланса и анализа)

- **Папка scripts/** — скрипты для визуализации и баланса игровых данных.
- **plot_wave_logs.py** — парсит сводную таблицу волн (файл или встроенные TABLE_ROWS) и при наличии — блок **[Руда по вышкам за раунд]** (вышка, def_id, руда_всего, руда_сек). Строит PNG: длительность, путь, чекпоинты, руда, **уровень успеха по волнам** (wave_success.png), **руда по вышкам** (tower_ore_per_round.png), дашборд. Запуск: `python plot_wave_logs.py [wave_log.txt]` (под WSL: `wsl python3 plot_wave_logs.py wave_log.txt` из корня проекта). Поддерживает ведущую строку [Сводка волн для графика]; колонка успех опциональна (уровень успеха 6+; для старых логов подставляется 10). Зависимости: matplotlib, numpy.
- **wave_log.txt** — пример лога (таб-колонки); можно копировать блок [Сводка волн для графика] из консоли игры.
- **balance_tiers.py** — перезапись урона в towers.json по ярусу крафта (см. 21-data-json).
- **docs/wave_charts.html** — интерактивные графики (Chart.js): тот же формат данных, вставка в массив waveData в HTML, открыть в браузере. Графики: длительность, путь, руда, чекпоинты, HP/уровень, урон вышек. Удобно для быстрого просмотра прогона без Python.
- Цепочка: игра выводит сводную таблицу → копировать в файл или в plot_wave_logs.py / wave_charts.html → получить графики. Подробнее: [29-logging-analytics](29-logging-analytics.md).

## Компоненты ECS (активно используются)

- towers (в т.ч. mvp_level), combat, enemies (abilities, evasion_chance), healths, positions, paths, projectiles, lasers.
- slow_effects, jade_poisons, poison_effects.
- volcano_effects, beacons, beacon_sectors.
- damage_flashes, ores, energy_lines, wave.
- game_state: tower_damage_this_wave, last_wave_tower_damage, wave_skipped (для MVP только при непропущенной волне); **alive_enemies_count** (спавн +1, kill_enemy и выход врага −1; для HUD и завершения волны); **stash_queue** (массив "Б"/"А" — очередь слотов стеша в фазе BUILD, заполняется при входе в BUILD, pop при постановке башни, push "Б" при снятии майнера/батареи); line_edit_mode, drag_source_tower_id, hidden_line_id (редактор энерголиний).
- auriga_lines (tower_id → {is_visible, hexes, current_direction, …}) — линии башни Auriga.

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

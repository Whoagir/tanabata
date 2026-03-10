# ECS (Entity-Component-System)

## Суть

Всё в игре — сущности (entities) с номерами. Свойства задаются компонентами. Логика живёт в системах, которые перебирают сущности по нужным компонентам.

## Сущности

У каждой сущности есть целочисленный ID. При создании ID растёт. Удаление — автоматическая очистка из всех зарегистрированных хранилищ компонентов (`_component_stores`) и удаление из реестра сущностей. Метод `kill_enemy(entity_id)` — единая точка для убийства врага: уменьшает **game_state["alive_enemies_count"]**, начисляет XP, обрабатывает триплет боссов и т.п., затем destroy_entity.

## Пространственные индексы

- **`ore_hex_index`** (`hex_key → ore_id`) — O(1) поиск руды по гексу. Заполняется при генерации, очищается в `destroy_entity()`.

## Основные компоненты

### Базовые

- **position** — мировые координаты в пикселях.
- **velocity** — скорость движения.
- **health** — текущее и максимальное здоровье (у врагов).

### Визуальные

- **renderable** — цвет, радиус, видимость (для отрисовки).

### Башни

- **tower** — def_id, уровень, гекс, активность, временная/постоянная, выбор, **mvp_level** (0–5, бафф урона).
- **combat** — урон, скорострельность, дальность, перезарядка, тип атаки.
- **turrets** — угол поворота (для будущих турелей).

### Враги

- **enemy** — def_id, броня (физ/маг), **abilities** (массив id способностей), **evasion_chance** (0–1, из волны).
- **path** — список гексов пути и индекс текущей точки.

### Снаряды и эффекты

- **projectile** — источник, цель, урон, скорость, тип урона.
- **laser** — начало, конец, таймер, цвет (для визуала лазера).
- **damage_flash** — таймер вспышки при уроне.

### Руда

- **ore** — мощность, текущий и максимальный запас, гекс.

### Энергосеть

- **energy_line** — ID двух башен, скрыта ли линия.

### Волны

- **wave** — номер волны, враги для спавна, интервал, таймер, путь.

### Игрок

- **player_state** — уровень, опыт, здоровье.

### Специальные (реализованы)

- **slow_effects** — замедление (LASER Silver, NI и др.). По источникам: entity_id -> { source_key -> { slow_factor, timer } }; разные источники стакаются (перемножение множителей).
- **bash_effects** — оглушение (Изумруд): entity_id -> { timer }. Враг не двигается, не использует активные скиллы (rush, blink).
- **poison_effects** — обычный яд: entity_id -> { def_id (NU1, NU2, …) -> { timer, damage_per_sec, tick_timer, source_tower_id } }. Разные башни (разный def_id) стакаются; один def_id — одно обновляемое состояние.
- **phys_armor_debuffs**, **mag_armor_debuffs** — снижение физ/маг брони на время (Ruby и др.): entity_id -> { amount, timer }.
- **jade_poisons** — стакающийся яд (Jade). instances (стаки), damage_per_stack, slow_factor_per_stack.
- **aura_effects** — ауры башен (скорость атаки у потребителей).
- **auras** — параметры ауры башни (radius, speed_multiplier, flying_only, slow_factor). **flying_aura_slows** — замедление летающих от аур (Кварц): enemy_id -> slow_factor.
- **beacons**, **beacon_sectors** — Маяк (вращающийся луч).
- **volcano_auras** — параметры вулкана (радиус, tick_timer). **volcano_effects** — визуал (огненные круги AoE).
- **tower_disarm** — дизарм от способности врагов: tower_id -> { timer }. Башня не стреляет.
- **tower_attack_slow** — замедление атаки башни (untouchable): tower_id -> { timer, multiplier }.
- **reactive_armor_stacks** — реактивная броня врага: enemy_id -> { stacks, timer }.
- **kraken_damage_taken** — накопленный урон до сброса эффектов (kraken_shell): enemy_id -> float.
- **enemy_regen_accumulator** — накопление дробного регена врагов: enemy_id -> float.
- **chain_lightning_effects** — визуал цепной молнии (Бладстоун): массив { positions, timer }.
- **auriga_lines** — линии урона башни Auriga: tower_id -> { is_visible, hexes, … }.

## Состояние игры

Отдельный компонент **game_state** (по сути синглтон). Инициализируется в init_game_state(); в ходе игры добавляются ключи, задаваемые системами.

**Основные (инициализация):**
- **phase** — BUILD, WAVE, TOWER_SELECTION.
- **current_wave** — номер текущей волны (0 до старта первой).
- **towers_built_this_phase**, **placements_made_this_phase** — счётчики за фазу BUILD.
- **time_speed**, **paused** — скорость времени и пауза.
- **total_enemies_killed**, **total_ore_spent_cumulative**.
- **line_edit_mode** — режим редактирования энерголиний (U). **drag_source_tower_id**, **drag_original_parent_id**, **hidden_line_id** — состояние перетаскивания линии.
- **future_path**, **cleared_checkpoints** — путь для отрисовки и пройденные чекпоинты.
- **difficulty**, **success_level**, **success_scale** — сложность и система успеха.
- **alive_enemies_count** — живые враги; +1 при спавне, −1 в kill_enemy и при выходе (MovementSystem).
- **stash_queue** — очередь слотов стеша в BUILD (массив "Б"/"А").

**Волны и отчёт:**
- **tower_damage_this_wave**, **last_wave_tower_damage**, **last_wave_number**, **wave_skipped** — урон за волну и MVP (wave_skipped = true при ручном переходе WAVE→BUILD, MVP не даётся).
- **wave_snapshots** — массив снимков состояния в начале каждой волны (seed, current_wave, towers); при проигрыше выводится в лог (log_snapshot_on_game_over). Инициализируется пустым массивом в init_game_state().
- **current_wave_enemy_count** — размер текущей волны (для HUD). **wave_start_time**, **wave_game_time**, **wave_path_length** — аналитика волны.
- **wave_ore_by_sector_start**, **wave_ore_spent_total**, **wave_ore_spent_by_sector**, **tower_ore_spent_this_wave** — руда за волну. **wave_enemy_checkpoints**, **wave_enemy_path_indices**, **wave_enemy_checkpoint_times** — прогресс врагов. **wave_ore_restored_by_sector** — восстановлено за волну. **wave_40_triplet_ids** — ID тройника боссов на волне 40.

**Дебаг и туториал:**
- **debug_tower_type** — тип башни при размещении в режиме отладки (1/2/3/6/0). **debug_start_wave** — стартовая волна в панели волны (0 = по счётчику).
- **developer_mode** — режим разработчика (I): кликабельный индикатор фазы, HP <= 0 не завершает игру.
- **game_over** — проигрыш; при true показывается меню конца игры.
- **is_tutorial**, **tutorial_index**, **tutorial_step_index**, **tutorial_wave_max** — туториал. **tutorial_complete_popup_visible** — блокировка кликов по карте. **removed_miner_stash** — флаг возврата слота Б при снятии майнера/батареи.
- **ore_flicker** — мигание индикатора руды (ниже порога). **hud_refresh_requested** — запрос обновления HUD. **ore_vein_hexes** — гексы жил (из OreGenerationSystem).

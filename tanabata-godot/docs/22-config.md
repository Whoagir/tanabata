# Config (конфигурация)

## Экрани и рендеринг

- Размер экрана, размер гекса, радиус карты.
- Ограничение delta для стабильной симуляции.
- **DISABLE_VSYNC** — при true при старте (main.gd) отключается вертикальная синхронизация для высокого FPS (снятие ограничения 60 FPS).

## Игровая логика

- Tick rate, фиксированный шаг.
- Базовое здоровье игрока.
- Лимит башен за фазу, сколько сохранять после выбора.

## Детерминированный рандом (сид)

- **GAME_SEED** (0) — сид прогона. 0 = при каждом запуске генерируется случайный сид (в консоль выводится строка для воспроизведения). Непустой = один и тот же сид при каждом запуске: одна и та же карта, порядок событий (уклонения, золотые враги, криты, мимик и т.д.).
- **Config.get_initial_run_seed()** — возвращает сид для текущего прогона: из командной строки (**--seed N**), иначе GAME_SEED. Запуск с воспроизведением: `godot -- --seed 12345` или в коде задать `GAME_SEED = 12345`.
- В начале игры (GameManager._init_with_config) вызывается seed(run_seed); карта и руда получают первый номер из этой ленты (map_seed = randi()); все последующие randf/randi в симуляции используют ту же ленту. **ecs.game_state["run_seed"]** хранит сид текущего прогона (для логов и отладки).

## Баланс ауры и спецбашен

- **AURA_ORE_COST_FACTOR** — множитель расхода руды для башен с аурой (DE, DA, Volcano, Lighthouse). Зависит от уровня игрока: 1.6 на 1 лвл, 0.6 на 5 лвл (линейная интерполяция). Функция `Config.get_aura_ore_cost_factor(player_level)`.
- **AURA_SPEED_ORE_COST_FACTOR** — дополнительный множитель стоимости выстрела для башни под аурой скорости. Зависит от уровня игрока: 1.3 на 1 лвл, 0.7 на 5 лвл. Функция `Config.get_aura_speed_ore_cost_factor(player_level)`.
- **JADE_POISON_REGEN_FACTOR** (0.5) — множитель регена врага под ядом Джейда.
- **BEACON_RANGE_MULTIPLIER** (1.3), **BEACON_DAMAGE_BASE_MULT** (4.0), **BEACON_DAMAGE_BONUS_MULT** (1.2) — множители дальности и урона за тик Маяка.

## Пути к данным

- **PATH_ABILITY_DEFINITIONS** — ability_definitions.json (способности врагов/башен: id, name, type).
- **PATH_MIMIC_WEIGHTS** — mimic_weights.json (веса выпадения вышек для крафта Мимика: tower_id → weight).

## Энергосеть

- **ENERGY_TRANSFER_RADIUS** (4) — майнер–майнер до 4 гексов. **ENERGY_TRANSFER_RADIUS_NORMAL** (1), **ENERGY_TRANSFER_RADIUS_MINER** (4) — для обычных башен и майнеров. **LINE_DEGRADATION_FACTOR** (0.9) — множитель за каждую атакующую башню в цепи (в коде не используется для расчёта питания; питание — по графу).
- **ORE_DEPLETION_THRESHOLD** (0.1) — порог истощения руды. **ORE_FLICKER_THRESHOLD** (3) — при total < 3 бар мигает красным; **ORE_LOW_THRESHOLD** (15) — при total < 15 синий/красный мигание, при >= 15 — синяя анимация.
- **RESISTANCE_PER_ATTACK_TOWER** (0.2), **RESISTANCE_CAP** (1.0) — сопротивление сети: каждая атакующая вышка на пути до ближайшей типа Б даёт +0.2; множитель урона max(0, 1 - resistance). См. 11-systems-energy-network.md.

## Руда

- Диапазон общей мощности карты.
- Пороги и множители урона от количества руды.
- **Восстановление руды за волну (фиксированное):**
  - **ORE_RESTORE_INTERVAL** (1.0 с) — интервал между тиками восстановления во время волны.
  - **ORE_RESTORE_TICKS_PER_WAVE** (20) — максимум тиков восстановления за одну волну. За волну с каждой жилы (с майнером) восстанавливается ровно `restore_per_round × wave_mult`, независимо от длительности волны (длинные волны не дают лишней руды).
  - **ORE_RESTORE_GLOBAL_MULT** (0.75) — глобальный множитель добычи майнеров.
  - **ORE_RESTORE_LEVEL_1_MULT** (0.9025) — множитель восстановления руды за волну только для майнеров 1 уровня (−10% суммарно).
  - **Config.get_ore_restore_mult_for_wave(wave_number)** — плавный коэффициент по номеру волны (1.0 на волне 1, до 1.25 к концу). Компенсирует рост средней длительности волн.
- **Config.get_success_ore_bonus_mult(success_level)** — бонус руды и очков при отклонении успеха от 10: deviation = |success_level - 10|, bonus = deviation × 5% (без ограничения), mult = 1 + bonus/100. Применяется к: восстановлению руды майнерами, накоплению батареи (charge_rate), XP за убийство (XP_PER_KILL).
- **ORE_COST_TIER2_MULTIPLIER** (1.7) — расход руды для башен второго яруса крафта (crafting_level >= 1).

## Успех (success level)

- **SUCCESS_LEVEL_DEFAULT** (10), **SUCCESS_LEVEL_MIN** (6), **SUCCESS_SCALE_MAX** (100). **SUCCESS_PENALTY_BASE_10** — штрафы за чекпоинт/выход при N=10; **SUCCESS_KILL_BONUS_BASE_10** (6) — бонус за убийство при N=10. Масштабирование на N врагов: coeff × 10 / N. **get_success_ore_bonus_mult(success_level)** — см. раздел «Руда».

## Волны и враги

- **INITIAL_WAVE** (1), **INITIAL_SPAWN_INTERVAL** (800), **MIN_SPAWN_INTERVAL** (100). **TOTAL_WAVE_DAMAGE** (100) — суммарный урон за волну (распределение между врагами).
- **RUSH_DURATION** (6.0 с), **RUSH_COOLDOWN** (5.0) — способность раш у врагов.
- **ENEMY_SPEED_GLOBAL_MULT** (0.9), **ENEMY_SPEED_TOUGH_MULT** (0.97), **ENEMY_SPEED_DARKNESS_MULT** (0.96), **ENEMY_SPEED_BOSS_MULT** (0.92). **ENEMY_FAST_WAVES_6_9_HP_MULT** (0.6) — множитель HP для быстрых (ENEMY_FAST) на волнах 6–9 (−40% суммарно). **get_difficulty_health_multiplier**, **get_difficulty_speed_multiplier**, **get_difficulty_regen_multiplier**, **get_difficulty_physical_armor_bonus**, **get_difficulty_magical_armor_bonus** — по сложности (EASY/MEDIUM/HARD).
- **Реген врагов:** база из **REGEN_TABLE_BY_WAVE** (волны 1–10 = 0, 11+ и боссы 20/30/40 — таблица); **get_regen_base_for_wave(wn)**. Итог: база × **get_regen_scale(path_length, speed, abilities, flying)** × сложность × regen_multiplier_modifier из волны. regen_scale учитывает длину пути (get_maze_length_for_regen по номеру волны), скорость и способности rush/blink. **REGEN_FLYING_PATH** (200), **REGEN_FLYING_SCALE_MULT** (0.5) — у летающих реген в два раза меньше. Реген не зависит от health_scale.
- **TOWER_DAMAGE_MULT_BY_WAVE** — таблица множителей урона башен по волнам. **Config.get_tower_damage_mult_for_wave(tower_def_id, wave)**.

## Снаряды и эффекты

- **PROJECTILE_SPEED**, **PROJECTILE_HIT_RADIUS**, **PROJECTILE_RADIUS**.
- **Блинк (враги):** BLINK_HEXES (6), BLINK_COOLDOWN (7.2 с), BLINK_START_COOLDOWN (5.2 с). Для конкретной волны в waves.json можно задать blink_hexes, blink_cooldown, blink_start_cooldown — они записываются во врага при спавне.
- **Потиковая донаводка:** HOMING_TICK_INTERVAL (0.06 с), HOMING_CORRECTION_STRENGTH (0.18), HOMING_ACTIVATE_DISTANCE (200 px) — коррекция направления к цели раз в тик при приближении.
- **LASER_DURATION** (0.4 с) — длительность визуала лазера.
- Длительность вспышки урона (DAMAGE_FLASH_DURATION).
- ENEMY_DAMAGE_COLOR, ENEMY_SLOW_COLOR, ENEMY_POISON_COLOR, ENEMY_JADE_POISON_COLOR.
- Параметры маяка и вулкана (тики, радиус, arc).

## UI

- Цвета фаз, размеры индикаторов.
- Цвета снарядов по типу урона.

## Длина пути (maze) и компенсация

- **MAZE_DAMAGE_TO_ENEMY_PATH_MIN/MAX** (350, 850) — множитель урона по врагам от длины пути (1.0–1.5). **MAZE_ENEMY_DAMAGE_PATH_START/END** (400, 900) — множитель урона врагов игроку от длины пути (1.0–0.6). **ENEMY_DAMAGE_TO_PLAYER_GLOBAL_MULT** (0.8) — глобальный множитель урона врагов игроку (−20%). Итог: база × get_path_length_enemy_damage_to_player_mult × ENEMY_DAMAGE_TO_PLAYER_GLOBAL_MULT. **get_path_length_damage_to_enemies_mult**, **get_path_length_enemy_damage_to_player_mult**, **get_path_length_effectiveness_mult**. **MAZE_SPEED_COMPENSATION_TIME_1/2** (135, 210 с) — при долгой волне ускорение врагов ×2 / ×4. **get_wave_duration_speed_compensation**.

## Опыт и крафт

- **XP_PER_KILL** (10) — базовый XP за убийство; умножается на get_success_ore_bonus_mult. **calculate_xp_for_level(level)** — пороги 580, 1850, 2070, 1500 для уровней 1–5. **get_total_xp(level, current_xp)** — суммарный XP для аналитики.
- **CRAFT_COST_LEVEL_1** (5), **CRAFT_COST_X2** (2), **CRAFT_COST_X4** (3), **CRAFT_COST_LEVEL_2** (9), **DOWNGRADE_COST** (3) — стоимость крафта и даунгрейда в руде.

## Статус-эффекты и способности врагов

- **DISARM_RANGE_HEX** (2), **DISARM_DURATION** (2). **UNTOUCHABLE_SLOW_MULTIPLIER** (6), **UNTOUCHABLE_DURATION** (3). **REFLECTION_STACKS** (4), **REFLECTION_COOLDOWN** (5). **HUS_REGEN_MAX_MULT** (2.5). **HEALER_AURA_RADIUS** (4), **HEALER_AURA_REGEN_BONUS** (20). **AGGRO_DURATION** (2), **AGGRO_COOLDOWN** (5), **AGGRO_RADIUS_HEX** (4). **REACTIVE_ARMOR_MAX_STACKS** (20), **REACTIVE_ARMOR_STACK_DURATION** (4). **KRAKEN_SHELL_DAMAGE_THRESHOLD** (200). **PHYS_ARMOR_DEBUFF_AMOUNT/DURATION**, **MAG_ARMOR_DEBUFF_AMOUNT/DURATION** (8, 4 с). **BEACON_ARC_ANGLE** (90), **BEACON_ROTATION_SPEED** (1.5), **BEACON_TICK_RATE** (24), **VOLCANO_TICK_RATE** (4).

## Дебаг

- **DEBUG_TEST_TOWER_IDS** — массив def_id башен для тестовой постановки (клавиша 6). По умолчанию: TOWER_QUARTZ, NI3, TA2, TOWER_LAKICHINZ. **god_mode**, **visual_debug_mode**, **fast_tower_placement**. **COMBAT_DEBUG** (false) — логи CombatSystem при отказе в выстреле.

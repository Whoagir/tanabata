# Данные (JSON)

## Правило баланса вышек

**Если просят добавить или убавить вышке что-то (урон, скорость, бонус и т.п.) и не указывают явно, что делать коэффициентом в коде — всегда меняем значения в `towers.json` (и при необходимости в других JSON: waves.json, wave_balance.json, enemies.json).** Не вводим множители в коде (типа `* 1.2` в системе). Исключение: только если явно сказано сделать именно коэффициентом или формулой.

## Баланс по ярусам крафта и здоровью врагов

- **Башни:** скрипт **scripts/balance_tiers.py** перезаписывает урон в `towers.json`: у атакующих башен (combat.damage > 0) масштаб по `crafting_level`: **0** — ×0.85 (−15%), **1** — ×1.07 (+7%), **2** — ×1.10 (+10%); округление, минимум 1.
- **Враги:** в `enemies.json` хранятся **базовые** HP. Код-множители HP по волнам заданы в **wave_balance.json** (секция wave_health); WaveSystem применяет их через DataRepository.get_wave_health_code_multiplier(). Сложность (difficulty) даёт свой множитель к HP/скорости/регену.

## Файлы

- **towers.json** — определения башен. id, name, type (ATTACK/MINER/WALL/BATTERY), crafting_level, combat (для атакующих), aura, visuals; для BATTERY — energy (transfer_radius, storage_max, charge_rate, discharge_rate, consume_rate). charge_rate в данных 0.5 (руды/с в режиме «добыча»); в игре умножается на Config.get_success_ore_bonus_mult(success_level). Баланс правят только в данных (см. правило баланса выше). Спецбашни: Изумруд (DA2+TE1+NA1) — баш с 35% на 3 с, fire_rate 1.25; Батарея (NA2+NU2+TOWER_MINER) — накопитель руды в сети; Парайба (TOWER_GRUSS+NE1+NI2) — аура all_enemies_slow, radius 4, 50% slow, при выходе из ауры 30% на 2 с, расход руды как DE4.
- **enemies.json** — определения врагов. id, name, health, speed, physical_armor, magical_armor, flying, visuals. Есть Хиллер, Танк, летающие (ENEMY_FLYING, ENEMY_FLYING_WEAK, ENEMY_FLYING_TOUGH, ENEMY_FLYING_FAST). Баланс задаётся в данных (базовые HP/скорость; глобальное снижение HP на 7% и для летающих ещё −7% скорости заложено в текущих значениях в JSON).
- **waves.json** — определения волн 1–39. Номер волны → count, enemy_id или enemies[] (смешанная волна), spawn_interval, health_multiplier или health_multiplier_flying/health_multiplier_ground, health_override, **abilities** (массив id: blink, reflection, hus, evasion, rush и т.д.), **evasion_chance** (0–1). База регена врагов задаётся таблицей по волнам в Config, не полем regen в JSON; в волне используется только **regen_multiplier_modifier** для точечной подстройки. **Модификаторы волны** (опционально): **health_multiplier_modifier**, **speed_multiplier_modifier**, **regen_multiplier_modifier**, **magical_armor_multiplier**, **pure_damage_resistance** (0–1), physical_armor_bonus, magical_armor_bonus, rush_start_cooldown_multiplier — применяются при спавне (WaveSystem). Для волн с блинком опционально: **blink_hexes** (длина телепорта в гексах), **blink_cooldown**, **blink_start_cooldown** (секунды); если не заданы — из Config. Примеры спецволн: 10 — босс −10% HP (health_multiplier_modifier 1.26); 14 — −20% HP врагов, блинк 4 гекса, кулдаун 8.2 с, старт 6.2 с + случайный сдвиг 0–0.2 с; 15 — летающие слабые −15% скорость, −10% HP (speed_multiplier_modifier 0.85, health_multiplier_modifier 0.9).
- **recipes.json** — рецепты крафта (inputs, output_id). Используются CraftingSystem и Recipe Book.
- **mimic_weights.json** — веса выпадения вышек для Мимика: объект tower_id (строка) → weight (число). При крафте PE1+TE2+DE1 результат — случайная вышка уровня крафта 1 (ATTACK); выбор взвешенный. Загружается DataRepository (mimic_weights). Путь: Config.PATH_MIMIC_WEIGHTS.
- **loot_tables.json** — таблицы лута; используются для выбора типа атакующей башни при размещении.
- **wave_balance.json** — код-множители HP врагов по волнам (wave_health: range_1_3, range_5_6, early_waves_1_5, extra_wave_2–5, wave_5/6/7/8/9/11/12/14/15/16/17/18/19/21/22/27/29/37–39, tutorial_multiplier). Волна 4: +40% (extra_wave_4). Волна 5: ×0.75 (−25%). Волны 6–7: +15% и +25% (1.265, 1.1875). Волна 8: ×1.03125 (−25% для ENEMY_FAST). Волна 9: +20% (0.96). Волны 14–16: −20%, +50%, +70% (0.8, 1.5, 1.7). Волны 21–22: +200% (3.0). Волна 27: −20% (0.8). Дополнительно в коде: быстрые (ENEMY_FAST) на волнах 6–9 получают множитель Config.ENEMY_FAST_WAVES_6_9_HP_MULT (0.6). Реген по волнам: в waves.json для волн 14, 15, 12 заданы regen_multiplier_modifier (14: 0.5, 15: 0.4, 12: 0.333). Загружается DataRepository (wave_balance). Итоговые множители — в _final_multipliers.
- **ability_definitions.json** — метаданные способностей (id, name, type: passive/active). Используется DataRepository.get_ability_def; отображение в InfoPanel. Список: effect_immunity, evasion, rush, disarm, untouchable, reactive_armor, kraken_shell, blink, reflection, hus, healer_aura, aggro.

Подробная таблица врагов и волн: **data/ENEMIES_REFERENCE.md**. Справочник всех вышек (базовые, майнер, стена, крафтованные): **data/TOWERS_REFERENCE.md**.

## Структура башни

- type — ATTACK, MINER, WALL, **BATTERY** (батарея: energy.transfer_radius, storage_max, charge_rate, discharge_rate, consume_rate; режим Добыча/Трата в игре). Батарея в энергосети считается **вышкой типа Б** (как майнер); не может выпасть с волны (не в дроп-луте); у батарей crafting_level 1.
- **crafting_level (уровень крафта)** — ярус получения башни (влияет на баланс урона через balance_tiers.py: 0 — −15%, 1 — +7%, 2 — +10%; ярус 3 не масштабируется скриптом):
  - **0** — первый ярус: базовые башни (дроп с волн, крафт TA+TE→TA2 и т.п.). У них есть **level** 1–6.
  - **1** — второй ярус: крафт из рецептов (Silver, Malachite, Jade, Volcano, Lighthouse, Pink и т.д.). Своей шкалы level не используют.
  - **2** — третий ярус: продвинутый крафт (Silver Knight, Ruby, Kailun и др.).
  - **3** — четвёртый ярус: топ-крафт (Хьюдж: Silver Knight + Silver + Pink).
- **level (уровень башни)** — только у башен первого яруса (crafting_level == 0): 1–6. Влияет на урон, размер, расход руды (shot_cost). Дроп даёт 1–5, шестой только крафтом. У башен второго яруса не используется для скейла.
- combat — для атакующих: damage, fire_rate, range, shot_cost, attack (type: PROJECTILE/LASER/AREA_OF_EFFECT, damage_type, params).
- attack.params — slow_multiplier/slow_duration (LASER), effect: JADE_POISON, impact_burst (Malachite, U235 и др.: fragment_count, radius_hex, fixed_damage, fragment_speed_multiplier), split_count, **bash_chance/bash_duration** (Изумруд). **projectile_speed_multiplier** — множитель скорости снаряда (CombatSystem передаёт в proj_data). Для башен с повторными попаданиями (U235): **repeat_hit_bonus_damage**, **repeat_hit_stack_duration** — бонус урона за стак и длительность стака в секундах; стаки хранятся в game_state["tower_hit_stacks"], декремент в StatusEffectSystem. Для LASER с критом: **crit_chance**, **crit_mult**; у Хьюдж также **damage_split** (PHYSICAL/PURE 0.5), **crit_splash_radius_hex**, **crit_splash_factor**. Тип урона **SPLIT** — половина физ, половина пуре.
- visuals — color (r,g,b,a), radius_factor.
- energy — для майнеров: transfer_radius, line_degradation_factor; для батареи: transfer_radius, storage_max, charge_rate (0.5, умножается на бонус успеха), discharge_rate, consume_rate.

## Башни второго и третьего яруса крафта (crafting_level >= 1)

Silver (TA+PA+NI), Malachite (PA+PE+PO), Volcano (PE+DE+NU), Lighthouse (TO+DE+PO), Jade (TE+NI+NU) — crafting_level 1; Изумруд (DA2+TE1+NA1) и др. — crafting_level 1 или 2. Расход руды и баланс у них задаются в def как есть, без скейла по level. Урон в def уже приведён скриптом balance_tiers.py по ярусу (+7% для яруса 1, +10% для яруса 2).

## Загрузка

**DataRepository** (автозагрузка) загружает все JSON при старте: towers, enemies, waves, wave_balance, recipes, loot_tables, ability_definitions, mimic_weights. Доступ: get_tower_def(id), get_enemy_def(id), get_wave_def(wave_number), get_ability_def(ability_id); словарь mimic_weights (tower_id → weight) для взвешенного выбора результата крафта Мимика. GameManager обращается к данным через DataRepository (или напрямую к DataRepository из систем).

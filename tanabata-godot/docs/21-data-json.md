# Данные (JSON)

## Правило баланса вышек

**Если просят добавить или убавить вышке что-то (урон, скорость, бонус и т.п.) и не указывают явно, что делать коэффициентом в коде — всегда меняем значения в `towers.json` (и при необходимости в других JSON: waves.json, enemies.json).** Не вводим множители в коде (типа `* 1.2` в системе). Исключение: только если явно сказано сделать именно коэффициентом или формулой.

## Файлы

- **towers.json** — определения башен. id, name, type (ATTACK/MINER/WALL), crafting_level, combat (damage, fire_rate, range, shot_cost, attack), aura (radius, speed_multiplier или damage_bonus), visuals (color, radius_factor). Баланс правят только в данных (см. правило баланса выше). Спецбашни: Изумруд (DA2+TE1+NA1) — баш с 35% на 3 с, fire_rate 1.25.
- **enemies.json** — определения врагов. id, name, health, speed, physical_armor, magical_armor, flying, visuals. Есть Хиллер (100 HP, аура +20 регена) и Танк (1200 HP, агрро). Баланс задаётся в данных.
- **waves.json** — определения волн 1–39. Номер волны → count, enemy_id или enemies[] (смешанная волна), spawn_interval, regen, health_multiplier или health_multiplier_flying/health_multiplier_ground, health_override, **abilities** (массив id: blink, reflection, hus, evasion, rush и т.д.), **evasion_chance** (0–1).
- **recipes.json** — рецепты крафта (inputs, output_id). Используются CraftingSystem и Recipe Book.
- **loot_tables.json** — таблицы лута; используются для выбора типа атакующей башни при размещении.
- **ability_definitions.json** — метаданные способностей (id, name, type: passive/active). Используется DataRepository.get_ability_def; отображение в InfoPanel. Список: effect_immunity, evasion, rush, disarm, untouchable, reactive_armor, kraken_shell, blink, reflection, hus, healer_aura, aggro.

Подробная таблица врагов и волн: **data/ENEMIES_REFERENCE.md**.

## Структура башни

- type — ATTACK, MINER, WALL.
- **crafting_level (уровень крафта)** — ярус получения башни:
  - **0** — первый ярус: базовые башни (дроп с волн, крафт TA+TE→TA2 и т.п.). У них есть **level** 1–6.
  - **1** — второй ярус: крафт из рецептов (Silver, Malachite, Jade, Volcano, Lighthouse и т.д.). Своей шкалы level не используют.
- **level (уровень башни)** — только у башен первого яруса (crafting_level == 0): 1–6. Влияет на урон, размер, расход руды (shot_cost). Дроп даёт 1–5, шестой только крафтом. У башен второго яруса не используется для скейла.
- combat — для атакующих: damage, fire_rate, range, shot_cost, attack (type: PROJECTILE/LASER/AREA_OF_EFFECT, damage_type, params).
- attack.params — slow_multiplier/slow_duration (LASER), effect: JADE_POISON, impact_burst (Malachite), split_count, **bash_chance/bash_duration** (Изумруд).
- visuals — color (r,g,b,a), radius_factor.
- energy — для майнеров: transfer_radius, line_degradation_factor.

## Башни второго яруса крафта (crafting_level == 1)

Silver (TA+PA+NI), Malachite (PA+PE+PO), Volcano (PE+DE+NU), Lighthouse (TO+DE+PO), Jade (TE+NI+NU), Изумруд (DA2+TE1+NA1). Расход руды и баланс у них задаются в def как есть, без скейла по level.

## Загрузка

**DataRepository** (автозагрузка) загружает все JSON при старте: towers, enemies, waves, recipes, loot_tables, ability_definitions. Доступ: get_tower_def(id), get_enemy_def(id), get_wave_def(wave_number), get_ability_def(ability_id). GameManager обращается к данным через DataRepository (или напрямую к DataRepository из систем).

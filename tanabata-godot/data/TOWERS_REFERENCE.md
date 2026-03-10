# Справочник вышек

Справочник по всем типам башен: базовые (ярус 0), майнер и стена, крафтованные (ярус 1–3). Источники правды: `towers.json`, `recipes.json`, скрипт `scripts/balance_tiers.py`, код `energy_network_system.gd` (восстановление руды майнерами). **Урон в таблицах** — значения из JSON; для яруса 1 и 2 скрипт balance_tiers применяет множители (+7%, +10%). HP врагов на волнах 1–6 при спавне −5% (WaveSystem).

## Баланс по ярусам крафта

- **crafting_level 0** (базовые башни): урон в игре ×0.85 (скрипт balance_tiers).
- **crafting_level 1**: урон ×1.07.
- **crafting_level 2**: урон ×1.10.
- **crafting_level 3**: топ-крафт (Хьюдж); урон в JSON без множителя скрипта.
Рецепты и комбинации: `recipes.json`. Книга рецептов в игре — клавиша B.

---

## Базовые атакующие башни (ярус 0, Lv.1–6)

У всех дальность 3 гекса, тип атаки PROJECTILE (кроме ауры). shot_cost растёт с уровнем.

| ID (Lv.1–6) | Название | Урон Lv1→Lv6 | fire_rate | shot_cost (Lv1 / Lv6) | Тип урона | Особенности |
|-------------|----------|--------------|-----------|------------------------|-----------|-------------|
| TA | Физ. атака | 15, 27, 48, 87, 156, 833 | 1.0 | 0.048 / 0.077 | PHYSICAL | — |
| TE | Маг. атака | 8, 26, 46, 82, 148, 790 | 1.0 | 0.056 / 0.09 | MAGICAL | — |
| TO | Чист. атака | 7, 12, 22, 41, 75, 408 | 1.0 | 0.032 / 0.052 | PURE | — |
| PA | Сплит физ. | 9, 14, 31, 56, 101, 540 | 1.0 | 0.064 / 0.103 | PHYSICAL | split_count: 2 |
| PE | Сплит маг. | 5, 10, 18, 32, 59, 310 | 1.0 | 0.048 / 0.077 | MAGICAL | split_count: 2 |
| PO | Сплит чист. | 5, 8, 15, 27, 49, 265 | 1.0 | 0.08 / 0.128 | PURE | split_count: 2 |
| NI | Замедление | 1, 1, 2, 2, 2, 3 | 1.67 | 0.072 / 0.116 | SLOW | slow_factor 0.4→0.95 по уровням |
| NA | Снижение физ. брони | 3, 3, 4, 5, 5, 6 | 1.2 | 0.064 / 0.112 | PHYS_ARMOR_DEBUFF | armor_debuff_amount 8→190 |
| NE | Снижение маг. брони | 1, 2, 2, 3, 3, 4 | 1.2 | 0.064 / 0.103 | MAG_ARMOR_DEBUFF | armor_debuff_amount 8→190 |
| NU | Яд | 1, 2, 3, 3, 4, 5 | 0.8 | 0.056 / 0.09 | POISON | poison_dps 5→94 по уровням |
| DA | Аура урона | 0 | 1.0 | 0.04 / 0.065 | INTERNAL | aura: damage_bonus 8→288, radius 2→4 |
| DE | Аура скорости | 0 | 1.0 | 0.04 / 0.069 | INTERNAL | aura: speed_multiplier 1.6→2.2, radius 2→3 |

---

## Майнер, батарея и стена

| ID | Название | Тип | Особенности |
|----|----------|-----|-------------|
| TOWER_MINER | Шахтер | MINER | Ставится только на гекс с рудой. energy.transfer_radius: 4, line_degradation_factor: 0.6. Уровень башни (1–5) задаётся при крафте/дропе; от уровня зависит восстановление руды за волну (см. ниже). |
| TOWER_BATTERY | Батарея | BATTERY | Крафт: NA2+NU2+TOWER_MINER. energy.transfer_radius: 5, storage_max: 200, charge_rate: 0.5, discharge_rate: 0.1, consume_rate: 0.05. Режимы: Добыча (жила под батареей питает сеть, батарея заряжается из сети) и Трата (запас отдаётся сети). Накопление в режиме «добыча» умножается на Config.get_success_ore_bonus_mult(success_level). Визуал: гекс, красный контур; on/off по режиму. |
| TOWER_WALL | Стена | WALL | Блокирует путь, не участвует в энергосети. Не потребляет руду. |

### Добыча майнеров за волну (на одну жилу)

Формула в коде (energy_network_system.gd):  
`base × ORE_RESTORE_GLOBAL_MULT (0.75) × level_mult + бонус карты (+1 при bless_ore1)`. При **выключенном майнере** (is_manually_disabled) на жиле +30% к восстановлению. Итог умножается на **Config.get_success_ore_bonus_mult(success_level)** (бонус отклонения успеха от 10, 5% за единицу).

**level_mult:** если уровень игрока больше уровня майнера — 1.0; если равен — доля прогресса XP до следующего уровня (0..1); иначе 1.0.

| Уровень майнера | base | За волну (×0.75, 100% level_mult) | С картой +1 руда |
|-----------------|------|-----------------------------------|------------------|
| 1 | 1.7 | 1.275 | 2.275 |
| 2 | 2.5 | 1.875 | 2.875 |
| 3 | 5.2 | 3.9 | 4.9 |
| 4 | 9.6 | 7.2 | 8.2 |
| 5 | 15.0 | 11.25 | 12.25 |

За волну выполняется ровно ORE_RESTORE_TICKS_PER_WAVE (20) тиков восстановления; итоговая сумма на жилу за волну = значение из таблицы × множитель по номеру волны (Config.get_ore_restore_mult_for_wave) × бонус отклонения успеха × (1.3 если майнер выключен).

### Батарея: накопление и ёмкость

Параметры в data/towers.json, энергоблок башни TOWER_BATTERY (battery_system.gd тикает раз в секунду):

| Параметр | Значение | Смысл |
|----------|----------|--------|
| storage_max | 200 | Максимум руды в хранилище батареи (ед.) |
| charge_rate | 0.5 | Рост запаса в режиме «добыча»: +0.5 руды/с в хранилище (умножается на get_success_ore_bonus_mult) |
| consume_rate | 0.05 | В режиме «добыча»: из сети (жилы майнеров) забирается 0.05 руды/с в батарею; остальное — «бонус накопителя» |
| discharge_rate | 0.1 | В режиме «трата» батарея отдаёт в сеть до 0.1 руды/с из буфера (потребители списывают через consume_from_power_source) |

Режимы: **добыча** — жила под батареей питает сеть, батарея копит (+0.5/с в себя с учётом бонуса успеха, из сети забирает 0.05/с если есть); **трата** — батарея становится источником для сети при руде в сети < 10 или при заполнении (storage >= 200) или при ручном включении разряда.

---

## Крафтованные вышки (TOWER_*)

Ярус 1–3. Урон в таблице — из JSON; в игре для яруса 1–2 применяется balance_tiers (×1.07 или ×1.10).

| ID | Название | Ярус | Урон | fire_rate | range | shot_cost | Атака | Тип урона | Особенности |
|----|----------|------|------|-----------|-------|-----------|-------|-----------|-------------|
| TOWER_SILVER | Сильвер | 1 | 126 | 1.08 | 4 | 0.15 | LASER | PHYSICAL | slow 30%, 2 с |
| TOWER_MALACHITE | Малахит | 1 | 24 | 1.1 | 4 | 0.3 | PROJECTILE | MAGICAL | split 3, impact_burst (радиус 3, 6 целей), осколки homing |
| TOWER_VOLCANO | Вулкан | 1 | 28 | 0.5 | 2 | 0.25 | NONE (AOE) | PHYSICAL | VolcanoSystem: урон по области, 4 тика/с |
| TOWER_LIGHTHOUSE | Маяк | 1 | 34 | 1.0 | 4 | 0.2 | NONE (BEACON) | PURE | BeaconSystem: вращающийся луч 90° (arc_angle 120) |
| TOWER_JADE | Jade (Яд) | 1 | 5 | 1.125 | 4 | 0.12 | PROJECTILE | MAGICAL | JADE_POISON: стакающийся яд, poison_damage_mult 1.3 |
| TOWER_GREY | Грей | 2 | 6→7 | 1.3 | 4.5 | 0.18 | PROJECTILE | MAGICAL | JADE_POISON (как Джейд), большая дальность, +50% руды |
| TOWER_SILVER_KNIGHT | Сильвер Найт | 2 | 1144 | 1.08 | 4 | 0.18 | LASER | PHYSICAL | slow 40%, 2 с |
| TOWER_VIVID_MALACHITE | Вивид Малахит | 2 | 294 | 1.1 | 4 | 0.32 | PROJECTILE | MAGICAL | split, impact_burst (7 целей) |
| TOWER_RUBY | Рубин | 2 | 28 | 0.5 | 2 | 0.25 | NONE (AOE) | PHYSICAL | Volcano-тип, крафт из Volcano+PE3+DE2 |
| TOWER_KAILUN | Кайлун | 2 | 264 | 1.0 | 4 | 0.32 | NONE (BEACON) | PURE | Луч 120°, range_mult 1.3, incinerate шанс |
| TOWER_GOLD | Голд | 1 | 18 | 1.1 | 3 | 0.1 | PROJECTILE | PURE | Дебафф физ/маг брони −15, 5 с |
| TOWER_EGYPT | Египт | 2 | 33 | 1.2 | 4 | 0.18 | PROJECTILE | PURE | Дебафф брони −25, slow 8% 2 с, ore_drop |
| TOWER_LIBRA | Либра | 1 | 4 | 0.9 | 3 | 0.08 | PROJECTILE | MAGICAL | split 3, poison_dps 15, 4 с |
| TOWER_GRUSS | Грус | 1 | 9 | 1.4 | 3 | 0.09 | PROJECTILE | SLOW | split 3, slow 50%, 3 с |
| TOWER_AURIGA | Аурига | 1 | 24 | 1.0 | 4 | 0.045 | LINE_BEAM | PURE | Линия до 5 гексов, поворот по врагам (AurigaSystem) |
| TOWER_QUARTZ | Кварц | 1 | 0 | 1.0 | 1 | 0.05 | — | INTERNAL | Аура: только по летающим, slow 60% |
| TOWER_PARAIBA | Парайба | 2 | 0 | 1.0 | 1 | 0.053 | NONE | INTERNAL | Аура: все враги в радиусе 4 — slow 50%; при выходе из ауры — 30% slow на 2 с. Расход руды как DE4. Рецепт: TOWER_GRUSS+NE1+NI2. |
| TOWER_EMERALD | Изумруд | 1 | 24 | 1.25 | 3 | 0.058 | PROJECTILE | PHYSICAL | bash 35%, 3 с (обездвиживание) |
| TOWER_DIPSEA | Дипсеа | 1 | 0 | 1.0 | 1 | 0.071 | NONE | INTERNAL | Аура: debuff_immunity (иммунитет союзных башен к дебаффам), radius 2 |
| TOWER_PINK | Пинк | 1 | 890 | 1.1 | 5 | 0.2 | LASER | PURE | Крит 35%, множитель 260%. При крите: луч 8 px, красный цвет; 3 треугольника-осколка в точке попадания. Обычный луч 4 px. Рецепт: NA3+NI4+TO5. |
| TOWER_238 | 238 | 1 | 327 | 1.5 | 5 | 0.12 | PROJECTILE | MAGICAL | Мультицель 11, projectile_speed_multiplier 1.4. Рецепт: PE5+PO3+NE4. |
| TOWER_U235 | U235 | 3 | 510 | 1.6 | 6 | 0.1 | PROJECTILE | MAGICAL | Мультицель 11, projectile_speed_multiplier 1.5. Impact burst: 2 осколка, радиус 4 гекса, fixed_damage 380, fragment_speed_multiplier 1.6. **Повторные попадания:** +6 урона за стак по той же цели, стак 7 с (repeat_hit_bonus_damage, repeat_hit_stack_duration). Рецепт: TOWER_238+TOWER_VIVID_MALACHITE+TOWER_MALACHITE. |
| TOWER_MIMIC | Мимик | 1 | (не ставится) | — | — | — | — | — | Спецрецепт: PE1+TE2+DE1. При крафте на гекс ставится **случайная вышка уровня крафта 1** (ATTACK); веса в data/mimic_weights.json. |
| TOWER_HUGE | Хьюдж | 3 | 3900 | 1.3 | 5 | 0.25 | LASER | SPLIT | 50% физ / 50% пуре. Крит 10%, множитель 900%. Замедление 60%, 2 с. При крите: сплеш в радиусе 0.7 гекса — 30% урона крита (физ+пуре). Обычный луч 7 px, при крите 12 px, красный. 6 треугольников при крите. Рецепт: Silver Knight + Silver + Pink. |
|| TOWER_BLOODSTONE | Бладстоун | 1 | 100 | 1.08 | 5 | 0.2 | PROJECTILE | MAGICAL | chain_lightning_chance 17%, 950 урона молнии, до 5 целей, радиус 450 px. Рецепт: NE3+PE4+PO5. |
|| TOWER_ANTIQUE | Антик | 2 | 250 | 0.5 | 4 | 0.25 | NONE (AOE) | MAGICAL | mag_armor_debuff_per_hit 0.2, chain_lightning_chance_per_tick 2%, 4000 урона молнии, до 7 целей. Рецепт: Ruby+Bloodstone+TO3. |
|| TOWER_CHARMING | Чарминг | 2 | 0 | 1.0 | 1 | 0.055 | NONE | INTERNAL | Аура: только летающие, slow 70%, flying_damage_taken_bonus +20% получаемого урона летающими, радиус 4. Рецепт: TOWER_QUARTZ+NE3+DA3. |
|| TOWER_LAKICHINZ | Лакичинз | 2 | 90 | 1.4 | 3 | 0.1 | PROJECTILE | PURE | **Lucky heal:** при попадании шанс 1/160 (0.625%) отхилить игрока на 1 HP (макс. BASE_HEALTH). Рецепт: TOWER_QUARTZ+NI3+TA2. |

---

## Мимик: веса выпадения (mimic_weights.json)

При крафте Мимика (PE1+TE2+DE1) на гекс ставится одна из атакующих вышек уровня крафта 1 с вероятностью по весам. Файл **data/mimic_weights.json** — объект `tower_id: weight`. Чем выше вес, тем чаще выпадает вышка. Новые вышки уровня 1 можно добавлять в файл с нужным весом; при отсутствии записи используется вес 1.0. Пример весов: TOWER_SILVER 11, TOWER_MALACHITE 11, TOWER_LIBRA 13, TOWER_GRUSS 13, TOWER_PINK 0.5, TOWER_BLOODSTONE 0.5, TOWER_238 0.5 и т.д.

---

## Рецепты (recipes.json)

Кратко: TA+PA+NI → Silver; PA+PE+PO → Malachite; PE+DE+NU → Volcano; TO+DE+PO → Lighthouse; TE+NI+NU → Jade; **Jade+DA2+NU3 → Grey**; **NA3+NI4+TO5 → Pink**; **NA2+NU2+TOWER_MINER → TOWER_BATTERY**; TOWER_SILVER+TA2+PA2 → Silver Knight; **TOWER_SILVER_KNIGHT+TOWER_SILVER+TOWER_PINK → Huge**; TOWER_MALACHITE+PA2+PO2 → Vivid Malachite; TOWER_VOLCANO+PE3+DE2 → Ruby; TOWER_LIGHTHOUSE+TO2+DA1 → Kailun; NE+NA+NI → Gold; TOWER_GOLD+NA2+NI1 → Egypt; DA+NU+PA → Libra; NI+PO+TO → Gruss; TA+TE+TO → Auriga; **TA1+PE2+NA1 → Quartz**; **TOWER_GRUSS+NE1+NI2 → TOWER_PARAIBA (Парайба)**; DA2+TE1+NA1 → Emerald; DE3+NE2+TO2 → Dipsea; **PE5+PO3+NE4 → TOWER_238**; **TOWER_238+TOWER_VIVID_MALACHITE+TOWER_MALACHITE → TOWER_U235**; **PE1+TE2+DE1 → TOWER_MIMIC** (результат — случайная вышка уровня крафта 1 по весам из mimic_weights.json); **NE3+PE4+PO5 → Bloodstone**; **Ruby+Bloodstone+TO3 → Antique**; **TOWER_QUARTZ+NE3+DA3 → Charming**; **TOWER_QUARTZ+NI3+TA2 → Lakichinz**. Полный список и уровни входов — в `recipes.json`. Дроп с волн даёт башни яруса 0 (loot_tables.json); уровни майнеров при крафте/дропе задаются отдельно.

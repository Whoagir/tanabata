# Баланс скорости и замедлений

Сводка: какие замедления есть, насколько замедляют, стакаются ли и по какой формуле, плюс реальные скорости врагов по волнам (сложность MEDIUM, без баффов/дебаффов).

---

## 1. Источники замедления (и ускорения) врагов

| Источник | Где задаётся | Эффект | Примечание |
|----------|--------------|--------|------------|
| **Сложность** | Config.get_difficulty_speed_multiplier | EASY: x0.9 (на 10% медленнее), MEDIUM: x1.0, HARD: x1.1 | Множитель к базовой скорости волны |
| **Обычный slow (башни)** | slow_effects по source_key (def_id башни) | speed *= произведение slow_factor по всем источникам | Разные башни (NI1, NI2, …) стакаются (перемножение); две одинаковые (два NI1) — один слот (перезапись по def_id). NI1 25%, NI2 30%, NI3 35%, NI4 40%, NI5 50%, NI6 70% замедления (slow_factor = 0.75 … 0.30). |
| **Яд изумруда (Jade)** | jade_poisons | speed *= max(0.1, 1 - total_slow), total_slow = min(0.9, 0.03 * stacks * path_mult) | Стакается по стакам; 3% за стак (Config.JADE_SLOW_PER_STACK), кап 90% замедления |
| **Аура замедления (Кварц, летающие)** | flying_aura_slows | speed *= (1 - flying_slow) | Только летающие; берётся максимум из аур (не сумма) |
| **Раш (Rush)** | RUSH_SPEED_MULT | speed *= 2.3 | Ускорение, не замедление |
| **Карта «Враги медленнее»** | bless_enemy_slow10 | speed *= 0.9 | Постоянно, если карта взята |
| **Долгая волна** | get_wave_duration_speed_compensation | wave_game_time >= 210 с: x4, >= 135 с: x2, иначе x1 | Ускорение врагов при затяжной волне |
| **Time speed (игра)** | time_speed (0.25 / 1 / 2 / 4) | Вся симуляция быстрее/медленнее | Не меняет «число пикселей в секунду» врага — меняет темп игрового времени |

Итоговая формула эффективной скорости (movement_system.gd, _calculate_effective_speed):

```
effective_speed = base_speed_wave
  * get_combined_slow_factor()  // произведение по всем источникам (def_id; разные NI стакаются)
  * jade_mult            // max(0.1, 1 - total_slow), total_slow до 0.9
  * (1 - flying_slow)    // только летающие, flying_slow = max по аурам
  * (RUSH_SPEED_MULT если раш активен, иначе 1)
  * card_enemy_speed_mult   // 0.9 или 1.0
  * wave_duration_speed_compensation  // 1, 2 или 4
```

base_speed_wave считается при спавне (wave_system):

```
base_speed_wave = enemy_def.speed * wave_def.speed_multiplier * diff_speed * wave_def.speed_multiplier_modifier
  * ENEMY_SPEED_GLOBAL_MULT (0.9)
  * (ENEMY_SPEED_TOUGH_MULT 0.97 для TOUGH/TOUGH_2, ENEMY_SPEED_DARKNESS_MULT 0.96 для DARKNESS, ENEMY_SPEED_BOSS_MULT 0.92 для BOSS)
```

По умолчанию в волне: speed_multiplier = 1.0, speed_multiplier_modifier = 1.0. Все враги на 10% медленнее; крепкие доп. -3%; тьма доп. -4%; боссы доп. -8%.

---

## 2. Стакается ли замедление и как

- **Обычный slow (slow_effects):** стакается по источнику (def_id башни). slow_effects[entity_id] = { source_key -> { timer, slow_factor } }. Один и тот же def_id (например два NI1) перезаписывают одну запись; разные def_id (NI1 и NI2) дают две записи, множители перемножаются. Итого: две NI1 по одному врагу — один эффект (последнее применение); NI1 + NI2 — два эффекта (оба действуют).
- **Jade (яд изумруда):** стакается по количеству стаков. total_slow = min(0.9, slow_per_stack * stacks * path_length_effect_mult), затем speed *= max(0.1, 1 - total_slow). slow_per_stack = Config.JADE_SLOW_PER_STACK = 0.03 (3% за стак).
- **Аура замедления (летающие):** не стакается между аурами — берётся максимальный slow_factor среди аур, затем speed *= (1 - flying_slow).
- **Slow и Jade одновременно:** перемножение: speed *= get_combined_slow_factor() * jade_mult * ...
- **Flying slow:** отдельный множитель (1 - flying_slow) для летающих.

Итого: все виды замедления перемножаются; внутри slow_effects — по одному слоту на def_id (и на "hit_"+def_id для замедления по хиту), внутри Jade — стаки по формуле выше.

---

## 3. Насколько именно замедляют

- **NI (башни замедления):** NI1 25% (slow_factor 0.75), NI2 30% (0.70), NI3 35% (0.65), NI4 40% (0.60), NI5 50% (0.50), NI6 70% (0.30). Остальные башни с slow — из params; от длины пути эффективность масштабируется (get_path_length_effectiveness_mult).
- **Jade:** 3% за стак (JADE_SLOW_PER_STACK 0.03), кап 90% замедления (минимум 10% скорости).
- **Кварц (летающие):** значение из описания ауры (slow_factor), один множитель на врага.
- **Карта «Враги медленнее»:** 10% замедления (speed *= 0.9).
- **Сложность EASY:** 10% замедления (speed *= 0.9).

Длительность обычного slow: Config.SLOW_DURATION = 3.0 с (для типа SLOW); у башен с «по хиту» замедлением — из params (slow_duration).

---

## 4. Реальные скорости врагов по волнам (MEDIUM, без slow/jade/rush/карт, компенсация волны = 1)

Базовая скорость на волне (пикселей/сек в игровом времени):

`speed = enemy_speed * wave_speed_mult * wave_speed_mod * diff_speed`

Для MEDIUM: diff_speed = 1.0. В таблице ниже: wave_speed_mult и wave_speed_mod по умолчанию 1.0, если не указаны в waves.json.

Базы из data/enemies.json: NORMAL_WEAK 80, NORMAL_WEAK_2 80, NORMAL 80, NORMAL_2 80, TOUGH 75, TOUGH_2 75, MAGIC_RESIST 80, MAGIC_RESIST_2 80, PHYSICAL_RESIST 80, PHYSICAL_RESIST_2 80, FAST 160, BOSS 78, FLYING 100, FLYING_WEAK 100, FLYING_TOUGH 90, HEALER 80, TANK 80, DARKNESS_1 110, DARKNESS_2 120.

| Волна | Враг(и) | speed_mult | speed_mod | Итоговая скорость (MEDIUM) |
|-------|---------|------------|-----------|----------------------------|
| 1 | ENEMY_NORMAL_WEAK | 1.0 | 1.0 | 80 |
| 2 | ENEMY_NORMAL_WEAK_2 | 1.0 | 1.0 | 80 |
| 3 | ENEMY_NORMAL_WEAK | 1.0 | 1.0 | 80 |
| 4 | ENEMY_TOUGH | 1.2 | 1.0 | 90 |
| 5 | ENEMY_NORMAL | 1.0 | 1.0 | 80 |
| 6 | ENEMY_MAGIC_RESIST | 1.0 | 1.0 | 80 |
| 7 | ENEMY_PHYSICAL_RESIST | 1.0 | 1.0 | 80 |
| 8 | ENEMY_FAST | 1.0 | 1.587 | 254.0 |
| 9 | ENEMY_NORMAL_WEAK_2 | 1.0 | 1.0 | 80 |
| 10 | ENEMY_BOSS | 1.0 | 1.0 | 78 |
| 11 | ENEMY_DARKNESS_1 | 1.0 | 1.0 | 110 |
| 12 | ENEMY_PHYSICAL_RESIST_2 | 1.0 | 1.0 | 80 |
| 13 | ENEMY_FAST | 1.0 | 1.404 | 224.6 |
| 14 | ENEMY_TOUGH_2 | 1.0 | 1.0 | 75 |
| 15 | ENEMY_FLYING_WEAK | 1.0 | 1.0 | 100 |
| 16 | ENEMY_DARKNESS_1 | 1.0 | 0.65 | 71.5 |
| 17 | ENEMY_FLYING_TOUGH | 1.0 | 1.0 | 90 |
| 18 | ENEMY_MAGIC_RESIST_2 | 1.0 | 1.0 | 80 |
| 19 | ENEMY_NORMAL_WEAK_2 | 1.0 | 1.0 | 80 |
| 20 | ENEMY_BOSS | 1.0 | 1.0 | 78 |
| 21 | ENEMY_MAGIC_RESIST, ENEMY_TANK | 1.0 | 1.0 | 80, 80 |
| 22 | ENEMY_PHYSICAL_RESIST_2 | 1.0 | 1.0 | 80 |
| 23 | ENEMY_DARKNESS_2 | 1.0 | 1.0 | 120 |
| 24 | ENEMY_FAST | 1.0 | 1.0 | 160 |
| 25 | ENEMY_FLYING | 1.0 | 0.5 | 50 |
| 26 | ENEMY_TOUGH | 1.0 | 1.0 | 75 |
| 27 | ENEMY_NORMAL_2, ENEMY_HEALER | 1.0 | 1.0 | 80, 80 |
| 28 | ENEMY_FLYING_TOUGH | 1.0 | 1.0 | 90 |
| 29 | ENEMY_MAGIC_RESIST_2 | 1.0 | 1.0 | 80 |
| 30 | ENEMY_FLYING_TOUGH | 1.0 | 1.0 | 90 |
| 31 | ENEMY_NORMAL_WEAK, ENEMY_TOUGH | 1.0 | 1.0 | 80, 75 |
| 32 | ENEMY_PHYSICAL_RESIST_2, ENEMY_MAGIC_RESIST_2 | 1.0 | 1.0 | 80, 80 |
| 33 | ENEMY_FLYING, ENEMY_NORMAL_2 | 1.0 | 1.0 | 100, 80 |
| 34 | ENEMY_TOUGH_2, ENEMY_HEALER | 1.0 | 1.0 | 75, 80 |
| 35 | TOUGH, PHYSICAL_RESIST_2, MAGIC_RESIST_2 | 1.0 | 1.0 | 75, 80, 80 |
| 36 | ENEMY_TANK | 1.0 | 1.0 | 80 |
| 37 | ENEMY_NORMAL_2 | 1.0 | 1.0 | 80 |
| 38 | ENEMY_TOUGH_2 | 1.0 | 1.0 | 75 |
| 39 | ENEMY_DARKNESS_2, ENEMY_PHYSICAL_RESIST_2, ENEMY_MAGIC_RESIST_2 | 1.0 | 1.0 | 120, 80, 80 |
| 40 | ENEMY_BOSS x3 | 1.0 | 1.0 | 78 |

Примечания:
- Смешанные волны (21, 27, 31–35, 39, 40): у каждого типа своя база и свои множители волны; в волне 32/33 могут быть отдельные множители для летающих/наземных (в формуле скорости в коде для смешанных волн по типам используется общий speed_multiplier/speed_multiplier_modifier из wave_def, отдельно flying/ground в этой формуле не применяются к скорости — только к HP). В таблице для простоты приведены скорости по типам с общими множителями волны из wave_def.
- Реальная «ощущаемая» скорость дополнительно умножается на card_enemy_speed_mult и wave_duration_speed_compensation (и при наличии — на slow, jade, flying_slow, rush) как в разделе 1.

---

## 5. Кратко для баланса скорости

- Замедления перемножаются: get_combined_slow_factor() * jade * flying_slow * карта * сложность * компенсация волны * раш.
- Обычный slow стакается по def_id (разные NI — разные слоты; два NI1 — один слот). Jade — 3% за стак, кап 90%. Раш 2.3x. Долгая волна: пороги 135 с (2x) и 210 с (4x). Все враги -10% скорости; крепкие -13%, тьма -14%, боссы -18%. Волна 8: -5% к множителю (1.50765 вместо 1.587).

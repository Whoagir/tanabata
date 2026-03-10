# WaveSystem (система волн)

## Назначение

Управляет волнами врагов: старт, спавн по таймеру, проверка завершения волны. Итоги урона и начисление MVP при завершении.

## Когда работает

Только в фазе WAVE. В BUILD и SELECTION ничего не делает.

## Старт волны

В начале start_wave() после установки current_wave вызывается **GameManager.record_wave_snapshot()** — снимок состояния (seed, current_wave, список вышек по гексам) добавляется в game_state["wave_snapshots"] для последующего вывода при проигрыше и симуляций. Берётся определение волны по номеру (из JSON). Рассчитывается путь через чекпоинты с учётом башен. Для **летающих** врагов путь строится с условной вставкой центра: между чекпоинтами i→i+1 центр вставляется, если этот отрезок длиннее отрезка i+1→i+2; при входе — через центр, если чекпоинт 1 входит в два самых дальних от входа; при выходе — через центр, если чекпоинт 6 входит в два самых дальних от выхода. Создаётся сущность волны с полями: номер волны, ID врага(ов), количество, интервал спавна, таймер, путь. Урон по игроку распределяется между врагами (damage_per_enemy). Поддержка смешанных волн (enemies[]), health_multiplier_flying / health_multiplier_ground.

**Модификаторы из waves.json:** для каждой волны применяются опциональные множители: **health_multiplier_modifier**, **speed_multiplier_modifier**, **regen_multiplier_modifier**, **magical_armor_multiplier**, **pure_damage_resistance** (0–1) и др. Они умножаются/применяются к базовым значениям при спавне. **Реген врагов:** база из таблицы по волнам в Config (REGEN_TABLE_BY_WAVE, волны 1–10 = 0), затем умножается на **regen_scale** (длина пути, скорость, способности rush/blink — Config.get_regen_scale), на множитель сложности и на regen_multiplier_modifier из волны. Реген не зависит от health_scale. Летающие: путь 200 гексов, regen_scale дополнительно ×0.5 (REGEN_FLYING_SCALE_MULT). **pure_damage_resistance** задаёт долю снижения чистого урона (PURE); при спавне записывается в компонент enemy (используется в projectile, combat, beacon, volcano, auriga через GameManager.get_pure_damage_resistance). У врага также сохраняются **spawned_wave** и копия **pure_damage_resistance** из определения волны.

## Спавн врагов

Каждые spawn_interval секунд создаётся один враг. Позиция -- Entry. Врагу задаются: позиция, скорость, здоровье (с учётом health_multiplier или health_multiplier_flying/ground), броня, путь, **abilities** и **evasion_chance** из определения волны. **Множители HP из wave_balance.json:** применяются через `DataRepository.get_wave_health_code_multiplier(wave_num)` -- произвольные `wave_N_multiplier` из раздела `wave_health` (напр. wave_8_multiplier: 1.03125 (−25% для быстрого врага), wave_9_multiplier: 0.8, wave_12_multiplier: 1.2, wave_17_multiplier: 1.4, wave_18_multiplier: 0.9 и др.). Ранние волны 1-5 имеют индивидуальные множители (волна 4: +40% через extra_wave_4). В **туториале** -- x0.3. Для способностей blink, reflection, aggro при создании инициализируются таймеры/счётчики (см. StatusEffectSystem, MovementSystem). **Блинк:** при спавне врага с ability blink в wave_def могут быть заданы **blink_hexes**, **blink_cooldown**, **blink_start_cooldown** (иначе берутся из Config); к начальному кулдауну добавляется случайный сдвиг **0-0.2 с**, чтобы враги блинковались в разное время. Хиллер и Танк получают свои пассивные способности (healer_aura, aggro) автоматически.

**Золотые враги:** при спавне каждого врага (кроме босса) проверяется шанс на золотого. Условия: волна > 5; прошло > 5 волн с прошлого золотого (`last_gold_spawned_wave`); ещё не было золотого на этой волне; success_level >= GOLD_MIN_SUCCESS_LEVEL; randf() < GOLD_CREATURE_CHANCE. При спавне золотого: HP умножается на GOLD_CREATURE_HP_MULT, цвет становится золотым, `is_gold = true` записывается в компонент enemy. Враги добавляются в ECS.

## Восстановление руды во время волны

Во время фазы WAVE руда восстанавливается **по тикам**: каждые **ORE_RESTORE_INTERVAL** (1 с) один тик. За волну выполняется не более **ORE_RESTORE_TICKS_PER_WAVE** (20) тиков — итоговая сумма восстановления на жилу фиксирована и не зависит от длительности волны. На каждый тик для каждой жилы с майнером добавляется порция: `(restore_per_round / ORE_RESTORE_TICKS_PER_WAVE) * get_ore_restore_mult_for_wave(wave_number)`. При **завершении волны** (если волна была короче ~20 с) добавляется остаток: `max(0, add_per_round * wave_mult - already_added)` по каждой жиле, чтобы за короткую волну игрок всё равно получил полную норму восстановления. Итоги по секторам записываются в game_state.wave_ore_restored_by_sector для логов.

## Подсчёт живых врагов и завершение волны

Используется единый счётчик **game_state["alive_enemies_count"]**: увеличивается на 1 при спавне каждого врага (_spawn_enemy), уменьшается в **ecs.kill_enemy()** при убийстве башней/эффектами и в **MovementSystem** при достижении врагом выхода (перед destroy_entity). Завершение волны проверяется по условию: все заспавнены (enemies_to_spawn = 0) и **alive_enemies_count == 0**.

## Завершение волны (действия)

Когда все враги заспавнены и alive_enemies_count == 0 — вызывается **log_wave_damage_report()**: сохранение last_wave_tower_damage, начисление **+1 MVP** первой по урону башне с mvp_level < 5 (только если волна не была пропущена — game_state.wave_skipped не true). Затем удаляются сущность волны и снаряды, **добавление остатка руды** (см. выше), пересборка энергосети, фаза → BUILD. При пропуске волны (переход WAVE→BUILD вручную через PhaseController) wave_skipped выставляется в true, log_wave_damage_report не вызывается — MVP не даётся.


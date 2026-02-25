# GameManager (автозагрузка)

## Назначение

Центральная точка инициализации. Создаёт ECS, карту, держит ссылки на системы и данные. Загрузка данных выполняется через DataRepository.

## Что создаётся при старте

- ECS мир с начальным game_state.
- HexMap с генерацией (радиус, seed).
- DataRepository загружает tower_defs, enemy_defs, wave_defs, recipes, loot_tables, ability_definitions.
- Сущность игрока (player_state).
- Генерация руды (OreGenerationSystem).
- EnergyNetworkSystem (логика сети, сами системы создаются в GameRoot).
- Таймер дебаунса пересчёта пути (_path_update_timer, 0.08 с).

## Путь врагов и руда

- **update_future_path()** — пересчёт предпросмотра пути (Entry → чекпоинты → Exit). Вызывается при старте и по таймеру после _request_future_path_update.
- **_request_future_path_update()** — запрос пересчёта с дебаунсом 0.08 с (при постановке/снятии башни и смене фазы).
- **get_ore_network_totals()** — глобальные суммы руды по всем жилам (для HUD).
- **get_ore_network_ratio()** — доля оставшейся руды (current/max).
- **_deferred_recalculate_crafting()** — отложенный пересчёт комбинаций крафта при смене фазы.

## Урон, MVP и уклонение

- **on_enemy_took_damage(entity_id, final_damage, source_tower_id)** — вызывается при нанесении урона врагу; добавляет final_damage в tower_damage_this_wave[source_tower_id]; обрабатывает reactive_armor, kraken_shell.
- **get_mvp_damage_mult(tower_id)** — множитель урона от MVP башни: 1.0 + mvp_level×0.2 (0→1.0, 5→2.0).
- **roll_evasion(entity_id)** — проверка уклонения врага по evasion_chance; true = уклонение (урон не применять).
- **get_top5_tower_damage()** — список из до 5 записей {tower_id, name, damage, mvp_level, is_top1, has_max_mvp} за текущую или прошлую волну (для HUD).
- **log_wave_damage_report()** — вызывается при завершении волны: сохраняет last_wave_tower_damage, last_wave_number; начисляет +1 MVP первой по урону башне с mvp_level < 5 **только если не wave_skipped**. PhaseController при переходе WAVE→BUILD выставляет wave_skipped = true; WaveSystem при старте волны сбрасывает в false.

## Доступ к данным

Через **DataRepository**: get_tower_def(id), get_enemy_def(id), get_wave_def(number), get_ability_def(ability_id). GameManager может проксировать вызовы к DataRepository.

## События

Сигнал event_dispatched и функция dispatch_event объявлены (типы в GameTypes.EventType). Задел на будущее; подписчиков нет.

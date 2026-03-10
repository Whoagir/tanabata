# GameManager (автозагрузка)

## Назначение

Центральная точка инициализации. Создаёт ECS, карту, держит ссылки на системы и данные. Загрузка данных выполняется через DataRepository.

## Что создаётся при старте

- ECS мир с начальным game_state.
- HexMap с генерацией (радиус, seed).
- DataRepository загружает tower_defs, enemy_defs, wave_defs, recipes, loot_tables, ability_definitions, mimic_weights.
- Сущность игрока (player_state).
- Генерация руды (OreGenerationSystem).
- EnergyNetworkSystem (логика сети, сами системы создаются в GameRoot).
- Таймер дебаунса пересчёта пути (_path_update_timer, 0.08 с).

## Путь врагов и руда

- **update_future_path()** — пересчёт предпросмотра пути (Entry → чекпоинты → Exit). Вызывается при старте и по таймеру после _request_future_path_update.
- **_request_future_path_update()** — запрос пересчёта с дебаунсом 0.08 с (при постановке/снятии башни и смене фазы).
- **get_ore_network_totals()** — глобальные суммы руды по всем жилам (для HUD).
- **get_ore_network_ratio()** — доля оставшейся руды (current/max).
- **get_ore_totals_by_sector()** — руда по секторам (0=центр, 1=середина, 2=край); для логов и баланса.
- **get_miner_count_by_sector()** — количество майнеров по секторам и всего.
- **spend_ore_global(amount)** — списание руды глобально (крафт, даунгрейд); при списании учитывается **record_ore_spent** для логов за волну.
- **record_ore_spent(amount, sector)** — учёт расхода руды за текущую волну (по секторам). Вызывается из CombatSystem, Auriga, Beacon, Volcano и spend_ore_global.
- **get_main_network_ore_stats()** — основная сеть (с макс. числом атакующих вышек): total_current, total_max, pct_remaining, pct_spent, attack_count. Для лога «остаток руды в основной сети».
- **_deferred_recalculate_crafting()** — отложенный пересчёт комбинаций крафта при смене фазы.

## Проклятия и чистый урон

- **get_curse_extra_ore_per_shot()** — возвращает 0.5 при активном проклятии curse_hp_percent (доп. расход руды за выстрел), иначе 0.0. Учитывается в CombatSystem, Auriga, Volcano, Beacon.
- **get_pure_damage_resistance(entity_id)** — возвращает долю сопротивления чистому урону (0–1) у врага из компонента enemy (поле pure_damage_resistance, задаётся из волны при спавне). Итоговый PURE-урон умножается на (1 − resistance).

## Урон, MVP, сопротивление и уклонение

- **get_tower_base_damage(tower_id)** — базовый урон башни: из def + бонус +1 для башен первого яруса с level 1 и crafting_level 0 (обучение/ранние волны). Учитывает Config.get_tower_damage_mult_for_wave для вулкана и др.
- **get_resistance_mult(tower_id)** — множитель урона от сопротивления сети: max(0, 1 - resistance); делегирует в EnergyNetworkSystem.get_resistance_mult. Используется в CombatSystem, ProjectileSystem, BeaconSystem, VolcanoSystem, AurigaSystem, AuraSystem.
- **on_enemy_took_damage(entity_id, final_damage, source_tower_id)** — вызывается при нанесении урона врагу; добавляет final_damage в tower_damage_this_wave[source_tower_id]; обрабатывает reactive_armor, kraken_shell.
- **get_mvp_damage_mult(tower_id)** — множитель урона от MVP башни: 1.0 + mvp_level×0.2 (0→1.0, 5→2.0).
- **roll_evasion(entity_id)** — проверка уклонения врага по evasion_chance; true = уклонение (урон не применять).
- **get_top5_tower_damage()** — список из до 5 записей {tower_id, name, damage, mvp_level, is_top1, has_max_mvp} за текущую или прошлую волну (для HUD).
- **log_wave_damage_report()** — вызывается при завершении волны: сохраняет last_wave_tower_damage, last_wave_number; начисляет +1 MVP первой по урону башне с mvp_level < 5 **только если не wave_skipped**. Выводит в консоль полный отчёт по волне (см. раздел «Логи после волны»).

## Доступ к данным

Через **DataRepository**: get_tower_def(id), get_enemy_def(id), get_wave_def(number), get_ability_def(ability_id). GameManager может проксировать вызовы к DataRepository.

## Логи после волны (log_wave_damage_report)

При завершении каждой волны в консоль выводится:

- **Лабиринт:** длительность волны (игровое и реальное время), число врагов в волне.
- **Чекпоинты:** сколько врагов дошло до каждого чекпоинта (0…max_cp), в процентах по волне и среднее за игру.
- **Среднее время между чекпоинтами** (игровое время) по сегментам (0→1, 1→2, …).
- **Путь:** всего гексов, макс/средний % пройденного пути врагами, средние за игру.
- **Руда по секторам:** центр/середина/край — до и после волны, восстановлено за волну, число майнеров.
- **Майнеров всего.**
- **Руда:** израсходовано за раунд, руда/сек (ср.), добыто за волну, гексов занято майнерами.
- **Руда траты по секторам:** центр, середина, конец.
- **Основная сеть:** (если есть атакующие) остаток руды в %, текущ/макс, израсходовано в %.
- **Башен всего** и группировка по def_id (например «TOWER_WALL x30, PA1 x2»).
- **Урон вышек за волну** и **Урон вышек всего** (накопительно с средним за раунд).
- **Сводка волн для графика** — таб-таблица (волна, длит_игр, длит_реал, врагов, путь_гексов, путь_макс%, путь_ср%, руда по секторам, чекпоинты %, времена сегментов, hp_игрока, lvl_игрока, xp_всего, пропущено_врагов, руда_всего, успех). Используется скриптом `scripts/plot_wave_logs.py` для построения графиков.

## Snapshot (симуляции)

- **get_snapshot()** — возвращает словарь { seed (map_seed), current_wave, towers: [ {q, r, def_id}, … ] } — состояние карты (все вышки и стены) для воспроизводимого «входа» симуляции. Башни отсортированы по (q, r).
- **record_wave_snapshot()** — вызывается в начале каждой волны (WaveSystem.start_wave): добавляет текущий get_snapshot() в **game_state["wave_snapshots"]**. Инициализация wave_snapshots = [] в init_game_state (ECSWorld).
- **log_snapshot_on_game_over()** — при первом показе экрана проигрыша (GameRoot): один раз выводит в консоль полный массив wave_snapshots в формате JSON (все волны: seed, current_wave, towers для каждой). Флаг snapshot_logged в game_state предотвращает повторный вывод.

Итог: при проигрыше в лог попадает массив снимков по всем пройденным волнам; по любому элементу можно воспроизвести прогон (тот же seed + расстановка вышек) для массовых симуляций.

## События

Сигнал event_dispatched и функция dispatch_event объявлены (типы в GameTypes.EventType). Задел на будущее; подписчиков нет.

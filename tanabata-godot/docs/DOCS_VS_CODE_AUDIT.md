# Аудит документации: соответствие коду

Проверка документов в `docs/` относительно реального кода проекта (состояние на момент проверки).

## Итог

Документация в целом **соответствует** коду. Структура проекта, фазы, ECS, системы, рендереры, данные и конфиг описаны верно. Ниже — уточнения и расхождения.

---

## Что совпадает

- **Структура проекта:** core/, godot_adapter/, autoload/, data/, scenes/ — как в 00-overview и 01-architecture.
- **Фазы игры:** BUILD_STATE, TOWER_SELECTION_STATE, WAVE_STATE и порядок переключения — как в коде (GameTypes, PhaseController).
- **ECS:** Компоненты из 02-ecs присутствуют в `ecs_world.gd` (positions, healths, towers, combat, enemies, paths, projectiles, ores, energy_lines, wave, game_state, slow_effects, bash_effects, poison_effects, jade_poisons, aura_effects, auras, beacons, beacon_sectors, volcano_auras, volcano_effects, auriga_lines, tower_disarm, tower_attack_slow, reactive_armor_stacks, kraken_damage_taken, enemy_regen_accumulator, chain_lightning_effects и т.д.). Пространственный индекс `ore_hex_index` и очистка в `destroy_entity` — как в документе.
- **HexMap:** Tile (passable, can_place_tower, has_tower, tower_id), entry, exit, checkpoints, генерация — совпадает с `hex_map.gd`.
- **Pathfinding:** A* с min-heap (frontier), стоимость 1, только проходимые тайлы; дебаунс пересчёта 0.08 с; летающие — условная вставка центра — как в `pathfinding.gd` и 05-pathfinding.
- **Системы в GameRoot:** InputSystem, WaveSystem, MovementSystem, CombatSystem, ProjectileSystem, StatusEffectSystem, AuraSystem, CraftingSystem, VolcanoSystem, BeaconSystem, AurigaSystem, BatterySystem, LineDragHandler — все создаются и регистрируются как в 20-game-root.
- **Рендереры:** EntityRenderer, OreRenderer, EnergyLineRenderer, AttackLinkRenderer, CraftingVisualRenderer, WallRenderer, AuraRenderer, PathOverlayLayer, TowerPreview — все подключены в `game_root.gd`. Лазеры на LaserLayer внутри EntityRenderer — как в 13-rendering-overview.
- **DataRepository:** Загрузка tower_defs, enemy_defs, wave_defs, recipes, loot_table_defs, wave_balance, ability_defs, mimic_weights — как в 21-data-json. Пути к JSON и методы get_tower_def, get_enemy_def, get_wave_def, get_ability_def — соответствуют.
- **Config и GameManager:** Описанные константы, пути, формулы (руда, реген, волны, снаряды, ауры, сопротивление сети и т.д.) и методы (get_ore_network_ratio, update_future_path, get_mvp_damage_mult, log_wave_damage_report, record_wave_snapshot и др.) присутствуют в коде.
- **Типы башен:** В игре используются типы ATTACK, MINER, BATTERY, WALL. В `GameTypes.TowerType` в коде только ATTACK, MINER, WALL; BATTERY задаётся полем `type` в JSON башни (def.get("type") == "BATTERY"). Документ 24-game-types описывает все четыре типа как логические — это верно.
- **README:** Ссылка на DEVELOPMENT_PLAN.md в корне проекта — файл существует.

---

## Расхождения и уточнения

### 1. GameTypes.TowerType и BATTERY

- **Документ 24-game-types:** перечисляет типы башен: ATTACK, MINER, BATTERY, WALL.
- **Код:** В `game_types.gd` enum `TowerType` содержит только ATTACK, MINER, WALL. BATTERY нигде не в enum; тип башни берётся из данных (towers.json, поле `type`).
- **Рекомендация:** В 24-game-types можно добавить одну фразу: «BATTERY задаётся в данных башни (type в JSON), в enum TowerType в коде только ATTACK, MINER, WALL».

### 2. Тип атаки AREA_OF_EFFECT vs AOE

- **Документ 24-game-types:** тип атаки назван AREA_OF_EFFECT (Volcano).
- **Код:** В `game_types.gd` enum `AttackType` значение называется `AOE`.
- **Рекомендация:** Оставить в документе AREA_OF_EFFECT как пояснение; при упоминании в коде везде используется AOE.

### 3. ECS: add_component и «скрытые» компоненты

- **Документ 02-ecs:** перечисляет компоненты, в том числе bash_effects, tower_disarm, tower_attack_slow, reactive_armor_stacks, kraken_damage_taken, enemy_regen_accumulator.
- **Код:** Эти компоненты есть в `_component_stores` и очищаются в `destroy_entity`. Но в `add_component()` нет веток для: `bash_effect`, `tower_disarm`, `tower_attack_slow`, `reactive_armor_stacks`, `kraken_damage_taken`, `enemy_regen_accumulator`. Они записываются напрямую в словари (например, `ecs.bash_effects[entity_id] = {...}`, `ecs.tower_disarm[tid] = {...}`).
- **Рекомендация:** Документацию менять не обязательно; при желании в 02-ecs можно указать, что часть компонентов обновляется прямым присвоением в хранилища, а не через add_component.

### 4. Дубликаты в add_component (ecs_world.gd)

- В `match component_type` дважды встречается `"energy_line"` (строки 188 и 199) и дважды `"ore"` (177 и 200). Вторая ветка для каждого перезаписывает первую.
- **Рекомендация:** Удалить дубликаты (оставить по одной ветке для energy_line и ore).

### 5. MetaballWallRenderer

- **Документация:** В 13-rendering-overview и 15-rendering-wall описан только WallRenderer (стены и линии). MetaballWallRenderer не упоминается.
- **Код:** В проекте есть `metaball_wall_renderer.gd` и шейдеры metaball; в сцену и игру он не подключён (в `game_root.gd` создаётся только WallRenderer). По смыслу это альтернативная/экспериментальная реализация.
- **Рекомендация:** Документацию можно не менять. При желании в 13-rendering-overview или 15-rendering-wall добавить примечание: «В репозитории также есть MetaballWallRenderer (liquid glass), он не используется в текущей сборке.»

---

## Проверенные файлы кода

- `core/ecs/ecs_world.gd` — компоненты, create_entity, destroy_entity, add_component, remove_component
- `core/types/game_types.gd` — фазы, TowerType, AttackType, DamageType
- `core/hexmap/hex_map.gd` — тайлы, entry, exit, checkpoints
- `core/hexmap/pathfinding.gd` — A*, min-heap
- `autoload/game_manager.gd` — инициализация, путь, руда, урон, MVP, snapshot
- `autoload/data_repository.gd` — загрузка JSON
- `scenes/game_root.gd` — системы, рендереры, порядок инициализации
- Системы: input, wave, movement, combat, energy_network, battery — выборочно сверены с документами 06–12, 11, 23

---

## Рекомендуемые правки в коде (минор)

1. **ecs_world.gd:** в `add_component()` убрать повторяющиеся ветки для `"energy_line"` и `"ore"`, оставив по одной каждой.

Документацию при необходимости можно точечно дополнить по пунктам 1–3 и 5 выше; критических ошибок в описании логики и архитектуры не найдено.

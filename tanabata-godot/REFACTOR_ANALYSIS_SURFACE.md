# Поверхностный анализ для рефакторинга (Godot)

Краткий отчёт: дублирование логики, неиспользуемые переменные/функции, места для проверки.

---

## 1. Функции с одинаковой логикой

| Место | Что дублируется | Действие |
|-------|------------------|----------|
| **game_root.gd** | `_get_hex_polygon(size)` и `_get_hex_outline(size)` — один и тот же расчёт 6 точек гекса | Одна функция, возвращающая точки; использовать для Polygon2D и Line2D |
| **game_root.gd** / **game_hud.gd** | Очистка сущностей: `_clear_entities()` vs `_clear_enemies()` + `_clear_projectiles()` — один паттерн (собрать ключи → destroy) | Общий хелпер «очистить по типу» (ECS/GameManager) |
| **info_panel.gd** / **game_hud.gd** | `_create_permanent_wall(hex)` — создание стены (entity + tower + renderable + place_tower) в двух файлах | Вынести в одно место (GameManager или TowerFactory) |
| **info_panel.gd** / **game_hud.gd** | Финализация выбора башен (кто удалять, кого в стену, пересбор сети) — `_finalize_tower_selection()` и `_remove_unselected_towers()` | Одна функция финализации, вызываемая из HUD и InfoPanel |
| **status_effect_system.gd** | `_update_slow_effects` и `_update_poison_effects` — один паттерн: to_remove, таймер −= delta, erase | Обобщить в один цикл по эффектам с таймером |
| **projectile_system.gd** | `_update_damage_flashes` и `_update_lasers` — тот же паттерн по таймеру | Общий шаблон обновления по таймеру |
| **projectile_system** / **combat_system** | Расчёт урона с броней, health, damage_flash, destroy при смерти — `_apply_damage` и `_apply_laser_damage` | Одна общая функция применения урона |
| **entity_renderer** / **energy_network_system** | «Майнер на руде»: перебор руды по гексу + `current_reserve >= ORE_DEPLETION_THRESHOLD` — `_is_miner_on_ore()` и `_is_on_ore(hex)` | Одна функция «есть ли активная руда на гексе» |
| **game_manager.gd** | `_process_tower_defs`, `_process_enemy_defs`, `_process_loot_table_defs`, `_process_wave_defs` — одна схема (Array/Dict + ключ) | Один обобщённый парсер JSON-дефов |
| **input_system** / **wall_renderer** / **tower_preview** | Правило «какая башня ставится»: дебаг, лимит 5, первая башня = майнер в волнах 1–4 | Одна точка истины (GameManager/Config) для «текущий тип башни для постройки» |

---

## 2. Неиспользуемые переменные и функции

| Файл | Что не используется |
|------|---------------------|
| **game_root.gd** | `debug_key_pressed` |
| **config.gd** | `LINE_HEIGHT` |
| **game_manager.gd** | `systems` (массив не заполняется и не читается) |
| **input_system.gd** | `hovered_hex` |
| **combat_system.gd** | `hex_map` (передаётся в _init, не используется) |
| **tower_preview.gd** | `input_system` |
| **info_panel.gd** | `button_hbox` |
| **ore_generation_system.gd** | `ore_vein_hexes` |
| **ecs_world.gd** | Словари компонентов: `turrets`, `beacons`, `beacon_sectors`, `volcano_auras`, `volcano_effects`, `combinables`, `texts`, `aoe_effects`, `manual_selection_markers` — нигде не заполняются |
| **entity_renderer.gd** | Функции: `_create_entity_visual`, `_create_triangle`, `_create_inverted_triangle`, `_add_triangle_outline`, `_add_inverted_triangle_outline`, `_add_hexagram_outline` |

---

## 3. Условия и места для проверки

- **game_root.gd** — `_is_ui_area()` с магическими числами (270, 100, 60, 160, 70). Вынести в Config. Пауза проверяется и в game_root, и в game_manager — согласовать.
- **game_manager.gd** — либо использовать `systems`, либо убрать переменную.
- **input_system.gd** — в `remove_tower()` дважды вызывается `rebuild_energy_network()`. Оставить один вызов. При `fast_tower_placement` путь при установке башни не проверяется.
- **hex_map.gd** — `_get_exclusion_zones(dist)` учитывает только entry/exit; в `is_in_exclusion_zone()` ещё и checkpoints. Согласовать с дизайном.
- **pathfinding.gd** — фронт как массив, минимум по стоимости ищется линейно. На больших картах рассмотреть приоритетную очередь (heap).
- **ecs_world.gd** — в `add_component` дублируются ветки для `"energy_line"` и `"ore"`. В `remove_component` нет ветки для `"position"` — проверить намеренно ли.
- **config.gd** vs **combat_system.gd** — бонус урона от руды: в Config одна формула, в combat — другая (10, 100, 2.0, 0.8). Свести к одной.
- **energy_network_system.gd** — в `_is_on_ore()` при каждой проверке идёт `print`. Убрать или под флаг дебага.
- **info_panel.gd** — на кнопку подписаны и `pressed`, и `button_down` на один обработчик; возможен двойной вызов.
- **ore_generation_system.gd** — суммарная мощность 240–270 захардкожена; в Config есть `TOTAL_MAP_POWER_MIN/MAX`. Использовать константы.
- **movement_system.gd** — учёт `jade_poison`: словарь `jade_poisons` нигде не заполняется — ветка мёртвая.
- **game_hud.gd** — проверка `kills_label.visible` с предупреждением при том, что метка нигде не скрывается.

---

## 4. Куда заглянуть (чеклист рефакторинга)

1. **game_root.gd** — объединить геометрию гекса; убрать `debug_key_pressed`; вынести константы UI.
2. **game_hud.gd** + **info_panel.gd** — одна реализация «создать постоянную стену» и «финализировать выбор башен».
3. **game_manager.gd** — судьба `systems`; при необходимости общий хелпер очистки врагов/снарядов.
4. **input_system.gd** — один вызов `rebuild_energy_network`; убрать `hovered_hex`.
5. **projectile_system** + **combat_system** — общая функция применения урона.
6. **status_effect_system** + **projectile_system** — обобщить обновление по таймеру.
7. **entity_renderer** + **energy_network_system** — одна функция «руда на гексе»; удалить неиспользуемые функции рендера.
8. **ecs_world.gd** — убрать дубликаты в `add_component`; решить, что делать с неиспользуемыми компонентами.
9. **config.gd** — убрать или использовать `LINE_HEIGHT`; согласовать формулу бонуса руды с combat.
10. **combat_system.gd** — убрать неиспользуемый `hex_map`; перейти на общую формулу бонуса руды.
11. **pathfinding.gd** — рассмотреть heap для A*.
12. **ore_generation_system.gd** — использовать Config для мощности; убрать или использовать `ore_vein_hexes`.
13. **Тип башни для постройки** — одна общая логика (input_system, wall_renderer, tower_preview).
14. **game_manager.gd** — обобщённый парсер JSON-дефов вместо пяти похожих функций.

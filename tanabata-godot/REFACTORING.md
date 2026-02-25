# Рефакторинг - Февраль 2026

## Цель
Устранение дублирования кода и разделение ответственности до того, как проект разрастется.

## Что было сделано

### 1. ✅ DataRepository (autoload/data_repository.gd)
**Проблема:** GameManager был God Object - хранил данные, управлял ECS, паузой, фазами.

**Решение:** Вынесли все данные (tower_defs, enemy_defs, wave_defs, loot_tables, recipes) в отдельный autoload.

**Результат:**
- GameManager сократился с 407 до ~150 строк
- Данные загружаются централизованно
- API: `DataRepository.get_tower_def()`, `DataRepository.get_enemy_def()`, etc.
- GameManager проксирует вызовы для обратной совместимости

### 2. ✅ EntityFactory (core/ecs/entity_factory.gd)
**Проблема:** Создание сущностей дублировалось в нескольких местах (input_system, game_manager, game_hud, info_panel).

**Решение:** Единая фабрика для создания всех типов сущностей.

**API:**
```gdscript
EntityFactory.create_tower(ecs, hex_map, hex, def_id)  → int
EntityFactory.create_wall(ecs, hex_map, hex)           → int
EntityFactory.create_enemy(ecs, def_id, path)          → int
EntityFactory.create_projectile(...)                   → int
EntityFactory.create_laser(...)                        → int
```

**Где используется:**
- GameManager._place_initial_walls() - начальные стены
- InputSystem.place_tower() - размещение башен игроком
- PhaseController.create_wall_at() - конвертация башен в стены

### 3. ✅ PhaseController (core/systems/phase_controller.gd)
**Проблема:** Логика переходов между фазами размазана по 3 файлам (game_root, game_hud, info_panel).

**Решение:** Единый контроллер фаз.

**API:**
```gdscript
phase_controller.cycle_phase()               # Переход в следующую фазу
phase_controller.transition_to_selection()   # BUILD → SELECTION
phase_controller.transition_to_wave()        # SELECTION → WAVE (с финализацией)
phase_controller.transition_to_build()       # WAVE → BUILD (с очисткой)
phase_controller.finalize_tower_selection()  # Финализация выбора башен
phase_controller.create_wall_at(hex)         # Создание стены
phase_controller.clear_wave_entities()       # Очистка врагов/снарядов
```

**Что делает при переходах:**
- SELECTION → WAVE: финализирует выбор (удаляет невыбранные башни, ставит стены, перестраивает энергосеть)
- WAVE → BUILD: очищает врагов, снаряды, лазеры, вспышки, сбрасывает счётчики

**Где используется:**
- game_root._cycle_phase() - хоткей Space
- game_hud._on_state_indicator_clicked() - клик по индикатору фазы
- info_panel._on_select_button_pressed() - автопереход при сохранении 2 башен

### 4. ✅ Удалено дублирование
**Удалены дублирующиеся функции:**
- `game_hud._create_permanent_wall()` → `PhaseController.create_wall_at()`
- `game_hud._remove_unselected_towers()` → `PhaseController.finalize_tower_selection()`
- `game_hud._clear_enemies()` → `PhaseController.clear_wave_entities()`
- `game_hud._clear_projectiles()` → `PhaseController.clear_wave_entities()`
- `info_panel._create_permanent_wall()` → `PhaseController.create_wall_at()`
- `info_panel._finalize_tower_selection()` → `PhaseController.finalize_tower_selection()`
- `game_root._clear_entities()` → `PhaseController.clear_wave_entities()`
- `input_system._create_tower_entity()` → `EntityFactory.create_tower()`

**Результат:** ~200 строк удалённого дублированного кода

### 5. ✅ Замена вызовов GameManager → DataRepository
**Заменено во всех системах:**
- `GameManager.get_tower_def()` → `DataRepository.get_tower_def()`
- `GameManager.get_enemy_def()` → `DataRepository.get_enemy_def()`
- `GameManager.get_wave_def()` → `DataRepository.get_wave_def()`

**Файлы обновлены:**
- input_system.gd
- wave_system.gd
- energy_network_system.gd
- game_hud.gd
- info_panel.gd

### 6. ✅ Использование констант вместо литералов
**Исправлено:**
- info_panel.gd: `>= 2` → `>= Config.TOWERS_TO_KEEP`

## Что НЕ было сделано (намеренно)

❌ **Resource-компоненты вместо словарей** - оставлено на будущее (когда MVP будет полностью готов)
❌ **Удаление "мёртвого" кода из ecs_world.gd** - это заготовки на будущее (beacons, volcano_auras, etc.)
❌ **SpatialHash** - не нужен пока количество сущностей < 500
❌ **EventBus** - прямые вызовы работают нормально для текущего масштаба

## Структура после рефакторинга

```
tanabata-godot/
├── autoload/
│   ├── config.gd              ✓ Константы
│   ├── data_repository.gd     ✅ НОВЫЙ: Данные (tower_defs, enemy_defs, etc.)
│   ├── game_manager.gd        ✅ УПРОЩЕН: ECS, hex_map, phase_controller, pause
│   └── profiler.gd            ✓ Профайлинг
│
├── core/
│   ├── ecs/
│   │   ├── ecs_world.gd       ✓ ECS
│   │   └── entity_factory.gd  ✅ НОВЫЙ: Фабрика сущностей
│   │
│   ├── systems/
│   │   ├── phase_controller.gd  ✅ НОВЫЙ: Контроллер фаз
│   │   ├── input_system.gd      ✅ ОБНОВЛЕН: использует EntityFactory
│   │   ├── wave_system.gd       ✅ ОБНОВЛЕН: использует DataRepository
│   │   ├── combat_system.gd     ✓ Боевая система
│   │   └── ...
│   │
│   └── ...
│
├── godot_adapter/
│   ├── ui/
│   │   ├── game_hud.gd       ✅ УПРОЩЕН: убрано дублирование
│   │   └── info_panel.gd     ✅ УПРОЩЕН: убрано дублирование
│   │
│   └── rendering/
│       └── ...
│
└── scenes/
    └── game_root.gd           ✅ УПРОЩЕН: _cycle_phase использует PhaseController
```

## Тестирование

**Что нужно проверить:**
1. ✅ Игра запускается
2. ✅ Размещение башен работает (BUILD фаза)
3. ✅ Переход BUILD → SELECTION по Space
4. ✅ Выбор 2 башен в SELECTION
5. ✅ Автопереход в WAVE при сохранении 2 башен
6. ✅ Невыбранные башни превращаются в стены
7. ✅ Волна запускается
8. ✅ Враги спавнятся и двигаются
9. ✅ Башни стреляют
10. ✅ Переход WAVE → BUILD после завершения волны
11. ✅ Энергосеть перестраивается корректно

## Обратная совместимость

✅ **Сохранена полностью:**
- GameManager.get_tower_def() проксирует к DataRepository
- Все старые вызовы работают как прежде
- Ничего не сломано

## Следующие шаги (когда будет нужно)

1. **Resource-компоненты** - заменить словари на типизированные классы
2. **SpatialHash** - когда врагов станет > 500
3. **EventBus** - если понадобится реактивность
4. **Оптимизация поиска целей** - кэширование запросов ECS

## Итог

✅ **Код чище**
✅ **Легче добавлять фичи**
✅ **Готов к масштабированию**
✅ **Ничего не сломано**

Рефакторинг выполнен аккуратно, логика энергосети и других систем не тронута.

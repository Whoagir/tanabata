# ECS Components

Все компоненты в ECS хранятся как **Dictionary** (ассоциативный массив) в `ECSWorld`.

## Структура компонентов

Часть компонентов — словари с полями, часть — прямые значения (например Vector2 для позиций).

```gdscript
# В ECSWorld:
var positions: Dictionary = {}  # entity_id -> Vector2
var towers: Dictionary = {}     # entity_id -> {def_id: String, level: int, hex: Hex, ...}
```

## Примеры структур компонентов

### Position
В коде хранится как **Vector2**: `positions[entity_id] = Vector2(x, y)`.

### Velocity
В коде хранится как **Vector2**. Для врагов при спавне пишется Vector2.ZERO; движение идёт по path, компонент velocity не читается системами.

### Health
```gdscript
{
    "current": 100,
    "max": 100
}
```

### Renderable
```gdscript
{
    "color": Color(1.0, 0.0, 0.0),
    "radius": 10.0,
    "visible": true
}
```

### Tower
```gdscript
{
    "def_id": "TA",           # ID башни из towers.json
    "level": 1,
    "crafting_level": 0,
    "hex": Hex.new(0, 0),     # Позиция на карте
    "is_active": true,        # Подключена к энергосети?
    "is_temporary": false,    # Временная (в фазе выбора)?
    "is_selected": false,     # Выбрана для сохранения?
    "is_manually_selected": false  # Выбрана Shift+Click?
}
```

### Combat
```gdscript
{
    "damage": 25,
    "fire_rate": 1.0,         # атак в секунду
    "range": 3,               # в гексах
    "fire_cooldown": 0.0,     # текущий кулдаун
    "shot_cost": 0.06,        # стоимость выстрела (энергия)
    "attack_type": GameTypes.AttackType.PROJECTILE,
    "damage_type": GameTypes.DamageType.PHYSICAL,
    "split_count": 1          # Количество снарядов (для сплит-атак)
}
```

### Turret (для TA башни)
```gdscript
{
    "current_angle": 0.0,     # текущий угол поворота (радианы)
    "target_angle": 0.0,      # целевой угол
    "current_pitch": 0.0,     # наклон (для 3D, в 2D не используется)
    "target_pitch": 0.0,
    "turn_speed": 8.0,        # скорость поворота (рад/сек)
    "acquisition_range": 4.2, # дальность захвата цели (1.4 * range)
    "target_id": -1           # ID текущей цели
}
```

### Enemy
```gdscript
{
    "def_id": "ENEMY_NORMAL",
    "physical_armor": 10,
    "magical_armor": 5,
    "last_checkpoint_index": -1,  # Индекс последнего пройденного чекпоинта
    "damage_to_player": 10        # Урон при достижении Exit
}
```

### Path
```gdscript
{
    "hexes": [Hex.new(0, 0), Hex.new(1, 0), ...],  # Массив гексов
    "current_index": 0                              # Текущая позиция в пути
}
```

### Projectile
```gdscript
{
    "source_id": 1,           # ID башни-источника
    "target_id": 2,           # ID цели
    "speed": 200.0,
    "damage": 25,
    "direction": 0.0,         # Направление (радианы)
    "attack_type": GameTypes.AttackType.PROJECTILE,
    "damage_type": GameTypes.DamageType.PHYSICAL,
    
    # Визуальные
    "age": 0.0,
    "scale_up_duration": 0.15,
    "spawn_height": 0.0,      # Для 3D (в 2D = 0)
    "visual_type": GameTypes.ProjectileVisualType.SPHERE,
    
    # Эффекты
    "slows_target": false,
    "slow_duration": 0.0,
    "slow_factor": 1.0,
    "applies_poison": false,
    "poison_duration": 0.0,
    "poison_dps": 0.0,
    
    # Impact Burst (для Malachite)
    "impact_burst_radius": 0.0,
    "impact_burst_target_count": 0,
    "impact_burst_damage_factor": 0.0,
    
    # Условное самонаведение
    "is_conditionally_homing": false,
    "target_last_slow_factor": 1.0
}
```

### Ore
```gdscript
{
    "power": 1.5,             # Мощность (0.0-3.0)
    "max_reserve": 150.0,     # Максимальный запас
    "current_reserve": 150.0, # Текущий запас
    "hex": Hex.new(0, 0),     # Позиция руды
    "pulse_rate": 2.0         # Скорость пульсации (для визуализации)
}
```

### SlowEffect
```gdscript
{
    "slow_factor": 0.5,       # Множитель скорости (0.5 = 50%)
    "timer": 2.0              # Оставшееся время эффекта
}
```

### PoisonEffect
```gdscript
{
    "damage_per_sec": 10.0,
    "timer": 2.0,             # Оставшееся время
    "tick_timer": 1.0         # Таймер до следующего тика (1 сек)
}
```

### JadePoison (стакующийся)
```gdscript
{
    "target_id": 5,
    "instances": [
        {"duration": 5.0, "tick_timer": 1.0},
        {"duration": 4.5, "tick_timer": 0.5},
        ...
    ],
    "damage_per_stack": 10.0,
    "slow_factor_per_stack": 0.05
}
```

### AuraEffect
```gdscript
{
    "speed_multiplier": 2.0   # Множитель скорости атаки
}
```

### Aura (на башне DE)
```gdscript
{
    "radius": 2,              # В гексах
    "speed_multiplier": 2.0
}
```

### DamageFlash
```gdscript
{
    "timer": 0.2              # Длительность вспышки
}
```

### Laser
```gdscript
{
    "target_pos": Vector2(100, 200),
    "timer": 0.15,
    "spawn_height": 0.0       # Для 3D
}
```

### AoeEffect
```gdscript
{
    "max_radius": 50.0,
    "current_radius": 0.0,
    "timer": 0.25,
    "color": Color.RED
}
```

### EnergyLine
```gdscript
{
    "tower1_id": 1,
    "tower2_id": 2,
    "is_hidden": false        # Для режима перетаскивания
}
```

### Text
```gdscript
{
    "text": "100%",
    "offset": Vector2(0, -20),
    "color": Color.WHITE
}
```

### Combinable
```gdscript
{
    "crafts": [
        {
            "recipe_index": 0,
            "combination": [1, 2, 3],  # Entity IDs башен
            "output_id": "TOWER_SILVER"
        },
        ...
    ]
}
```

### Wave
```gdscript
{
    "wave_number": 1,
    "enemy_def_id": "ENEMY_NORMAL_WEAK",
    "enemies_to_spawn": 5,
    "spawn_interval": 0.8,
    "spawn_timer": 0.0,
    "current_path": [Hex.new(0, 0), ...],
    "damage_per_enemy": [10, 10, 10, 10, 10]
}
```

### PlayerState
```gdscript
{
    "level": 1,
    "current_xp": 0,
    "xp_to_next_level": 100,
    "health": 100
}
```

### Beacon (маяк)
```gdscript
{
    "current_angle": 0.0,
    "rotation_speed": 1.5,    # рад/сек
    "arc_angle": 1.5708,      # 90 градусов в радианах
    "tick_timer": 0.0
}
```

### BeaconSector (визуализация)
```gdscript
{
    "is_visible": true,
    "range": 4.0,
    "arc": 1.5708,
    "angle": 0.0
}
```

### VolcanoAura
```gdscript
{
    "radius": 2,              # В гексах
    "tick_timer": 0.0,
    "tick_interval": 0.25     # 4 тика/сек
}
```

### VolcanoEffect (визуальный)
```gdscript
{
    "max_radius": 30.0,
    "timer": 0.25,
    "color": Color.ORANGE
}
```

### ManualSelectionMarker
```gdscript
{
    "order": 0                # Порядок выбора
}
```

### GameState (глобальный, один экземпляр)
```gdscript
{
    "phase": GameTypes.GamePhase.BUILD_STATE,
    "current_wave": 0,
    "towers_built_this_phase": 0,
    "time_speed": 1.0,
    "paused": false
}
```

## Как использовать

### Создание сущности с компонентами

```gdscript
# Создаем врага
var enemy_id = ecs.create_entity()

# Добавляем компоненты
ecs.add_component(enemy_id, "position", {"x": 100.0, "y": 200.0})
ecs.add_component(enemy_id, "velocity", {"x": 50.0, "y": 0.0})
ecs.add_component(enemy_id, "health", {"current": 100, "max": 100})
ecs.add_component(enemy_id, "enemy", {
    "def_id": "ENEMY_NORMAL",
    "physical_armor": 10,
    "magical_armor": 5,
    "last_checkpoint_index": -1,
    "damage_to_player": 10
})
ecs.add_component(enemy_id, "renderable", {
    "color": Color.RED,
    "radius": 15.0,
    "visible": true
})
```

### Чтение компонентов в системе

```gdscript
# В системе MovementSystem
func update(delta: float):
    # Получаем всех врагов с position и velocity
    for entity_id in ecs.velocities.keys():
        if not entity_id in ecs.positions:
            continue
        
        var pos = ecs.positions[entity_id]
        var vel = ecs.velocities[entity_id]
        
        # Обновляем позицию
        pos.x += vel.x * delta
        pos.y += vel.y * delta
```

### Удаление компонентов

```gdscript
ecs.remove_component(enemy_id, "velocity")
```

### Проверка наличия компонента

```gdscript
if ecs.has_component(enemy_id, "enemy"):
    print("This is an enemy!")
```

## Заметки

1. **Position и Velocity** в коде — Vector2. Добавление через add_component("position", data) принимает данные в том виде, в каком они записываются в словарь (в т.ч. Vector2).

2. **Hex объекты**: Hex — класс, передаётся по ссылке.

3. **Неиспользуемые компоненты**: Ряд объявленных в ECS словарей (turrets, beacons, beacon_sectors, volcano_auras, volcano_effects, combinables, texts, aoe_effects, manual_selection_markers) нигде не заполняются — заготовки под спецбашни и крафт.

4. **Wave**: в коде поля wave_number, enemy_def_id, enemies_to_spawn, spawn_interval, spawn_timer, current_path, damage_per_enemy.

5. **Производительность**: для врагов и снарядов используется NodePool в EntityRenderer.

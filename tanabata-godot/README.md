# Tanabata - Godot Edition

## 🎯 Описание

Tower Defense на гексагональной карте с энергосетью (майнеры на руде, MST), процедурной генерацией карты и руды, тремя фазами (BUILD → выбор башен → WAVE). Перенос с Go в Godot (2D).

**Краткое описание проекта:** см. [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md).  
**Риски при расширении (новые башни, локации, прокачка, статистика):** см. [EXTENSION_RISKS.md](EXTENSION_RISKS.md).  
**Слои архитектуры и паттерны (Presentation / Application / Domain / Infrastructure):** см. [ARCHITECTURE_LAYERS.md](ARCHITECTURE_LAYERS.md).

## 📁 Структура проекта

```
tanabata-godot/
├── core/                    # ❤️ ЧИСТАЯ СИМУЛЯЦИЯ (БЕЗ GODOT)
│   ├── ecs/                 # Entity-Component-System (ecs_world.gd)
│   ├── systems/             # Игровые системы (input, wave, movement, combat, projectile, status_effect, aura, energy_network, ore_generation)
│   ├── hexmap/              # Гексагональная математика и карта
│   ├── types/               # Базовые типы и энумы (game_types.gd)
│   └── utils/               # Утилиты (union_find)
│
├── godot_adapter/           # 🎮 ИНТЕГРАЦИЯ С GODOT
│   ├── rendering/           # Рендеринг (entity, wall, ore, energy_line, aura, tower_preview)
│   └── ui/                  # UI (game_hud, info_panel)
│
├── data/                    # 📊 ДАННЫЕ (JSON)
│   ├── towers.json
│   ├── enemies.json
│   ├── recipes.json
│   ├── loot_tables.json
│   └── waves.json
│
├── assets/                  # 🎨 РЕСУРСЫ
│   ├── sprites/
│   ├── textures/
│   ├── fonts/
│   └── sounds/
│
├── scenes/                  # 🎬 СЦЕНЫ GODOT (МИНИМУМ)
│   ├── main.tscn           # Главная сцена
│   └── game_root.tscn      # Корневая игровая сцена
│
└── autoload/                # 🌐 АВТОЗАГРУЗКА (синглтоны)
    ├── game_manager.gd      # Главный менеджер
    └── config.gd            # Константы и настройки
```

## 🏗️ Архитектурные принципы

### 1. Разделение Core и Adapter

**CORE (чистая логика):**
- ❌ НЕ импортирует ничего из Godot
- ✅ Только GDScript, математика, структуры данных
- ✅ Полностью тестируемо без движка

**ADAPTER (интеграция):**
- ✅ Использует Godot API (Node, Sprite2D, Camera2D, etc.)
- ✅ Читает состояние из Core
- ✅ Рендерит и обрабатывает ввод

### 2. Игровой цикл

GameManager объявляет fixed timestep (30 тиков/сек) и `update_simulation(delta)`, но массив `systems` не заполняется — системы создаются в GameRoot и вызываются из `game_root._process()` с переменным delta (с учётом паузы и time_speed). Фактический порядок: input → wave → movement → status_effect → aura → combat → projectile. Рендереры обновляются в своём _process.

### 3. ECS в GDScript

Файл: `core/ecs/ecs_world.gd`, класс `ECSWorld`. Сущности — целочисленные ID, `entities[id] = true`. Компоненты хранятся в отдельных словарях: `positions`, `velocities`, `healths`, `towers`, `enemies`, `projectiles`, `ores`, `waves`, `game_state` и др. Методы: `create_entity()`, `destroy_entity()`, `add_component()`, `has_component()`. Позиции хранятся как Vector2.

## 🎮 Основные системы (порядок вызова из GameRoot)

1. **InputSystem** — очередь команд, размещение/снятие башен, выбор
2. **WaveSystem** — спавн врагов по таймеру в фазе WAVE
3. **MovementSystem** — движение врагов по пути
4. **StatusEffectSystem** — таймеры slow/poison
5. **AuraSystem** — буст скорострельности от аур
6. **CombatSystem** — атака башен (снаряды/лазеры), расход энергии
7. **ProjectileSystem** — полёт снарядов, попадание, урон, вспышки

Энергосеть (EnergyNetworkSystem) живёт в GameManager, вызывается при постановке/снятии башни и при смене фазы. Генерация руды (OreGenerationSystem) — один раз при старте. Крафт и отдельный OreSystem в цикле не реализованы. Рендеринг — несколько рендереров (Entity, Wall, Ore, EnergyLine, Aura, TowerPreview).

## 🗺️ Гексагональная карта (2D)

```gdscript
# core/hexmap/hex.gd
class_name Hex

var q: int
var r: int

func _init(q_: int, r_: int):
    q = q_
    r = r_

func to_pixel(hex_size: float) -> Vector2:
    var x = hex_size * (sqrt(3) * q + sqrt(3)/2 * r)
    var y = hex_size * (3.0/2.0 * r)
    return Vector2(x, y)

func distance_to(other: Hex) -> int:
    return (abs(q - other.q) + abs(r - other.r) + abs(s - other.s)) / 2  # s = -q - r
```

## 🎨 Рендеринг (2D)

- **Башни** — Polygon2D (круг/шестиугольник по типу), Line2D для обводки
- **Враги** — Polygon2D (квадрат), пул узлов
- **Снаряды** — Polygon2D (круг), пул узлов
- **Стены** — WallRenderer: Polygon2D гексы + Line2D соединения и обводка
- **Карта** — Polygon2D гексы, Line2D обводка
- **Энергосеть** — Line2D между башнями
- **Руда, ауры, лазеры** — Polygon2D / Line2D

## 📦 Данные (JSON → GDScript)

```gdscript
# Загрузка данных при старте
var tower_defs = load_json("res://data/towers.json")
var enemy_defs = load_json("res://data/enemies.json")

func load_json(path: String) -> Dictionary:
    var file = FileAccess.open(path, FileAccess.READ)
    var json = JSON.parse_string(file.get_as_text())
    file.close()
    return json
```

## 🚀 Состояние разработки

Реализовано: ECS, гексагональная карта и pathfinding, генерация руды, энергосеть (MST), все основные системы (input, wave, movement, combat, projectile, status_effect, aura), рендеринг (entity, wall, ore, energy_line, aura, tower_preview и др.), HUD, InfoPanel и Recipe Book (B), три фазы (BUILD → SELECTION → WAVE). **Крафт:** CraftingSystem, 5 рецептов (Silver, Malachite, Volcano, Lighthouse, Jade), игрок крафтит в фазе выбора по подсвеченной группе. **Спецбашни:** Volcano (AoE), Lighthouse (Beacon). Дальнейший план — DEVELOPMENT_PLAN.md.

## 🎯 Ключевые отличия от Go версии

| Аспект | Go (3D) | Godot (2D) |
|--------|---------|------------|
| Рендеринг | Raylib 3D (OBJ модели) | Godot 2D (Sprite2D) |
| Координаты | 3D позиции (x, y, z) | 2D позиции (x, y) |
| Камера | 3D Perspective/Ortho | 2D Camera2D |
| Башни | Цилиндры/кубы/модели | Спрайты с поворотом |
| Враги | Сферы | Спрайты (AnimatedSprite2D) |
| Линии энергии | 3D линии на высоте | Line2D на земле |
| Эффекты | 3D частицы | GPUParticles2D |

## 🔧 Настройки проекта

**project.godot:**
```ini
[application]
config/name="Tanabata"
run/main_scene="res://scenes/main.tscn"

[display]
window/size/viewport_width=1200
window/size/viewport_height=993

[rendering]
renderer/rendering_method="forward_plus"  # Лучшая производительность
textures/canvas_textures/default_texture_filter=0  # Pixel perfect
```

## 📚 Ресурсы и референсы

- **Hexagonal Grids:** https://www.redblobgames.com/grids/hexagons/
- **ECS Pattern:** https://github.com/SanderMertens/ecs-faq
- **Godot Best Practices:** https://docs.godotengine.org/en/stable/tutorials/best_practices/

## 🤝 Вклад

Проект в активной разработке. Механики переносятся из Go версии в Godot с адаптацией под 2D.

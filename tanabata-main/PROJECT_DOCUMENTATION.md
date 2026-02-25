# Tanabata - Tower Defense на Go с гексагональной картой

## Оглавление
1. [Обзор проекта](#обзор-проекта)
2. [Архитектура и паттерны](#архитектура-и-паттерны)
3. [Структура проекта](#структура-проекта)
4. [Игровые системы](#игровые-системы)
5. [Механики игры](#механики-игры)
6. [Данные и конфигурация](#данные-и-конфигурация)
7. [Рекомендации по написанию с нуля](#рекомендации-по-написанию-с-нуля)

---

## Обзор проекта

**Tanabata** — это 3D Tower Defense игра на языке Go с использованием библиотеки **Raylib** для рендеринга. Игра имеет гексагональную карту, систему крафта башен, уникальную механику энергосети и различные типы врагов.

### Основные особенности
- **Гексагональная карта** с процедурной генерацией
- **ECS архитектура** (Entity-Component-System)
- **3D рендеринг** с моделями .obj
- **Система энергосети** — башни требуют соединения с источниками энергии (рудой)
- **Система крафта** — комбинирование башен для создания более мощных
- **Система волн врагов** с различными типами и характеристиками
- **Чекпоинты** — враги должны проходить через определенные точки
- **Data-driven подход** — данные загружаются из JSON файлов

### Технологический стек
- **Язык:** Go 1.21+
- **Графика:** Raylib (через биндинги github.com/gen2brain/raylib-go)
- **Модели:** OBJ формат
- **Данные:** JSON

---

## Архитектура и паттерны

### Entity-Component-System (ECS)

Игра построена на классической ECS архитектуре, которая идеально подходит для gamedev:

```go
// internal/entity/ecs.go
type ECS struct {
    GameTime      float64
    NextID        types.EntityID
    Positions     map[types.EntityID]*component.Position
    Velocities    map[types.EntityID]*component.Velocity
    Healths       map[types.EntityID]*component.Health
    Towers        map[types.EntityID]*component.Tower
    Enemies       map[types.EntityID]*component.Enemy
    Projectiles   map[types.EntityID]*component.Projectile
    // ... много других компонентов
}
```

**Преимущества ECS:**
- Данные хранятся отдельно от логики
- Системы обрабатывают только нужные компоненты
- Легко добавлять новые сущности и поведения
- Хорошая производительность за счет кэш-локальности

### State Machine (Машина состояний)

Игра использует паттерн State Machine для управления состояниями:

```
MenuState → GameState ↔ PauseState
```

Каждое состояние реализует интерфейс:
```go
type State interface {
    Enter()
    Update(deltaTime float64)
    Draw()
    Exit()
}
```

### Event System (Система событий)

Для loose coupling между системами используется Event Dispatcher:

```go
// internal/event/types.go
const (
    EnemyKilled EventType = iota
    TowerPlaced
    TowerRemoved
    OreDepleted
    WaveEnded
    OreConsumed
    // ...
)
```

Системы могут подписываться на события:
```go
eventDispatcher.Subscribe(event.EnemyKilled, g.PlayerSystem)
eventDispatcher.Subscribe(event.TowerPlaced, g.CraftingSystem)
```

---

## Структура проекта

```
tanabata-main/
├── cmd/
│   └── game/
│       └── main.go              # Точка входа, главный цикл
├── internal/
│   ├── app/
│   │   ├── game.go              # Основная игровая логика
│   │   ├── energy_network.go    # Логика энергосети башен
│   │   ├── ore_generation.go    # Генерация жил руды
│   │   └── tower_management.go  # Управление башнями
│   ├── assets/
│   │   └── model_manager.go     # Загрузка 3D моделей
│   ├── component/               # ECS компоненты
│   │   ├── tower.go
│   │   ├── enemy.go
│   │   ├── combat.go
│   │   ├── projectile.go
│   │   └── ...
│   ├── config/
│   │   └── config.go            # Все константы и настройки
│   ├── defs/                    # Определения данных
│   │   ├── towers.go
│   │   ├── enemies.go
│   │   ├── recipes.go
│   │   ├── waves.go
│   │   └── loader.go
│   ├── entity/
│   │   └── ecs.go               # ECS контейнер
│   ├── event/
│   │   ├── event.go             # Система событий
│   │   └── types.go
│   ├── interfaces/              # Интерфейсы для DI
│   ├── state/                   # State Machine
│   │   ├── game_state.go
│   │   ├── menu_state.go
│   │   └── pause_state.go
│   ├── system/                  # ECS системы
│   │   ├── combat.go
│   │   ├── movement.go
│   │   ├── render.go
│   │   ├── wave.go
│   │   ├── projectile.go
│   │   └── ...
│   ├── types/
│   │   └── types.go             # Базовые типы (EntityID)
│   ├── ui/                      # UI компоненты
│   │   ├── info_panel.go
│   │   ├── recipe_book.go
│   │   └── ...
│   └── utils/
│       ├── coords.go
│       ├── math.go
│       └── prng.go
├── pkg/
│   ├── hexmap/                  # Гексагональная карта
│   │   ├── hex.go               # Математика гексов
│   │   ├── map.go               # Карта и генерация
│   │   └── pathfinding.go       # A* алгоритм
│   └── render/
│       ├── color.go
│       └── hex_renderer.go
├── assets/
│   ├── data/
│   │   ├── towers.json
│   │   ├── enemies.json
│   │   ├── recipes.json
│   │   └── loot_tables.json
│   ├── fonts/
│   │   └── arial.ttf
│   ├── models/                  # 3D модели в OBJ
│   └── textures/
└── go.mod
```

---

## Игровые системы

### 1. Система гексагональной карты (`pkg/hexmap/`)

Карта использует **осевые координаты** (Q, R) для гексов с "острой" ориентацией (pointy-top).

```go
type Hex struct {
    Q, R int
}

// Преобразование в пиксельные координаты
func (h Hex) ToPixel(hexSize float64) (x, y float64) {
    x = hexSize * (Sqrt3*float64(h.Q) + Sqrt3/2*float64(h.R))
    y = hexSize * (3.0 / 2.0 * float64(h.R))
    return
}
```

**Карта генерируется процедурно:**
1. Создается базовая гексагональная сетка заданного радиуса
2. Определяются Entry (вход) и Exit (выход)
3. Генерируются 6 чекпоинтов в случайном порядке
4. Процедурно добавляются/удаляются секции границы
5. Постобработка для удаления изолированных гексов

### 2. Система волн врагов (`internal/system/wave.go`)

```go
type WaveDefinition struct {
    EnemyID       string        // Тип врага
    Count         int           // Количество
    SpawnInterval time.Duration // Интервал спавна
}

var WavePatterns = map[int]WaveDefinition{
    1:  {EnemyID: "ENEMY_NORMAL_WEAK", Count: 5, SpawnInterval: 800*ms},
    // ... до волны 10 (босс)
}
```

После 10 волны — циклический повтор волн 6-10.

### 3. Система боя (`internal/system/combat.go`)

**Типы атак:**
- `PROJECTILE` — выпускает снаряд к цели
- `LASER` — мгновенный луч
- `AOE` — урон по площади
- `BEACON` — вращающийся луч (маяк)
- `NONE` — специальные башни (Вулкан)

**Типы урона:**
- `PHYSICAL` — уменьшается от физической брони
- `MAGICAL` — уменьшается от магической брони
- `PURE` — игнорирует броню
- `SLOW` — замедляет врага
- `POISON` — наносит урон со временем

```go
// Формула расчета урона
func ApplyDamage(ecs *entity.ECS, targetID types.EntityID, damage int, damageType AttackDamageType) {
    switch damageType {
    case defs.AttackPhysical:
        reduction := enemy.PhysicalArmor
        finalDamage = max(damage - reduction, 0)
    case defs.AttackMagical:
        reduction := enemy.MagicalArmor
        finalDamage = max(damage - reduction, 0)
    case defs.AttackPure:
        finalDamage = damage // Игнорирует броню
    }
}
```

### 4. Система энергосети (`internal/app/energy_network.go`)

Уникальная механика — башни работают только если соединены с источником энергии (рудой).

**Правила соединения:**
1. Любые башни соединяются на расстоянии 1 гекс
2. Башни-шахтеры соединяются на расстоянии до 3 гексов, если на одной линии
3. Сеть строится как MST (Minimum Spanning Tree) алгоритмом Крускала
4. Линии имеют коэффициент деградации — чем длиннее путь, тем меньше урон

```go
// Расчет множителя деградации
func calculateLineDegradationMultiplier(path []types.EntityID) float64 {
    attackerCount := 0
    for _, towerID := range path {
        if towerDef.Type != TowerTypeMiner && towerDef.Type != TowerTypeWall {
            attackerCount++
        }
    }
    return math.Pow(config.LineDegradationFactor, float64(attackerCount))
}
```

### 5. Система крафта (`internal/system/crafting.go`)

Башни можно комбинировать для создания более мощных:

```json
// assets/data/recipes.json
{
  "inputs": [
    {"id": "TA", "level": 1},
    {"id": "TA", "level": 1}
  ],
  "output_id": "TOWER_SILVER"
}
```

Система автоматически находит все возможные комбинации на карте.

### 6. Система рендеринга (`internal/system/render.go`)

- **Frustum culling** для оптимизации
- **Batch rendering** для снарядов
- Загрузка OBJ моделей
- Поддержка турелей с вращением

### 7. Система статус-эффектов

- `SlowEffect` — замедление
- `PoisonEffect` — урон со временем
- `JadePoisonContainer` — стакающийся яд от Jade башни
- `AuraEffect` — ускорение от DE башни

---

## Механики игры

### Фазы игры

```go
type GamePhase int
const (
    BuildState          GamePhase = iota  // Строительство
    WaveState                             // Волна врагов
    TowerSelectionState                   // Выбор башен для сохранения
)
```

### Типы башен

| ID | Название | Тип | Особенность |
|---|---|---|---|
| TA | Физ. атака | ATTACK | Физический урон |
| TE | Маг. атака | ATTACK | Магический урон |
| TO | Чист. атака | ATTACK | Чистый урон |
| PA/PE/PO | Сплит | ATTACK | 2 снаряда |
| DE | Аура | ATTACK | Ускоряет соседей |
| NI | Замедление | ATTACK | Slow эффект |
| NU | Яд | ATTACK | Poison эффект |
| TOWER_MINER | Шахтер | MINER | Добыча энергии |
| TOWER_WALL | Стена | WALL | Блокирует путь |
| TOWER_SILVER | Сильвер | ATTACK | Лазер, крафт |
| TOWER_VOLCANO | Вулкан | ATTACK | AOE урон, крафт |
| TOWER_LIGHTHOUSE | Маяк | ATTACK | Вращающийся луч, крафт |

### Типы врагов

| ID | Здоровье | Скорость | Физ. броня | Маг. броня |
|---|---|---|---|---|
| ENEMY_NORMAL_WEAK | 35 | 80 | 5 | 0 |
| ENEMY_NORMAL | 115 | 80 | 10 | 5 |
| ENEMY_TOUGH | 280 | 75 | 25 | 15 |
| ENEMY_MAGIC_RESIST | 240 | 80 | -20 | 80 |
| ENEMY_PHYSICAL_RESIST | 240 | 80 | 80 | -20 |
| ENEMY_FAST | 140 | 160 | 5 | 10 |
| ENEMY_BOSS | 6000 | 60 | 40 | 40 |

### Система руды

Карта содержит 3 жилы руды:
1. **Центральная** — слабая, 4 гекса
2. **Средняя** — на расстоянии 4-9, средняя
3. **Дальняя** — на расстоянии 10+, самая мощная

Руда расходуется при выстрелах башен (`shot_cost`).

---

## Данные и конфигурация

### config.go — центр всех констант

```go
const (
    ScreenWidth       = 1200
    ScreenHeight      = 993
    HexSize           = 20.0
    MapRadius         = 15
    ProjectileSpeed   = 200.0
    TowerTurnSpeed    = 3.14  // Скорость поворота турели
    // ... сотни других констант
)
```

### JSON файлы данных

- `towers.json` — определения всех башен
- `enemies.json` — определения всех врагов
- `recipes.json` — рецепты крафта
- `loot_tables.json` — таблицы дропа

---

## Рекомендации по написанию с нуля

### Этап 1: Основы (1-2 недели)

1. **Изучите гексагональную математику**
   - Рекомендую статью [Red Blob Games - Hexagonal Grids](https://www.redblobgames.com/grids/hexagons/)
   - Осевые координаты (axial) — оптимальный выбор

2. **Выберите архитектуру**
   - ECS — лучший выбор для игр
   - State Machine — для управления состояниями

3. **Создайте базовую структуру**
   ```
   cmd/game/main.go
   internal/entity/ecs.go
   internal/component/
   internal/system/
   pkg/hexmap/
   ```

### Этап 2: Рендеринг (1 неделя)

1. **Начните с 2D**
   - Отрисуйте гексагональную сетку
   - Реализуйте преобразование координат

2. **Перейдите к 3D**
   - Raylib отлично подходит для 3D
   - Используйте ортографическую камеру для начала

### Этап 3: Игровая логика (2-3 недели)

1. **Реализуйте A\* pathfinding**
   ```go
   func AStar(start, goal Hex, hm *HexMap) []Hex
   ```

2. **Система волн**
   - Спавн врагов
   - Движение по пути

3. **Система башен**
   - Размещение
   - Атака по врагам
   - Снаряды

### Этап 4: Продвинутые механики (2+ недели)

1. **Система энергосети** (если нужна)
2. **Крафт**
3. **Разные типы башен и атак**
4. **Статус-эффекты**

### Советы по коду

**1. Используйте data-driven подход**
```go
// Плохо
damage := 25
if towerType == "TA" { damage = 25 }
else if towerType == "TE" { damage = 30 }

// Хорошо
damage := towerDef.Combat.Damage
```

**2. Избегайте глобального состояния**
```go
// Плохо
var globalGame *Game

// Хорошо
func NewSystem(ecs *entity.ECS, dispatcher *event.Dispatcher) *System
```

**3. Используйте интерфейсы для тестируемости**
```go
type GameContext interface {
    GetHexMap() *hexmap.HexMap
    GetClearedCheckpoints() map[hexmap.Hex]bool
}
```

**4. Разделяйте данные и логику**
```
internal/defs/     — структуры данных
internal/system/   — логика обработки
internal/component/ — ECS компоненты
```

**5. События вместо прямых вызовов**
```go
// Плохо
playerSystem.AddXP(10)

// Хорошо
dispatcher.Dispatch(event.Event{Type: event.EnemyKilled, Data: enemyID})
```

### Оптимизация

1. **Используйте профайлер Go**
   ```go
   go func() {
       log.Println(http.ListenAndServe("localhost:6060", nil))
   }()
   ```

2. **Frustum culling** — не рендерите то, что не видно

3. **Object pooling** — переиспользуйте снаряды

4. **Spatial partitioning** — для поиска целей в радиусе

### Инструменты разработки

1. **Флаг dev mode** для быстрого тестирования:
   ```go
   devMode := flag.Bool("dev", false, "Start directly in game")
   ```

2. **Горячие клавиши** для отладки:
   - F3 — визуальный дебаг
   - F5 — перезагрузка моделей
   - F10 — god mode

3. **Экспорт данных**:
   ```go
   exportModels := flag.Bool("export-models", false, "Export models")
   ```

---

## Заключение

Этот проект демонстрирует профессиональный подход к разработке игр на Go:

- **Чистая архитектура** с ECS и State Machine
- **Data-driven** дизайн
- **Модульность** — системы независимы друг от друга
- **Расширяемость** — легко добавить новые башни/врагов через JSON

Основные сложности:
1. Гексагональная математика (особенно pathfinding)
2. Система энергосети (граф с MST)
3. Синхронизация UI с игровым состоянием

Проект хорошо подходит как reference для изучения gamedev на Go.




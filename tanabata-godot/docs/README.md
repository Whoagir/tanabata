# Документация проекта Tanabata (Godot)

Описание всех систем и механик проекта. Только текст, без кода.

**Одно общее описание (лаконичное):** в корне проекта **[PROJECT_OVERVIEW.md](../PROJECT_OVERVIEW.md)** — о чём игра, что есть в проекте, что происходит по шагам, технологии. Чуть подробнее в **[00-overview](00-overview.md)** (обзор + поток фаз + кратко реализовано).

В корне также: **DEVELOPMENT_PLAN.md** — приоритизированный план разработки.

**Вся документация в одном файле:** [ALL_DOCS.md](ALL_DOCS.md) (исходные файлы не удалены).

## Содержание

**Общее**
- [28-game-mechanics](28-game-mechanics.md) — **краткое описание игры и все механики**
- [00-overview](00-overview.md) — обзор проекта
- [IMPLEMENTED](IMPLEMENTED.md) — **итог: что реализовано**
- [01-architecture](01-architecture.md) — архитектура
- [02-ecs](02-ecs.md) — ECS
- [03-game-phases](03-game-phases.md) — фазы игры
- [24-game-types](24-game-types.md) — типы и константы

**Карта и путь**
- [04-hexmap](04-hexmap.md) — гексагональная карта
- [05-pathfinding](05-pathfinding.md) — поиск пути

**Системы**
- [06-systems-input](06-systems-input.md) — ввод (в т.ч. редактор энерголиний U)
- [07-systems-wave](07-systems-wave.md) — волны
- [08-systems-movement](08-systems-movement.md) — движение врагов
- [09-systems-combat](09-systems-combat.md) — бой
- [10-systems-projectile](10-systems-projectile.md) — снаряды и эффекты
- [11-systems-energy-network](11-systems-energy-network.md) — энергосеть
- [ENERGY_NETWORK_LINES_BUG_ANALYSIS](ENERGY_NETWORK_LINES_BUG_ANALYSIS.md) — разбор бага пропадания линий при пустых майнерах и исправление (handle_tower_removal не удаляет линии по is_active)
- [ENERGY_NETWORK_RISKS_AND_EDGE_CASES](ENERGY_NETWORK_RISKS_AND_EDGE_CASES.md) — риски и неочевидное поведение энергосети (корни батареи, rebuild при истощении, режим U, кэш питания, мосты и др.)
- [12-systems-ore-generation](12-systems-ore-generation.md) — генерация руды
- [31-systems-auriga](31-systems-auriga.md) — башня Auriga (линия урона)

**Рендеринг**
- [13-rendering-overview](13-rendering-overview.md) — обзор
- [14-rendering-entity](14-rendering-entity.md) — башни, враги, снаряды, лазеры
- [15-rendering-wall](15-rendering-wall.md) — стены
- [16-rendering-energy-lines](16-rendering-energy-lines.md) — линии энергосети
- [17-rendering-ore](17-rendering-ore.md) — руда
- [18-rendering-tower-preview](18-rendering-tower-preview.md) — превью башни

**UI и сцены**
- [19-ui-hud](19-ui-hud.md) — HUD (в т.ч. режим U — редактор линий)
- [20-game-root](20-game-root.md) — главная сцена
- [32-boss-reward-cards](32-boss-reward-cards.md) — награда за босса (карты благословений/проклятий)

**Данные и конфиг**
- [21-data-json](21-data-json.md) — JSON данные
- [22-config](22-config.md) — конфигурация
- [23-game-manager](23-game-manager.md) — GameManager

**Утилиты**
- [25-union-find](25-union-find.md) — Union-Find
- [26-node-pool](26-node-pool.md) — пул узлов
- [27-profiler](27-profiler.md) — профилировщик

**Механики, логи, туториал**
- [28-game-mechanics](28-game-mechanics.md) — описание игры и все механики
- [29-logging-analytics](29-logging-analytics.md) — логи после волны, сводная таблица (успех, руда по вышкам), папка **scripts/** (plot_wave_logs.py: графики успеха и руды по вышкам, balance_tiers.py), [wave_charts.html](wave_charts.html) (интерактивные графики)
- [30-level-config-tutorial](30-level-config-tutorial.md) — LevelConfig и уровни обучения (0–4)
- [SPEED_AND_SLOW_BALANCE](SPEED_AND_SLOW_BALANCE.md) — баланс скорости врагов, замедлений (NI, Jade, Кварц), длительность волн

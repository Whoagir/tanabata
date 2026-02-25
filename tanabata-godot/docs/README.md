# Документация проекта Tanabata (Godot)

Описание всех систем и механик проекта. Только текст, без кода.

В корне проекта: **PROJECT_OVERVIEW.md** — краткое описание: о чём игра, что есть, что происходит по шагам. **DEVELOPMENT_PLAN.md** — приоритизированный план разработки (что делаем дальше).

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
- [06-systems-input](06-systems-input.md) — ввод
- [07-systems-wave](07-systems-wave.md) — волны
- [08-systems-movement](08-systems-movement.md) — движение врагов
- [09-systems-combat](09-systems-combat.md) — бой
- [10-systems-projectile](10-systems-projectile.md) — снаряды и эффекты
- [11-systems-energy-network](11-systems-energy-network.md) — энергосеть
- [12-systems-ore-generation](12-systems-ore-generation.md) — генерация руды

**Рендеринг**
- [13-rendering-overview](13-rendering-overview.md) — обзор
- [14-rendering-entity](14-rendering-entity.md) — башни, враги, снаряды, лазеры
- [15-rendering-wall](15-rendering-wall.md) — стены
- [16-rendering-energy-lines](16-rendering-energy-lines.md) — линии энергосети
- [17-rendering-ore](17-rendering-ore.md) — руда
- [18-rendering-tower-preview](18-rendering-tower-preview.md) — превью башни

**UI и сцены**
- [19-ui-hud](19-ui-hud.md) — HUD
- [20-game-root](20-game-root.md) — главная сцена

**Данные и конфиг**
- [21-data-json](21-data-json.md) — JSON данные
- [22-config](22-config.md) — конфигурация
- [23-game-manager](23-game-manager.md) — GameManager

**Утилиты**
- [25-union-find](25-union-find.md) — Union-Find
- [26-node-pool](26-node-pool.md) — пул узлов
- [27-profiler](27-profiler.md) — профилировщик

# Рендеринг (обзор)

## Слои сцены

Карта и игровые объекты рисуются на разных слоях (Node2D) с разным z_index:

- HexLayer — гексы карты.
- TowerLayer — башни.
- EnemyLayer — враги.
- ProjectileLayer — снаряды.
- EffectLayer — volcano/beacon эффекты. Лазеры рисуются на LaserLayer (внутри EntityRenderer).

## Рендереры

- **EntityRenderer** — башни, враги, снаряды, лазеры, volcano_effects. Использует пулы узлов.
- **WallRenderer** — стены и линии между ними, обводка.
- **EnergyLineRenderer** — линии энергосети между башнями.
- **OreRenderer** — руда (пульсирующая подсветка).
- **AuraRenderer** — круги аур активных башен.
- **TowerPreview** — полупрозрачный превью башни под курсором.

## Object Pooling

Для врагов и снарядов используется пул узлов. При создании сущности — взять узел из пула. При удалении — вернуть в пул. Меньше созданий и удалений узлов.

## Оптимизации рендеринга

- **Dirty flags** — `AuraRenderer` обновляет круги только при изменении состояния башни (is_active, radius, hex). `PathOverlayLayer` перерисовывает только при изменении `hash(future_path)`, cleared_checkpoints или фазы — не каждый кадр.
- **Dictionary lookup для эффектов** — лазеры (`laser_nodes`), volcano effects (`volcano_effect_nodes`), beacon sectors (`beacon_sector_nodes`) используют Dictionary id→node вместо `get_children()` + парсинг строковых имён.
- **Scale вместо polygon regen** — пульсация руды (OreRenderer) через `circle.scale` вместо пересоздания PackedVector2Array из 32 точек каждый кадр. Volcano effects используют unit-circle + scale.

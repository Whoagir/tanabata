# MovementSystem (система движения)

## Назначение

Передвигает врагов по пути от точки входа к выходу через чекпоинты.

## Когда работает

Только в фазе WAVE.

## Как движется враг

У каждого врага есть путь — массив гексов (path.hexes, path.current_index). Текущая цель — гекс по индексу. Позиция цели в пикселях — target_hex.to_pixel(). Направление — от текущей позиции к цели. Эффективная скорость умножается на **get_combined_slow_factor** (slow_effects: стаки замедлений от NI, Грус, Парайба и др.), **flying_aura_slows** (Кварц — только летающие), jade_poisons (замедление по стакам яда Jade). Ауры с **all_enemies_slow** (Парайба): в радиусе враги получают запись в slow_effects (50% slow); при выходе из ауры накладывается дебафф 30% slow на 2 с (тоже через slow_effects). Обработка — **_update_all_enemies_aura_slows()** в начале update().

## Достижение точки

Когда враг достаточно близко к целевой точке, current_index увеличивается. При переходе на новый гекс вызывается **_apply_environmental_damage(enemy_id, hex)** (см. ниже). Если индекс достиг конца пути — враг считается дошедшим: наносится урон игроку (_damage_player), вызываются GameManager.record_enemy_wave_progress и on_enemy_reached_exit; **game_state["alive_enemies_count"]** уменьшается на 1 (так как kill_enemy при выходе не вызывается), затем сущность удаляется (destroy_entity).

## Экологический урон (environmental damage)

При входе врага на гекс применяется **_apply_environmental_damage**:

- **Руда:** если гекс — жила руды и current_reserve >= ORE_DEPLETION_THRESHOLD, добавляется **ENV_DAMAGE_ORE_PER_TICK** (фиксированный урон за тик).
- **Энерголиния:** если гекс принадлежит линии энергосети (line_hex_set), урон от линии: **max(1, int(ore_amount * player_level / 40.0))**, где ore_amount — текущая сумма руды в сети (get_ore_network_totals().total_current), player_level — уровень игрока. Урон в 8 раз ниже прежней формулы (/5), чтобы не доминировал над боем.

Итоговый урон вычитается из health; при смерти вызывается kill_enemy. Показывается damage_flash.

## Обновление позиции

Позиция обновляется по направлению к текущей цели: pos + direction * (effective_speed * delta). Компонент velocity не используется для движения (движение по пути).

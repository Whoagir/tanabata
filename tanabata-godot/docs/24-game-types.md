# GameTypes (типы и константы)

## Фазы игры

- BUILD_STATE — строительство.
- WAVE_STATE — волна врагов.
- TOWER_SELECTION_STATE — выбор башен.

## Типы башен

- ATTACK — атакующая.
- MINER — майнер.
- WALL — стена.

## Типы атак

- PROJECTILE — снаряд (split, impact_burst, JADE_POISON).
- LASER — лазер (опционально slow).
- AREA_OF_EFFECT — Volcano (AoE по области).
- BEACON — Lighthouse (вращающийся луч).
- NONE — нет атаки (поддержка, ауры).

## Типы урона

- PHYSICAL — уменьшается физ. броней.
- MAGICAL — уменьшается маг. броней.
- PURE — игнорирует броню.
- SLOW, POISON — с эффектами (реализованы в StatusEffectSystem и ProjectileSystem).
- INTERNAL — внутренний (спецбашни).

## События

- ENEMY_KILLED, TOWER_PLACED, TOWER_REMOVED.
- ORE_DEPLETED, WAVE_ENDED, ORE_CONSUMED.
- COMBINE_TOWERS_REQUEST, TOGGLE_TOWER_SELECTION_FOR_SAVE_REQUEST.
- ENEMY_REMOVED_FROM_GAME.

## Утилиты

Функции перевода enum в строку для отладки. Функция цвета по типу урона.

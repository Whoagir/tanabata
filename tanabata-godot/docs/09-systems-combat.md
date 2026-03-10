# CombatSystem (система боя)

## Назначение

Управляет атакой башен: поиск целей, создание снарядов или лазеров, учёт энергии.

## Когда работает

Только в фазе WAVE. Только для башен с компонентом combat и is_active = true.

## Поиск целей

Для каждой башни ищутся враги в радиусе (range из combat). Учитываются только живые враги (health > 0). Цели сортируются по расстоянию. Берётся до split_count целей (ближайшие). Радиус считается в гексах через distance_to.

## Энергия

Башня может стрелять, только если есть доступ к энергии. Источники — смешанные: жилы под майнерами и батареями (type "ore") и батареи в режиме разряда с запасом (type "battery"). EnergyNetworkSystem._find_power_sources возвращает массив таких источников; запас — get_power_source_reserve, списание — consume_from_power_source. Результат поиска источников кэшируется на 0.5 секунды. **Эффективная стоимость выстрела:** для башен с аурой (DE, DA и т.д.) — shot_cost × Config.get_aura_ore_cost_factor(player_level); если у башни есть аура скорости (speed_multiplier > 1) — дополнительно × Config.get_aura_speed_ore_cost_factor(player_level). Для башен под aura_effects стоимость делением на speed_mult не увеличивает расход руды в секунду. Суммарный запас по всем источникам должен быть не меньше effective_cost. При выстреле энергия списывается с одного выбранного источника (оре или батарея). **Множитель урона от руды в сети** — только get_network_ore_damage_mult(tower_id) (доля руды в сети: много — 1.0, мало — до 1.5); отдельного буста от «выбранной жилы» нет.

## Типы атак

**PROJECTILE** — создаются сущности снарядов. В proj_data передаётся **projectile_speed_multiplier** из attack.params (если есть); иначе скорость из Config. Урон учитывает: множитель от руды в сети (get_network_ore_damage_mult), **MVP** (get_mvp_damage_mult: 1.0 + mvp_level×0.2), **сопротивление сети** (get_resistance_mult: max(0, 1 - resistance)), ранний крафт (get_early_craft_curse_damage_multiplier), бонус от ауры урона. Поддержка split_count, impact_burst (Malachite, U235 и др.: fragment_count, radius_hex, fixed_damage, fragment_speed_multiplier в params), JADE_POISON (Jade). Перед нанесением урона в ProjectileSystem/Volcano/Beacon проверяется **roll_evasion** — при успехе урона и эффектов нет (визуал попадания остаётся).

**Формула урона (общая):** `final_damage = base_damage × network_ore_mult × mvp_mult × resistance_mult × early_mult` (+ карты, бонус ауры урона). То же применяется к лазеру, вулкану, маяку, ауриге, чейн-лайтнингу.

**LASER** — мгновенный урон с учётом MVP и сети; для каждой цели проверка roll_evasion. Создаётся визуальный эффект (линия на Config.LASER_DURATION; толщина и цвет по def_id: Пинк 4/8 px, Хьюдж 7/12 px, при крите луч красный). Если в attack.params есть slow_multiplier и slow_duration — применяется замедление (Silver 30%, Silver Knight 40%, Huge 60%). Типы урона: PHYSICAL, MAGICAL, PURE или **SPLIT** (50% физ + 50% пуре, бонус карты к физ. части). При **SPLIT** урон применяется двумя вызовами (физ и пуре). Если в params есть **crit_chance** и **crit_mult** — для каждой цели свой бросок крита; при крите создаётся эффект с is_crit (толщина луча больше, цвет красный, в точке попадания — осколки-треугольники: 3 для Пинка, 6 для Хьюдж). У Хьюдж при крите дополнительно **crit_splash_radius_hex** и **crit_splash_factor**: враги в радиусе 0.7 гекса от цели получают 30% урона крита (половинки физ/пуре).

**NONE / AREA_OF_EFFECT** — пропускаются CombatSystem; Volcano и Lighthouse используют VolcanoSystem и BeaconSystem (там тоже учёт MVP и evasion).

## Cooldown

После выстрела ставится перезарядка: 1 / fire_rate секунд. Башня не стреляет, пока cooldown > 0. Каждый кадр cooldown уменьшается на delta (с учётом aura_effects — множитель скорости атаки).

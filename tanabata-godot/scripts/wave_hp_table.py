#!/usr/bin/env python3
"""
Суммарное HP по волнам: сырое и эффективное (EHP) против физ/маг/чистого урона.
Логика совпадает с WaveSystem: health_override, health_multiplier, health_multiplier_modifier,
множители по номеру волны (1-3: 0.6, 5-6: 0.95, 8: 1.25, 11: 0.76, 37: 3, 38: 3, 39: 4).
Сложность MEDIUM (diff_health=1.0, бонусы брони 0).
Формула брони: factor = 1 - (0.06*armor)/(1+0.06*|armor|); EHP = HP / factor.
Чистый урон: factor_pure и (1 - pure_damage_resistance).
"""
import json
import os

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(SCRIPT_DIR, "..", "data")
WAVES_PATH = os.path.join(DATA_DIR, "waves.json")
ENEMIES_PATH = os.path.join(DATA_DIR, "enemies.json")

ENEMY_SPEED_GLOBAL_MULT = 0.9
ENEMY_SPEED_TOUGH_MULT = 0.97
ENEMY_SPEED_DARKNESS_MULT = 0.96
ENEMY_SPEED_BOSS_MULT = 0.92
REF_SPEED = 80.0
PATH_LENGTH_START = 150.0
PATH_LENGTH_END = 900.0
REGEN_REF_SEC = 10.0

# Sposobnosti: uchet v EHP
EVASION_MULT = lambda ev: 1.0 / (1.0 - ev) if ev < 1.0 else 10.0
REFLECTION_SAVE = 0.95
REACTIVE_ARMOR_BONUS = 12
UNTOUCHABLE_REDUCTION = 0.6
DISARM_REDUCTION = 0.9
BLINK_SPEED_MULT = 1.2
RUSH_SPEED_MULT = 1.4
HUS_REGEN_MULT = 1.9
FLYING_PATH = 150.0


def path_length_for_wave(wn: int) -> float:
    if wn <= 1:
        return PATH_LENGTH_START
    if wn >= 40:
        return PATH_LENGTH_END
    return PATH_LENGTH_START + (PATH_LENGTH_END - PATH_LENGTH_START) * (wn - 1) / 39.0


def _enemy_speed(enemy_id: str, base_speed: float, wave_def: dict) -> float:
    s = base_speed * wave_def.get("speed_multiplier", 1.0) * wave_def.get("speed_multiplier_modifier", 1.0)
    s *= ENEMY_SPEED_GLOBAL_MULT
    if enemy_id in ("ENEMY_TOUGH", "ENEMY_TOUGH_2"):
        s *= ENEMY_SPEED_TOUGH_MULT
    elif enemy_id in ("ENEMY_DARKNESS_1", "ENEMY_DARKNESS_2"):
        s *= ENEMY_SPEED_DARKNESS_MULT
    elif enemy_id == "ENEMY_BOSS":
        s *= ENEMY_SPEED_BOSS_MULT
    return s


def armor_to_damage_factor(armor: float) -> float:
    if armor == 0.0:
        return 1.0
    return 1.0 - (0.06 * armor) / (1.0 + 0.06 * abs(armor))


def get_enemy_def(enemies_by_id: dict, enemy_id: str) -> dict:
    return enemies_by_id.get(enemy_id, {})


def wave_number_mult(wn: int) -> float:
    if 1 <= wn <= 3:
        return 0.6
    if 5 <= wn <= 6:
        return 0.95
    if wn == 8:
        return 1.25
    if wn == 11:
        return 0.76
    if wn == 37:
        return 3.0
    if wn == 38:
        return 3.0
    if wn == 39:
        return 4.0
    return 1.0


def compute_wave_entries(wave_def: dict, enemies_by_id: dict, wn: int) -> list:
    """Возвращает список (enemy_id, count, base_health, phys_armor, mag_armor, pure_armor, pure_resist)."""
    entries = []
    if "enemies" in wave_def:
        for e in wave_def["enemies"]:
            enemy_id = e["enemy_id"]
            count = e.get("count", 1)
            enemy_def = get_enemy_def(enemies_by_id, enemy_id)
            if not enemy_def:
                continue
            flying = enemy_def.get("flying", False)
            health_mult = wave_def.get("health_multiplier", 1.0)
            if "health_multiplier_flying" in wave_def and "health_multiplier_ground" in wave_def:
                health_mult = wave_def["health_multiplier_flying"] if flying else wave_def["health_multiplier_ground"]
            health_mult *= wave_def.get("health_multiplier_modifier", 1.0)
            base_health = wave_def.get("health_override", enemy_def.get("health", 100))
            if base_health <= 0:
                base_health = enemy_def.get("health", 100)
            base_health = int(base_health * health_mult * 1.0)  # diff_health=1
            base_health = max(1, int(base_health * wave_number_mult(wn)))
            phys_bonus = wave_def.get("physical_armor_bonus", 0)
            mag_bonus = wave_def.get("magical_armor_bonus", 0)
            mag_armor = (enemy_def.get("magical_armor", 0) + mag_bonus) * wave_def.get("magical_armor_multiplier", 1.0)
            pure_resist = wave_def.get("pure_damage_resistance", 0.0)
            speed = _enemy_speed(enemy_id, enemy_def.get("speed", 80.0), wave_def)
            abilities = e.get("abilities", wave_def.get("abilities", []))
            if not isinstance(abilities, list):
                abilities = list(abilities) if abilities else []
            else:
                abilities = list(abilities)
            if enemy_id == "ENEMY_HEALER" and wn == 34:
                if "bkb" not in abilities:
                    abilities.append("bkb")
            evasion_chance = float(e.get("evasion_chance", wave_def.get("evasion_chance", 0.0)))
            regen = wave_def.get("regen", 0.0) * wave_def.get("regen_multiplier_modifier", 1.0)
            entries.append({
                "enemy_id": enemy_id,
                "count": count,
                "base_health": base_health,
                "phys_armor": enemy_def.get("physical_armor", 0) + phys_bonus,
                "mag_armor": mag_armor,
                "pure_armor": enemy_def.get("pure_armor", 0),
                "pure_resist": pure_resist,
                "speed": speed,
                "flying": flying,
                "abilities": abilities,
                "evasion_chance": evasion_chance,
                "regen": regen,
            })
    else:
        enemy_id = wave_def.get("enemy_id", "")
        count = wave_def.get("count", 0)
        enemy_def = get_enemy_def(enemies_by_id, enemy_id)
        if not enemy_def:
            return entries
        flying = enemy_def.get("flying", False)
        health_mult = wave_def.get("health_multiplier", 1.0)
        if "health_multiplier_flying" in wave_def and "health_multiplier_ground" in wave_def:
            health_mult = wave_def["health_multiplier_flying"] if flying else wave_def["health_multiplier_ground"]
        health_mult *= wave_def.get("health_multiplier_modifier", 1.0)
        base_health = wave_def.get("health_override", enemy_def.get("health", 100))
        if base_health <= 0:
            base_health = enemy_def.get("health", 100)
        base_health = int(base_health * health_mult * 1.0)
        base_health = max(1, int(base_health * wave_number_mult(wn)))
        phys_bonus = wave_def.get("physical_armor_bonus", 0)
        mag_bonus = wave_def.get("magical_armor_bonus", 0)
        mag_armor = (enemy_def.get("magical_armor", 0) + mag_bonus) * wave_def.get("magical_armor_multiplier", 1.0)
        pure_resist = wave_def.get("pure_damage_resistance", 0.0)
        speed = _enemy_speed(enemy_id, enemy_def.get("speed", 80.0), wave_def)
        abilities = wave_def.get("abilities", [])
        if not isinstance(abilities, list):
            abilities = list(abilities) if abilities else []
        else:
            abilities = list(abilities)
        if enemy_id == "ENEMY_HEALER" and wn == 34:
            if "bkb" not in abilities:
                abilities.append("bkb")
        evasion_chance = float(wave_def.get("evasion_chance", 0.0))
        regen = wave_def.get("regen", 0.0) * wave_def.get("regen_multiplier_modifier", 1.0)
        entries.append({
            "enemy_id": enemy_id,
            "count": count,
            "base_health": base_health,
            "phys_armor": enemy_def.get("physical_armor", 0) + phys_bonus,
            "mag_armor": mag_armor,
            "pure_armor": enemy_def.get("pure_armor", 0),
            "pure_resist": pure_resist,
            "speed": speed,
            "flying": flying,
            "abilities": abilities,
            "evasion_chance": evasion_chance,
            "regen": regen,
        })
    return entries


def main():
    with open(WAVES_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    waves = data.get("waves", [])

    with open(ENEMIES_PATH, "r", encoding="utf-8") as f:
        enemies_list = json.load(f)
    enemies_by_id = {e["id"]: e for e in enemies_list}

    rows = []
    for w in waves:
        wn = w.get("wave_number", 0)
        entries = compute_wave_entries(w, enemies_by_id, wn)
        path_len = path_length_for_wave(wn)
        total_raw = 0
        total_regen_per_sec = 0.0
        total_ehp_phys = 0.0
        total_ehp_mag = 0.0
        total_ehp_pure = 0.0
        mixed_ehp = 0.0
        effective_total_hp = 0.0
        speed_sum = 0.0
        total_count = 0
        for e in entries:
            ab = e.get("abilities", [])
            regen_sec = e["regen"]
            if "hus" in ab:
                regen_sec *= HUS_REGEN_MULT
            effective_hp_raw = e["base_health"] + regen_sec * REGEN_REF_SEC
            total_raw += e["base_health"] * e["count"]
            total_regen_per_sec += regen_sec * e["count"]
            total_count += e["count"]
            speed_sum += e["speed"] * e["count"]

            phys_a = float(e["phys_armor"])
            mag_a = float(e["mag_armor"])
            if "reactive_armor" in ab:
                phys_a += REACTIVE_ARMOR_BONUS
                mag_a += REACTIVE_ARMOR_BONUS
            f_phys = armor_to_damage_factor(phys_a) if "ivasion" not in ab else 0.0
            f_mag = armor_to_damage_factor(mag_a) if "bkb" not in ab else 0.0
            f_pure = armor_to_damage_factor(float(e["pure_armor"])) * (1.0 - e["pure_resist"])
            f_sum = f_phys + f_mag + f_pure
            if f_sum <= 0:
                f_sum = 1.0

            ability_mult = 1.0
            ev = e.get("evasion_chance", 0.0)
            if ev > 0 and ev < 1.0:
                ability_mult *= 1.0 / (1.0 - ev)
            if "reflection" in ab:
                ability_mult *= 1.0 / REFLECTION_SAVE
            if "untouchable" in ab:
                ability_mult *= 1.0 / UNTOUCHABLE_REDUCTION
            if "disarm" in ab:
                ability_mult *= 1.0 / DISARM_REDUCTION

            speed_eff = e["speed"]
            if "blink" in ab:
                speed_eff *= BLINK_SPEED_MULT
            if "rush" in ab:
                speed_eff *= RUSH_SPEED_MULT
            path_eff = FLYING_PATH if e["flying"] else path_len

            per_unit = (effective_hp_raw / f_sum) * ability_mult
            mixed_ehp += per_unit * e["count"]
            effective_total_hp += per_unit * (path_eff / speed_eff) * e["count"]

            hp_eff = effective_hp_raw * ability_mult
            if f_phys > 0:
                total_ehp_phys += (hp_eff / f_phys) * e["count"]
            else:
                total_ehp_phys += hp_eff * e["count"]
            if f_mag > 0:
                total_ehp_mag += (hp_eff / f_mag) * e["count"]
            else:
                total_ehp_mag += hp_eff * e["count"]
            if f_pure > 0:
                total_ehp_pure += (hp_eff / f_pure) * e["count"]
            else:
                total_ehp_pure += hp_eff * e["count"]

        avg_speed = speed_sum / total_count if total_count else 0.0
        rows.append((wn, total_raw, total_regen_per_sec, total_ehp_phys, total_ehp_mag, total_ehp_pure, avg_speed, mixed_ehp, effective_total_hp))

    out_path = os.path.join(DATA_DIR, "WAVE_HP_TABLE.md")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("# Суммарное HP по волнам (сложность MEDIUM)\n\n")
        f.write("Учтены способности: уклонение (EHP x1/(1-ev)), БКБ/Ивейжн (маг/физ=0), рефлекшн (сейв 5%%), "
                "реактивная броня (+12 к броне), неприкасаемый (-40%% урона), блинк (+20%% скорости), раш (+40%%), "
                "разоружение (-10%% получаемого урона), хус (реген x1.9). Летающие: путь 150 гексов (лабиринт 150-900 по волнам). "
                "Реген: эквивалент HP за 10 сек добавлен к живучести; общий реген/с по волне в таблице.\n\n")
        f.write("| Волна | Сырое HP | Реген/с | EHP (физ) | EHP (маг) | EHP (пуре) | Скорость | mixed EHP | Общее эфф. HP |\n")
        f.write("|------|----------|---------|-----------|-----------|------------|----------|-----------|---------------|\n")
        for r in rows:
            wn, raw, regen_sec, ehp_phys, ehp_mag, ehp_pure, avg_speed, mixed_ehp, effective_total_hp = r
            f.write("| %d | %d | %.1f | %.0f | %.0f | %.0f | %.1f | %.0f | %.0f |\n" % (
                wn, raw, regen_sec, ehp_phys, ehp_mag, ehp_pure, avg_speed, mixed_ehp, effective_total_hp))
    print("Written %s" % out_path)

    if HAS_MATPLOTLIB and rows:
        waves_num = [r[0] for r in rows]
        eff_hp = [r[8] for r in rows]
        ranges = [(1, 10), (11, 20), (21, 30), (31, 40)]
        fig, axes = plt.subplots(2, 2, figsize=(11, 8))
        axes = axes.flatten()
        for idx, (lo, hi) in enumerate(ranges):
            ax = axes[idx]
            mask = [lo <= w <= hi for w in waves_num]
            x = [w for w, m in zip(waves_num, mask) if m]
            y = [v for v, m in zip(eff_hp, mask) if m]
            if x and y:
                ax.fill_between(x, y, alpha=0.3)
                ax.plot(x, y, marker="o", markersize=5)
            ax.set_xlim(lo - 0.5, hi + 0.5)
            ax.set_xlabel("Volna")
            ax.set_ylabel("Obshchee eff. HP")
            ax.set_title("%d - %d" % (lo, hi))
            ax.grid(True, alpha=0.4)
        fig.suptitle("Obshchee effektivnoe HP po volnam (mixed EHP * speed/80)")
        fig.tight_layout()
        plot_path = os.path.join(DATA_DIR, "WAVE_EFFECTIVE_HP.png")
        fig.savefig(plot_path, dpi=120)
        plt.close()
        print("Written %s" % plot_path)

        # Proizvodnaya (skorost prirosta) po volnam: obshchiy 0-40 i 4 paneli 1-10, 11-20, 21-30, 31-40
        deriv_x = []
        deriv_y = []
        for i in range(len(waves_num)):
            if i == 0:
                d = eff_hp[1] - eff_hp[0] if len(eff_hp) > 1 else 0
            elif i == len(waves_num) - 1:
                d = eff_hp[-1] - eff_hp[-2]
            else:
                d = (eff_hp[i + 1] - eff_hp[i - 1]) / 2.0
            deriv_x.append(waves_num[i])
            deriv_y.append(d)
        # Odin grafik 0-40
        fig2, ax2 = plt.subplots(figsize=(11, 4))
        ax2.bar(deriv_x, deriv_y, width=0.7, alpha=0.7, edgecolor="none")
        ax2.axhline(y=0, color="gray", linestyle="-", linewidth=0.8)
        ax2.set_xlabel("Volna")
        ax2.set_ylabel("Prirost obshchego eff. HP za volnu")
        ax2.set_title("Skorost prirosta (proizvodnaya) obshchego effektivnogo HP")
        ax2.grid(True, alpha=0.4, axis="y")
        fig2.tight_layout()
        deriv_path = os.path.join(DATA_DIR, "WAVE_EFFECTIVE_HP_DERIVATIVE.png")
        fig2.savefig(deriv_path, dpi=120)
        plt.close()
        print("Written %s" % deriv_path)
        # 4 paneli po diapazonam
        fig3, axes3 = plt.subplots(2, 2, figsize=(11, 8))
        axes3 = axes3.flatten()
        for idx, (lo, hi) in enumerate(ranges):
            ax = axes3[idx]
            x_band = [xx for xx in deriv_x if lo <= xx <= hi]
            y_band = [deriv_y[deriv_x.index(xx)] for xx in x_band]
            if x_band and y_band:
                ax.bar(x_band, y_band, width=0.7, alpha=0.7, edgecolor="none")
            ax.axhline(y=0, color="gray", linestyle="-", linewidth=0.8)
            ax.set_xlim(lo - 0.5, hi + 0.5)
            ax.set_xlabel("Volna")
            ax.set_ylabel("Prirost za volnu")
            ax.set_title("%d - %d" % (lo, hi))
            ax.grid(True, alpha=0.4, axis="y")
        fig3.suptitle("Skorost prirosta obshchego eff. HP po diapazonam")
        fig3.tight_layout()
        deriv_ranges_path = os.path.join(DATA_DIR, "WAVE_EFFECTIVE_HP_DERIVATIVE_RANGES.png")
        fig3.savefig(deriv_ranges_path, dpi=120)
        plt.close()
        print("Written %s" % deriv_ranges_path)
    elif not HAS_MATPLOTLIB:
        print("Install matplotlib to generate WAVE_EFFECTIVE_HP.png")


if __name__ == "__main__":
    main()

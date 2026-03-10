#!/usr/bin/env python3
"""Применяет баланс по ярусам крафта (только башни). Враги не трогает; -5%% HP только на волнах 1-6 — в коде WaveSystem."""
import json
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(SCRIPT_DIR, "..", "data")
TOWERS_PATH = os.path.join(DATA_DIR, "towers.json")

# Башни: crafting_level 0 -> урон * 0.85; 1 -> * 1.07; 2 -> * 1.10
DAMAGE_MULT = {0: 0.85, 1: 1.07, 2: 1.10}


def main():
    with open(TOWERS_PATH, "r", encoding="utf-8") as f:
        towers = json.load(f)

    for t in towers:
        cl = t.get("crafting_level", 0)
        if cl not in DAMAGE_MULT:
            continue
        combat = t.get("combat")
        if not combat or "damage" not in combat:
            continue
        d = combat["damage"]
        if isinstance(d, (int, float)) and d > 0:
            new_d = max(1, round(d * DAMAGE_MULT[cl]))
            combat["damage"] = new_d

    with open(TOWERS_PATH, "w", encoding="utf-8") as f:
        json.dump(towers, f, ensure_ascii=False, indent=2)

    print("Done: towers damage by tier (0: -15%%, 1: +7%%, 2: +10%%). Enemy HP unchanged; -5%% only on waves 1-6 in game.")


if __name__ == "__main__":
    main()

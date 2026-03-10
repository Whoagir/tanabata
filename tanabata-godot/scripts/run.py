#!/usr/bin/env python3
"""
One-click runner: runs headless simulations on all snapshots, then builds plots.
Usage: python run.py   (or: wsl python3 run.py)
No arguments needed -- everything is auto-detected.
"""
import os
import sys
import subprocess
import glob
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.join(SCRIPT_DIR, "..")
SNAPSHOTS_DIR = os.path.join(PROJECT_ROOT, "snapshots")

RUNS_PER_WAVE = 100
WAVE_MAX = 43
PARALLEL_JOBS = 4
CSV_MIN_SIZE = 3000

GODOT_STEAM = os.path.join(
    os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"),
    "Steam", "steamapps", "common", "Godot Engine", "godot.windows.opt.tools.64.exe"
)


def find_godot():
    if os.environ.get("GODOT_PATH"):
        return os.environ["GODOT_PATH"]
    if os.path.isfile(GODOT_STEAM):
        return GODOT_STEAM
    return "godot"


def find_snapshot_dirs():
    dirs = []
    for d in sorted(os.listdir(SNAPSHOTS_DIR)):
        full = os.path.join(SNAPSHOTS_DIR, d)
        if os.path.isdir(full) and d.startswith("run_") and os.path.isfile(os.path.join(full, "snapshot.json")):
            dirs.append(full)
    return dirs


def count_good_csvs(run_dir, wave_max):
    count = 0
    for w in range(1, wave_max + 1):
        p = os.path.join(run_dir, "wave_%d.csv" % w)
        if os.path.isfile(p) and os.path.getsize(p) > CSV_MIN_SIZE:
            count += 1
    return count


def detect_wave_max(snap_path):
    import json
    with open(snap_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, list):
        return len(data)
    return WAVE_MAX


def run_headless(run_dir):
    godot = find_godot()
    snap_path = os.path.join(run_dir, "snapshot.json")
    wmax = detect_wave_max(snap_path)
    out_dir = run_dir.replace("\\", "/")

    existing = count_good_csvs(run_dir, wmax)
    if existing >= wmax:
        print("  [skip] %s -- already has %d/%d CSVs" % (os.path.basename(run_dir), existing, wmax))
        return wmax

    print("  [run]  %s -- %d waves x %d runs, %d parallel" % (os.path.basename(run_dir), wmax, RUNS_PER_WAVE, PARALLEL_JOBS))
    chunk_size = max(1, (wmax + PARALLEL_JOBS - 1) // PARALLEL_JOBS)
    for i in range(PARALLEL_JOBS):
        c_min = 1 + i * chunk_size
        c_max = min(1 + (i + 1) * chunk_size - 1, wmax)
        if c_min > wmax:
            break
        cmd = [godot, "--headless", "--path", PROJECT_ROOT, "--",
               "--snapshot", snap_path, "--out-dir", out_dir,
               "--wave", str(c_min), "--wave-max", str(c_max),
               "--runs", str(RUNS_PER_WAVE), "--seed", "0"]
        subprocess.Popen(cmd)

    start = time.time()
    while True:
        time.sleep(10)
        done = count_good_csvs(run_dir, wmax)
        elapsed = (time.time() - start) / 60.0
        print("    %.0f min: %d/%d waves..." % (elapsed, done, wmax))
        if done >= wmax:
            break
        if elapsed > 360:
            print("    Timeout!")
            break
    return wmax


def combine_results(run_dirs):
    combined = os.path.join(SNAPSHOTS_DIR, "combined")
    os.makedirs(combined, exist_ok=True)
    for f in glob.glob(os.path.join(combined, "*.csv")):
        os.remove(f)
    for f in glob.glob(os.path.join(combined, "*.png")):
        os.remove(f)

    all_waves = set()
    for rd in run_dirs:
        for f in glob.glob(os.path.join(rd, "wave_*.csv")):
            try:
                w = int(os.path.basename(f).replace("wave_", "").replace(".csv", ""))
                all_waves.add(w)
            except ValueError:
                pass

    for w in sorted(all_waves):
        out_path = os.path.join(combined, "wave_%d.csv" % w)
        header_written = False
        with open(out_path, "w", encoding="utf-8") as out_f:
            for rd in run_dirs:
                csv_path = os.path.join(rd, "wave_%d.csv" % w)
                if not os.path.isfile(csv_path):
                    continue
                snap_id = os.path.basename(rd)
                with open(csv_path, "r", encoding="utf-8") as in_f:
                    lines = in_f.readlines()
                if len(lines) <= 1:
                    continue
                if not header_written:
                    out_f.write(lines[0].rstrip() + ",snapshot_id\n")
                    header_written = True
                for line in lines[1:]:
                    if line.strip():
                        out_f.write(line.rstrip() + "," + snap_id + "\n")

    print("Combined %d wave CSVs from %d snapshots into %s" % (len(all_waves), len(run_dirs), combined))
    return combined


def run_plots(target_dir):
    plot_script = os.path.join(SCRIPT_DIR, "plot_wave_runs.py")
    print("\nBuilding plots from %s ..." % target_dir)
    subprocess.run([sys.executable, plot_script, target_dir], check=False)


def main():
    print("=== Tanabata Wave Test Runner ===\n")
    run_dirs = find_snapshot_dirs()
    if not run_dirs:
        print("No snapshot folders found in %s" % SNAPSHOTS_DIR)
        print("Play until game over -- snapshots are saved automatically.")
        sys.exit(1)

    print("Found %d snapshot(s):" % len(run_dirs))
    for d in run_dirs:
        print("  %s" % os.path.basename(d))
    print()

    for rd in run_dirs:
        run_headless(rd)
        run_plots(rd)
        print()

    if len(run_dirs) > 1:
        combined = combine_results(run_dirs)
        run_plots(combined)

    print("\nAll done!")


if __name__ == "__main__":
    main()

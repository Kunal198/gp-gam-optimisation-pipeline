#!/usr/bin/env python3
"""
Benchmark GP emulation (baseline vs optimised) on the tiny example.

- Reads grid points from examples/tasks_table.csv
- Runs:
    Rscript scripts/gp/baseline/emulate_phase3_predict_DJF_baseline.R  ilat=... ilon=... month=...
    Rscript scripts/gp/optimised/emulate_phase3_predict_DJF_optimised.R ilat=... ilon=... month=...
- Measures total time and per-task times for each mode
- Saves a comparison table: scripts/utils/outputs/gp_benchmark_summary.csv
- Organises outputs into:
    examples/tiny_sample_outputs/gp_emulation/baseline/
    examples/tiny_sample_outputs/gp_emulation/optimised/

Windows-friendly. Requires Rscript in PATH (or set RSCRIPT_PATH env var).

Usage (from repo root):
  conda activate gp-gam
  python scripts/utils/benchmark_gp_tiny.py
"""

from pathlib import Path
import csv, time, subprocess, shutil, sys
from datetime import datetime

REPO = Path(__file__).resolve().parents[2]
TASKS_CSV = REPO / "examples" / "tasks_table.csv"
OUT_ROOT  = REPO / "examples" / "tiny_sample_outputs" / "gp_emulation"
OUT_BASELINE = OUT_ROOT / "baseline"
OUT_OPTIMISED = OUT_ROOT / "optimised"
LOG_DIR = REPO / "scripts" / "utils" / "outputs"
LOG_DIR.mkdir(parents=True, exist_ok=True)

RSCRIPT = Path.environ.get("RSCRIPT_PATH") if hasattr(Path, "environ") else None
if RSCRIPT is None:
    # Fallback to just "Rscript" in PATH
    RSCRIPT = "Rscript"

BASELINE_R = REPO / "scripts" / "gp" / "baseline" / "emulate_phase3_predict_DJF_baseline.R"
OPTIMISED_R = REPO / "scripts" / "gp" / "optimised" / "emulate_phase3_predict_DJF_optimised.R"

def read_tasks():
    rows = []
    with open(TASKS_CSV, "r", encoding="utf-8") as f:
        r = csv.DictReader(f)
        for row in r:
            rows.append(row)
    if not rows:
        print(f"[ERROR] No rows in {TASKS_CSV}")
        sys.exit(1)
    return rows

def list_out_files():
    if not OUT_ROOT.exists():
        return set()
    return set([p for p in OUT_ROOT.glob("*") if p.is_file()])

def move_new_outputs(new_files, dest_dir):
    dest_dir.mkdir(parents=True, exist_ok=True)
    moved = []
    for p in new_files:
        # skip .bak or temp files if any
        if p.name.startswith(".") or p.suffix not in {".dat"}:
            continue
        target = dest_dir / p.name
        # If file exists, append a timestamp suffix to avoid overwrite
        if target.exists():
            ts = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
            target = dest_dir / f"{p.stem}_{ts}{p.suffix}"
        shutil.move(str(p), str(target))
        moved.append(target)
    return moved

def run_mode(mode_name, r_script, tasks):
    print(f"\n=== Running mode: {mode_name} ===")
    # Capture pre-run files
    before = list_out_files()

    per_task = []
    t0 = time.perf_counter()
    for i, t in enumerate(tasks, start=1):
        ilat = f"{float(t['lat']):.3f}"
        ilon = f"{float(t['lon']):.3f}"
        month = t["month"].strip()

        cmd = [RSCRIPT, str(r_script), f"ilat={ilat}", f"ilon={ilon}", f"month={month}"]
        start = time.perf_counter()
        try:
            subprocess.run(cmd, check=True, cwd=str(REPO))
            ok = True
            err = ""
        except subprocess.CalledProcessError as e:
            ok = False
            err = str(e)
        dt = time.perf_counter() - start
        per_task.append({"mode": mode_name, "task": i, "ilat": ilat, "ilon": ilon, "month": month, "ok": ok, "seconds": dt, "error": err})
        status = "OK" if ok else "FAIL"
        print(f"[{mode_name}] Task {i}/{len(tasks)} ({ilat},{ilon},{month}) -> {status} in {dt:.2f}s")

    total = time.perf_counter() - t0
    # Detect and move new files for this mode
    after = list_out_files()
    new_files = after - before
    dest = OUT_BASELINE if mode_name == "baseline" else OUT_OPTIMISED
    moved = move_new_outputs(new_files, dest)
    print(f"[{mode_name}] Moved {len(moved)} new files to {dest}")

    return per_task, total

def write_summary(baseline_total, optimised_total, per_task_all):
    # Save detailed per-task times
    det_csv = LOG_DIR / "gp_benchmark_per_task.csv"
    with open(det_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["mode","task","ilat","ilon","month","ok","seconds","error"])
        w.writeheader()
        for row in per_task_all:
            w.writerow(row)

    # Save comparison summary
    sum_csv = LOG_DIR / "gp_benchmark_summary.csv"
    speedup = baseline_total / optimised_total if optimised_total > 0 else float("nan")
    with open(sum_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["metric","baseline_seconds","optimised_seconds","speedup_factor"])
        w.writerow(["overall_time", f"{baseline_total:.3f}", f"{optimised_total:.3f}", f"{speedup:.2f}x"])

    # Print a friendly table to console
    print("\n=== GP Emulation Benchmark Summary ===")
    print(f"Baseline total:  {baseline_total:.2f} s")
    print(f"Optimised total: {optimised_total:.2f} s")
    print(f"Speed-up:        {speedup:.2f}x")
    print(f"\nSaved:")
    print(f" - Detailed per-task: {det_csv}")
    print(f" - Summary table:     {sum_csv}")
    print(f"\nOutputs organised under:\n - {OUT_BASELINE}\n - {OUT_OPTIMISED}")

def main():
    if not BASELINE_R.exists() or not OPTIMISED_R.exists():
        print("[ERROR] Could not find baseline/optimised R scripts in scripts/gp/*/.")
        sys.exit(1)

    tasks = read_tasks()
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    OUT_BASELINE.mkdir(parents=True, exist_ok=True)
    OUT_OPTIMISED.mkdir(parents=True, exist_ok=True)

    # Run baseline
    base_results, base_total = run_mode("baseline", BASELINE_R, tasks)
    # Run optimised
    opt_results, opt_total = run_mode("optimised", OPTIMISED_R, tasks)

    write_summary(base_total, opt_total, base_results + opt_results)

if __name__ == "__main__":
    main()

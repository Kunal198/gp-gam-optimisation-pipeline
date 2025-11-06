#!/usr/bin/env python3
"""
Run baseline & optimised GAM for several grid points, time them,
and print/save a comparison table.

Outputs CSV:
  examples/tiny_sample_outputs/gam_variance/comparison/timing_compare.csv
"""

import subprocess, sys, time, os, csv
from pathlib import Path

# ---- Repo root & scripts
REPO = Path(__file__).resolve().parents[2]  # .../gp-gam-optimisation-pipeline
BASELINE_PY = REPO / "scripts" / "gam" / "baseline" / "GAM_baseline.py"
OPTIMISED_R = REPO / "scripts" / "gam" / "optimised" / "GAM_optimised.R"

# ---- Points & month (match your tiny example or edit here)
POINTS = [
    (34.375, -10.3125),
    (35.625,   6.5625),
    (36.875,  10.3125),
    (38.125,   2.8125),
]
MONTH = "jan"

# ---- Where to store comparison CSV
OUT_DIR = REPO / "examples" / "tiny_sample_outputs" / "gam_variance" / "comparison"
OUT_DIR.mkdir(parents=True, exist_ok=True)
CSV_PATH = OUT_DIR / "timing_compare.csv"

def run_cmd(cmd, cwd) -> float:
    """Run a command and return elapsed seconds, raising on failure."""
    t0 = time.perf_counter()
    proc = subprocess.run(cmd, cwd=str(cwd))
    t1 = time.perf_counter()
    if proc.returncode != 0:
        raise RuntimeError(f"Command failed ({proc.returncode}): {' '.join(map(str, cmd))}")
    return t1 - t0

def run_baseline(lat: float, lon: float, month: str) -> float:
    # Baseline is Python; pass Case-B args (no indices) — script auto-discovers files
    cmd = [sys.executable, str(BASELINE_PY), "--ilat", f"{lat}", "--ilon", f"{lon}", "--month", month]
    return run_cmd(cmd, REPO)

def run_optimised(lat: float, lon: float, month: str) -> float:
    # Optimised is R; respects repo-relative paths inside the script
    cmd = ["Rscript", str(OPTIMISED_R), f"{lat}", f"{lon}", month]
    # Optional: let mgcv use all cores if available (Linux/mac builds with OpenMP)
    env = os.environ.copy()
    env.setdefault("OMP_NUM_THREADS", str(os.cpu_count() or 1))
    t0 = time.perf_counter()
    proc = subprocess.run(cmd, cwd=str(REPO), env=env)
    t1 = time.perf_counter()
    if proc.returncode != 0:
        raise RuntimeError(f"Command failed ({proc.returncode}): {' '.join(map(str, cmd))}")
    return t1 - t0

def main():
    # Existence checks
    if not BASELINE_PY.exists():
        raise FileNotFoundError(f"Baseline script not found: {BASELINE_PY}")
    if not OPTIMISED_R.exists():
        raise FileNotFoundError(f"Optimised script not found: {OPTIMISED_R}")

    rows = []
    print("\n== Running GAM BASELINE (Python) then OPTIMISED (R) for 4 points (month=jan) ==\n")

    for lat, lon in POINTS:
        tb = run_baseline(lat, lon, MONTH)
        print(f"[baseline]  lat={lat:.3f} lon={lon:.4f}  time={tb:.2f}s")
        rows.append({"case":"baseline","lat":lat,"lon":lon,"month":MONTH,"elapsed_s":tb})

        to = run_optimised(lat, lon, MONTH)
        print(f"[optimised] lat={lat:.3f} lon={lon:.4f}  time={to:.2f}s")
        rows.append({"case":"optimised","lat":lat,"lon":lon,"month":MONTH,"elapsed_s":to})

    # Build comparison table keyed by (lat,lon)
    paired = {}
    for r in rows:
        key = (r["lat"], r["lon"])
        paired.setdefault(key, {})
        paired[key][r["case"]] = r["elapsed_s"]

    # Print table
    print("\n=== GAM Time comparison (seconds) ===")
    print(f"{'lat':>8} {'lon':>10} {'baseline':>12} {'optimised':>12} {'speedup':>10}")
    total_b = total_o = 0.0
    table_rows = []
    for (lat, lon), d in paired.items():
        b = d.get("baseline", float('nan'))
        o = d.get("optimised", float('nan'))
        sp = (b / o) if (o and o > 0) else float('nan')
        total_b += b
        total_o += o
        print(f"{lat:8.3f} {lon:10.4f} {b:12.2f} {o:12.2f} {sp:10.2f}x")
        table_rows.append([lat, lon, MONTH, f"{b:.2f}", f"{o:.2f}", f"{sp:.2f}"])

    overall_sp = (total_b / total_o) if total_o > 0 else float('nan')
    print("-" * 58)
    print(f"{'TOTAL':>20} {total_b:12.2f} {total_o:12.2f} {overall_sp:10.2f}x\n")

    # Save CSV
    with open(CSV_PATH, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["lat","lon","month","baseline_s","optimised_s","speedup_x"])
        w.writerows(table_rows)
        w.writerow([])
        w.writerow(["TOTAL","","", f"{total_b:.2f}", f"{total_o:.2f}", f"{overall_sp:.2f}"])
    print(f"Saved: {CSV_PATH}")

if __name__ == "__main__":
    main()

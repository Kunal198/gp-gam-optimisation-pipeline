#!/usr/bin/env python3
"""
Run baseline & optimised GP emulation for 4 grid points, time them,
and print/save a comparison table.

Outputs CSV:
  examples/tiny_sample_outputs/gp_emulation/comparison/timing_compare.csv
"""

import subprocess, sys, time, os, csv
from pathlib import Path

# ---- Repo root & scripts
REPO = Path(__file__).resolve().parents[2]  # .../gp-gam-optimisation-pipeline
BASELINE = REPO / "scripts" / "gp" / "baseline" / "emulate_baseline.R"
OPTIMISED = REPO / "scripts" / "gp" / "optimised" / "emulate_optimised.R"

# ---- Points & month (same as your tiny example)
POINTS = [
    (34.375, -10.3125),
    (35.625,   6.5625),
    (36.875,  10.3125),
    (38.125,   2.8125),
]
MONTH = "jan"

# ---- Where to store comparison CSV
OUT_DIR = REPO / "examples" / "tiny_sample_outputs" / "gp_emulation" / "comparison"
OUT_DIR.mkdir(parents=True, exist_ok=True)
CSV_PATH = OUT_DIR / "timing_compare.csv"

def run_r(script: Path, lat: float, lon: float, month: str) -> float:
    """Run Rscript <script> <lat> <lon> <month>, return elapsed seconds."""
    cmd = ["Rscript", str(script), f"{lat}", f"{lon}", month]
    t0 = time.perf_counter()
    proc = subprocess.run(cmd, cwd=str(REPO))
    t1 = time.perf_counter()
    if proc.returncode != 0:
        raise RuntimeError(f"Command failed ({proc.returncode}): {' '.join(cmd)}")
    return t1 - t0

def main():
    rows = []
    print("\n== Running BASELINE then OPTIMISED for 4 points (month=jan) ==\n")

    for lat, lon in POINTS:
        # Baseline
        tb = run_r(BASELINE, lat, lon, MONTH)
        print(f"[baseline] lat={lat:.3f} lon={lon:.4f}  time={tb:.2f}s")
        rows.append({"case":"baseline","lat":lat,"lon":lon,"month":MONTH,"elapsed_s":tb})

        # Optimised
        to = run_r(OPTIMISED, lat, lon, MONTH)
        print(f"[optimised] lat={lat:.3f} lon={lon:.4f}  time={to:.2f}s")
        rows.append({"case":"optimised","lat":lat,"lon":lon,"month":MONTH,"elapsed_s":to})

    # Build comparison table
    # key by (lat,lon)
    paired = {}
    for r in rows:
        key = (r["lat"], r["lon"])
        paired.setdefault(key, {})
        paired[key][r["case"]] = r["elapsed_s"]

    # Print table
    print("\n=== Time comparison (seconds) ===")
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

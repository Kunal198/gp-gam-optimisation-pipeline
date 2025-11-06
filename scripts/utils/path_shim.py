#!/usr/bin/env python3
"""
Path shim for gp-gam-optimisation-pipeline
- Detects repo root reliably
- Provides canonical locations for tiny example inputs/outputs
- Robust GP output file finder (baseline/optimised; multiple precisions)
"""
from pathlib import Path
import re

# --- Repo root (…/gp-gam-optimisation-pipeline) ---
def repo_root(from_file: str) -> Path:
    p = Path(from_file).resolve()
    # scripts/<area>/<tier>/<file> -> go up 3 parents to the repo root
    return p.parents[3]

# --- Canonical tiny-example paths (relative to repo) ---
def tiny_input_dir(repo: Path) -> Path:
    return repo / "examples" / "tiny_sample_inputs" / "H2SO4" / "jan"

def tiny_gp_out_dir(repo: Path) -> Path:
    # Root of GP outputs; subfolders may be baseline/optimised/lat<lat>
    return repo / "examples" / "tiny_sample_outputs" / "gp_emulation"

def tiny_gam_out_dir(repo: Path) -> Path:
    # Root of GAM outputs; caller adds baseline/optimised/lat<lat>
    return repo / "examples" / "tiny_sample_outputs" / "gam_variance"

# --- Robust GP output finder for the GAM step ---
def find_gp_file(repo: Path, ilat: float, ilon: float, month: str) -> Path:
    """
    Look for GP mean file for (ilat, ilon, month) in:
      - examples/tiny_sample_outputs/gp_emulation/baseline/lat<lat>/
      - examples/tiny_sample_outputs/gp_emulation/optimised/lat<lat>/
      - examples/tiny_sample_outputs/gp_emulation/lat<lat>/       (fallback)
    Accepts names like:
      emulated_mean_values_H2SO4_jan_ilat_34.375_ilon_-10.3125_10000_w_o_carb.dat
    Falls back to raw input (demo) if no GP file exists.
    """
    base = tiny_gp_out_dir(repo)
    lat_folder = f"lat{ilat:.3f}"

    search_roots = [
        base / "baseline"  / lat_folder,
        base / "optimised" / lat_folder,
        base / lat_folder,  # plain fallback
    ]

    # Build several precision patterns (strict → relaxed)
    precise = re.compile(
        rf"^emulated_mean_values_H2SO4_{re.escape(month)}_ilat_{ilat:.3f}_ilon_{ilon:.4f}_(\d+)_w_o_carb\.dat$"
    )

    relaxed_patterns = [
        re.compile(
            rf"^emulated_mean_values_H2SO4_{re.escape(month)}_ilat_{ilat:.3f}_ilon_{ilon:.3f}_(\d+)_w_o_carb\.dat$"
        ),
        re.compile(
            rf"^emulated_mean_values_H2SO4_{re.escape(month)}_ilat_{ilat}_ilon_{ilon}_(\d+)_w_o_carb\.dat$"
        ),
    ]

    candidates = []

    # Search each root
    for root in search_roots:
        if not root.exists():
            continue

        # 1) precise pattern first
        for p in root.glob("emulated_mean_values_H2SO4_*.dat"):
            if precise.match(p.name):
                candidates.append(p)

        if candidates:
            break

        # 2) relaxed patterns
        for pat in relaxed_patterns:
            for p in root.glob("emulated_mean_values_H2SO4_*.dat"):
                if pat.match(p.name):
                    candidates.append(p)
            if candidates:
                break

        if candidates:
            break

        # 3) ultra-relaxed: check tokens in name
        lat_key3 = f"{ilat:.3f}"
        lon_key3 = f"{ilon:.3f}"
        for p in root.glob("*.dat"):
            name = p.name
            if (
                "emulated_mean_values_H2SO4_" in name and
                month in name and
                lat_key3 in name and
                lon_key3 in name
            ):
                candidates.append(p)

        if candidates:
            break

    if not candidates:
        # Final fallback: allow demo to run from raw input
        raw = tiny_input_dir(repo) / f"lat_{ilat:.3f}_lon_{ilon:.3f}.dat"
        if raw.exists():
            return raw
        raise FileNotFoundError(
            f"No GP emulation file found in {base} for ilat={ilat}, ilon={ilon}, month={month}. "
            f"Tried baseline, optimised, and root lat folders."
        )

    # Prefer newest file if multiple matches
    candidates.sort(key=lambda q: q.stat().st_mtime, reverse=True)
    return candidates[0]

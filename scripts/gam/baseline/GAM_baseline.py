#!/usr/bin/env python
"""
GAM calculation for emulated H2SO4 data (baseline)
GP means are assumed to be computed from the FIRST N rows of the raw 1,000,000-row LHC.

Features:
- Repo-relative paths (Windows/Linux/HPC portable)
- Auto-discovers GP emulation file for (ilat, ilon, month)
- Uses FIRST N rows of the raw LHC (no indices)
- Spline spec matches original concept: LinearGAM() with default per-feature smooths
- Drops non-finite rows before fit; robust slope calc (polyfit fallback is kept)
- Output filenames include the true N from the GP filename (if present)
"""

import argparse
import re
from pathlib import Path
import numpy as np
import pandas as pd
from pygam import LinearGAM

# --- Repo-relative helpers ---
try:
    from scripts.utils.path_shim import (
        repo_root, tiny_gp_out_dir, tiny_gam_out_dir, find_gp_file
    )
except ModuleNotFoundError:
    import sys
    sys.path.append(str(Path(__file__).resolve().parents[3] / "scripts" / "utils"))
    from path_shim import repo_root, tiny_gp_out_dir, tiny_gam_out_dir, find_gp_file

# ---------------- Consts ----------------
VAR = "H2SO4"
PARAMETER_NAMES_55 = [
    'bl_nuc','ait_width','cloud_ph','carb_ff_ems_eur','carb_ff_ems_nam','carb_ff_ems_chi','carb_ff_ems_asi',
    'carb_ff_ems_mar','carb_ff_ems_r','carb_bb_ems_sam','carb_bb_ems_naf','carb_bb_ems_saf','carb_bb_ems_bnh',
    'carb_bb_ems_rnh','carb_bb_ems_rsh','carb_res_ems_chi','carb_res_ems_asi','carb_res_ems_afr','carb_res_ems_lat',
    'carb_res_ems_r','carb_ff_diam','carb_bb_diam','carb_res_diam','prim_so4_diam','sea_spray','anth_so2_chi',
    'anth_so2_asi','anth_so2_eur','anth_so2_nam','anth_so2_r','volc_so2','bvoc_soa','dms','prim_moc','dry_dep_ait',
    'dry_dep_acc','dry_dep_so2','kappa_oc','sig_w','rain_frac','cloud_ice_thresh','conv_plume_scav','scav_diam',
    'bc_ri','oxidants_oh','oxidants_o3','bparam','two_d_fsd_factor','c_r_correl','autoconv_exp_lwp','autoconv_exp_nd',
    'dbsdtbs_turb_0','ai','m_ci','a_ent_1_rp'
]
# 37-feature subset indices (must match your LHC column order)
PAR_INDEX = (
    0, 1, 2, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
    33, 34, 35, 36, 37, 38, 39, 40, 41, 43, 44, 45, 46, 47, 48,
    49, 50, 51, 52, 53, 54
)
PARAMETER_NAMES_SUBSET = [PARAMETER_NAMES_55[i] for i in PAR_INDEX]

def load_lhc_first_n(sample_file: Path, rows_needed: int) -> np.ndarray:
    """
    Case B: Load raw LHC and return the FIRST rows_needed rows (no retained indices).
    Returns X subset with shape [rows_needed x 37] using PAR_INDEX.
    Raises if sample file is missing or malformed.
    """
    if not sample_file.exists():
        raise FileNotFoundError(f"Missing LHC sample file: {sample_file}")

    LHC = np.loadtxt(sample_file)
    if LHC.ndim != 2 or LHC.shape[1] < 55:
        raise ValueError(f"LHC must be [n,>=55]; got {LHC.shape}")

    if LHC.shape[0] < rows_needed:
        raise ValueError(f"LHC has only {LHC.shape[0]} rows; need {rows_needed}")

    X = LHC[:rows_needed, :][:, PAR_INDEX]
    return X

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ilat", type=float, required=True)
    ap.add_argument("--ilon", type=float, required=True)
    ap.add_argument("--month", type=str, required=True)
    ap.add_argument("--samples", type=str, default="",
                    help="Path to raw LHC sample (.dat) with 1,000,000 rows; we take the FIRST N rows.")
    # NOTE: No --indices in Case B
    args = ap.parse_args()

    # Repo root & output dirs
    REPO = repo_root(__file__)
    GAM_DIR = tiny_gam_out_dir(REPO) / "baseline" / f"lat{args.ilat:.3f}"
    GAM_DIR.mkdir(parents=True, exist_ok=True)

    # --- Find GP emulation file & infer N ---
    gp_file = find_gp_file(REPO, args.ilat, args.ilon, args.month)
    print(f"[GAM] Using GP mean: {gp_file}")

    m = re.search(r"_(\d+)_w_o_carb\.dat$", gp_file.name)
    N_gp = int(m.group(1)) if m else None

    y = np.loadtxt(gp_file)
    if y.ndim == 2 and y.shape[1] > 1:
        y = y[:, 0]
    y = np.asarray(y, dtype=float).ravel()

    # --- LHC sample (Case B: FIRST N rows; NO indices) ---
    default_samples = REPO / "examples" / "large_sample" / "constrained_multi_million_sample_first_million.dat"
    sample_path = Path(args.samples) if args.samples else default_samples

    X = load_lhc_first_n(sample_path, len(y))
    X = np.asarray(X, dtype=float)

    # --- Clean non-finite rows BEFORE fitting ---
    mask = np.isfinite(y)
    for j in range(X.shape[1]):
        mask &= np.isfinite(X[:, j])

    if not np.any(mask):
        raise ValueError("No finite rows remain after cleaning X/y.")

    Xn = X[mask]
    yn = y[mask]
    N = len(yn)  # rows actually used

    # --- Fit GAM with default per-feature smooths (match original concept) ---
    # LinearGAM() with no explicit terms builds one default s() per column internally.
    gam = LinearGAM().fit(Xn, yn)

    # --- Variance & gradient sign (robust) ---
    variances = np.zeros(Xn.shape[1], dtype=float)
    grad_sign = np.zeros(Xn.shape[1], dtype=float)

    med = np.median(Xn, axis=0)
    X_med = np.tile(med, (N, 1))  # allocate once
    eps_var = 1e-15

    for i in range(Xn.shape[1]):
        xcol = Xn[:, i]
        if np.nanstd(xcol) < 1e-12:
            variances[i] = 0.0
            grad_sign[i] = 0.0
            continue

        X_med[:, :] = med
        X_med[:, i] = xcol
        y_pred = gam.predict(X_med)

        finite = np.isfinite(xcol) & np.isfinite(y_pred)
        if np.count_nonzero(finite) < 2:
            variances[i] = 0.0
            grad_sign[i] = 0.0
            continue

        yv = y_pred[finite]
        xv = xcol[finite]

        # variance importance (sample variance with ddof=1 to match earlier baseline; 
        # switch to ddof=0 if you want population variance like some legacy code)
        variances[i] = float(np.var(yv, ddof=1)) if len(yv) > 1 else 0.0

        vx = np.var(xv, ddof=1) if len(xv) > 1 else 0.0
        if vx < eps_var:
            slope = 0.0
        else:
            # robust slope = cov/var; swap to np.polyfit(xv, yv, 1)[0] for exact legacy behaviour
            slope = float(np.cov(xv, yv, ddof=1)[0, 1] / vx)

        grad_sign[i] = 1.0 if slope > 0 else (-1.0 if slope < 0 else 0.0)

    # --- Save outputs (with true N in the name) ---
    N_out = int(N_gp) if (N_gp == len(y)) else int(N)

    out_var  = GAM_DIR / f"GAM_variances_{VAR}_{args.month}_{N_out}_ilat_{args.ilat:.3f}_ilon_{args.ilon:.4f}.dat"
    out_sign = GAM_DIR / f"GAM_gradient_signs_{VAR}_{args.month}_{N_out}_ilat_{args.ilat:.3f}_ilon_{args.ilon:.4f}.dat"
    np.savetxt(out_var,  variances, fmt="%.8e")
    np.savetxt(out_sign, grad_sign, fmt="%.0f")

    print(f"✅ GAM baseline complete. rows_used={N}\n→ {out_var}\n→ {out_sign}")

if __name__ == "__main__":
    main()

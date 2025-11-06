# gp-gam-optimisation-pipeline (Demo)

High-performance workflow for **Gaussian Process (GP) emulation** and **Generalized Additive Model (GAM)** fitting in Earth‑system model analysis.

This repository accompanies the manuscript:

> **Ghosh, K. & Regayre, L.A. (2025):**  
> *Optimizing Gaussian Process Emulation and Generalized Additive Model Fitting for Rapid, Reproducible Earth System Model Analysis*  
> _Geoscientific Model Development_ (Submitted)

The workflow integrates Python and R components for high‑performance statistical emulation and variance analysis, and provides both **baseline** and **optimised** implementations benchmarked on HPC systems.  
A **tiny self‑contained example (H₂SO₄, January 2017)** is included to validate functionality locally without requiring JASMIN or any external dataset.

---

## Repository structure

```
gp-gam-optimisation-pipeline/
├── README.md
├── LICENSE                       ← MIT (code)
├── CITATION.cff
├── .zenodo.json                  ← Zenodo metadata for software release
│
├── envs/
│   ├── environment.yml           ← Python (NumPy, pandas, SciPy, pygam)
│   └── install_R_deps.R          ← R (mgcv, DiceKriging, etc.)
│
├── configs/
│   └── pipeline.yml              ← Minimal YAML config for local run
│
├── scripts/
│   │   ├── gp/
│   │   ├── baseline/             ← Full baseline GP implementation (R)
│   │   └── optimised/            ← Full optimised GP implementation (R)
│   ├── gam/
│   │   ├── baseline/             ← Baseline GAM (Python, pygam)
│   │   └── optimised/            ← Optimised GAM (R, mgcv::bam)
│   └── utils/
│       └── validate_example.py   ← Verifies input/output integrity
│
├── examples/
│   ├── tiny_sample_inputs/
│   │   └── H2SO4/jan/            ← 4 input grid‑point .dat files
│   ├── tiny_sample_outputs/
│   │   ├── gp_emulation/         ← Matching GP outputs
│   │   └── gam_variance/         ← GAM variance outputs
│   └── tasks_table.csv           ← Example coordinate table (4 points)
│
├── notebooks/
│   └── reproduce_figures.ipynb   ← Placeholder for plotting diagnostics
```
---

## Installation

### 1) Clone the repository
```bash
git clone https://github.com/kunalghosh/gp-gam-optimisation-pipeline.git
cd gp-gam-optimisation-pipeline
```

### 2) Set up the Python environment
```bash
conda env create -f envs/environment.yml
conda activate gp-gam
```

### 3) (Optional) Install R dependencies
```bash
Rscript envs/install_R_deps.R
```
This installs: `mgcv`, `DiceKriging`, `lhs`, `sensitivity`, `trapezoid`, `readr`, and `truncnorm`.

---

## GP demo (4‑grid quick test)

This demo runs Gaussian‑Process emulation for **four grid points** (H₂SO₄, January 2017) using:

- **Baseline (loop)** – simple R loop (sequential, laptop‑friendly)  
- **Optimised (array)** – same algorithm but parallelisable via SLURM arrays (HPC)

Each script uses identical inputs and consistent arguments (`ilat`, `ilon`, `month`).  
By default, both scripts predict on **50,000 rows** (`reduce_size = 50000`), which can be increased to 100,000–1,000,000 for performance tests.

---

### A. Windows (PowerShell/CMD)

**Baseline (single point quick test):**
```bat
cd "<your path>\gp-gam-optimisation-pipeline"
conda activate gp-gam
Rscript scripts\gp\baseline\emulate_baseline.R 34.375 -10.3125 jan
```
Repeat for other grid points:
```bat
Rscript scripts\gp\baseline\emulate_baseline.R 35.625 6.5625 jan
Rscript scripts\gp\baseline\emulate_baseline.R 36.875 10.3125 jan
Rscript scripts\gp\baseline\emulate_baseline.R 38.125 2.8125 jan
```

**Optimised (single point quick test):**
```bat
Rscript scripts\gp\optimised\emulate_optimised.R 34.375 -10.3125 jan
```
Repeat for other grid points:
```bat
Rscript scripts\gp\optimised\emulate_optimised.R 35.625 6.5625 jan
Rscript scripts\gp\optimised\emulate_optimised.R 36.875 10.3125 jan
Rscript scripts\gp\optimised\emulate_optimised.R 38.125 2.8125 jan
```

**Baseline vs optimised timing comparison (auto runs both):**
```bat
python scripts\gp\run_compare_gp.py
```
This prints a timing table and writes  
`examples\tiny_sample_outputs\gp_emulation\comparison\timing_compare_gp.csv`

> **Optional (reproducible timings):**
> ```bat
> set OMP_NUM_THREADS=1
> set MKL_NUM_THREADS=1
> set OPENBLAS_NUM_THREADS=1
> ```

---

### B. Linux / macOS

**Baseline (single‑point quick test):**
```bash
cd gp-gam-optimisation-pipeline
conda activate gp-gam
Rscript scripts/gp/baseline/emulate_baseline.R 34.375 -10.3125 jan
Rscript scripts/gp/baseline/emulate_baseline.R 35.625 6.5625 jan
Rscript scripts/gp/baseline/emulate_baseline.R 36.875 10.3125 jan
Rscript scripts/gp/baseline/emulate_baseline.R 38.125 2.8125 jan
```

**Optimised (single‑point quick test):**
```bash
Rscript scripts/gp/optimised/emulate_optimised.R 34.375 -10.3125 jan
Rscript scripts/gp/optimised/emulate_optimised.R 35.625 6.5625 jan
Rscript scripts/gp/optimised/emulate_optimised.R 36.875 10.3125 jan
Rscript scripts/gp/optimised/emulate_optimised.R 38.125 2.8125 jan
```

**Compare baseline vs optimised:**
```bash
python scripts/gp/run_compare_gp.py
```

---

# HPC (SLURM): GP emulation workflows

Both the **baseline** and **optimised** GP stages can be run efficiently on HPC systems (e.g. **JASMIN**, **ARCHER**) using SLURM array jobs.  
Each task corresponds to one `(lat, lon, month)` combination, allowing thousands of independent jobs to run in parallel.

---

## Baseline GP emulation (R loop version)

The baseline GP workflow uses a single‑core R script (`emulate_baseline.R`) run in a job array.  
Each SLURM array task reads one line from a task file specifying latitude, longitude, and month.

**Submit job**
```bash
sbatch scripts/gp_demo/baseline_array/submit_gp_baseline.slurm
```

**Typical SLURM script**
```bash
#!/bin/bash
#SBATCH --job-name=gp_baseline
#SBATCH --output=slurm_logs/gp_baseline_%A_%a.out
#SBATCH --error=slurm_logs/gp_baseline_%A_%a.err
#SBATCH --time=06:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=8000
#SBATCH --partition=short-serial
#SBATCH --account=<PROJECT>
#SBATCH --array=1-4         # 4 grid points (adjust to match your taskfile)

# === Environment setup ===
module purge
module load R/4.3.1
module load Anaconda3
conda activate gp-gam

# === Task file ===
TASKFILE=/path/to/gam_latlon_month_table.txt

# Read i-th line (ilat, ilon, month)
read ILAT ILON MONTH < <(sed -n "${SLURM_ARRAY_TASK_ID}p" "$TASKFILE")

echo " Running baseline GP for lat=$ILAT lon=$ILON month=$MONTH"

# === Run emulation ===
srun Rscript scripts/gp/baseline/emulate_baseline.R "$ILAT" "$ILON" "$MONTH"
```

**Output directory**
```
examples/tiny_sample_outputs/gp_emulation/baseline/lat<lat>/
```
Each task writes:
```
emulated_mean_values_H2SO4_<month>_ilat_<lat>_ilon_<lon>_<N>_w_o_carb.dat
emulated_sd_values_H2SO4_<month>_ilat_<lat>_ilon_<lon>_<N>_w_o_carb.dat
```

>  Use `--array=1-N` where `N = $(wc -l < gam_latlon_month_table.txt)`.

---

## Optimised GP emulation (vectorised R + array streaming)

The optimised workflow uses `emulate_optimised.R` (vectorised operations + faster I/O).  
This version runs more efficiently for 50k–1M samples per grid point.

**Submit job**
```bash
bash scripts/gp_demo/optimised_array/run_emulation.sh
```
This wrapper automatically submits:
- `submit_gp_optimised.slurm` → main array job  
- `post_check_resubmit_emulation.sbatch` → re‑submit missing outputs if any fail

**Output directory**
```
examples/tiny_sample_outputs/gp_emulation/optimised/lat<lat>/
```

---

##  Example module setup (HPC)

Make sure your environment matches `envs/environment.yml` and the R dependencies.

```bash
module load R/4.3.1
module load Anaconda3
conda activate gp-gam
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
```

For reproducibility, keep threading fixed when benchmarking.

---

##  Task file format

Both workflows use the same task file (one line per job):

```
ilat   ilon      month
34.375 -10.3125  jan
35.625   6.5625  jan
36.875  10.3125  jan
38.125   2.8125  jan
```

Generate with:
```bash
python scripts/utils/generate_gam_task_file.py
```

---

##  Post run checks (GP)

List outputs:
```bash
find examples/tiny_sample_outputs/gp_emulation -type f | sort
```

If any outputs are missing, re‑submit failed tasks:
```bash
sbatch scripts/gp_demo/optimised_array/post_check_resubmit_emulation.sbatch
```

---

##  Keeping baseline vs optimised comparable (GP)

Edit both R scripts so that they use the **same work size and chunking**:

```r
# In emulate_baseline.R and emulate_optimised.R
reduce_1M      <- 1
reduce_size    <- 10000     # identical in both
nPredBreakVal  <- 10000     # use 20000–50000 on HPC if memory allows
# For a 1M‑row stress test:
# reduce_size <- 1000000
```

---

##  GP outputs

```
examples/tiny_sample_outputs/gp_emulation/
├── baseline/
│   └── lat<lat>/
│       ├── emulated_mean_values_H2SO4_*.dat
│       └── emulated_sd_values_H2SO4_*.dat
├── optimised/
│   └── lat<lat>/
│       ├── emulated_mean_values_H2SO4_*.dat
│       ├── emulated_sd_values_H2SO4_*.dat
│       └── timing_log_*.txt
└── comparison/
    └── timing_compare_gp.csv   ← Produced by run_compare_gp.py
```

Example timing table (10,000‑row demo):

| lat   | lon      | baseline_s | optimised_s | speedup_x |
|-------|----------|------------|-------------|-----------|
| 34.375 | −10.3125 | 5.4        | 3.0         | 1.8×      |
| 35.625 |   6.5625 | 5.3        | 2.9         | 1.8×      |
| 36.875 |  10.3125 | 5.5        | 3.0         | 1.8×      |
| 38.125 |   2.8125 | 5.4        | 3.0         | 1.8×      |
| **Total** |          | **21.7**    | **11.9**     | **1.8×**    |

> Results vary by CPU and BLAS library. Expect ~1.5–2× speed‑up in the optimised version for this small demo; larger speed‑ups appear at scale (>100k samples).

---

# GAM variance analysis: Baseline (Python) & Optimised (R)

This stage computes **per‑parameter variance contributions** and **gradient signs** for **H₂SO₄** using:

- **Baseline**: `pygam.LinearGAM` (Python) — median‑hold evaluation (Case B: first N rows of the raw LHC).  
- **Optimised**: `mgcv::bam` (R) — uses `type="terms"` for a fast, output‑identical computation (also Case B).

Outputs are written under:
```
examples/tiny_sample_outputs/gam_variance/
  ├── baseline/lat<lat>/GAM_variances_*.dat, GAM_gradient_signs_*.dat
  └── optimised/lat<lat>/GAM_variances_*.dat, GAM_gradient_signs_*.dat
```

Both automatically locate the matching GP file in:
```
examples/tiny_sample_outputs/gp_emulation/baseline/lat<lat>/
```

---

##  A. Windows (conda)

**Setup**
```bat
conda activate gp-gam
```

**1) Baseline (Python)**
```bat
python scripts\gam\baseline\GAM_baseline.py --ilat 34.375 --ilon -10.3125 --month jan
python scripts\gam\baseline\GAM_baseline.py --ilat 35.625 --ilon 6.5625 --month jan
python scripts\gam\baseline\GAM_baseline.py --ilat 36.875 --ilon 10.3125 --month jan
python scripts\gam\baseline\GAM_baseline.py --ilat 38.125 --ilon 2.8125 --month jan
```

**2) Optimised (R)**
```bat
Rscript scripts\gam\optimised\GAM_optimised.R 34.375 -10.3125 jan
Rscript scripts\gam\optimised\GAM_optimised.R 35.625 6.5625 jan
Rscript scripts\gam\optimised\GAM_optimised.R 36.875 10.3125 jan
Rscript scripts\gam\optimised\GAM_optimised.R 38.125 2.8125 jan
```

**3) Compare baseline vs optimised**
```bat
python scripts\gam\run_compare_gam.py
```
Outputs:
```
examples\tiny_sample_outputs\gam_variance\comparison\timing_compare_gam.csv
```

---

##  B. Linux / macOS

**Setup**
```bash
conda activate gp-gam
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
```

**1) Baseline**
```bash
python scripts/gam/baseline/GAM_baseline.py --ilat 34.375 --ilon -10.3125 --month jan
```

**2) Optimised**
```bash
Rscript scripts/gam/optimised/GAM_optimised.R 34.375 -10.3125 jan
```

**3) Compare timings**
```bash
python scripts/gam/run_compare_gam.py
```

---

##  C. HPC (SLURM)

**Task file (common to both)**: each line defines one job:
```
ilat   ilon      month
34.375 -10.3125  jan
35.625   6.5625  jan
36.875  10.3125  jan
38.125   2.8125  jan
```
Path: `/path/to/gam_latlon_month_table.txt`

**1) Baseline GAM (Python / pygam)**: submit job
```bash
sbatch scripts/gam/baseline/submit_gam_baseline.sbatch
```
Example sbatch:
```bash
#!/bin/bash
#SBATCH --job-name=gam_baseline
#SBATCH --output=slurm_logs/gam_baseline_%A_%a.out
#SBATCH --error=slurm_logs/gam_baseline_%A_%a.err
#SBATCH --time=06:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=16000
#SBATCH --partition=short-serial
#SBATCH --account=<PROJECT>
#SBATCH --array=1-4

module purge
module load Anaconda3
conda activate gp-gam

TASKFILE=/path/to/gam_latlon_month_table.txt
read ILAT ILON MONTH < <(sed -n "${SLURM_ARRAY_TASK_ID}p" "$TASKFILE")

echo " GAM baseline: lat=$ILAT lon=$ILON month=$MONTH"
srun python scripts/gam/baseline/GAM_baseline.py --ilat "$ILAT" --ilon "$ILON" --month "$MONTH"
```

Outputs:
```
examples/tiny_sample_outputs/gam_variance/baseline/lat<lat>/
  GAM_variances_H2SO4_<month>_<N>_ilat_<lat>_ilon_<lon>.dat
  GAM_gradient_signs_H2SO4_<month>_<N>_ilat_<lat>_ilon_<lon>.dat
```

**2) Optimised GAM (R / mgcv::bam)**: submit job
```bash
sbatch scripts/gam/optimised/submit_gam_optimised.sbatch
```
Re‑submit missing jobs (optional):
```bash
sbatch scripts/gam/optimised/post_check_resubmit.sbatch
```

Outputs:
```
examples/tiny_sample_outputs/gam_variance/optimised/lat<lat>/
  GAM_variances_H2SO4_<month>_<N>_ilat_<lat>_ilon_<lon>.dat
  GAM_gradient_signs_H2SO4_<month>_<N>_ilat_<lat>_ilon_<lon>.dat
```

Recommended modules:
```bash
module load R/4.3.1
module load Anaconda3
conda activate gp-gam
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
```

---

##  Perfect output, matching (GAM)

| Step          | Description                                   | Method              |
|---------------|-----------------------------------------------|---------------------|
| Data subset   | Case B — first N rows from raw LHC            | Identical           |
| Variance      | Median‑hold (Python) / `type="terms"` (R)     | Same                |
| Gradient sign | From `cov(x, f_i(x))`                         | Same                |
| Filtering     | Drops non‑finite rows                         | Same                |
| Output files  | Identical structure and precision             | Same                |

**Post‑run checks**
```bash
find examples/tiny_sample_outputs/gam_variance -type f | sort
python scripts/gam/run_compare_gam.py    # writes comparison/timing_compare_gam.csv
```

---

##  Summary

>  *Actual runtime depends on hardware, thread count, and BLAS/OpenMP configuration.*

| Script           | Language                | Method                | Runtime (4 pts) | Speedup |
|------------------|-------------------------|-----------------------|-----------------|---------|
| GAM_baseline.py  | Python (pygam)          | Median‑hold           | ~130 s          | —       |
| GAM_optimised.R  | R (mgcv::bam, `type="terms"`) | Vectorised           | ~60 s           | 2.2×    |

---

##  License

- **Code:** MIT License (see `LICENSE`)  
- **Data (tiny example):** Creative Commons Attribution 4.0 International (CC BY 4.0)

---

## Citation

If you use this workflow or dataset, please cite:

> **Ghosh, K. & Regayre, L.A. (2025):**  
> *Optimizing Gaussian Process Emulation and Generalized Additive Model Fitting for Rapid, Reproducible Earth System Model Analysis.*  
> _Geoscientific Model Development_ (submitted)

**Software:** [10.5281/zenodo.17543623](https://doi.org/10.5281/zenodo.17543623)  
**Dataset:** [10.5281/zenodo.17544324](https://doi.org/10.5281/zenodo.17544324)


---

##  Related dataset

The accompanying dataset archived on Zenodo provides all input and output artefacts
used in the example and figures described in the paper and software documentation.

**Zenodo:** [gp-gam-optimisation-dataset: Example input and output data for Gaussian Process and GAM workflow (H₂SO₄, January 2017)](https://doi.org/10.5281/zenodo.17544324)


---

##  Acknowledgements

Supported by NERC projects:  
- **A‑CURE** (NE/P013406/1)  
- **Aerosol‑MFR** (NE/X013901/1)

Computations performed on **JASMIN (CEDA)** and **ARCHER (n02‑NEP013406)**.  
With thanks to *Ken Carslaw, Leighton Regayre, Jill Johnson, Jonathan Owen, Léa Prévost, Iain Webb,* and *Jeremy Oakley* for discussions and feedback.

---

##  Contact

**Kunal Ghosh**  
School of Earth and Environment, University of Leeds  
📧 k.ghosh@leeds.ac.uk  
🔗 [ORCID 0000-0002-3179-6844](https://orcid.org/0000-0002-3179-6844)

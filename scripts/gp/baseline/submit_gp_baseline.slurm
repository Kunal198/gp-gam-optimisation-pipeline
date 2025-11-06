#!/bin/bash
#SBATCH --job-name=gp_base
#SBATCH --output=logs/gp_base_%A_%a.out
#SBATCH --error=logs/gp_base_%A_%a.err
#SBATCH --array=1-4
#SBATCH --time=02:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=1 #For large sweeps, adjust --array, --time, --mem, --cpus-per-task

set -euo pipefail

# --- Site-specific modules (edit as needed) ---
module load Anaconda3 || true
module load R/4.3.1 || true

# --- Environment (edit if your cluster uses micromamba etc.) ---
source ~/.bashrc 2>/dev/null || true
conda activate gp-gam

# --- Assume submission from repo root ---
REPO="$PWD"

# Grid to sweep (edit as needed)
LATS=(34.375 35.625 36.875 38.125)
LONS=(-10.3125 6.5625 10.3125 2.8125)
MONTH="jan"

# Map array index -> (ilat, ilon)
IDX=$((SLURM_ARRAY_TASK_ID - 1))
N=${#LATS[@]}
ilat=${LATS[$((IDX % N))]}
ilon=${LONS[$(((IDX / N) % N))]}

echo "[$SLURM_JOB_ID:$SLURM_ARRAY_TASK_ID] ilat=$ilat ilon=$ilon month=$MONTH"

Rscript "$REPO/scripts/gp/baseline/emulate_baseline.R" ilat=$ilat ilon=$ilon month=$MONTH

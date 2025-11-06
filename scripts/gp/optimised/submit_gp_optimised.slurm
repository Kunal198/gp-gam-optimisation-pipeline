#!/usr/bin/env bash
#SBATCH --job-name=gpopt
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --output=%x_%A_%a.out
#SBATCH --error=%x_%A_%a.err

set -euo pipefail

# --- Site env (edit for your cluster) ---
# module load Anaconda3 || true
# module load R/4.5.1   || true
# source ~/.bashrc 2>/dev/null || true
# conda activate gp-gam || true

REPO="${REPO:-$PWD}"
TASKS_CSV="${TASKS_CSV:-$REPO/examples/tasks_table.csv}"
LOGDIR="${LOGDIR:-$REPO/slurm_logs}"
mkdir -p "$LOGDIR"

# --- Pull row for this array task (skip header) ---
ROWNUM=$(( SLURM_ARRAY_TASK_ID + 1 ))
LINE=$(sed -n "${ROWNUM}p" "$TASKS_CSV")

# CSV: grid_id,lat,lon,variable,month,filename
IFS=',' read -r GRID LAT LON VAR MONTH FILE <<< "$LINE"

echo "[array:$SLURM_ARRAY_TASK_ID] grid=$GRID lat=$LAT lon=$LON var=$VAR month=$MONTH file=$FILE"

# --- Export paths used by emulate_optimised.R (repo-relative defaults are fine too) ---
export TRAIN_BASE="$REPO/examples/tiny_sample_inputs/H2SO4/$MONTH"
export DESIGN_FILE="$REPO/examples/design/UKESM_PPE_Unit_emulation_ready.dat"
export SAMPLE_DIR="$REPO/examples/large_sample"
export JJCODE_FILE="$REPO/scripts/gp/optimised/JJCode_EmPred_LargeSample.r"
export OUTPUT_ROOT="$REPO/examples/tiny_sample_outputs/gp_emulation/optimised"

# --- Run ---
Rscript "$REPO/scripts/gp/optimised/emulate_optimised.R" "$LAT" "$LON" "$MONTH"

#!/usr/bin/env bash
# Launch the optimised GP emulation as a SLURM array and then run a post-check
# Run from repo root:  bash scripts/gp/optimised/run_emulation.sh

set -euo pipefail

# --- Repo paths (relative) ---
REPO="${REPO:-$PWD}"
TASKS_CSV="${TASKS_CSV:-$REPO/examples/tasks_table.csv}"
ARRAY_SCRIPT="${ARRAY_SCRIPT:-$REPO/scripts/gp/optimised/submit_gp_optimised.slurm}"
POSTCHECK="${POSTCHECK:-$REPO/scripts/gp/optimised/post_check_resubmit_emulation.sbatch}"
LOGDIR="${LOGDIR:-$REPO/slurm_logs}"
mkdir -p "$LOGDIR"

# --- Environment (edit for your site) ---
# module load Anaconda3 || true
# module load R/4.5.1   || true
# source ~/.bashrc 2>/dev/null || true
# conda activate gp-gam || true

# --- Figure out number of tasks from tasks_table.csv ---
if [[ ! -f "$TASKS_CSV" ]]; then
  echo "ERROR: tasks CSV not found: $TASKS_CSV" >&2
  exit 1
fi
NTASKS=$(( $(wc -l < "$TASKS_CSV") - 1 ))
if (( NTASKS <= 0 )); then
  echo "ERROR: no tasks in $TASKS_CSV" >&2
  exit 1
fi

echo "[run] Submitting array of $NTASKS tasks..."
SUBMIT_OUT=$(sbatch --export=ALL,REPO="$REPO",TASKS_CSV="$TASKS_CSV",LOGDIR="$LOGDIR" \
                    --parsable --array=1-"$NTASKS" "$ARRAY_SCRIPT")
JOBID="${SUBMIT_OUT%%.*}"
echo "[run] Submitted array job: $JOBID"

echo "[run] Submitting post-check job (afterok:$JOBID)..."
sbatch --export=ALL,REPO="$REPO",TASKS_CSV="$TASKS_CSV",ARRAY_JOBID="$JOBID",LOGDIR="$LOGDIR" \
       --dependency=afterok:"$JOBID" "$POSTCHECK"

echo "[run] Done. Logs: $LOGDIR"

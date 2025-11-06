#!/usr/bin/env bash
#SBATCH --job-name=gpopt_postcheck
#SBATCH --time=00:15:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

set -euo pipefail

REPO="${REPO:-$PWD}"
TASKS_CSV="${TASKS_CSV:-$REPO/examples/tasks_table.csv}"
LOGDIR="${LOGDIR:-$REPO/slurm_logs}"
mkdir -p "$LOGDIR"

MISSING=()

# Iterate tasks (skip header)
N=$(wc -l < "$TASKS_CSV")
for ((i=2; i<=N; i++)); do
  LINE=$(sed -n "${i}p" "$TASKS_CSV")
  IFS=',' read -r GRID LAT LON VAR MONTH FILE <<< "$LINE"

  OUTDIR="$REPO/examples/tiny_sample_outputs/gp_emulation/optimised/lat${LAT}"
  MEAN="$OUTDIR/emulated_mean_values_H2SO4_${MONTH}_ilat_${LAT}_ilon_${LON}_"*"_w_o_carb.dat"
  SD="$OUTDIR/emulated_sd_values_H2SO4_${MONTH}_ilat_${LAT}_ilon_${LON}_"*"_w_o_carb.dat"

  HAS_MEAN=$(compgen -G "$MEAN" || true)
  HAS_SD=$(compgen -G "$SD" || true)

  if [[ -z "$HAS_MEAN" || -z "$HAS_SD" ]]; then
    IDX=$((i-1))   # array index (1-based)
    MISSING+=("$IDX")
    echo "[postcheck] Missing outputs for task index $IDX (lat=$LAT lon=$LON month=$MONTH)"
  fi
done

if (( ${#MISSING[@]} == 0 )); then
  echo "[postcheck] All outputs present. ✅"
  exit 0
fi

# Re-submit only missing indices
IDX_LIST=$(IFS=','; echo "${MISSING[*]}")
echo "[postcheck] Resubmitting missing indices: $IDX_LIST"

sbatch --export=ALL,REPO="$REPO",TASKS_CSV="$TASKS_CSV",LOGDIR="$LOGDIR" \
       --parsable --array="$IDX_LIST" "$REPO/scripts/gp/optimised/submit_gp_optimised.slurm" \
  | tee "$LOGDIR/resubmit_$(date +%Y%m%d_%H%M%S).log"

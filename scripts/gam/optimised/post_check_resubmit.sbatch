#!/bin/bash
#SBATCH --job-name=gam_r_postcheck
#SBATCH --output=slurm_logs/gam_stream/postcheck_%j.out
#SBATCH --error=slurm_logs/gam_stream/postcheck_%j.err
#SBATCH --time=00:20:00
#SBATCH --mem=2000
#SBATCH --cpus-per-task=1
#SBATCH --partition=<PARTITION>
#SBATCH --qos=<QOS>
#SBATCH --account=<ACCOUNT>

set -euo pipefail

LOG_DIR="slurm_logs/gam_stream"
SUCCESS_SENTINEL="✅ Completed successfully."
DEFAULT_ARRAY_SCRIPT="gam_r_filtered_stream.sbatch"  # <-- your actual name

# -------- helpers --------
die(){ echo "❌ $*"; exit 1; }

detect_latest_array_jobid() {
  # expects files like gam_r_filtered_stream_<JOBID>_<TASK>.out
  local latest
  latest=$(ls -1 "${LOG_DIR}/gam_r_filtered_stream_"*"_*.out" 2>/dev/null \
           | sed -E 's/.*gam_r_filtered_stream_([0-9]+)_.*/\1/' \
           | sort -n | tail -1 || true)
  echo "$latest"
}

# -------- inputs / defaults --------
ARRAY_JOBID="${ARRAY_JOBID:-}"
ARRAY_SCRIPT="${ARRAY_SCRIPT:-}"
MAX_RETRY="${MAX_RETRY:-1}"

mkdir -p "$LOG_DIR"

# Default ARRAY_SCRIPT if not provided
if [[ -z "$ARRAY_SCRIPT" ]]; then
  if [[ -f "$DEFAULT_ARRAY_SCRIPT" ]]; then
    ARRAY_SCRIPT="$(readlink -f "$DEFAULT_ARRAY_SCRIPT")"
    echo "ℹ️ ARRAY_SCRIPT not provided; using default: $ARRAY_SCRIPT"
  else
    die "ARRAY_SCRIPT not provided and default '$DEFAULT_ARRAY_SCRIPT' not found in $(pwd)."
  fi
fi
[[ -r "$ARRAY_SCRIPT" ]] || die "ARRAY_SCRIPT not readable: $ARRAY_SCRIPT"

# Default ARRAY_JOBID if not provided (take the latest one seen in logs)
if [[ -z "$ARRAY_JOBID" ]]; then
  ARRAY_JOBID="$(detect_latest_array_jobid)"
  [[ -n "$ARRAY_JOBID" ]] || die "ARRAY_JOBID not provided and could not detect any from ${LOG_DIR}."
  echo "ℹ️ ARRAY_JOBID not provided; detected latest: $ARRAY_JOBID"
fi

echo "🔎 Post-checking array job: $ARRAY_JOBID"
echo "🗂 Logs: $LOG_DIR"
echo "📝 Resubmit script: $ARRAY_SCRIPT"
echo "🔁 MAX_RETRY: $MAX_RETRY"

# Gather per-task OUT logs for this array job
mapfile -t OUT_FILES < <(ls -1 "${LOG_DIR}/gam_r_filtered_stream_${ARRAY_JOBID}_"*.out 2>/dev/null || true)

if (( ${#OUT_FILES[@]} == 0 )); then
  die "No .out logs found for job ${ARRAY_JOBID} in ${LOG_DIR}."
fi

FAILED_IDS=()

for out in "${OUT_FILES[@]}"; do
  # Extract array index: ..._<JOBID>_<TASK>.out
  idx="${out##*_}"; idx="${idx%.out}"

  # Paired .err (may or may not exist)
  err="${LOG_DIR}/gam_r_filtered_stream_${ARRAY_JOBID}_${idx}.err"

  # Success if sentinel found in .out
  if grep -q "$SUCCESS_SENTINEL" "$out"; then
    continue
  fi

  # If no success sentinel, treat as failure unless .err is empty AND .out shows clean end
  if [[ -s "$err" ]]; then
    FAILED_IDS+=("$idx")
  else
    # optional: still count as failure if no clear success in .out
    FAILED_IDS+=("$idx")
  fi
done

if (( ${#FAILED_IDS[@]} == 0 )); then
  echo "🎉 All tasks show success; nothing to resubmit."
  exit 0
fi

# Unique, sorted list
FAILED_UNIQ=$(printf "%s\n" "${FAILED_IDS[@]}" | sort -n | uniq | tr '\n' ',' | sed 's/,$//')
echo "❌ Failed task indices: ${FAILED_UNIQ}"

# Retry guard
RETRY_FLAG="${LOG_DIR}/retry_count_${ARRAY_JOBID}.txt"
CURRENT=0
[[ -f "$RETRY_FLAG" ]] && CURRENT=$(cat "$RETRY_FLAG" || echo 0)

if (( CURRENT >= MAX_RETRY )); then
  echo "🛑 Reached MAX_RETRY=$MAX_RETRY for ${ARRAY_JOBID}. Not resubmitting."
  echo "Failed indices (final): ${FAILED_UNIQ}"
  exit 0
fi

NEW=$((CURRENT+1))
echo "$NEW" > "$RETRY_FLAG"
echo "🔁 Resubmitting ${#FAILED_IDS[@]} failed tasks (retry $NEW/$MAX_RETRY)."

# Resubmit only failed indices
echo "➡️ sbatch --array=${FAILED_UNIQ} \"$ARRAY_SCRIPT\""
sbatch --array="${FAILED_UNIQ}" "$ARRAY_SCRIPT"

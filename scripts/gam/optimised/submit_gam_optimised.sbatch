#!/bin/bash
#SBATCH --job-name=gam_r_filtered
#SBATCH --output=slurm_logs/gam_stream/gam_r_filtered_stream_%A_%a.out
#SBATCH --error=slurm_logs/gam_stream/gam_r_filtered_stream_%A_%a.err
#SBATCH --time=4:00:00
#SBATCH --mem=12000
#SBATCH --cpus-per-task=1
#SBATCH --partition=<PARTITION>
#SBATCH --qos=<QOS>
#SBATCH --account=<ACCOUNT>
#SBATCH --array=1-9672     # Adjust if your TASKFILE has fewer/more lines 9672

### === Environment ===
# module load ... (edit for your cluster)
export R_LIBS_USER=<HOME_PATH>

# Tame hidden threading (prevents per-thread memory spikes)
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

### === Paths ===
TASKFILE=<HOME_PATH>
SCRIPT=<HOME_PATH>

### === Create log folder ===
mkdir -p slurm_logs/gam_stream

### === Sanity checks ===
if [ ! -f "$TASKFILE" ]; then
  echo "❌ Task file not found: $TASKFILE"
  exit 1
fi
if [ ! -f "$SCRIPT" ]; then
  echo "❌ R script not found: $SCRIPT"
  exit 1
fi

# Ensure the array index doesn’t exceed number of lines in TASKFILE
NUM_LINES=$(wc -l < "$TASKFILE")
if [ "$SLURM_ARRAY_TASK_ID" -gt "$NUM_LINES" ]; then
  echo "⚠️  Task ID $SLURM_ARRAY_TASK_ID exceeds line count $NUM_LINES in $TASKFILE — exiting."
  exit 0
fi

### === Extract args for this task (ilat, ilon, month) ===
read ilat ilon month < <(sed -n "${SLURM_ARRAY_TASK_ID}p" "$TASKFILE")
if [ -z "$ilat" ] || [ -z "$ilon" ] || [ -z "$month" ]; then
  echo "❌ Failed to parse ilat/ilon/month for task $SLURM_ARRAY_TASK_ID"
  exit 1
fi

echo "🚀 Running R GAM (streaming predict): ilat=$ilat, ilon=$ilon, month=$month"
echo "📄 Using TASKFILE=$TASKFILE"
echo "📜 Script=$SCRIPT"

### === Run with resource timing ===
/usr/bin/time -v Rscript "$SCRIPT" "$ilat" "$ilon" "$month"
RC=$?

if [ $RC -ne 0 ]; then
  echo "❌ Rscript exited with code $RC"
  exit $RC
else
  echo "✅ Completed successfully."
fi

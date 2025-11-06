#!/bin/bash
#SBATCH --job-name=gam_cpu                         # Name for the job
#SBATCH --output=slurm_logs/gam_output_%A_%a.out   # Output log per task
#SBATCH --error=slurm_logs/gam_error_%A_%a.err     # Error log per task
#SBATCH --time=24:00:00                            # Max time per task
#SBATCH --cpus-per-task=1                          # One CPU per GAM task
#SBATCH --mem=80000                                # 80GB memory is reasonable for large sample
#SBATCH --partition=<PARTITION>                       # Use standard queue
#SBATCH --qos=<QOS>                                 # High priority QoS
#SBATCH --account=<ACCOUNT>                            # Correct project
#SBATCH --array=1-100                               # Array range matches table lines

# === Load Python environment ===
# module load ... (edit for your cluster)
# No need for `source activate` — Jaspy handles env setup

# === Paths ===
TASKFILE=<HOME_PATH>
SCRIPT=<HOME_PATH>

# === Sanity Check ===
if [ ! -f "$TASKFILE" ]; then
    echo "❌ Task file not found: $TASKFILE"
    exit 1
fi

# === Read 3 arguments: ilat, ilon, month ===
read ilat ilon month < <(sed -n "${SLURM_ARRAY_TASK_ID}p" "$TASKFILE")

# === Execute Python GAM script ===
echo "🚀 Running GAM with lat=$ilat, lon=$ilon, month=$month"
python "$SCRIPT" "$ilat" "$ilon" "$month"

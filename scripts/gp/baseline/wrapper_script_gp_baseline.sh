#!/bin/bash

months=(jan feb mar apr may jun jul aug sep oct nov dec)
MAX_PARALLEL_JOBS=8

function float_calc() {
    printf "%.6f" "$(echo "$1 + $2 * $3" | bc -l)"
}

function run_rscript() {
    local rscript_name="$1"
    local ilat="$2"
    local ilon="$3"
    local month="$4"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Rscript for $month: ilat=$ilat, ilon=$ilon"
    local start_time=$(date +%s)

    Rscript ~/Structeral_error/Structeral_error_KG/emulation/Sulphate/Months/"$rscript_name" "$ilat" "$ilon" "$month"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Finished Rscript for $month: ilat=$ilat, ilon=$ilon (Duration: ${duration}s)"
}

for month in "${months[@]}"; do
    if [[ "$month" == "jan" || "$month" == "feb" || "$month" == "dec" ]]; then
        rscript_name="emulate_phase3_and_predict_large_samples_Sulphate_KG_DJF.R"
    else
        rscript_name="emulate_phase3_and_predict_large_samples_Sulphate_KG_JJASON.R"
    fi

    for i in $(seq 0 30); do
        ilat=$(float_calc 34.375 1.25 $i)
        for j in $(seq 0 25); do
            ilon=$(float_calc -10.3125 1.875 $j)

            # Run in background with function and arguments
            run_rscript "$rscript_name" "$ilat" "$ilon" "$month" &

            # Control max parallel jobs
            while (( $(jobs -rp | wc -l) >= MAX_PARALLEL_JOBS )); do
                wait -n
            done
        done
    done
done

wait

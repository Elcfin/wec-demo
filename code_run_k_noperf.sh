#!/bin/bash

# Function to cleanup processes (原perf相关清理逻辑移除，可根据实际补充)
cleanup() {
    echo "Cleaning up temporary resources..."
    # 可根据实际需求补充清理逻辑，比如删除临时文件等
}

# Cleanup on script exit
trap cleanup EXIT

# Global parameters for the experiment
m=4
b=32
s=2
f=/home/elcfin/shm
k_values=(4 8 16 32 64 128)
isal_flags=(true false)  # Array for isal flag

# Check if temporary directory exists, create it if not
if [ ! -d "$f" ]; then
    echo "Creating temporary directory: $f"
    mkdir -p "$f"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create temporary directory $f"
        exit 1
    fi
fi

# Create results directory (include timestamp in name)
RESULTS_DIR="res/results_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR" || { echo "Failed to create results directory"; exit 1; }
echo "All results will be saved to: $RESULTS_DIR"

# Define constants and parameter sets
EXECUTABLE="./code_demo"
OUTPUT_BASE="m${m}_b${b}"

# Function to check if command executed successfully
check_status() {
    if [ $? -ne 0 ]; then
        echo "Error: Command failed - $1" >&2
        return 1
    fi
    return 0
}

# Iterate through k values and execute commands
for k in "${k_values[@]}"; do
    for isal in "${isal_flags[@]}"; do
        # Execute initialization command
        echo -e "[$(date '+%H:%M:%S')] Executing initialization command: ./file_demo -f $f -k $k -b $b -s $s"
        INIT_LOG="$RESULTS_DIR/init_$(date +%H%M%S).log"
        ./file_demo -f $f -k $k -b $b -s $s > "$INIT_LOG" 2>&1

        if [ $? -ne 0 ]; then
            echo -e "\n[$(date '+%H:%M:%S')] Error: Initialization command failed" >&2
            echo "Check log: $INIT_LOG" >&2
            exit 1
        else
            echo -e "\n[$(date '+%H:%M:%S')] Initialization completed successfully"
            echo "Initialization log: $INIT_LOG"
        fi

        i_param=$([ "$isal" = true ] && echo "-i" || echo "")
        echo -e "\n[$(date '+%H:%M:%S')] Starting execution: $EXECUTABLE -v -f $f -k $k -b $b -s $s -o "${RESULTS_DIR}/${OUTPUT_BASE}_s${s}_k${k}_i${isal}.csv" $i_param"

        # Execute command and capture output 
        LOG_FILE="$RESULTS_DIR/log_${OUTPUT_BASE}_s${s}_k${k}_i${isal}.txt"
        start_time=$(date +%s.%N)
        
        $EXECUTABLE -v -f $f -k $k -b $b -s $s -o "${RESULTS_DIR}/${OUTPUT_BASE}_s${s}_k${k}_i${isal}.csv" $i_param > "$LOG_FILE" 2>&1
        check_status "Execution for k=$k failed" || continue
        
        end_time=$(date +%s.%N)
        elapsed=$(echo "$end_time - $start_time" | bc)
        
        echo -e "[$(date '+%H:%M:%S')] Completed (Duration: ${elapsed}s)"
        echo "Log saved to: $LOG_FILE"
        echo "------------------------"
    done
done

# Summarize results
echo -e "\n=== Execution Summary ==="
echo "Performance and throughput summary (check log files for details):"
grep "Encoding throughput" "$RESULTS_DIR"/*.txt | sort -k2 -n || echo "No throughput data found"

# Merge all CSV files
echo -e "\n=== Merging CSV Files ==="
MERGED_FILE="$RESULTS_DIR/${OUTPUT_BASE}_merged.csv"

# Find the first CSV file to get the header
FIRST_CSV=$(find "$RESULTS_DIR" -name "*.csv" -type f | sort | head -n 1)
if [ -z "$FIRST_CSV" ]; then
    echo "No CSV files found to merge."
    exit 1
fi

# Extract header from the first CSV
head -n 1 "$FIRST_CSV" > "$MERGED_FILE"
echo "Header extracted from: $(basename "$FIRST_CSV")"

# Merge data from all CSVs (skipping headers)
echo "Merging data from:"
find "$RESULTS_DIR" -name "*.csv" -type f | sort | while read -r csv_file; do
    echo "  - $(basename "$csv_file")"
    tail -n +2 "$csv_file" >> "$MERGED_FILE"
done

echo -e "\nCSV files merged into: $MERGED_FILE"
echo "Total rows in merged file: $(($(wc -l < "$MERGED_FILE") - 1))"

# Final summary
echo -e "\n=== Experiment Completed ==="
echo "Results saved to: $RESULTS_DIR"
echo "Merged CSV results: $MERGED_FILE"
echo "Execution log files: $RESULTS_DIR/log_*.txt"
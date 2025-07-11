#!/bin/bash

# Global parameters for the experiment
m=4
b=32
s=8
f=/home/elcfin/shm
k_values=(4 8 16 32 64 128)

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
RESULTS_DIR="results_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR" || { echo "Failed to create results directory"; exit 1; }
echo "All results will be saved to: $RESULTS_DIR"

# Define constants and parameter sets
EXECUTABLE="./part_chunk_demo"
OUTPUT_BASE="m${m}_b${b}_s${s}"

# Function to check if command executed successfully
check_status() {
    if [ $? -ne 0 ]; then
        echo "Error: Command failed - $1" >&2
        return 1
    fi
    return 0
}

# Iterate through x values and execute commands
for k in "${k_values[@]}"; do
    s=$((128 / k))

    # Execute initialization command
    echo -e "[$(date '+%H:%M:%S')] Executing initialization command: ./file_demo -f $f -k $k -b $b -s $s"
    INIT_LOG="$RESULTS_DIR/init_$(date +%H%M%S).log"
    ./file_demo -f $f -k $k -b $b -s $s > "$INIT_LOG" 2>&1

    if [ $? -ne 0 ]; then
        echo -e "\n[$(date '+%H:%M:%S')] Error: Initialization command failed" >&2
        echo "Check log: $INIT_LOG" >&2
        # Stop dstat monitoring
        kill -9 $DSTAT_PID
        exit 1
    else
        echo -e "\n[$(date '+%H:%M:%S')] Initialization completed successfully"
        echo "Initialization log: $INIT_LOG"
    fi

    x=$k
    xy=$k
    echo -e "\n[$(date '+%H:%M:%S')] Starting execution: $EXECUTABLE -v -f $f -k $k -b $b -s $s -o "${RESULTS_DIR}/${OUTPUT_BASE}_k$k.csv" -x $x -a ${xy}"
    
    # Execute command and capture output
    LOG_FILE="$RESULTS_DIR/log_${OUTPUT_BASE}_k${k}.txt"
    start_time=$(date +%s.%N)
    
    # Redirect stdout and stderr to log file
    $EXECUTABLE -v -f $f -k $k -b $b -s $s -o "${RESULTS_DIR}/${OUTPUT_BASE}_k$k.csv" -x $x -a ${xy} > "$LOG_FILE" 2>&1
    check_status "Execution for k=$k failed" || continue
    
    end_time=$(date +%s.%N)
    elapsed=$(echo "$end_time - $start_time" | bc)
    
    echo -e "[$(date '+%H:%M:%S')] Completed (Duration: ${elapsed}s)\n"
    echo "Log saved to: $LOG_FILE"
    echo "------------------------"
done

# Summarize results
echo -e "\n=== Execution Summary ==="
grep "Encoding throughput" "$RESULTS_DIR"/*.txt | sort -k2 -n || echo "No throughput data found"

# Merge all CSV files
echo -e "\n=== Merging CSV Files ==="
MERGED_FILE="$RESULTS_DIR/${OUTPUT_BASE}_merged.csv"

# Find the first CSV file to get the header
FIRST_CSV=$(find "$RESULTS_DIR" -name "*.csv" -type f | sort | head -n 1)
if [ -z "$FIRST_CSV" ]; then
    echo "No CSV files found to merge."
    # Stop dstat monitoring
    kill -9 $DSTAT_PID
    exit 1
fi

# Extract header from the first CSV
head -n 1 "$FIRST_CSV" > "$MERGED_FILE"
echo "Header extracted from: $(basename "$FIRST_CSV")"

# Merge data from all CSVs (skipping headers)
echo "Merging data from:"
find "$RESULTS_DIR" -name "*.csv" -type f | sort | while read -r csv_file; do
    # if [ "$csv_file" != "$FIRST_CSV" ]; then
        echo "  - $(basename "$csv_file")"
        tail -n +2 "$csv_file" >> "$MERGED_FILE"
    # fi
done

echo -e "\nCSV files merged into: $MERGED_FILE"
echo "Total rows in merged file: $(($(wc -l < "$MERGED_FILE") - 1))"

# Final summary
echo -e "\n=== Experiment Completed ==="
echo "Results saved to: $RESULTS_DIR"
echo "Merged CSV results: $MERGED_FILE"
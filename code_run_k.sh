#!/bin/bash

# Function to cleanup perf processes
cleanup_perf() {
    echo "Cleaning up any existing perf processes..."
    pkill -f "perf record" 2>/dev/null || true
    pkill -f "perf stat" 2>/dev/null || true
}

# Cleanup on script exit
trap cleanup_perf EXIT

# Global parameters for the experiment
m=4
b=32
s=2
f=/home/elcfin/shm
# k_values=(4 8 16 32 64 68 72 76 80 84 88 92 96 100 104 108 112 116 120 124 128)
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
<<<<<<< HEAD
RESULTS_DIR="res/results_$(date +%Y%m%d_%H%M%S)"
=======
RESULTS_DIR="res_zhaoxin/results_$(date +%Y%m%d_%H%M%S)"
>>>>>>> a3fba8ad2e54129f870d76aac4ecb0bde3547fa6
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

# Iterate through x values and execute commands
for k in "${k_values[@]}"; do
    for isal in "${isal_flags[@]}"; do
        # s=$((128 / k))

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

        i_param=$([ "$isal" = true ] && echo "-i" || echo "")
        echo -e "\n[$(date '+%H:%M:%S')] Starting execution with perf monitoring: $EXECUTABLE -v -f $f -k $k -b $b -s $s -o "${RESULTS_DIR}/${OUTPUT_BASE}_s${s}_k${k}_i${isal}.csv" $i_param"

        # Execute command and capture output with perf monitoring
        LOG_FILE="$RESULTS_DIR/log_${OUTPUT_BASE}_s${s}_k${k}_i${isal}.txt"
        PERF_FILE="$RESULTS_DIR/perf_${OUTPUT_BASE}_s${s}_k${k}_i${isal}.txt"
        start_time=$(date +%s.%N)
        
        # Start perf stat monitoring for cache statistics
        echo -e "[$(date '+%H:%M:%S')] Starting perf monitoring for cache statistics..."
        perf stat -e cache-references,cache-misses,L1-dcache-loads,L1-dcache-load-misses,L1-dcache-stores,L1-dcache-store-misses,L1-icache-loads,L1-icache-load-misses,LLC-loads,LLC-load-misses,LLC-stores,LLC-store-misses,dTLB-loads,dTLB-load-misses,dTLB-stores,dTLB-store-misses,iTLB-loads,iTLB-load-misses -o "$PERF_FILE" $EXECUTABLE -v -f $f -k $k -b $b -s $s -o "${RESULTS_DIR}/${OUTPUT_BASE}_s${s}_k${k}_i${isal}.csv" $i_param > "$LOG_FILE" 2>&1
        check_status "Execution for k=$k failed" || continue
        
        end_time=$(date +%s.%N)
        elapsed=$(echo "$end_time - $start_time" | bc)
        
        echo -e "[$(date '+%H:%M:%S')] Completed (Duration: ${elapsed}s)"
        echo "Log saved to: $LOG_FILE"
        echo "Perf cache statistics saved to: $PERF_FILE"
        
        # Extract and display key cache metrics
        if [ -f "$PERF_FILE" ]; then
            echo "Cache hit rates for k=$k:"
            echo "  L1 Data Cache:"
            L1_LOADS=$(grep -o '[0-9,]\+[[:space:]]\+L1-dcache-loads' "$PERF_FILE" | awk '{print $1}' | tr -d ',')
            L1_MISSES=$(grep -o '[0-9,]\+[[:space:]]\+L1-dcache-load-misses' "$PERF_FILE" | awk '{print $1}' | tr -d ',')
            if [ -n "$L1_LOADS" ] && [ -n "$L1_MISSES" ] && [ "$L1_LOADS" -gt 0 ]; then
                L1_HIT_RATE=$(echo "scale=2; 100 - ($L1_MISSES * 100 / $L1_LOADS)" | bc)
                echo "    Hit rate: ${L1_HIT_RATE}% (${L1_LOADS} loads, ${L1_MISSES} misses)"
            fi
            
            echo "  LLC (Last Level Cache):"
            LLC_LOADS=$(grep -o '[0-9,]\+[[:space:]]\+LLC-loads' "$PERF_FILE" | awk '{print $1}' | tr -d ',')
            LLC_MISSES=$(grep -o '[0-9,]\+[[:space:]]\+LLC-load-misses' "$PERF_FILE" | awk '{print $1}' | tr -d ',')
            if [ -n "$LLC_LOADS" ] && [ -n "$LLC_MISSES" ] && [ "$LLC_LOADS" -gt 0 ]; then
                LLC_HIT_RATE=$(echo "scale=2; 100 - ($LLC_MISSES * 100 / $LLC_LOADS)" | bc)
                echo "    Hit rate: ${LLC_HIT_RATE}% (${LLC_LOADS} loads, ${LLC_MISSES} misses)"
            fi
        fi
        echo "------------------------"
    done
done

# Summarize results
echo -e "\n=== Execution Summary ==="
echo "Performance and throughput summary:"
grep "Encoding throughput" "$RESULTS_DIR"/*.txt | sort -k2 -n || echo "No throughput data found"

echo -e "\n=== Cache Performance Summary ==="
echo "Cache hit rates across all k values:"
for perf_file in "$RESULTS_DIR"/perf_*.txt; do
    if [ -f "$perf_file" ]; then
        k_value=$(basename "$perf_file" | grep -o 'k[0-9]\+' | grep -o '[0-9]\+')
        echo "k=$k_value:"
        
        # L1 Data Cache summary
        L1_LOADS=$(grep -o '[0-9,]\+[[:space:]]\+L1-dcache-loads' "$perf_file" | awk '{print $1}' | tr -d ',')
        L1_MISSES=$(grep -o '[0-9,]\+[[:space:]]\+L1-dcache-load-misses' "$perf_file" | awk '{print $1}' | tr -d ',')
        if [ -n "$L1_LOADS" ] && [ -n "$L1_MISSES" ] && [ "$L1_LOADS" -gt 0 ]; then
            L1_HIT_RATE=$(echo "scale=2; 100 - ($L1_MISSES * 100 / $L1_LOADS)" | bc)
            echo "  L1 Data: ${L1_HIT_RATE}%"
        fi
        
        # LLC summary
        LLC_LOADS=$(grep -o '[0-9,]\+[[:space:]]\+LLC-loads' "$perf_file" | awk '{print $1}' | tr -d ',')
        LLC_MISSES=$(grep -o '[0-9,]\+[[:space:]]\+LLC-load-misses' "$perf_file" | awk '{print $1}' | tr -d ',')
        if [ -n "$LLC_LOADS" ] && [ -n "$LLC_MISSES" ] && [ "$LLC_LOADS" -gt 0 ]; then
            LLC_HIT_RATE=$(echo "scale=2; 100 - ($LLC_MISSES * 100 / $LLC_LOADS)" | bc)
            echo "  LLC: ${LLC_HIT_RATE}%"
        fi
    fi
done

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
echo "Perf cache statistics files: $RESULTS_DIR/perf_*.txt"

# Create a summary of cache performance
CACHE_SUMMARY="$RESULTS_DIR/cache_summary.txt"
echo "=== Cache Performance Summary ===" > "$CACHE_SUMMARY"
echo "Generated on: $(date)" >> "$CACHE_SUMMARY"
echo "" >> "$CACHE_SUMMARY"

for perf_file in "$RESULTS_DIR"/perf_*.txt; do
    if [ -f "$perf_file" ]; then
        k_value=$(basename "$perf_file" | grep -o 'k[0-9]\+' | grep -o '[0-9]\+')
        echo "k=$k_value:" >> "$CACHE_SUMMARY"
        cat "$perf_file" >> "$CACHE_SUMMARY"
        echo "" >> "$CACHE_SUMMARY"
        echo "----------------------------------------" >> "$CACHE_SUMMARY"
    fi
done

echo "Cache performance summary saved to: $CACHE_SUMMARY"
#!/bin/bash

# Global parameters for the experiment
k=128
m=4
b=32
s=16
f=/home/elcfin/shm
xy = 128

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

# Collect comprehensive CPU information
CPU_INFO="$RESULTS_DIR/cpu_info.txt"
echo "=== CPU Information ===" > "$CPU_INFO"

# Basic CPU info
echo "CPU Model:" >> "$CPU_INFO"
cat /proc/cpuinfo | grep "model name" | head -1 | awk -F': ' '{print $2}' >> "$CPU_INFO"
echo "Architecture:" >> "$CPU_INFO"
uname -m >> "$CPU_INFO"
echo "CPU Family:" >> "$CPU_INFO"
cat /proc/cpuinfo | grep "cpu family" | head -1 | awk -F': ' '{print $2}' >> "$CPU_INFO"
echo "Model:" >> "$CPU_INFO"
cat /proc/cpuinfo | grep "model" | head -1 | awk -F': ' '{print $2}' >> "$CPU_INFO"
echo "Stepping:" >> "$CPU_INFO"
cat /proc/cpuinfo | grep "stepping" | head -1 | awk -F': ' '{print $2}' >> "$CPU_INFO"

# CPU core counts
echo "Physical Cores:" >> "$CPU_INFO"
lscpu | grep "Core(s) per socket" | awk -F':\t' '{print $2}' >> "$CPU_INFO"
echo "Threads per Core:" >> "$CPU_INFO"
lscpu | grep "Thread(s) per core" | awk -F':\t' '{print $2}' >> "$CPU_INFO"
echo "Total Logical Cores:" >> "$CPU_INFO"
cat /proc/cpuinfo | grep "processor" | wc -l >> "$CPU_INFO"

# CPU frequency
echo "CPU Frequency (min):" >> "$CPU_INFO"
lscpu | grep "CPU min MHz" | awk -F':\t' '{print $2 " MHz"}' >> "$CPU_INFO"
echo "CPU Frequency (max):" >> "$CPU_INFO"
lscpu | grep "CPU max MHz" | awk -F':\t' '{print $2 " MHz"}' >> "$CPU_INFO"
echo "CPU Boost Status:" >> "$CPU_INFO"
cat /sys/devices/system/cpu/cpufreq/boost 2>/dev/null | grep -q "1" && echo "Enabled" || echo "Disabled" >> "$CPU_INFO"

# Cache information (all levels)
echo "L1 Data Cache:" >> "$CPU_INFO"
lscpu | grep "L1d cache" | awk -F':\t' '{print $2}' >> "$CPU_INFO"
echo "L1 Instruction Cache:" >> "$CPU_INFO"
lscpu | grep "L1i cache" | awk -F':\t' '{print $2}' >> "$CPU_INFO"
echo "L2 Cache:" >> "$CPU_INFO"
lscpu | grep "L2 cache" | awk -F':\t' '{print $2}' >> "$CPU_INFO"
echo "L3 Cache:" >> "$CPU_INFO"
lscpu | grep "L3 cache" | awk -F':\t' '{print $2}' >> "$CPU_INFO"

# Additional performance features
echo "Hyper-threading:" >> "$CPU_INFO"
cat /proc/cpuinfo | grep "siblings" | head -1 | awk -F': ' '{print $2 " cores (HT enabled if > physical cores)"}' >> "$CPU_INFO"
echo "Virtualization Support:" >> "$CPU_INFO"
cat /proc/cpuinfo | grep -q "vmx\|svm" && echo "Enabled (VT-x/AMD-V)" || echo "Disabled" >> "$CPU_INFO"
echo "AVX2 Support:" >> "$CPU_INFO"
cat /proc/cpuinfo | grep -q "avx2" && echo "Yes" || echo "No" >> "$CPU_INFO"
echo "AVX-512 Support:" >> "$CPU_INFO"
cat /proc/cpuinfo | grep -q "avx512" && echo "Yes" || echo "No" >> "$CPU_INFO"

# Thermal and power management
echo "Thermal Design Power (TDP):" >> "$CPU_INFO"
cat /sys/class/hwmon/hwmon*/power1_max 2>/dev/null | head -1 | awk '{print $1/1000000 " W"}' >> "$CPU_INFO" || echo "N/A" >> "$CPU_INFO"
echo "CPU Temperature:" >> "$CPU_INFO"
cat /sys/class/hwmon/hwmon*/temp1_input 2>/dev/null | head -1 | awk '{print $1/1000 " °C"}' >> "$CPU_INFO" || echo "N/A (requires lm-sensors)" >> "$CPU_INFO"

# Display CPU information
echo -e "\n=== System CPU Information ==="
cat "$CPU_INFO"

# Define dstat output file
DSTAT_LOG="$RESULTS_DIR/dstat_system_monitor.csv"

# Start dstat monitoring in the background (capture CPU, disk, memory every second)
echo "Starting system monitoring with dstat..."
dstat -t -cdm -1 --output "$DSTAT_LOG" >/dev/null 2>&1 &
DSTAT_PID=$!
echo "Dstat monitoring started with PID: $DSTAT_PID"

# Execute initialization command
echo -e "[$(date '+%H:%M:%S')] Executing initialization command: ./file_demo -f $f -k $k -b $b -s 2"
INIT_LOG="$RESULTS_DIR/init_$(date +%H%M%S).log"
./file_demo -f $f -k $k -b $b -s 2 > "$INIT_LOG" 2>&1

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

# Define constants and parameter sets
EXECUTABLE="./part_chunk_demo"
OUTPUT_BASE="k${k}_m${m}_b${b}_s${s}_xy${xy}"
x_values=(4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 48 50 52 54 56 58 60 62 64)

# Function to check if command executed successfully
check_status() {
    if [ $? -ne 0 ]; then
        echo "Error: Command failed - $1" >&2
        return 1
    fi
    return 0
}

# Iterate through x values and execute commands
for x in "${x_values[@]}"; do
    echo -e "\n[$(date '+%H:%M:%S')] Starting execution: $EXECUTABLE -v -f $f -k $k -b $b -s $s -o "${RESULTS_DIR}/${OUTPUT_BASE}_x$x.csv" -x $x -a $xy"
    
    # Execute command and capture output
    LOG_FILE="$RESULTS_DIR/log_${OUTPUT_BASE}_x${x}.txt"
    start_time=$(date +%s.%N)
    
    # Redirect stdout and stderr to log file
    $EXECUTABLE -v -f $f -k $k -b $b -s $s -o "${RESULTS_DIR}/${OUTPUT_BASE}_x$x.csv" -x $x  -a $xy > "$LOG_FILE" 2>&1
    check_status "Execution for x=$x failed" || continue
    
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
    if [ "$csv_file" != "$FIRST_CSV" ]; then
        echo "  - $(basename "$csv_file")"
        tail -n +2 "$csv_file" >> "$MERGED_FILE"
    fi
done

echo -e "\nCSV files merged into: $MERGED_FILE"
echo "Total rows in merged file: $(($(wc -l < "$MERGED_FILE") - 1))"

# Stop dstat monitoring
echo -e "\nStopping system monitoring..."
kill -9 $DSTAT_PID
echo "System monitoring results saved to: $DSTAT_LOG"

# Final summary
echo -e "\n=== Experiment Completed ==="
echo "Results saved to: $RESULTS_DIR"
echo "CPU information: $CPU_INFO"
echo "System performance data: $DSTAT_LOG"
echo "Merged CSV results: $MERGED_FILE"
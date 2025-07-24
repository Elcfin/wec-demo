#!/bin/bash

# Function to cleanup processes
cleanup() {
    echo "Cleaning up temporary resources..."
    # 可根据实际需求补充清理逻辑，比如删除临时文件等
}

# Cleanup on script exit
trap cleanup EXIT

# Global parameters for the experiment
m=4
b=32
s=1
f=/home/elcfin/shm
k_values=(4 8 16 32 64 128)
isal_flags=(true)  # Array for isal flag

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
RESULTS_DIR="res_zhaoxin/results_$(date +%Y%m%d_%H%M%S)"
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

# Function to get current CPU core of a process
get_cpu_core() {
    local pid=$1
    # 获取进程当前运行的CPU核心
    local core=$(ps -o psr= -p "$pid")
    local core="${core#"${core%%[![:space:]]*}"}"  # 去除前导空格
    echo "$core"
}

# Function to get current CPU frequency of a core
get_cpu_frequency() {
    local core="${1#"${1%%[![:space:]]*}"}"
     # 从/proc/cpuinfo获取指定核心的当前频率（单位：MHz）
    local freq=$(grep -A 10 "processor[[:space:]]*: $core" /proc/cpuinfo | grep "cpu MHz" | awk '{print $4}')
    if [ -n "$freq" ]; then
        echo "$freq"
    else
        echo "N/A"
    fi
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
        # CPU核心和频率监控日志文件
        CPU_LOG="$RESULTS_DIR/cpu_${OUTPUT_BASE}_s${s}_k${k}_i${isal}.csv"
        touch "$CPU_LOG"  # 创建空文件

        # 写入表头
        echo "timestamp,pid,core,frequency(MHz)" >> "$CPU_LOG"

        start_time=$(date +%s.%N)
        
        # 后台运行主程序并获取PID
        $EXECUTABLE -v -f $f -k $k -b $b -s $s -o "${RESULTS_DIR}/${OUTPUT_BASE}_s${s}_k${k}_i${isal}.csv" $i_param > "$LOG_FILE" 2>&1 &
        main_pid=$!
        
        # 定期记录CPU核心和频率信息到独立日志文件
        echo "CPU core and frequency monitoring started for PID $main_pid" >> "$CPU_LOG"
        while kill -0 $main_pid 2>/dev/null; do
            core=$(get_cpu_core "$main_pid")
            freq=$(get_cpu_frequency "$core")
            timestamp=$(date +%s.%N)
            echo "$timestamp,$main_pid,$core,$freq" >> "$CPU_LOG"  # 直接写入原始输出
            sleep 0.5
        done
        
        # 等待主程序完成并检查状态
        wait $main_pid
        check_status "Execution for k=$k failed" || continue
        
        end_time=$(date +%s.%N)
        elapsed=$(echo "$end_time - $start_time" | bc)
        
        echo -e "[$(date '+%H:%M:%S')] Completed (Duration: ${elapsed}s)"
        echo "Log saved to: $LOG_FILE"
        echo "CPU core and frequency log saved to: $CPU_LOG"
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
echo "CPU core and frequency log files: $RESULTS_DIR/cpu_*.txt"
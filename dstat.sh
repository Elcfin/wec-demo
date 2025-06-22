#!/bin/bash

# =============================================
# Script: start_dstat_monitoring.sh
# Purpose: Start dstat monitoring with timestamped output filenames.
#          Automatically creates output directory and handles basic error checking.
# Usage:   ./start_dstat_monitoring.sh [interval_seconds] [count]
# Example: ./start_dstat_monitoring.sh 1 3600  # Monitor every 1 second for 1 hour (3600 samples)
# =============================================

# Create output directory for dstat results if it doesn't exist
OUTPUT_DIR="./dstat"
mkdir -p "$OUTPUT_DIR" || { 
    echo "Error: Failed to create output directory $OUTPUT_DIR"
    exit 1 
}

# Generate a filename with timestamp (format: dstat_output_YYYYMMDD_HHMMSS.csv)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${OUTPUT_DIR}/dstat_output_${TIMESTAMP}.csv"

# Check if dstat is installed
if ! command -v dstat &> /dev/null; then
    echo "Error: dstat command not found. Install it with:"
    echo "  Debian/Ubuntu: sudo apt install dstat"
    echo "  CentOS/RHEL:   sudo yum install dstat"
    exit 1
fi

# Start dstat monitoring
echo "Starting system monitoring. Output will be saved to: $OUTPUT_FILE"
echo "Sampling interval: ${INTERVAL} second(s)"
echo "Press Ctrl+C to stop monitoring (if count is set to 0)"

dstat -t -cdm --output "$OUTPUT_FILE"
EXIT_CODE=$?

# Post-monitoring status
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "\nMonitoring completed successfully."
    echo "Results saved to: $OUTPUT_FILE"
else
    echo -e "\nMonitoring terminated abnormally (exit code: $EXIT_CODE)"
    [ -f "$OUTPUT_FILE" ] && echo "Partial data saved to: $OUTPUT_FILE"
fi
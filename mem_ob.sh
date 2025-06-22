#!/bin/bash

# =============================================
# Script: run_demo_tests.sh
# Purpose: 
#   1. Initialize temporary data files using file_demo
#   2. Run part_chunk_demo in a loop for a specified number of times, 
#      with timestamp recorded for each iteration
#   3. Handle errors to ensure smooth execution flow
#
# Dependencies:
#   - Ensure file_demo and part_chunk_demo are executable (chmod +x)
#   - These programs should be in the current working directory
# =============================================

# ==================== Configuration Section ====================
# Shared memory directory (passed to -f)
SHM_DIR="/home/elcfin/shm"  

# Common parameters for both programs
BLOCK_SIZE="32"   # -b: Block size
K_VALUE="128"     # -k: Parameter k (e.g., chunk count)
S_VALUE="1"       # -s: Parameter s (e.g., segment size)

# ==================== Execution Section ====================
# Step 1: Initialize temporary data with file_demo
# echo "=== Step 1: Initializing Temporary Files with file_demo ==="
# ./file_demo -f "$SHM_DIR" -b "$BLOCK_SIZE" -k "$K_VALUE" -s "$S_VALUE"

# # Check if file_demo succeeded
# if [ $? -ne 0 ]; then
#     echo "Error: file_demo initialization failed! Script aborted."
#     exit 1
# fi
# echo "=== file_demo Initialization Complete ==="
# echo ""

# Step 2: Run part_chunk_demo in a loop
echo "=== Step 2: Starting part_chunk_demo Loop (${LOOP_COUNT} iterations) ==="
for i in 4 8 16 32 64 128; do
    # Get current timestamp for each iteration
    CURRENT_TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    echo "--- Iteration ${i} (Start Time: ${CURRENT_TIMESTAMP}) : Running part_chunk_demo ---"

    x="$i"
    a="$i"
    k="$i"

    ./part_chunk_demo -f "$SHM_DIR" -b "$BLOCK_SIZE" -k $k -s "$S_VALUE" -x $x -a $a -v
    
    # Check if part_chunk_demo succeeded
    if [ $? -ne 0 ]; then
        echo "Error: part_chunk_demo failed at iteration ${i}! Script aborted."
        exit 1
    fi
    
    # Get timestamp when iteration finishes (optional, if you want end time too)
    END_TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    echo "--- Iteration ${i} (End Time: ${END_TIMESTAMP}) : part_chunk_demo Complete ---"
done
echo "=== part_chunk_demo Loop Finished ==="
echo ""

echo "All operations completed successfully!"
SHM_DIR="/home/elcfin/shm"  
BLOCK_SIZE="32"   # -b: Block size
K_VALUE="128"     # -k: Parameter k (e.g., chunk count)
S_VALUE="8"       # -s: Parameter s (e.g., segment size)

echo "=== Step 1: Initializing Temporary Files with file_demo ==="
./file_demo -f "$SHM_DIR" -b "$BLOCK_SIZE" -k "$K_VALUE" -s "$S_VALUE"

# Check if file_demo succeeded
if [ $? -ne 0 ]; then
    echo "Error: file_demo initialization failed! Script aborted."
    exit 1
fi
echo "=== file_demo Initialization Complete ==="
echo ""
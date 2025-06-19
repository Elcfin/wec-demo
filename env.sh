#!/bin/bash

# ======================================================
# Script: setup_isa_l.sh
# Purpose: 
#   1. Install system dependencies for building ISA-L
#   2. Clone, build, and install Intel ISA-L library
#   3. Install Performance Co-Pilot (pcp) for system monitoring
#
# Usage: 
#   sudo bash setup_isa_l.sh
#
# Notes: 
#   - Requires sudo privileges for system package installation and `make install`
#   - Logs errors at each step for troubleshooting
# ======================================================

# Step 1: Update package lists and install build dependencies
echo "==== Step 1: Update package manager and install dependencies ===="
# Update apt repositories
sudo apt update 
# Install required tools: compilers, assembler, build tools, utilities, and pcp
sudo apt install -y gcc g++ make nasm autoconf libtool git ssh openssh-server pcp

# Check if apt installation succeeded
if [ $? -ne 0 ]; then
    echo "Error: Failed to install system dependencies. Check network or apt repository."
    exit 1
fi


# Step 2: Clone, build, and install ISA-L
echo "==== Step 2: Clone, build, and install ISA-L ===="
# GitHub repository for ISA-L
ISA_L_REPO="https://github.com/intel/isa-l.git"
# Temporary directory to clone the repo (avoids clutter in current directory)
mkdir -p ~/tmp && cd ~/tmp

# Clone the ISA-L repository
git clone $ISA_L_REPO
if [ $? -ne 0 ]; then
    echo "Error: Failed to clone ISA-L repository. Check network or repository URL."
    exit 1
fi

# Navigate into the cloned repository
cd isa-l || exit 1  # Exit if directory does not exist (should not happen if clone succeeded)

# Generate build configuration (required for custom builds)
echo "Running autogen.sh to generate build scripts..."
./autogen.sh
if [ $? -ne 0 ]; then
    echo "Error: autogen.sh failed. Missing build tools?"
    exit 1
fi

# Configure the build (detects system environment)
echo "Configuring build with ./configure..."
./configure 
# Build the library and binaries
echo "Building ISA-L with make..."
make 

# Check if configure or make failed
if [ $? -ne 0 ]; then
    echo "Error: configure or make failed. Check build logs above."
    exit 1
fi

# Install ISA-L system-wide (requires sudo)
echo "Installing ISA-L system-wide with make install..."
sudo make install 

# Check if make install failed
if [ $? -ne 0 ]; then
    echo "Error: make install failed. Requires sudo privileges or missing permissions."
    exit 1
fi


# Final confirmation
echo "==== All steps completed successfully ===="
echo "ISA-L is installed. Verify with commands like: "
echo "  - isa-lctl --version (check tool version)"
echo "  - ls /usr/local/lib | grep libisal (check installed libraries)"
echo ""
echo "PCP (Performance Co-Pilot) is installed. Use commands like:"
echo "  - pcp -v (check PCP version)"
echo "  - pmstat (system performance monitoring)"
echo ""
echo "Note: If 'isa-lctl' is not found, add /usr/local/bin to your PATH or check installation logs."
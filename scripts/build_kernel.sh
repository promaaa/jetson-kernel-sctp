#!/usr/bin/env bash

# build_kernel.sh
# Automates downloading, extracting, and compiling custom SCTP kernel and NVIDIA out-of-tree modules on Jetson Orin Nano (L4T R36.4.4 / JP 6.2).
# To be run natively on the Jetson Orin Nano board.

set -euo pipefail

# 1. Configurable Parameters
L4T_VERSION="R36.4.4"
SOURCE_URL="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.4/sources/public_sources.tbz2"
WORKSPACE_DIR="${HOME}/jetson-kernel-build"
SWAP_SIZE_GB=4

echo "=== Jetson Orin Nano SCTP Kernel Builder ==="
echo "Target BSP Release: ${L4T_VERSION}"
echo "Build Directory   : ${WORKSPACE_DIR}"

# 2. Check System Requirements
if [[ $(uname -m) != "aarch64" ]]; then
    echo "ERROR: This script must be run natively on the Jetson Orin Nano (aarch64 architecture)." >&2
    exit 1
fi

# 3. Create Swap Space (Critical for native build RAM limits)
echo "--- Checking Memory and Configuring Swap ---"
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
echo "Detected RAM: ${TOTAL_RAM_GB} GB"
if [[ ${TOTAL_RAM_GB} -lt 12 ]]; then
    echo "Configuring a temporary ${SWAP_SIZE_GB}GB swap space to prevent link-time Out-Of-Memory crashes..."
    if ! swapon --show | grep -q "/swapfile_build"; then
        sudo swapoff -a || true
        sudo dd if=/dev/zero of=/swapfile_build bs=1M count=$((SWAP_SIZE_GB * 1024)) status=progress
        sudo chmod 600 /swapfile_build
        sudo mkswap /swapfile_build
        sudo swapon /swapfile_build
        echo "Swap space successfully activated."
    else
        echo "Build swapfile already active."
    fi
fi

# 4. Install Compilation Dependencies
echo "--- Installing Build Dependencies ---"
sudo apt-get update
sudo apt-get install -y build-essential bc bison flex libssl-dev libelf-dev libncurses-dev rsync checkpolicy

# 5. Download and Extract Sources
mkdir -p "${WORKSPACE_DIR}"
cd "${WORKSPACE_DIR}"

if [[ ! -f "public_sources.tbz2" ]]; then
    echo "--- Downloading L4T R36.4.4 BSP Sources ---"
    wget -O public_sources.tbz2 "${SOURCE_URL}"
else
    echo "BSP Sources archive already exists, skipping download."
fi

echo "--- Extracting Sources ---"
tar -xjf public_sources.tbz2
cd Linux_for_Tegra/source

echo "Extracting kernel sources and NVIDIA OOT drivers..."
tar -xjf kernel_src.tbz2
tar -xjf nvidia_kernel_display_driver_source.tbz2

# 6. Configure Kernel with SCTP
echo "--- Configuring Kernel ---"
cd kernel/kernel-5.15

# Clean build directory state
make mrproper

# Use default Tegra defconfig
make defconfig

# Apply SCTP and custom localversion options
echo "Applying custom SCTP and localversion config parameters..."
scripts/config --set-val CONFIG_IP_SCTP m
scripts/config --set-str CONFIG_LOCALVERSION "-tegra-oai-sctp"

# Validate configuration updates
make olddefconfig
echo "Verifying CONFIG_IP_SCTP value:"
grep -Hn "CONFIG_IP_SCTP" .config
echo "Verifying CONFIG_LOCALVERSION value:"
grep -Hn "CONFIG_LOCALVERSION" .config

# 7. Compile Main Kernel and In-Tree Modules
echo "--- Compiling Kernel Image (-j4) ---"
make -j4 Image

echo "--- Compiling In-Tree Modules (-j4) ---"
make -j4 modules

# 8. Compile NVIDIA Out-Of-Tree (OOT) Drivers
echo "--- Compiling NVIDIA OOT display and nvgpu drivers ---"
cd "${WORKSPACE_DIR}/Linux_for_Tegra/source"

# Set kernel directory environment for OOT compilation
export KERNEL_HEADERS="${WORKSPACE_DIR}/Linux_for_Tegra/source/kernel/kernel-5.15"

echo "Building nvidia OOT modules..."
make -j4 modules -C kernel/nvidia

echo "Building nvidia-oot modules..."
make -j4 modules -C nvidia-oot

echo "=== Build Completed Successfully ==="
echo "Next step: Run install_kernel.sh to copy artifacts and configure dual-boot entry."

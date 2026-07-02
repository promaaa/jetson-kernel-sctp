#!/usr/bin/env bash

# install_kernel.sh
# Automates the safe installation of compiled SCTP kernel Image, modules, initrd, and updates extlinux.conf.
# To be run natively on the Jetson Orin Nano board.

set -euo pipefail

WORKSPACE_DIR="${HOME}/jetson-kernel-build"
KERNEL_VERSION="5.15.148-tegra-oai-sctp-tegra-oai-sctp"
SOURCE_DIR="${WORKSPACE_DIR}/Linux_for_Tegra/source"

echo "=== Jetson Orin Nano SCTP Kernel Installer ==="
echo "Target Kernel Version: ${KERNEL_VERSION}"
echo "Source Directory     : ${SOURCE_DIR}"

# 1. Check if compile was run
if [[ ! -d "${SOURCE_DIR}/kernel/kernel-5.15" ]]; then
    echo "ERROR: Compiled sources not found. Run build_kernel.sh first." >&2
    exit 1
fi

# 2. Backup extlinux.conf
echo "--- Backing up Boot Configurations ---"
sudo cp /boot/extlinux/extlinux.conf "/boot/extlinux/extlinux.conf.bak.$(date +%F_%T)"
echo "Backup created successfully."

# 3. Install Kernel Image
echo "--- Installing Kernel Image ---"
sudo cp "${SOURCE_DIR}/kernel/kernel-5.15/arch/arm64/boot/Image" /boot/Image-oai-sctp
echo "Image copied to /boot/Image-oai-sctp"

# 4. Install Modules (In-tree and Out-Of-Tree)
echo "--- Installing Modules ---"
cd "${SOURCE_DIR}/kernel/kernel-5.15"
sudo make modules_install INSTALL_MOD_PATH=/

cd "${SOURCE_DIR}"
export KERNEL_HEADERS="${SOURCE_DIR}/kernel/kernel-5.15"
sudo make modules_install INSTALL_MOD_PATH=/ -C kernel/nvidia
sudo make modules_install INSTALL_MOD_PATH=/ -C nvidia-oot

# Generate module dependencies
echo "Generating module dependencies..."
sudo depmod -a "${KERNEL_VERSION}"
echo "Modules installed successfully under /lib/modules/${KERNEL_VERSION}/"

# 5. Generate Custom Initrd
echo "--- Generating custom Initrd ---"
sudo mkinitramfs -o /boot/initrd.img-oai-sctp "${KERNEL_VERSION}"
echo "Initrd generated at /boot/initrd.img-oai-sctp"

# 6. Configure Extlinux BootloaderSafely
echo "--- Updating extlinux.conf ---"

# Extract root partitions options from primary entry
ROOT_LINE=$(grep -E '^\s*APPEND' /boot/extlinux/extlinux.conf | head -n 1 | sed 's/^[[:space:]]*//')

# Check if entry already exists
if grep -q "LABEL oai-sctp" /boot/extlinux/extlinux.conf; then
    echo "OAI SCTP bootloader entry already exists, skipping append."
else
    echo "Appending oai-sctp custom entry to /boot/extlinux/extlinux.conf..."
    sudo sh -c "cat >> /boot/extlinux/extlinux.conf <<EOF

LABEL oai-sctp
      MENU LABEL custom-tegra-oai-sctp kernel with SCTP
      LINUX /boot/Image-oai-sctp
      INITRD /boot/initrd.img-oai-sctp
      ${ROOT_LINE}
EOF"
fi

# Set default boot entry to custom SCTP kernel
echo "Setting DEFAULT entry to oai-sctp..."
sudo sed -i 's/^DEFAULT.*/DEFAULT oai-sctp/' /boot/extlinux/extlinux.conf

echo "=== Installation Complete! ==="
echo "Please reboot your Jetson: sudo reboot"
echo "After rebooting, verify support with: uname -r && checksctp"

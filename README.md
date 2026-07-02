# Jetson Orin Nano Custom SCTP Kernel & OOT Drivers Guide

This repository contains fully tested automation scripts and step-by-step instructions to compile and deploy a custom SCTP-enabled kernel on the **Jetson Orin Nano Developer Kit** (running NVIDIA L4T R36.4.4 / JetPack 6.2).

---

## Why this Repository?

OpenAirInterface (OAI) and other cellular protocol stacks require userspace SCTP socket communication. However, default NVIDIA L4T kernels are compiled with SCTP support disabled (`# CONFIG_IP_SCTP is not set`).

Compiling a custom kernel with SCTP support on Jetson boards is prone to mistakes. This repository helps you avoid the common pitfalls we encountered:
1. **Broken Out-Of-Tree (OOT) Modules**: The Jetson BSP relies heavily on out-of-tree proprietary drivers (such as `nvgpu` and display drivers). If you only compile the main kernel, the display manager will crash and GPU capabilities will be broken.
2. **Module Format Mismatch**: OOT modules must be compiled against the exact same kernel headers, configuration, and compiler version as the main kernel to prevent symbol format errors (`-1 Invalid module format`) on boot.
3. **Link-Time Out-Of-Memory**: Native compilation on the Jetson's 8GB memory scope easily triggers Out-Of-Memory (OOM) compiler crashes.
4. **Bricking Danger**: Editing boot loader configurations without a recovery entry can easily soft-brick the board.

Our scripts handle all of these concerns automatically.

---

## How it Works

The scripts compile the custom kernel **natively** on the Jetson Orin Nano. 
- It configures a temporary **4GB Swap Space** to prevent link-time OOM crashes.
- It downloads the official **L4T R36.4.4 BSP sources** (`public_sources.tbz2`) directly on the board.
- It applies the custom configurations (`CONFIG_IP_SCTP=m` and `CONFIG_LOCALVERSION="-tegra-oai-sctp"`).
- It compiles the kernel, in-tree modules, and all out-of-tree NVIDIA drivers coherently.
- It builds a custom boot `initrd`, copies the kernel `Image`, and updates `/boot/extlinux/extlinux.conf` with a safe dual-boot entry.

---

## Step-by-Step Installation

### Step 1: Clone the Repository Natively on the Jetson Orin Nano
Open a terminal on your Jetson Orin Nano and run:
```bash
git clone https://github.com/promaaa/jetson-kernel-sctp.git
cd jetson-kernel-sctp
```

### Step 2: Make the Scripts Executable
```bash
chmod +x scripts/*.sh
```

### Step 3: Run the Kernel Builder
This script downloads the public sources, configures swap space, installs dependencies, and compiles the kernel and NVIDIA drivers. This will take about **30–45 minutes** using parallelization limited to 4 cores (`-j4`):
```bash
./scripts/build_kernel.sh
```

### Step 4: Run the Installer
This script copies the compiled Image, installs all modules, generates a new `initrd`, and adds the bootloader entry:
```bash
./scripts/install_kernel.sh
```

### Step 5: Reboot the Board
```bash
sudo reboot
```

---

## Verification

After the board boots back up, run the following verification commands to ensure the custom kernel is loaded and SCTP is working:

1. **Verify Kernel Release Version**:
   ```bash
   uname -r
   # Expected Output: 5.15.148-tegra-oai-sctp-tegra-oai-sctp
   ```
2. **Verify SCTP Kernel Support**:
   ```bash
   checksctp
   # Expected Output: SCTP supported
   ```
3. **Verify NVIDIA GPU Drivers and Display**:
   Check if the display server and GPU load correctly:
   ```bash
   nvidia-smi
   ```

---

## Rollback & Recovery

If the custom kernel fails to boot or causes issues, you can boot back into the default stock kernel:

1. **Serial Console Recovery**:
   If you have a serial console attached to the Jetson Orin Nano DevKit, interrupt the bootloader during early boot and select the fallback option:
   ```text
   2: primary (default stock kernel)
   ```
2. **File System Mount Recovery**:
   If the GUI is down but you have SSH access, edit `/boot/extlinux/extlinux.conf` to change the default boot selection back to `primary`:
   ```bash
   sudo sed -i 's/^DEFAULT.*/DEFAULT primary/' /boot/extlinux/extlinux.conf
   sudo reboot
   ```
   Or mount the Jetson's storage card (SD card or NVMe) on a different host computer and edit `/boot/extlinux/extlinux.conf` manually to revert the default boot label.

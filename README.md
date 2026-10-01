# Jetson Orin Nano SCTP Kernel

Reproducible native build and safe installation of an SCTP-enabled kernel for
the Jetson Orin Nano Developer Kit.

## At a glance

| Category | Configuration |
|---|---|
| Target | Jetson Orin Nano Developer Kit |
| Platform | Jetson Linux R36.4.4 / JetPack 6.2.1 |
| Kernel change | `CONFIG_IP_SCTP=m` |
| Build | Native `aarch64` build from pinned NVIDIA sources |
| Boot strategy | Separate `oai-sctp` entry with the stock `primary` entry preserved |
| Purpose | SCTP support with NVIDIA OOT driver compatibility |

## Why a custom kernel

The stock NVIDIA kernel does not enable SCTP. Applications that rely on SCTP
therefore need a custom kernel, while the NVIDIA out-of-tree and display modules
must remain aligned with that kernel build.

The scripts therefore build the kernel, in-tree modules, NVIDIA OOT modules,
and display modules from one verified source bundle. They also account for the
Jetson's memory constraints and preserve a stock boot path.

Built so a Jetson Orin Nano can run an OpenAirInterface 5G DU, whose F1-C
interface runs over SCTP. See
[kaust-5G-research](https://github.com/promaaa/kaust-5G-research).

## Quick start

Requirements: a Jetson Orin Nano running Jetson Linux R36.4.4 / JetPack 6.2.1,
internet access, `sudo`, sufficient free storage, and a serial-console or
filesystem recovery path before activating the custom kernel.

```bash
git clone https://github.com/promaaa/jetson-kernel-sctp.git
cd jetson-kernel-sctp

./scripts/build_kernel.sh
./scripts/install_kernel.sh
```

The first install preserves the current default boot entry. Review
`/boot/extlinux/extlinux.conf` and its timestamped backup, then activate the
custom entry when ready:

```bash
./scripts/install_kernel.sh --activate
sudo reboot
./scripts/verify_kernel.sh
```

## Commands

| Task | Command |
|---|---|
| Build the kernel and modules | `./scripts/build_kernel.sh` |
| Install without changing the default entry | `./scripts/install_kernel.sh` |
| Install and select the custom entry | `./scripts/install_kernel.sh --activate` |
| Verify after reboot | `./scripts/verify_kernel.sh` |
| Check shell scripts | `shellcheck scripts/*.sh tests/*.sh` |
| Test boot-entry updates | `tests/extlinux.test.sh` |

## Pinned inputs

[`sources.env`](sources.env) records the Jetson Linux and JetPack versions,
official NVIDIA source URL, archive size, SHA-256 checksum, and custom kernel
local version.

The build verifies the archive before extraction. If NVIDIA changes the bytes
at the same URL, it stops until the source pin is reviewed and updated
deliberately.

The default external workspace is `~/jetson-kernel-build`. Override build
settings without changing the repository:

| Variable | Default | Purpose |
|---|---|---|
| `JETSON_KERNEL_WORKSPACE` | `~/jetson-kernel-build` | Downloads, extracted sources, and build records |
| `JETSON_KERNEL_BUILD_JOBS` | `4` | Parallel build jobs |
| `JETSON_KERNEL_SWAP_FILE` | `/swapfile_build` | Dedicated build swapfile |
| `JETSON_KERNEL_SWAP_SIZE_GB` | `4` | Build swapfile size |

Example:

```bash
JETSON_KERNEL_WORKSPACE=/mnt/nvme/jetson-kernel-build \
  ./scripts/build_kernel.sh
```

The build derives the final release with `make kernelrelease` and writes source,
compiler, package, and kernel-release metadata to `build-inputs.txt` beside the
external source tree.

## Installation safeguards

- Installs a versioned kernel image and initrd instead of replacing the stock
  files.
- Preserves the stock `primary` boot entry.
- Creates a timestamped backup of `extlinux.conf`.
- Adds or updates one idempotent `oai-sctp` entry.
- Changes the default entry only when `--activate` is supplied.

Do not activate the custom kernel without a tested recovery path.

## Rollback

At boot, select the stock `primary` entry. If SSH still works, restore it as the
default and reboot:

```bash
sudo sed -i 's/^DEFAULT.*/DEFAULT primary/' /boot/extlinux/extlinux.conf
sudo reboot
```

If the board does not reach userspace, use the serial console or mount the boot
filesystem on another host and restore the timestamped `extlinux.conf` backup.

## Validation

Repository checks validate the shell scripts, pinned source metadata, and
boot-entry transformation without compiling the Jetson kernel in CI:

```bash
shellcheck scripts/*.sh tests/*.sh
tests/extlinux.test.sh
```

After boot, `verify_kernel.sh` confirms the expected kernel-release marker,
loads the SCTP module, queries SCTP support, and checks NVIDIA userspace.

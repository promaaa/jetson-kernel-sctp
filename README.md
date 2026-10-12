# Jetson Orin Nano SCTP Kernel

**[Quick start](#quick-start)** · **[Rollback](#rollback)** · **[Pinned sources](sources.env)** · **[OAI split-DU testbed](https://github.com/promaaa/oai-cu-du-lab)** · **[Paper (PDF)](https://github.com/promaaa/oai-cu-du-lab/blob/main/docs/PDFs/research-paper.pdf)**

[![CI](https://img.shields.io/github/actions/workflow/status/promaaa/jetson-kernel-sctp/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/promaaa/jetson-kernel-sctp/actions/workflows/ci.yml)
[![Jetson Orin Nano](https://img.shields.io/badge/Jetson-Orin%20Nano-76b900?style=flat-square&logo=nvidia&logoColor=white)](#at-a-glance)
[![JetPack 6.2.1](https://img.shields.io/badge/JetPack-6.2.1%20%C2%B7%20L4T%20R36.4.4-555?style=flat-square)](sources.env)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)

The stock kernel of the Jetson Orin Nano, `5.15.148-tegra`, is built without SCTP. `modprobe sctp` fails with `Module sctp not found`, and every program that opens an SCTP socket stops there. One of them is the OpenAirInterface 5G distributed unit (DU), whose F1-C link to the central unit runs over SCTP.

This repository rebuilds the whole kernel from NVIDIA's pinned source bundle with `CONFIG_IP_SCTP=m`. It builds the NVIDIA out-of-tree (OOT) and display modules against the same tree, then installs the result beside the stock kernel. The stock boot entry stays untouched as the way back.

![Pinned NVIDIA sources are checked by SHA-256, built on the Jetson and installed; extlinux.conf then offers the untouched stock 5.15.148-tegra entry as rollback and the 5.15.148-oai-sctp entry, which becomes the default after activate](docs/assets/boot-path.svg)

## At a glance

| Category | Configuration |
|---|---|
| Target | Jetson Orin Nano Developer Kit |
| Platform | Jetson Linux R36.4.4 / JetPack 6.2.1 |
| Kernel change | `CONFIG_IP_SCTP=m`, release suffix `-oai-sctp` |
| Build | Native `aarch64` build from a SHA-256-pinned NVIDIA bundle |
| Boot | New `oai-sctp` entry, stock `primary` entry kept |
| Rollback | Pick `primary` at boot, or restore the `extlinux.conf` backup |

**Why not build only `sctp.ko`?** A module must match the exact build of the running kernel. In the lab, a separately built `sctp.ko` failed to load on the stock kernel. A full rebuild gives one kernel release whose in-tree, NVIDIA OOT and display modules all come from the same tree.

## Used in

This kernel lets a Jetson Orin Nano run the DU of a real-radio OpenAirInterface split testbed ([oai-cu-du-lab](https://github.com/promaaa/oai-cu-du-lab)). The Jetson DU drives a USRP B210 in band n78 and keeps 87.5–89.0 % of an x86 DU's handset downlink on all three F1 links:

| F1 link | Jetson Orin Nano | x86 mini PC | Jetson / x86 |
|---|---:|---:|---:|
| Ethernet | 87.9 | 99.4 | 88.4 % |
| Wi-Fi with GRE | 45.3 | 51.8 | 87.5 % |
| 5G with WireGuard | 67.8 | 76.2 | 89.0 % |

Mean handset downlink in Mbps, 20 trials per configuration. The Jetson, B210 and 5G modem weigh 657.4 g and draw about 28 W under sustained traffic.

## Quick start

Requirements: a Jetson Orin Nano on Jetson Linux R36.4.4 / JetPack 6.2.1, internet access, `sudo`, free storage, and a serial console or another way to recover the boot files.

```bash
git clone https://github.com/promaaa/jetson-kernel-sctp.git
cd jetson-kernel-sctp
./jetson-sctp
```

`./jetson-sctp` reads the state of the board, shows it, and offers the next step. Run it again after each step:

```
Jetson Orin Nano SCTP kernel · status
  ✓ Built      5.15.148-oai-sctp
  ✓ Installed  5.15.148-oai-sctp
  · Default    primary (stock kernel)
  · Running    5.15.148-tegra

Next: make oai-sctp the default boot entry.
Run ./jetson-sctp activate now? [Y/n]
```

The steps are always the same: **build**, **install**, **activate**, **reboot**, **verify**. Over SSH, start the build inside `tmux` or `screen`, because the build stops if the connection drops. Without them, the build asks before it starts.

The install keeps `DEFAULT primary` and appends this entry to `/boot/extlinux/extlinux.conf`. Its `APPEND` line, and any `FDT` or `OVERLAYS` line, are copies of the stock entry's lines:

```
LABEL oai-sctp
      MENU LABEL custom SCTP kernel 5.15.148-oai-sctp
      LINUX /boot/Image-5.15.148-oai-sctp
      INITRD /boot/initrd.img-5.15.148-oai-sctp
      APPEND ${cbootargs} root=PARTUUID=... rw rootwait ...
```

Review the file and its timestamped backup before you activate the entry. After the reboot, `verify` runs five checks and lists each result: the architecture, a release that contains `oai-sctp`, the `sctp` module, SCTP sockets through `checksctp`, and the NVIDIA driver through `nvidia-smi`. Each failed check comes with a hint.

### Terminal output

The build and install show one line per step, with a running clock and the newest output line:

```
✓ [6/8] Configure kernel                        0:01  CONFIG_IP_SCTP=m, release 5.15.148-oai-sctp
▸ [7/8] Build kernel Image and modules         12:41  CC      net/sctp/socket.o
```

The full output of every command goes to a log in `~/jetson-kernel-build/logs/`. When a step fails, the tool marks it with `✗`, shows the last lines of the log, and names the failed command and the log file. Use `--verbose` to see all output in the terminal. Pipes and CI logs always get all output. Colors follow [`NO_COLOR`](https://no-color.org).

## Commands

| Task | Command |
|---|---|
| Show the status and offer the next step | `./jetson-sctp` |
| Show the status only | `./jetson-sctp status` |
| Build the kernel and modules | `./jetson-sctp build` |
| Install beside the stock kernel | `./jetson-sctp install` |
| Make `oai-sctp` the default entry | `./jetson-sctp activate` |
| Make the stock `primary` entry the default | `./jetson-sctp rollback` |
| Check the running kernel | `./jetson-sctp verify` |
| Remove the kernel, its modules and its entry | `./jetson-sctp uninstall` |
| Show all command output | add `--verbose` |
| Show the commands | `./jetson-sctp help` |

The scripts in [`scripts/`](scripts/) still work on their own, for example `./scripts/install_kernel.sh --activate`.

## Settings

The build works in `~/jetson-kernel-build`, outside the repository. Environment variables override the defaults:

| Variable | Default | Purpose |
|---|---|---|
| `JETSON_KERNEL_WORKSPACE` | `~/jetson-kernel-build` | Downloads, extracted sources, build records and logs |
| `JETSON_KERNEL_BUILD_JOBS` | `4` | Parallel build jobs |
| `JETSON_KERNEL_SWAP_FILE` | `/swapfile_build` | Build swapfile, created when RAM is below 12 GB |
| `JETSON_KERNEL_SWAP_SIZE_GB` | `4` | Build swapfile size |
| `JETSON_EXTLINUX_CONF` | `/boot/extlinux/extlinux.conf` | Boot configuration that the tool reads and changes |
| `JETSON_KERNEL_EXPECTED_MARKER` | `oai-sctp` | Text that `verify` expects in `uname -r` |

```bash
JETSON_KERNEL_WORKSPACE=/mnt/nvme/jetson-kernel-build ./jetson-sctp build
```

The build swapfile stays on disk. It is not added to `/etc/fstab`, so it is inactive after the next reboot. Then you can delete it with `sudo rm /swapfile_build`.

## Pinned inputs

[`sources.env`](sources.env) records the Jetson Linux and JetPack versions, the official NVIDIA source URL, the archive size and SHA-256 checksum, and the kernel release suffix. The build checks the archive before extraction. If NVIDIA changes the bytes behind the same URL, the build stops until someone reviews and updates the pin.

The build derives the final release with `make kernelrelease`. It writes the repository commit, source, compiler, package versions and kernel release to `build-inputs.txt` beside the extracted sources.

## Installation safeguards

- Installs a versioned kernel image and initrd. The stock `/boot/Image` and `/boot/initrd` are not replaced.
- Installs modules under `/lib/modules/<release>`, so the stock `5.15.148-tegra` modules stay as they are.
- Backs up `extlinux.conf` with a timestamp before every change.
- Adds or updates one `oai-sctp` entry, and running the install again gives the same file.
- Copies `APPEND`, `FDT` and `OVERLAYS` from the stock `primary` entry, and stops if that entry is missing.
- Replaces `extlinux.conf` with one atomic rename, so an interrupted run cannot leave a half-written file.
- Changes `DEFAULT` only on `activate` and `rollback`, and refuses a `DEFAULT` that names no entry.

Do not activate the custom kernel without a tested recovery path.

## Rollback and removal

To go back to the stock kernel:

```bash
./jetson-sctp rollback
sudo reboot
```

If the custom kernel does not boot, select the stock `primary` entry in the boot menu, then run the commands above. If the board does not reach userspace, use the serial console, or mount the root filesystem on another computer and restore the timestamped `extlinux.conf` backup.

`./jetson-sctp uninstall` removes the kernel image, initrd, modules and boot entry, after a question. It refuses while the board runs the custom kernel. The build in `~/jetson-kernel-build` stays.

## Validation

CI checks the shell scripts, the pinned source metadata, the boot-entry changes and the terminal output, and scans the Git history for secrets. It does not compile the Jetson kernel.

```bash
shellcheck jetson-sctp scripts/*.sh tests/*.sh
tests/extlinux.test.sh
tests/ui.test.sh
```

The boot-entry test checks that the custom entry copies the stock options, that a second run changes nothing, that `activate` and `rollback` change only `DEFAULT`, that `uninstall` gives back the stock file, and that a file without a `primary` entry is left unchanged. The output test checks `--help`, unknown options and commands, the report of a failed step, and the next step that `./jetson-sctp` offers.

## What's in this repository

| Path | Contents |
|---|---|
| [`jetson-sctp`](jetson-sctp) | Main command: status, next step, and all actions |
| [`scripts/build_kernel.sh`](scripts/build_kernel.sh) | Downloads, verifies, configures and builds the kernel and all modules |
| [`scripts/install_kernel.sh`](scripts/install_kernel.sh) | Installs the image, initrd and modules, then adds the boot entry |
| [`scripts/verify_kernel.sh`](scripts/verify_kernel.sh) | Checks the running kernel, SCTP and the NVIDIA driver stack |
| [`scripts/update_extlinux.sh`](scripts/update_extlinux.sh) | Adds, removes or selects the `oai-sctp` entry in `extlinux.conf` |
| [`scripts/common.sh`](scripts/common.sh) | Shared paths, steps, logs and error reports |
| [`sources.env`](sources.env) | Pinned NVIDIA source bundle |
| [`tests/`](tests/) | Boot-entry and output tests, with an `extlinux.conf` fixture |

## Citation

If this kernel helps your research, please cite the testbed paper:

```bibtex
@unpublished{duboc2026lightweight,
  author = {Duboc, Marc and El Falou, Ammar},
  title  = {Toward Lightweight Aerial 5G Cells: A Reproducible Real-Radio {OAI} Split-{DU} Testbed on Commodity Arm Platforms},
  note   = {Submitted},
  year   = {2026}
}
```

## License

Scripts and documentation: MIT ([LICENSE](LICENSE)). The Linux kernel and NVIDIA sources that the build downloads keep their own licenses.

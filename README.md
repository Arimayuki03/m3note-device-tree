<div align="center">

<img src="assets/icon.svg" alt="m3note project icon" width="120" height="120">

# Meizu M3 Note (m3note) Device Tree & Kernel Notes

**Device-support resource for the Meizu M3 Note (m3note / MT6755)**

![Device](https://img.shields.io/badge/Device-Meizu%20M3%20Note-red)
![Android](https://img.shields.io/badge/Android-7.0-3DDC84?logo=android&logoColor=white)
![Flyme](https://img.shields.io/badge/Flyme-8.0.0.0A-00A0E9)
![Kernel](https://img.shields.io/badge/Kernel-3.18.35--docker--qtaguid%20%233307-orange)
![Platform](https://img.shields.io/badge/Platform-arm64-blue)
![Docker](https://img.shields.io/badge/Docker-26.1.3--m3note-2496ED?logo=docker&logoColor=white)
![License](https://img.shields.io/badge/License-MIT%20%2B%20GPL--2.0-green)
![Status](https://img.shields.io/badge/Status-field%20tested-brightgreen)

[English](README.md) · [简体中文](README.zh-CN.md) · [Documentation](docs/INDEX.md) · [Current state](docs/CURRENT-STATE.md)

</div>

---

## 🧭 About

A community-maintained device tree and kernel worklog for the Meizu M3 Note
(m3note / MT6755). It collects the device-tree sources, kernel configs and patches, boot
image tooling, Linux chroot/Docker setup, and hardware fixes verified on a real early-batch
device running Flyme 8.0.0.0A.

**Topics:** `android` · `meizu` · `m3note` · `mt6755` · `flyme` · `device-tree` ·
`kernel` · `linux` · `docker` · `magisk` · `arm64` · `mediatek` · `custom-kernel` ·
`chroot`

> Suggested GitHub repository topics are listed above; copy them into the repository's
> **About → Topics** field.

---

### 📖 Overview

This repository is a **device-support package**, not a complete Android ROM or a single
flashable ZIP. It provides source-level material, configuration, tooling and field notes
for one Meizu M3 Note (early hardware batch) running Flyme 8.0.0.0A / Android 7.0.

The main pieces are:

- MT6755 / `wt6755_66_n` device-tree sources extracted from the 3.18.35 kernel
- Kernel defconfigs, the container-enabled config, and hardware/Docker patches
- Boot-image inspection, repacking and hash-verified flashing helpers
- A Linux chroot + Docker workflow on top of Android
- Wi-Fi-only server mode, SD-card Docker storage, zRAM and battery-display scripts

### 📱 Target device

| Item | Value |
|---|---|
| Device | Meizu M3 Note (`m3note`), early hardware batch |
| SoC | MediaTek MT6755 / `mz6755_66_n`, arm64, 8 cores |
| OS | Flyme 8.0.0.0A (Android 7.0, API 24) |
| Kernel | `3.18.35-docker-qtaguid #3307` |
| Root | Magisk 16.3; SELinux runtime **Enforcing** |
| Linux userland | Ubuntu 20.04.5 LTS arm64 chroot |
| Docker | `26.1.3-m3note`, `vfs` storage driver |
| Storage | 64 GB SD card, ext4; Docker data on SD |
| Display | 1080 × 1920 @ 60 Hz |
| Network | Wi-Fi-only server mode (no SIM) |

### 📦 What is included

| Path | Contents |
|---|---|
| `kernel/dts/` | MT6755 / `wt6755_66_n` device tree and required dt-bindings |
| `kernel/configs/` | Vendor defconfig, container config, #32 hardware-fix config |
| `kernel/patches/` | Display, touch, torch, sensor and Docker/cgroup/qtaguid patches |
| `kernel/scripts/` | Kernel build, flash, performance-module and patch scripts |
| `scripts/` | Boot-image tools, chroot, Wi-Fi mode, battery and SD64 helpers |
| `device-scripts/` | Historical 2026-10-15 Magisk `service.d` snapshot |
| `device/` | Partition table (`scatter.txt`) |
| `README.zh-CN.md` | Chinese README |
| `assets/` | Project icon (`icon.svg`) |
| `docs/` | Current state, bring-up, kernel, hardware, chroot, Docker and storage notes |
| `sources/` | How to obtain the kernel source, toolchain and rootfs (large files not included) |

### ✅ Verified features

- Unlocked bootloader, TWRP via `fastboot boot`, Magisk 16.3 root
- Custom 3.18.35 kernel with touch, brightness, dual-LED warm-white torch,
  rear-camera flash, volume-up key, light/proximity sensor and ST480 compass fixes
- Device-tree and kernel-config material for reproducible builds
- Ubuntu 20.04 chroot with SSH and Docker 26.1.3 (`vfs`)
- 64 GB SD-card Docker storage with fail-closed identity checks and boot watchdog
- Wi-Fi-only server mode, 4 GiB zRAM (lz4) and battery-level display helper

### ⚠️ Known limitations

- Front camera (S5K5E8YX) still has a pink/purple color cast
- Docker uses `vfs`; no overlay2, PIDs controller, cgroup v2 or buildx
- Android 7 security patch level is 2019-08-01; Ubuntu 20.04 is past standard support
- Long-term high-load stability has not been certified
- Fixed 100% battery reporting is for always-on/display use, not normal battery use

### 🚀 Quick start

1. **Get the kernel source** — see [`sources/README.md`](sources/README.md).
2. **Build** — start from `kernel/configs/defconfig-wt6755_66_n`; use
   `kernel/scripts/build_fix32.sh` for the hardware-fix baseline, then apply
   `kernel/patches/docker/` for the #3307 feature set.
3. **Repack and flash boot** — use `scripts/bootimg_inspect.py`,
   `scripts/boot_pack.py` / `boot_pack_containers.py`, and the hash-verified
   flashing examples in `scripts/` and `kernel/scripts/`.
4. **Device side** — `scripts/linux.sh` for chroot, `scripts/wifi-server-mode/`,
   `scripts/battery-full/` and `scripts/sd64-migration/`.

> **Warning:** Unlocking, rooting and flashing always carry a risk of data loss or a
> bricked device. Verify your rescue path and keep full partition backups. Do not
> flash `lk` or `preloader`.

### 📚 Documentation

- [Documentation index](docs/INDEX.md)
- [Current state (2026-10-22)](docs/CURRENT-STATE.md)
- [Device bring-up notes (historical)](docs/device-notes.md)
- [Kernel and Docker bring-up (historical)](docs/kernel-and-docker.md)
- [Linux chroot](docs/linux-chroot.md)
- [Wi-Fi server mode](docs/wifi-server-mode.md)
- [SD-card Docker migration](docs/sd64-migration.md)
- [Docker boot fix](docs/sd64-docker-fix.md)
- [Battery display helper](docs/battery-full.md)

### 🙏 Credits and resources

- Reference tutorial: <https://www.juyifx.cn/article/518488655.html>
- Some firmware, flashing tools and resource links in this project were obtained
  from that tutorial. This repository does **not** redistribute those binaries;
  copyright and licensing remain with the original authors or publishers.
- Kernel source: `android_kernel_m3note-master` (Linux 3.18.35 vendor BSP), GPL-2.0.
- TWRP, Magisk, SuperSU, Xposed, mtkclient and other third-party tools are not
  included; obtain them from their upstream projects.
- Third-party components, licensing notes and redistribution restrictions:
  see [`NOTICE.md`](NOTICE.md).

### ⚖️ License

Original scripts and documentation are released under the **MIT License** (see `LICENSE`).
Kernel-derived material under `kernel/dts/` and non-Docker kernel patches follows
**GPL-2.0** (see `LICENSE.GPL-2.0`). Docker/runc/CLI patches under
`kernel/patches/docker/` follow their upstream licenses (Apache-2.0). Third-party
components and firmware keep their own licenses; see [`NOTICE.md`](NOTICE.md).

### 🛡️ Disclaimer

This project is for personal research, backup and learning on owned hardware. Unlocking,
flashing and modifying a device may affect warranty, terms of service or local law; verify
authorization and compliance yourself. The authors are not responsible for data loss,
hardware damage or legal consequences. Do not expose this device or its services directly
to the public internet.

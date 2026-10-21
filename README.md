<div align="center">

<img src="assets/icon.svg" alt="m3note project icon" width="120" height="120">

# Meizu M3 Note (m3note) Device Tree & Kernel Notes

**Bilingual device-support resource for the Meizu M3 Note / 魅蓝 Note 3 (MT6755)**

![Device](https://img.shields.io/badge/Device-Meizu%20M3%20Note-red)
![Android](https://img.shields.io/badge/Android-7.0-3DDC84?logo=android&logoColor=white)
![Flyme](https://img.shields.io/badge/Flyme-8.0.0.0A-00A0E9)
![Kernel](https://img.shields.io/badge/Kernel-3.18.35--docker--qtaguid%20%233307-orange)
![Platform](https://img.shields.io/badge/Platform-arm64-blue)
![Docker](https://img.shields.io/badge/Docker-26.1.3--m3note-2496ED?logo=docker&logoColor=white)
![License](https://img.shields.io/badge/License-MIT%20%2B%20GPL--2.0-green)
![Status](https://img.shields.io/badge/Status-field%20tested-brightgreen)

[English](#english) · [中文](#中文) · [Documentation](docs/INDEX.md) · [Current state](docs/CURRENT-STATE.md)

</div>

---

## 🧭 About / 关于

**English:** A community-maintained device tree and kernel worklog for the Meizu M3 Note
(m3note / MT6755). It collects the device-tree sources, kernel configs and patches, boot
image tooling, Linux chroot/Docker setup, and hardware fixes verified on a real early-batch
device running Flyme 8.0.0.0A.

**中文：** 魅蓝 Note 3（m3note / MT6755）的社区设备树与内核实践资料，包含设备树源、
内核配置与补丁、boot 镜像工具、Linux chroot/Docker 部署，以及在 Flyme 8.0.0.0A
实机上验证过的硬件修复。

**Topics:** `android` · `meizu` · `m3note` · `mt6755` · `flyme` · `device-tree` ·
`kernel` · `linux` · `docker` · `magisk` · `arm64` · `mediatek` · `custom-kernel` ·
`chroot`

> Suggested GitHub repository topics are listed above; copy them into the repository's
> **About → Topics** field.

---

## English

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
| Device | Meizu M3 Note / 魅蓝 Note 3 (`m3note`), early hardware batch |
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

---

## 中文

### 📖 项目简介

本仓库是**设备支持资料包**，不是完整 Android ROM，也不是一个可直接刷入的 ZIP。
它面向一台早期硬件批次的魅蓝 Note 3（Flyme 8.0.0.0A / Android 7.0），提供源码级
材料、配置、工具和实机记录：

- 从 3.18.35 内核提取的 MT6755 / `wt6755_66_n` 设备树
- 内核 defconfig、容器内核配置、硬件与 Docker 补丁
- boot 镜像解析、重打包和带哈希校验/回滚的刷写工具
- Android 上的 Linux chroot + Docker 工作流
- Wi-Fi 服务器模式、SD 卡 Docker 存储、zRAM 和电池显示脚本

### 📱 目标设备

| 项目 | 值 |
|---|---|
| 设备 | 魅蓝 Note 3 / Meizu M3 Note（`m3note`），早期硬件批次 |
| SoC | MediaTek MT6755 / `mz6755_66_n`，arm64，8 核 |
| 系统 | Flyme 8.0.0.0A（Android 7.0，API 24） |
| 内核 | `3.18.35-docker-qtaguid #3307` |
| Root | Magisk 16.3；SELinux 运行时 **Enforcing** |
| Linux 用户态 | Ubuntu 20.04.5 LTS arm64 chroot |
| Docker | `26.1.3-m3note`，`vfs` 存储驱动 |
| 存储 | 64 GB SD 卡 ext4；Docker 数据在 SD |
| 屏幕 | 1080 × 1920 @ 60 Hz |
| 网络 | Wi-Fi 服务器模式（无 SIM） |

### 📦 仓库内容

| 路径 | 内容 |
|---|---|
| `kernel/dts/` | MT6755 / `wt6755_66_n` 设备树及所需 dt-bindings |
| `kernel/configs/` | 原厂 defconfig、容器配置、#32 硬件修复最终配置 |
| `kernel/patches/` | 显示、触摸、手电筒、传感器、Docker/cgroup/qtaguid 补丁 |
| `kernel/scripts/` | 内核构建、刷写、性能模块和补丁脚本 |
| `scripts/` | boot 工具、chroot、Wi-Fi、电池、SD64 脚本 |
| `device-scripts/` | 2026-10-15 的 Magisk `service.d` 历史快照 |
| `device/` | 分区表（`scatter.txt`） |
| `assets/` | 项目图标（`icon.svg`） |
| `docs/` | 当前状态、解锁、内核、硬件、chroot、Docker、存储记录 |
| `sources/` | 内核源码、工具链、rootfs 的获取方式（不包含大文件） |

### ✅ 已验证功能

- 解锁 BL、`fastboot boot` 启动 TWRP、Magisk 16.3 root
- 自编 3.18.35 内核：触摸、亮度、双 LED 暖白手电筒、后摄闪光、音量上键、
  光线/接近传感器、ST480 磁力计
- 可复现的设备树和内核配置材料
- Ubuntu 20.04 chroot、SSH、Docker 26.1.3（`vfs`）
- 64 GB SD 卡 Docker 存储，带 fail-closed 身份校验和开机看护
- Wi-Fi 服务器模式、4 GiB zRAM（lz4）、电池显示脚本

### ⚠️ 已知限制

- 前摄（S5K5E8YX）仍偏粉紫
- Docker 仅 `vfs`；无 overlay2、PIDs controller、cgroup v2、buildx
- Android 7 安全补丁停留在 2019-08-01；Ubuntu 20.04 已过标准支持期
- 未做长期高负载稳定性认证
- 固定 100% 电量只适合长期插电/展示，不适用于正常电池使用

### 🚀 快速开始

1. **获取内核源码**：见 [`sources/README.md`](sources/README.md)。
2. **构建**：以 `kernel/configs/defconfig-wt6755_66_n` 为基线；硬件修复用
   `kernel/scripts/build_fix32.sh`，再应用 `kernel/patches/docker/` 得到 #3307 特性。
3. **重打包与刷写**：使用 `scripts/bootimg_inspect.py`、`scripts/boot_pack.py` /
   `boot_pack_containers.py`，以及 `scripts/` 和 `kernel/scripts/` 中的哈希校验/回滚示例。
4. **设备端**：`scripts/linux.sh` 管理 chroot；`scripts/wifi-server-mode/`、
   `scripts/battery-full/`、`scripts/sd64-migration/` 分别是 Wi-Fi 模式、电池和 SD64 脚本。

> **警告**：解锁、root、刷写都有数据丢失或变砖风险。请先确认救砖通道并保留完整分区备份；
> 不要刷 `lk` 或 `preloader`。

### 📚 文档

- [文档索引](docs/INDEX.md)
- [当前状态（2026-10-22）](docs/CURRENT-STATE.md)
- [设备总记录（历史）](docs/device-notes.md)
- [内核与 Docker 部署（历史）](docs/kernel-and-docker.md)
- [Linux chroot](docs/linux-chroot.md)
- [Wi-Fi 服务器模式](docs/wifi-server-mode.md)
- [SD 卡 Docker 迁移](docs/sd64-migration.md)
- [Docker 启动修复](docs/sd64-docker-fix.md)
- [电池显示脚本](docs/battery-full.md)

### 🙏 参考与资源来源

- 参考教程：<https://www.juyifx.cn/article/518488655.html>
- 项目中的部分固件、刷机工具和资源链接从该教程文章获取。本仓库**不重新分发**
  这些二进制资源；版权和许可归原作者或原发布者。
- 内核源码：`android_kernel_m3note-master`（Linux 3.18.35 厂商 BSP），GPL-2.0。
- TWRP、Magisk、SuperSU、Xposed、mtkclient 等第三方工具未包含，请从上游获取。
- 第三方组件与再分发限制详见 [NOTICE.md](NOTICE.md)。

### ⚖️ 许可

项目作者编写的脚本和文档使用 **MIT 许可**（见 `LICENSE`）。
`kernel/dts/` 和非 Docker 内核补丁遵循 **GPL-2.0**（见 `LICENSE.GPL-2.0`）；
`kernel/patches/docker/` 中的 Docker/runc/CLI 补丁遵循上游许可（Apache-2.0）。
第三方组件和固件遵循各自许可，详见 [NOTICE.md](NOTICE.md)。

### 🛡️ 免责声明

本项目仅用于自有设备的研究、备份和学习。解锁、刷写和修改设备可能影响保修、服务条款
或当地法律；请自行确认授权与合规性。作者不对任何数据丢失、硬件损坏或法律后果负责。
不要把设备或其服务直接暴露在公网。

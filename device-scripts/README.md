> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# 设备脚本全量备份（2026-10-15 晚，内核 #32 运行中）

> **历史快照**：本目录是 2026-10-15 的设备脚本快照（当时 zRAM 2 GiB、内核 #32）。
> 当前内核为 #3307；4 GiB zRAM、SD64、Docker 看护和电池脚本以 `scripts/` 为准。
> 2026-10-22 实测的 `service.d` 还包含 `battery-full`、`docker-watchdog`、
> `dsh-server`、`dsha-ubuntu-client`、`m3note-wifi-server.sh`、
> `m3note-zram-4g.sh`、`magpie-server` 等，详见
> [../docs/CURRENT-STATE.md](../docs/CURRENT-STATE.md)。
> 注意：本目录的 `selinux-permissive` 是当时脚本；2026-10-22 实测运行时
> SELinux 为 **Enforcing**，启动参数才是 `permissive`。

本目录是 **2026-10-15 时设备上生效的** Magisk 启动脚本 + 关键日志的原样备份。
所有 md5 已与设备逐一核对一致（见下表"核对"列）。

## 目录结构

```
device-scripts-2026-10-15/
├── service.d/          ← /sbin/.core/img/.core/service.d/（late_start 阶段，串行执行）
├── post-fs-data.d/     ← /sbin/.core/img/.core/post-fs-data.d/（更早阶段）
├── tmp/                ← /data/local/tmp/ 下的运维脚本（含历史版本）
└── logs/               ← 各脚本的开机运行日志（验证证据）
```

## service.d（按开机执行顺序排列，readdir 顺序）

| 文件 | md5 | 作用 | 备注 |
|---|---|---|---|
| `docker-server` | `01b16dd2…` | 挂载 Ubuntu chroot、拉起 dockerd + sshd | 约 57s 后退出（慢但不堵链） |
| `m3note-zram-2g.sh` | `3fcbd80c…` | zram 扩容到 2GiB | 幂等；post-fs-data.d 也会提前触发一次 |
| `m3note-performance.sh` | `7bebadb9…` | 关 HPS、8 核全开（PPM/CPU online） | boot_completed 后重复执行一次 |
| `m3note-tailscale.sh` | `5a34ebcf…` | **rev3**：入口派生看护进程后**立即退出** | 看护循环：维护 5205 规则 + 保活 tailscaled |
| `m3note-io-tuning.sh` | `6cdbe4a3…` | **I/O 调优**：`deadline` + `read_ahead=1024` | 立即写一次 + boot_completed 后补写一次 |

**关键约束**：Magisk v16.3 串行执行并以 `waitpid` 等待每个脚本退出——
**任何不退出脚本都会堵死整条链**（rev2 tailscale 曾把 io-tuning 堵到永不执行，
详见 `docs/kernel/service-d-blocking.md`）。
以后新增脚本必须快速退出；长期运行的东西用 `setsid … &` 派生。

## post-fs-data.d

| 文件 | md5 | 作用 |
|---|---|---|
| `m3note-model.sh` | `3bada78b…` | 修正 `ro.meizu.product.model`（m91 机型标识）；并提前 20s 触发 zram 扩容 |
| `selinux-permissive` | `2cf06b0d…` | 保持 SELinux permissive |

## tmp/（/data/local/tmp 运维脚本与历史版本）

| 文件 | md5 | 说明 |
|---|---|---|
| `m3note-tailscale.rev2.sh` | `a59d472f…` | tailscale 旧版（含 busybox ip 修复，但**死循环堵链**）——仅作对照 |
| `m3note-tailscale.sh.bak.old` | `10ed568c…` | 最老版本（`.`bak`，最初误留在 service.d 里，同样死循环） |
| `m3note-tailscale-fixed.sh` | `5a34ebcf…` | rev3 源文件（= service.d 里生效的版本） |
| `m3note-io-tuning.sh` | `6cdbe4a3…` | io-tuning 源文件（= service.d 里生效的版本） |
| `live-unblock-io.sh` | `862af680…` | 现场解堵验证脚本（kill 阻塞进程→观察链走完） |
| `test-ts-rev3.sh` | `5cef6f8c…` | rev3 派生机制独立测试 |
| `diag-service-boot.sh` | `7dbf5d5e…` | 首次诊断（进程/日志/目录顺序取证） |

## logs/（验证证据，2026-10-15 20:43 开机）

| 文件 | 证明了什么 |
|---|---|
| `m3note-io.log` | **io-tuning 开机自动执行**：20:43:00 / 20:43:05 两条 applied |
| `m3note-tailscale-boot.log` | rev3 入口 `watchdog detached, exiting` + 看护进程启动 + 规则安装 |
| `m3note-performance.log` | 12:42:59 applying / 12:43:00 online=0-7 |
| `m3note-zram-2g.log` | already target（幂等） |
| `m3note-model-boot.txt` | post-fs-data 阶段 model 修正记录 |

## 恢复方法（设备端，按需单条执行）

```sh
# 恢复某个脚本（例：io-tuning）
adb push <本目录>/service.d/m3note-io-tuning.sh /data/local/tmp/
adb shell "su -c 'cp /data/local/tmp/m3note-io-tuning.sh /sbin/.core/img/.core/service.d/; chmod 755 /sbin/.core/img/.core/service.d/m3note-io-tuning.sh'"

# 回退 tailscale 到 rev2（注意：会再次堵链，仅不建议）
adb push <本目录>/tmp/m3note-tailscale.rev2.sh /data/local/tmp/
adb shell "su -c 'cp /data/local/tmp/m3note-tailscale.rev2.sh /sbin/.core/img/.core/service.d/m3note-tailscale.sh; chmod 755 /sbin/.core/img/.core/service.d/m3note-tailscale.sh'"
```

> 内核镜像备份不在本目录：见 `<ARTIFACTS>/boot-fix32-test.img`
> （md5 `712e4e65b0ba1f36f005f03e817d8743`，= 当时启动分区内容；当前运行内核为 #3307）。

---
*备份：2026-10-15 20:5x*

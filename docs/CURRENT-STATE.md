# 当前状态（2026-10-22）

> 本文以设备实测和最近一次重启验证为准。文中的旧记录（`device-notes.md`、
> `kernel-and-docker.md`、`touch-and-light.md`、`linux-chroot.md` 等）是
> 当时的过程记录，版本和构建号可能已经过时。

## 系统与启动

| 项目 | 当前值 |
|---|---|
| 机型 | 魅蓝 Note 3（Meizu M3 Note），早期硬件批次 |
| SoC | MediaTek MT6755 / mz6755_66_n，arm64，8 核 |
| 系统 | Flyme 8.0.0.0A（Android 7.0） |
| Android 安全补丁 | 2019-08-01 |
| Bootloader | 已解锁；TWRP 通过 `fastboot boot twrp.img` 临时启动 |
| Root | Magisk 16.3（MagiskSU 16.3:1630），SELinux 运行时 Enforcing（enforce=1；启动参数 `ro.boot.selinux=permissive`） |
| 当前内核 | `3.18.35-docker-qtaguid #3307`，已写入 boot 分区 |
| 回滚基线 | #32（硬件修复最终版），原 boot 备份保留 |
| 内存 / 显示 | MemTotal 约 2.72 GiB；zRAM 4 GiB（lz4，实测正在使用）；8 核在线；1080×1920 @ 60 Hz |
| 存储 | 64 GB SD 卡 ext4（实测约 58 GiB，当前约 57 GiB 空闲），Docker 数据在 SD；内部 `/data` 约 25 GiB，当前约 17 GiB 空闲 |
| 分区工具 | `bootimg_inspect.py` / `boot_pack.py` / `boot_pack_containers.py` |

### 内核 #3307

- 基于 #32，保留 lz4 zram、aw8738、ltr579、IRTX 关闭、deadline I/O 等改动。
- 新增 5 个配置项：`CFS_BANDWIDTH`、`BLK_DEV_THROTTLING`、`MEMCG_SWAP`、
  `MEMCG_SWAP_ENABLED`、`DEVPTS_MULTIPLE_INSTANCES`。
- 新增补丁：
  - `net-compat.patch`：Android IPv4 路由 UID 属性与 RTA_VIA 冲突
  - `cpuset-compat.patch`：Android `noprefix` cpuset 层级的标准文件别名
  - `qtaguid-netns-lifetime.patch`：qtaguid 跨网络命名空间生命周期修复
- 已通过普通重启验证；完整 16 MiB 回读校验通过。
- 用户空间配套：`runc-rootfix`、`dockerd-cpusetfix`、`docker-throttlefix`
  （补丁见 `kernel/patches/docker/`）。

## 硬件

### 已修复并验证

| 项目 | 状态 |
|---|---|
| 触摸 | Protocol A 释放帧修正，`ABS_MT_PRESSURE` 注册；桌面点击/打开应用正常 |
| 屏幕亮度 | PWM MUX 时钟在开关时成对 enable/disable，亮度调节正常 |
| 手电筒 | 双 LED 暖白、`flash1`/`flash2` sysfs、Meizu Toolbox 强度调节正常 |
| 后摄闪光 | 拍照闪光正常 |
| 音量上键 | 关闭 IRTX，恢复为普通按键 |
| 光线/接近 | ltr579 驱动与 alsps 框架注册 |
| 传感器 | MTK Light/Proximity、MPL 加速度/陀螺仪/磁场/旋转矢量均已注册并有事件 |
| 水平仪 | ST480 磁力计，`/dev/msensor`，HAL type 1，方向与姿态数据正常 |
| 相机枚举 | 后摄 OV13853、前摄 S5K5E8YX 均可打开 |

### 已知问题

- **前摄偏粉紫**：S5K5E8YX 的 OTP/校准解析已修正，颜色问题仍未解决。
- 主存储 `mmcblk0` 仍会被 Flyme 早期用户态调优写回 `cfq + read_ahead 512`；
  `mmcblk0boot0` 的 deadline 默认值正常。
- 3.18 内核的 syscall/驱动兼容范围有限，较新的容器镜像不保证都能运行。
- Android 7 安全补丁停留在 2019-08-01；Ubuntu 20.04 已结束标准支持，
  长期联网需自行评估安全风险。

## Linux chroot 与 Docker

| 项目 | 当前值 |
|---|---|
| rootfs | Ubuntu 20.04.5 LTS arm64，`/data/ubuntu` |
| SSH | 已启用，密钥登录；服务随开机脚本启动 |
| Docker | 26.1.3-m3note，`vfs` 存储驱动 |
| 容器 | 当前仅 `beszel-agent` 运行（3 个镜像）；AstrBot 已删除（无容器/镜像） |
| 网络 | 桥接、NAT、DNS、端口映射、Compose 已通过短时回归 |
| 限制 | 无 overlay2、PIDs controller、cgroup v2、buildx、IPv6 外网 NAT、macvlan/ipvlan |

### 当前服务（adb 实测，2026-10-22）

| 服务 | 版本/状态 |
|---|---|
| DSH | 0.2.0-rc.2，运行中；Web 3080（本机/局域网） |
| DSHA | 0.2.0-ubuntu20.0.9，运行中（Android 包 `com.dsh.client.ubuntu20` + Ubuntu 侧 broker） |
| Magpie | 0.1.1313，运行中；监听 3425/3430 |
| AstrBot | 已删除（无容器/镜像） |

DSHA 由 Android 客户端和 Ubuntu 侧 broker 组成；DSH 与 Magpie 运行在 Ubuntu chroot 中，
不是 Docker 容器。以上状态为 2026-10-22 adb 实测。

Docker 已修复 qtaguid 生命周期 panic 路径，并通过 10 分钟定向回归和普通重启；
这不等同于数天高负载稳定性认证。

### 当前 Magisk 开机脚本

`service.d`（2026-10-22 实测）：

`battery-full`、`docker-server`、`docker-watchdog`、`dsh-server`、
`dsha-ubuntu-client`、`m3note-app-background.sh`、`m3note-eight-core.sh`、
`m3note-io-tuning.sh`、`m3note-performance.sh`、`m3note-tailscale.sh`、
`m3note-wifi-server.sh`、`m3note-zram-4g.sh`、`magpie-server`

`post-fs-data.d`：

`m3note-model.sh`、`selinux-permissive`

> `selinux-permissive` 脚本仍在，但 2026-10-22 实测运行时为 **Enforcing**
> （`getenforce=Enforcing`，`/sys/fs/selinux/enforce=1`）。启动参数
> `ro.boot.selinux=permissive` 不等于运行时状态。

## 存储

- 64 GB SD 卡，ext4，卷标 `<SD_VOLUME_LABEL>`。
- Docker 数据、容器可写层、Beszel 数据在 SD 卡；AstrBot 已删除。
- 开机流程：校验卡身份/分区几何/ext4 UUID → `e2fsck -p` → 挂载 →
  绑定数据目录 → 启动 Docker。
- 卡缺失、身份不匹配、只读或检查失败时 **fail-closed**，不会回退到内部旧数据。
- 内部旧业务快照已清理；运行期间不要拔卡。
- `docker-watchdog` 在开机后重试 SD 挂载和 Docker 启动（最多 15 次，每次 60 秒）。

## 网络与电源

- **Wi-Fi 服务器模式**：不插 SIM，飞行模式 + Wi-Fi；拨号、通话界面、短信/彩信、
  虚拟 SIM、魅族云/账户/同步/查找手机已禁用。
- 保留 `com.android.phone`、Telecom、联系人等底层框架，避免破坏系统服务。
- Tailscale 可选；SSH 仍可通过局域网访问。
- **供电/电池**：按记录为长期插电/直供电改造；`dumpsys battery` 实测
  `present=true`、电压约 4.87 V、温度约 31 °C。`level`/`status`/`ac` 是
  `battery-full` 脚本覆盖值，不代表真实电量。
- **电池满电脚本**：每 30 秒把系统上报值设为 100%/charging；只是显示值，
  不是真实充电，长期使用需注意电池老化和突然关机风险。

## 回退与安全

- boot 分区回滚目标为 #32；不要刷 `lk` / `preloader`。
- 所有写分区脚本都应先校验基线哈希、写入后回读校验，并保留可回滚镜像。
- 当前设备已解锁、已 root；SELinux 运行时为 Enforcing，但启动参数为
  `permissive`，安全边界仍低于原生系统；不要把它当作暴露在公网的生产服务器。

## 相关文档

- [文档索引](INDEX.md)
- [历史：解锁与早期内核调试](device-notes.md)
- [历史：内核与 Docker 部署](kernel-and-docker.md)
- [Linux chroot](linux-chroot.md)
- [Wi-Fi 服务器模式](wifi-server-mode.md)
- [SD 卡 Docker 迁移](sd64-migration.md)
- [Docker 启动失败修复](sd64-docker-fix.md)
- [电池满电脚本](battery-full.md)

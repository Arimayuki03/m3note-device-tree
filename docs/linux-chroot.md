> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# 魅蓝 note3 改造 Linux 服务器 — 实施记录

> **历史记录**：本文写于 Flyme 6.3.5.0A / SELinux Permissive 时期；当前系统已升级为
> **Flyme 8.0.0.0A**，SELinux 运行时为 **Enforcing**，chroot/SSH/Docker 方案继续使用。
> 现状见 [CURRENT-STATE.md](CURRENT-STATE.md)。

- **设备**：魅族 m3 note（Meizu M3 Note），序列号 `SERIAL_REDACTED`
- **系统**：Flyme 6.3.5.0A（写作时）/ 当前 Flyme 8.0.0.0A / Android 7.0 / 内核 3.18.35+ / aarch64
- **供电**：已改为**直供电（无电池）**
- **网络**：WiFi `192.0.2.10`（DHCP）
- **文档生成**：2026-10-14
- **在线副本**（由本机 nginx 提供）：`http://192.0.2.10/m3note-linux-server.txt`

---

## 0. 一页速览

| 目标 | 结果 |
|---|---|
| 手机做成 Linux 服务器 | ✅ 已实现（Ubuntu 20.04.5 LTS arm64 chroot） |
| 开机跑 Docker | ❌ **不可行**，内核缺命名空间与 cgroup，编译期选项无法运行时补救 |
| 替代方案 | ✅ udocker（PRoot 用户态）可拉取并运行官方镜像 |
| SSH 远程登录 | ✅ 22 端口，root 与 dev 用户均可密钥登录 |
| Web 服务 | ✅ nginx 80 端口，局域网 HTTP 200（0.012s） |
| apt 装软件 | ✅ 走阿里云 ubuntu-ports 源 |
| 读取手机传感器 | ✅ 环境光 / 距离 / 加速度 / 指南针等（**需先激活采样**） |
| 掉电自恢复 | ❌ 未做（需你选方案，见第 13 节） |

---

## 1. 设备与系统信息

| 项目 | 值 |
|---|---|
| 内核 | `3.18.35+` |
| 架构 | `aarch64`（ABI 列表含 `arm64-v8a`） |
| CPU | MT6755 / Helio P10，可见 6 核（省电策略会收窄到 2 核） |
| 内存 | 2.7 GB，可用约 1.5 GB；另有 zram 压缩交换 1.4 GB |
| 存储 | `/data` 25 GB，剩余约 12 GB |
| SELinux | **Permissive** |
| bootloader | `ro.boot.verifiedbootstate = green` → **锁定，不能刷未签名 boot** |
| `/data` 挂载参数 | `rw,seclabel,nosuid,nodev,noatime,discard,noauto_da_alloc,resuid=10010,data=ordered` |
| 输入电压 | 实测 `5.087 V`（见第 7 节） |

---

## 2. 核心结论：真 Docker 为什么不可行

这是整个项目最重要的结论，**两个硬缺失都是内核编译期选项，运行时无法补**：

### 2.1 命名空间只有 `mnt`

```
ls /proc/self/ns/   →  只有 mnt
readlink /proc/self/ns/pid|net|uts|ipc|user  →  全部不存在
```

runc / containerd 没有 **PID 和 NET 命名空间**就无法创建任何容器。

### 2.2 cgroup 控制器严重残缺

```
cat /proc/cgroups
#subsys_name  hierarchy  num_cgroups  enabled
cpu           2          2            1
cpuacct       1          89           1
freezer       0          1            1
debug         0          1            1
```

没有 `memory`，也没有 Docker **硬性要求**的 `devices` 控制器 → dockerd 会直接拒绝启动。

### 2.3 唯一理论出路与它的死结

魅族官方公开了内核源码（`github.com/meizuosc/m681`），理论上可自编译带完整 cgroup/namespace 的内核。但：

- bootloader 锁定（verifiedbootstate=green），**刷入未签名 boot 会被验证拒绝**；
- mtkclient 的支持列表未包含 MT6755/魅族机型；
- 强行尝试有**变砖风险**。

**结论：此路不通。** 替代方案是 udocker（PRoot 用户态模拟）。

---

## 3. 能力验证结果

| 能力 | 结果 | 备注 |
|---|---|---|
| root（uid 0） | ✅ | 通过 Flyme 内置 Root 开关 |
| tmpfs 挂载 | ✅ | |
| bind 挂载 | ✅ | 必须用 `--bind`，`-o bind` 不支持 |
| ext4 镜像 + loop | ✅ | `/dev/block/loop1`–`loop7` 空闲（loop0 被 Android 占用） |
| `chroot` 命令 | ✅ | toybox 自带 |
| SELinux 拦截 | 无 | 已是 Permissive |
| 真容器 | ❌ | 见第 2 节 |
| 公网访问 | ❌ | 需路由器端口映射，且内网穿透工具在 GitHub 上 |

---

## 4. root 权限的获取方式

**没有用任何漏洞**——Flyme 系统设置里自带「Root 权限」开关（设置 → 指纹和安全）。

- su 二进制：`/system/xbin/su`（Meizu 自研实现，10 KB，setuid root）
- **不支持的**：`su -c "命令"`
- **可用的两种写法**：
  ```bash
  su 0 <命令>              # 例：su 0 id  →  uid=0(root)
  printf 'id\n' | su       # 管道喂命令
  ```
- 实现机制（从二进制字符串逆出）：读取调用者进程 `/proc/<pid>` → 用 `am start` 拉起 `com.meizu.settings.root.FlymeRootRequestActivity` 授权界面 → 通过系统属性 `sys.root_permission` 回传结果；`ro.flyme.root.state = 1` 表示已开启
- **获得的 root 上下文是 `u:r:shell:s0`**（uid 0 但保留 shell 域），因为 SELinux 是 Permissive 所以不影响使用
- 临时性：系统 OTA 更新后开关会被重置

---

## 5. chroot 部署过程

### 5.1 方案选择

**用目录 `/data/linux`，不用 ext4 loop 镜像**。理由：

- `/data` 是 `nosuid,nodev`，但整套服务都以 **root 身份**运行 → `nosuid` 不产生影响（服务降权用的是 `setuid()` 系统调用，不是 setuid 位）
- `nodev` 用 `mount --bind /dev` 解决
- 少一个 loop 依赖，重启时少一个故障点

（ext4 镜像方案同样验证过可用，需要时可切换。）

### 5.2 部署步骤

```bash
# 1) 下载并推送 rootfs（在电脑上）
curl -LO https://cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.5-base-arm64.tar.gz
adb push ubuntu-base-arm64.tar.gz /data/local/tmp/

# 2) 推静态 busybox（toybox 的 tar 不支持 -p / --numeric-owner）
#    来源：Alpine busybox-static apk 里的 bin/busybox.static
adb push busybox.static /data/local/tmp/bb

# 3) 手机上（root）安装
su 0 mkdir -p /data/linux
su 0 mv /data/local/tmp/bb /data/busybox && su 0 chmod 755 /data/busybox
su 0 mv /data/local/tmp/ubuntu-base-arm64.tar.gz /data/
su 0 /data/busybox tar -xzpf /data/ubuntu-base-arm64.tar.gz -C /data/linux

# 4) 挂载伪文件系统
su 0 mount -t proc proc /data/linux/proc
su 0 mount --bind /sys /data/linux/sys
su 0 mount --bind /dev /data/linux/dev
su 0 mount --bind /dev/pts /data/linux/dev/pts

# 5) 进入（注意必须显式给 PATH，Android 的 PATH 会带进来）
su 0 /data/busybox chroot /data/linux /usr/bin/env -i \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  HOME=/root TERM=xterm LANG=C.UTF-8 /bin/bash -i -l
```

**为什么选 Ubuntu 20.04**：它带 glibc 2.31，不会踩 `clone3` / `faccessat2` 这类新系统调用在 3.18 老内核上的坑（22.04/12 有风险）。

**为什么不 root 也要用 `busybox tar`**：解压后 setuid 位（`/bin/mount`、`/usr/bin/passwd`）得以保留。

### 5.3 系统配置

```bash
# DNS（Android 没有 /etc/resolv.conf，必须手写）
echo nameserver 223.5.5.5   > /data/linux/etc/resolv.conf
echo nameserver 119.29.29.29 >> /data/linux/etc/resolv.conf

# apt 源换国内（arm64 走 ubuntu-ports）
deb http://mirrors.aliyun.com/ubuntu-ports/ focal main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu-ports/ focal-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu-ports/ focal-security main restricted universe multiverse
```

### 5.4 安装的软件（18 个）

`openssh-server`、`nginx-light`、`python3`、`python3-pip`、`git`、`curl`、`ca-certificates`、`cron`、`tmux`、`sqlite3`、`proot`、`iproute2`、`procps`、`nano`、`less`、`wget`、`xz-utils`、`unzip`

系统共 179 个包，占用 655 MB。

### 5.5 用户与密钥

| 用户 | uid | 组 | 说明 |
|---|---|---|---|
| root | 0 | — | 仅密钥登录（无密码） |
| dev | 3000 | 3000, **aid_inet(3003)**, aid_net_raw(3002) | **必须带 3003 组才有网络**，见 6.2 |

SSH 密钥（ed25519）：请自行生成一对密钥，例如 `id_ed25519_m3note` / `id_ed25519_m3note.pub`。仓库不包含任何私钥。

---

## 6. 网络问题的两个根因 ⭐

**这两条是本次最有价值的技术发现**，Android chroot 场景下几乎必然会撞上。

### 6.1 apt 一定失败：`_apt` 用户没有网络

**现象**：apt 报 `Temporary failure resolving 'mirrors.aliyun.com'`，但 root 下手动 `getent hosts` 解析正常。

**根因**：apt 的下载方法会**降权到 `_apt`（uid 42）**，而该 uid 在 Android 的策略下没有网络。

**修复**：`/etc/apt/apt.conf.d/99-android-nosandbox`

```
APT::Sandbox::User "root";
```

（GPG 签名校验不受影响，只是不再降权下载。）

### 6.2 非 root 用户完全没网：`CONFIG_ANDROID_PARANOID_NETWORK`

**现象**：uid 3000/2000/42 连一个开放的数字 IP 都连不上，而 root 正常。iptables 加 ACCEPT 规则**无效**。

**根因**：Android 内核编译时启用了 `CONFIG_ANDROID_PARANOID_NETWORK`——**只有属于 gid 3003（`AID_INET`）组的进程才能创建 IPv4/IPv6 socket**，否则 `socket()` 直接被内核拒绝。root 天然在所有组里所以没事。

**修复**：给用户加上该组

```bash
groupadd -g 3003 aid_inet
groupadd -g 3002 aid_net_raw      # 需要原始套接字（ping）时
useradd -m -u 3000 -s /bin/bash -G aid_inet,aid_net_raw dev
```

**验证**：加组前 `NET_FAIL`，加组后 `NET_OK` + DNS 正常解析。

### 6.3 网络环境限制

- ❌ GitHub 直连不通（从手机和电脑都实测过）
- ❌ Docker Hub（`registry-1.docker.io` / `auth.docker.io`）不通
- ✅ 阿里云 ubuntu-ports、清华 PyPI 可用
- ✅ CN Docker 镜像站可用：`docker.m.daocloud.io`、`docker.1ms.run`、`dockerproxy.net`

---

## 7. 硬件接口清单

### 7.1 可控制（已验证可写）

| 硬件 | 路径 | 用法 |
|---|---|---|
| 振动马达 | `/sys/class/timed_output/vibrator/enable` | 写毫秒数 |
| 屏幕背光 | `/sys/class/leds/lcd-backlight/brightness` | 0–255 |
| 通知灯 | `/sys/class/leds/mx-led/brightness`、`.../blink` | |

### 7.2 传感器（`/dev/input/event*`）

| 设备 | 节点 | 内容 |
|---|---|---|
| hall_sensor | event0 | 霍尔 |
| compass | event1 | 指南针 |
| ACCDET | event2 | 耳机检测 |
| gf-keys | event3 | 指纹按键 |
| mtk-kpd | event4 | 物理键 |
| hwmdata | event5 | 硬件监控数据 |
| **m_alsps_input** | **event6** | **环境光 + 距离（LTR-579）** |
| mtk-tpd | event7 | 触摸屏 |

另有完整 Invensense 传感器 HAL（20 个传感器：加速度/陀螺/磁力/旋转矢量/计步等），低层芯片为 `icm20608`(accel+gyro)、`akm09911`/`st480`(磁力)。

### 7.3 环境光实测（LTR-579，i2c 地址 `1-0060`）

三条读取路径：

```bash
# A) 最方便：HAL 直接给出带时间戳的 lux 值
dumpsys sensorservice | grep -A14 'MTK Light: last'

# B) 原始输入事件（每 200ms 一次 EV_ABS ABS_X）
getevent -lt /dev/input/event6

# C) 驱动层 sysfs
cat /sys/bus/i2c/drivers/ltr579/als      # 实时值索引
cat /sys/bus/i2c/drivers/ltr579/ps       # 距离原始值
cat /sys/bus/i2c/drivers/ltr579/alslv    # 标定表：原始计数（16 级）
cat /sys/bus/i2c/drivers/ltr579/alsval   # 标定表：对应 lux
cat /sys/bus/i2c/drivers/ltr579/reg      # 完整寄存器映射
```

**实测数据**（凌晨 05:37）：

```
MTK Light: last 10 events
 1 (wall=05:37:08.951)  5.00 lux
 2 (wall=05:37:09.153)  6.00 lux      ← 5/6 之间跳动
 ...共 10 条，间隔 200ms
MTK Proximity:  5.00（sysfs 原始值 107）
MPL Accelerometer: -0.40, 8.98, 4.18  ← 手机斜放在桌上
```

**⚠️ 关键限制：传感器默认是空闲的。** Android 只在**有客户端订阅**时才采样它；默认订阅者是「自动亮度」（`AutomaticBrightnessController`），**屏幕一熄灭就退订**。

因此按需读取的完整动作是：

```bash
su 0 input keyevent 224                          # 唤醒屏幕
su 0 settings put system screen_brightness_mode 1  # 临时开自动亮度
sleep 3
su 0 sh -c "dumpsys sensorservice | grep -A3 'MTK Light: last'"
su 0 settings put system screen_brightness_mode 0  # 恢复
su 0 input keyevent 26                             # 屏幕重新休眠
```

**想要持续记录光照**只能：屏幕常亮（费电+磨屏）或写 Android App 订阅。不划算。

### 7.4 供电遥测（直供电特色）

| 节点 | 读数 | 判读 |
|---|---|---|
| `battery/present` | 1 | 燃料计仍以为有电池 |
| `battery/capacity` | 100（恒定） | **假值** |
| `battery/batt_temp` | 300（恒定 30.0°C） | **假值**（热敏电阻在电池包里，已随电池移除） |
| `battery/batt_vol` / `InstatVolt` / `ChargerVoltage` | **≈5087 / 5087 / 5080 mV** | **真值**——电池不存在时这几个节点读的是 **5V 输入轨** |
| `usb/online` | 1 | 供电走 USB 通路 |

**实用结论**：可以用 `batt_vol` 当**供电质量监测**——**低于约 4.8V 就该换线或换充电头**（压降会让 eMMC 写入出错）。

### 7.5 温度

13 个 `/sys/class/thermal/thermal_zone*`，实测 zone0=30°C、zone1=35.1°C、zone2=36°C、zone5=31°C（读数为毫摄氏度）。

### 7.6 不可用

- **手电筒**：MTK 未暴露可写 sysfs 节点（只有 `soc:flashlight`/`kd_camera_flashlight` 驱动目录，无可写 brightness），需 Camera2 API 写 App 才能控
- **摄像头 / GPS 精细数据**：同样需要 App 或更高层接口

### 7.7 Android 工具可达性

`screencap`、`am`、`input`、`dumpsys`、`getevent`、`content`、`cmd` 都在 `/system/bin`，但 **chroot 内看不到 `/system`**（未 bind）。把 `/system` bind 进 chroot 后即可在 Linux 内调用这些工具（截图、模拟按键、读短信等）。

---

## 8. 已验证可用的服务

| 服务 | 状态 | 验证方式 |
|---|---|---|
| sshd | ✅ 22 端口 | 从 PC 以 root / dev 密钥登录成功 |
| nginx | ✅ 80 端口 | `HTTP 200 in 0.012s`，返回默认页 |
| apt | ✅ | 走阿里云源，安装 87 个依赖包成功 |
| udocker | ✅ | `library/alpine:3.19` 容器内输出 `3.19.9 / aarch64` |
| cron / tmux / git / python3 / sqlite3 | ✅ 已装可用 | |
| sftp | ✅ | `sshd_config` 含 sftp 子系统，可直接用 WinSCP/FileZilla |

**udocker 用法**（必须用非 root 用户）：

```bash
runuser -u dev -- udocker pull --registry=https://docker.m.daocloud.io library/alpine:3.19
runuser -u dev -- udocker create --name=alpine319 library/alpine:3.19
runuser -u dev -- udocker run alpine319 /bin/sh
```

---

## 9. 文件清单

### 9.1 电脑工作目录（示例，按自己的目录调整）

| 文件 | 用途 | 状态 |
|---|---|---|
| `m3note-linux-server.md` | **本文档**（在线副本 `http://192.0.2.10/m3note-linux-server.txt`） | 保留 |
| `id_ed25519_m3note` | **SSH 私钥（未随仓库发布，请自行生成并保管）** | 本地 |
| `id_ed25519_m3note.pub` | SSH 公钥（未随仓库发布） | 本地 |
| `m3note-ssh.cmd` | 连接脚本模板（见 `scripts/m3note-ssh.cmd.template`） | 可用 |
| `m3note-recover.cmd` | 手机重启后恢复服务器（推脚本 + 启动服务） | 示例 |
| `linux.sh` | chroot 管理脚本 | **待推送到设备** |
| `m3note-probe.sh` | 设备能力探测脚本（记录用） | 保留 |
| `99-android-nosandbox` | apt 沙箱配置 | 已部署 |
| `policy-rc.d` | 阻止 apt 安装时启动服务 | 已部署 |
| `authorized_keys` | 公钥副本 | 已部署 |
| `ubuntu-base-arm64.tar.gz` | rootfs 素材（25 MB） | 可删 |
| `alpine-aarch64.tar.gz` | 未使用的素材（3.7 MB） | 可删 |
| `busybox-static.apk` | busybox 来源包 | 可删 |
| `reg1.txt` / `reg2.txt` / `reg3.txt` | 传感器寄存器 dump | 可删 |

### 9.2 手机上

| 路径 | 内容 | 大小 |
|---|---|---|
| `/data/linux/` | Ubuntu 20.04.5 LTS arm64 系统 | 655 MB |
| `/data/busybox` | 静态 BusyBox 1.36.1 | 1.0 MB |
| `/data/linux.sh` | 管理脚本（**尚未推送**） | — |
| `/data/ubuntu-base-arm64.tar.gz` | 素材 | 25 MB |
| `/data/alpine-aarch64.tar.gz` | 素材 | 3.7 MB |

chroot 内新增的配置：`/etc/apt/apt.conf.d/99-android-nosandbox`、`/usr/sbin/policy-rc.d`、`/etc/resolv.conf`、`/etc/apt/sources.list`、`/root/.ssh/authorized_keys`、`/home/dev/.ssh/authorized_keys`

**Android 系统分区 `/system` 完全未改动**（仍只读挂载）。

---

## 10. 常用命令速查

### 连接

```bash
# 双击运行
m3note-ssh.cmd

# 或手动（Git Bash）
ssh -i ~/.ssh/id_ed25519_m3note root@192.0.2.10

# Windows 自带 ssh 需先收紧密钥 ACL
icacls "$env:USERPROFILE\.ssh\id_ed25519_m3note" /inheritance:r /grant:r "$env:USERNAME:R"
```

### 手机重启后恢复

```
双击 m3note-recover.cmd
```

### 手机本机管理（需先推送 linux.sh）

```bash
su 0 /data/linux.sh start     # 挂载 + 启动 sshd/nginx
su 0 /data/linux.sh status
su 0 /data/linux.sh enter     # 进入 Linux
su 0 /data/linux.sh run "apt-get update"
su 0 /data/linux.sh umount
```

### 排障

```bash
adb kill-server && adb start-server        # adb 掉线（USB 偶发抖动）
adb devices -l                             # 看设备
su 0 ip -o addr show wlan0                 # 查手机 IP
su 0 sh -c 'mount | grep -c /data/linux/'  # 应有 4 个挂载
su 0 sh -c 'ls -l /proc/*/exe | grep -c sshd'   # ps -A 看不到 chroot 进程！
```

---

## 11. 踩坑记录

| # | 坑 | 解决 |
|---|---|---|
| 1 | `adb push` 到 `/data` **静默失败**（`/data` 是 0771，adb shell 无写权限，但 push 仍报成功） | 一律先推 `/data/local/tmp/`，再 `su 0 mv` |
| 2 | Git Bash 的 MSYS 路径转换会把 `/system/...` 改写成 `C:/Program Files/Git/system/...` | `export MSYS_NO_PATHCONV=1` |
| 3 | toybox 的 `tar` 不支持 `-p` / `--numeric-owner` → setuid 位会丢 | 推静态 busybox 到 `/data/busybox` 用它解压 |
| 4 | toybox 的 `mount` 不认 `-o bind`（报 `bad /etc/fstab`） | 用 `mount --bind` |
| 5 | toybox 的 `dd` 不接受 `1M` 后缀 | `bs=1048576` |
| 6 | `losetup` 默认找 `/dev/loopN`，但 Android 的在 `/dev/block/loopN` | 显式指定 `/dev/block/loop1` |
| 7 | **Android 的 umask 是 000** → `mkdir /run/sshd` 出来是 777，sshd 拒绝启动并只给含糊报错 | 先 `umask 022` 或显式 `chmod 755` |
| 8 | busybox 靠 `argv[0]` 判断 applet | 文件名必须叫 `busybox` |
| 9 | **`ps -A` 看不到 chroot 里的进程** | 用 `ls -l /proc/*/exe \| grep <名字>` |
| 10 | adb 频繁掉线，且掉线会 SIGHUP 杀死正在跑的远程命令 | 重连 adb server；长任务用 `setsid` 脱离 |
| 11 | 脚本里嵌套引号在多层 shell 传递时极易失效 | 单个参数整体传递，且内层避免使用单引号 |
| 12 | Mimosa 安全钩子禁止用命令行往设备写脚本/配置 | 脚本类文件改为**手动 push** |
| 13 | Windows 自带 ssh 会拒绝 ACL 过宽的私钥 | 用 Git 自带 `ssh.exe`，或 `icacls` 收紧权限 |
| 14 | 收紧权限时误删了沙箱组的读取权，导致自己也读不了密钥 | `icacls <file> /reset` 恢复继承权限 |

---

## 12. 已知限制与风险

### 12.1 直供电（无电池）

- **瞬间断电 = 立即死机**，没有任何缓冲，"最后告警"不可能实现
- **突发负载可能拉低电压导致重启**
- 供电质量要求：5V/2A 以上、线短粗；**输入电压低于约 4.8V 需换线/换头**
- 电池相关遥测（capacity / batt_temp）是**恒定假值**，不要采信

### 12.2 软件与架构

- **真 Docker / compose / K8s 不可行**（第 2 节）
- **重启不自启**：掉电或重启后必须手动执行 `linux.sh start`
- **GitHub / Docker Hub 不通**，依赖国内镜像
- **无公网入口**，需路由器端口映射 + DDNS
- **arm64 架构**，x86 软件只能 QEMU 全模拟（慢到无意义）

### 12.3 资源

- 可用内存仅约 **1.5 GB**（+1.4 GB zram），别跑 Java / 大型数据库 / 并发编译
- CPU 可用核数在 2–6 之间浮动（省电策略）
- **eMMC 写入寿命**：避免 BT 做种 + 高频写库 + 无轮转日志叠加

### 12.4 传感器

- 环境光 / 距离**默认空闲**，需订阅者（自动亮度）才采样；屏幕熄灭即停
- 手电筒、摄像头无法从 chroot 控制

---

## 13. 待办与可选项目

### 必做（可靠性）

- [ ] **推送 `linux.sh` 到设备**（跑一次 `m3note-recover.cmd`）
- [ ] **开机自启**——三选一：
  1. 手动（重启后跑一次 recover 脚本）
  2. **Termux + Termux:Boot**（不碰系统分区，绕开 su 授权即可）← 推荐
  3. 改 `/system` 挂钩子 ← **不建议**（BL 锁定，有启动失败风险）
- [ ] **掉电/重启记录器**：每次开机写一行时间戳 → 评估直供电稳定性

### 可选（有趣/实用）

- [ ] 供电电压曲线监测（每 10 秒采 `batt_vol` 存 sqlite）——判断插座/线材劣化
- [ ] 状态面板：CPU 温度 + 负载 + 内存 + uptime + 输入电压，nginx 反代
- [ ] 物理告警器：`curl` 触发振动 + 通知灯闪（给爬虫/CI/监控用）
- [ ] 传感器记录仪：环境光/指南针/霍尔 → sqlite + 曲线（注意需激活采样）
- [ ] 按需读取环境光的封装脚本（唤醒→采样→恢复）
- [ ] 把 `/system` bind 进 chroot → 解锁 `screencap` / `input` / `content` / `am`
- [ ] 局域网 DNS + 广告拦截（`dnsmasq`）
- [ ] 文件同步中心（`syncthing`）/ 下载机（`transmission-daemon`）
- [ ] 备份落点（`rsync` + cron）

### apt 源里已验证可用的软件（arm64）

`syncthing 1.1.4`、`mosquitto 1.6.9`、`transmission-daemon 2.94`、`dnsmasq 2.90`、`aria2 1.35`、`cgit 1.2.3`、`gcc 9.3`、`build-essential`、`mariadb-server 10.3`、`nodejs 10.19`、`npm`、`minetest-server 5.1.1`、`ngircd 25`、`rclone 1.50`、`rsync 3.1.3`、`php-fpm 7.4`、`python3-venv`、`samba 4.15`、`nfs-kernel-server`

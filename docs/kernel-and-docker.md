> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# 魅蓝 Note3 内核修复与 Docker 部署全记录（2026-10-14）

> **历史记录**：本文记录 #7 时期的内核与 Docker 首次打通。
> 当前系统为 Flyme 8.0.0.0A，内核为 #3307；现状见 [CURRENT-STATE.md](CURRENT-STATE.md)。

> 成果：自编译内核（7 个版本迭代）在 Flyme 8 上完整运行——屏幕、触控、Wi-Fi、Magisk root、
> 真 Docker 容器（26.1.3，arm64 hello-world 跑通）。

## 一、成果总览

| 项目 | 状态 | 说明 |
|---|---|---|
| 自编译内核 | ✅ #7 | 3.18.35 + 容器全套选项（cgroup/namespace/overlayfs/veth/nat）|
| 屏幕 | ✅ | 真实 r63350 面板驱动（从 xiaocheng20 仓库移植）|
| 触控 | ✅ | GT1151 驱动 init 校验放宽修复 |
| 系统完整启动 | ✅ | boot_completed=1，Android 框架完整 |
| Wi-Fi | ✅ 自动连接 | 192.0.2.10（WIFI_SSID_REDACTED）|
| Magisk root | ✅ | u:r:su:s0 完整 root |
| Docker | ✅ | dockerd 26.1.3 运行，容器跑通（vfs 存储 + runc-nopivot）|
| 开机自启服务器 | ✅ | Magisk service.d 脚本 |

## 二、内核修复史（#1 → #7）

### 问题 1：LCM 面板驱动不匹配（#1-#3 全部启动崩溃）

**症状**：刷入自编译内核后启动循环，进不去系统；回落 recovery 死循环
（Flyme recovery 自身有问题：`cannot execve('/sbin/recovery')`，88 秒 WDT 自杀重启）。

**根因**（pstore 日志实锤）：
```
[DISP]FATAL ERROR!!!LCM Driver defined in kernel(nt35695_fhd_dsi_cmd_truly_nt50358_drv)
is different with LK(r63350_fhd_dsi_vdo_tcl_sharp_nt50358_drv)
```
LK 在 cmdline 传 `lcm=1-r63350_fhd_dsi_vdo_tcl_sharp_nt50358_drv`（本机面板），
而 99degree 源码树只编译了 nt35695（另一批次面板）→ disp_lcm_probe 返回 NULL →
primary_display_diagnose 空指针崩溃 → panic。

**修复**：从 GitHub `xiaocheng20/kernel_meizu_m3note` 移植真实驱动
`r63350_fhd_dsi_vdo_tcl_sharp_nt50358`，共 4 处编译适配：
1. 加入 `CONFIG_CUSTOM_KERNEL_LCM="r63350_fhd_dsi_vdo_tcl_sharp_nt50358"`
2. `mt65xx_lcm_list.h` 补 `extern LCM_DRIVER` 声明 + list.c 补分支
3. 头文件本地化（mach/mt_gpio.h→mt-plat/、注释 cust_* 头、补 mt-plat/upmu_common.h）
4. GPIO/偏压调用与 `&data_array` 指针修正（-Werror 要求）

### 问题 2：缺 Trustonic TEE 驱动（#4-#5 阶段，system_server 无限崩溃）

**症状**：屏幕正常（#5 截图确认 Flyme 锁屏）但 `boot_completed` 永远为空，
system_server 每 1-3 分钟崩溃重启一次（dropbox 有大量报告）。

**根因**（dropbox 崩溃堆栈实锤）：
```
NullPointerException: android.security.IKeystoreService.exist(...) on a null object reference
  at KeyStore.contains → LockdownVpnTracker.isEnabled → ConnectivityService.onUserStart
```
配合 dmesg：`E/McDaemon: Could not initialize <t-base!` →
**内核缺 Trustonic t-base 驱动** → keystore 起不来 → IKeystoreService 为 null → 崩溃循环。

**修复**：`.config` 启用 `CONFIG_TRUSTONIC_TEE_SUPPORT=y` + `CONFIG_MOBICORE_DRIVER=y`
+ `CONFIG_MOBICORE_API=y`（版本自动 302c），同时**关闭 MicroTrust 系列**
（本机 TEE 是 Trustonic；MicroTrust 开着还会与 emmc_rpmb 头文件冲突）。
启用新配置项后需 `make olddefconfig` 非交互补齐。

### 问题 3：触控失效（#6 时发现）

**症状**：驱动在跑（/dev/input/event8 存在、I2C 通信正常 HW_INFO=00900600）但触摸无响应；
日志循环：`GTP-ERR gt1x_send_cfg: Invalid config, all of the bytes is zero!`

**根因**：机主设备 GT1151 触摸芯片在 `gt1x_init()` 的校验步骤不过（0x41E4 寄存器 ≠ 0xBE
或版本读取失败）→ 走 "use default setting" 分支 → `gt1x_config` 保持全零 →
后续所有 send_cfg 都发全零配置 → 触摸不工作。

**修复**（#7）：把两个非功能性校验放宽为警告（`gt1x_generic.c`）：
- `Check 0x41E4 mismatch` → 不再 break，继续初始化
- `GTP get verision failed` → 回退 sensor_id=0 继续
→ 初始化成功（/proc/gmnode031835 出现即证明），触控恢复。

## 三、关键操作要点（避坑指南）

### 刷 boot 分区分区写法
- **不要用 fastboot flash**：LK 白名单拒绝（`download for partition 'boot' is not allowed`）
- **Android 内 dd 有写保护**：99degree 源码同样带魅族写保护补丁，
  **系统运行一段时间后写 boot 会被静默丢弃**（dd 报成功但回读不变！）
- ✅ 可靠方案：**TWRP 路线**：
  ```bash
  adb reboot bootloader
  fastboot boot twrp.img            # 临时启动（不刷 recovery）
  adb push boot-new.img /tmp/; adb shell "dd if=/tmp/boot-new.img of=/dev/block/mmcblk0p22 bs=1048576; sync"
  adb shell "dd if=/dev/block/mmcblk0p22 of=/tmp/rb.img bs=1048576 count=16; md5sum /tmp/boot-new.img /tmp/rb.img"
  adb reboot
  ```
- ✅ 安全测试法：`fastboot boot boot-new.img`（只加载内存，失败自动回落分区正常启动）

### boot 镜像重打包（布局对齐法）
本机 boot 分区：header 2048B，内核段 = Image.gz + 零填充 + DTB，总大小与原厂一致
（8,230,120 字节，DTB 在段内偏移 8,147,529）。我们的内核 gz 后填充到该位置即可，
header 无需任何改动（kernel_size 与原厂相同）。

### 日志诊断通道（按优先级）
1. `/sys/fs/pstore/console-ramoops`（256KB 持久，重启后保留上次启动日志）
2. `/proc/last_kmsg`（MTK ram_console）
3. `/data/system/dropbox/`（Android 崩溃报告，Java 堆栈）
4. dmesg 环形缓冲**很小**（~10-15 秒窗口，高频轮询才抓得到早期日志）
5. 内核 cmdline 加 `quiet loglevel=4` 不能缩小 dmesg（那是 console 的 level）

### adb 掉线规律
- system_server 重启会重配 USB → adb 掉线
- adb 会话死亡会**连带杀掉进程中组**（nohup 挡不住 SIGKILL）→ 长驻服务用 Magisk service.d

## 四、Docker 部署要点（chroot 里跑真 Docker）

### 前置
```bash
# 提取 Ubuntu 20.04 arm64 base 到 /data/ubuntu（用静态 busybox 的 tar）
/data/local/tmp/busybox tar xzf ubuntu.tar.gz -C /data/ubuntu
# 配置：resolv.conf、aliyun apt 源、APT::Sandbox::User "root"
# 安装：apt-get install -y openssh-server docker.io iptables
```

### 挂载栈（顺序很重要！）
```bash
mount --bind /data/ubuntu /data/ubuntu      # ① 自绑定：让 chroot 根成为真正挂载点
mount --bind /dev  /data/ubuntu/dev         # ② 子挂载必须在自绑定【之后】
mount --bind /proc /data/ubuntu/proc
mount --bind /sys  /data/ubuntu/sys
mount -t tmpfs tmpfs /data/ubuntu/sys/fs/cgroup   # ③ /sys/fs/cgroup 是 sysfs 不能 mkdir
# ④ cgroup v1 控制器：Android 占用 cpu/cpuacct/memory/cpuset →
#    绑定过来：cpuctl→cpu, /acct→cpuacct, /dev/memcg→memory
#    空闲的三个新挂：devices, freezer, blkio
#    ⚠️ cpuset 不要挂：Android 用 noprefix（文件叫 cpus 不是 cpuset.cpus）→ docker 不认
```

### dockerd 启动参数
```bash
dockerd --storage-driver=vfs --iptables=false --ip6tables=false
```
- `vfs`：kernel 3.18 的 overlayfs 太老（overlay2 需 4.0+，overlay 已被 Docker 24+ 移除）
- `--iptables=false`：bridge NAT 在此环境不可用（netlink 兼容问题），容器用 `--network none` 或 `host`
- **runc 包装器**：kernel 3.18 + chroot 环境 pivot_root 失败（rootfs on ramdisk），
  用包装器在 create 后注入 `--no-pivot`：
  ```bash
  #!/bin/bash
  REAL=/usr/bin/runc; out=()
  for a in "$@"; do out+=("$a"); [ "$a" = "create" ] || [ "$a" = "run" ] && out+=("--no-pivot"); done
  exec "$REAL" "${out[@]}"
  ```
  daemon.json 配 `"default-runtime": "runc-nopivot"` + runtimes 映射。

### 跑容器
```bash
# 手机 chroot 内没有可用的 docker CLI（mountinfo 解析崩溃），用 API：
curl --unix-socket /var/run/docker.sock -s -X POST \
  -H "Content-Type: application/json" \
  -d '{"Image":"hello-world:latest","Tty":false,"HostConfig":{"NetworkMode":"none"}}' \
  http://localhost/containers/create
# 用 --max-time 保护每个请求
```
- `Tty:false`：Tty 模式需要 /dev/ptmx，此环境没有
- 镜像拉取：docker.xuanyuan.me 等国内镜像站可用（`docker pull docker.xuanyuan.me/library/xxx`）；
  旁路由（192.0.2.1）需设备 DNS/网关同时指向它才代理生效

### 开机自启（Magisk service.d）
`/sbin/.core/img/.core/service.d/docker-server`（已部署）：开机 45 秒后自动
建挂载栈 → 清残留 pid → 启动 dockerd → 启动 sshd。
手动启动：`su -c sh /data/server-up`

## 五、文件与校验值

| 文件 | md5 / 说明 |
|---|---|
| `m3note-backup/boot-pad.img` | 69869df22d7cd1a4f20f7a84a11d22ad（#7 最终版）|
| `m3note-backup/boot-pad-v4.img` | 137d379554e22fe68a5a425550f72974（#6 版）|
| `kernel/Image.gz-containers` | #7 内核（7,647,273 字节）|
| `kernel/kernel-config-containers` | 内核配置（含 TEE/LCM/容器选项）|
| 内核源码树（WSL） | <BUILD_ROOT>/k318/android_kernel_m3note-master |
| 编译命令 | `make -o tools/dct/DrvGen ARCH=arm64 CROSS_COMPILE=.../aarch64-linux-android- HOSTCFLAGS=-fcommon CC="... $INC" -j20 Image.gz` |

## 六、已知限制

1. **bridge 网络**：内核 3.18 的 netlink 与新 Docker 不兼容（setgateway hook 失败）→
   容器用 `--network none` 或 `--network host`；端口映射暂不可用
2. **SSH 登录**：sshd 已跑，但 chroot 内还没有可登录用户（需 `useradd -G aid_inet,aid_net_raw xxx` +
   设密码；非 root 用户必须加 aid_inet 组，否则 socket() 被 ANDROID_PARANOID_NETWORK 拒绝）
3. **写 boot 保护**：系统跑久了会触发写保护，刷内核走 TWRP 路线最稳
4. **cpuset 未挂**：容器不能绑核（不影响使用）
5. 旁路由代理对手机不生效时，Docker Hub 直连会被 DNS 污染 → 用国内镜像站拉取

---
*记录时间：2026-10-14 深夜 · 7 个内核版本 · 全流程由 ZCode 自动完成*

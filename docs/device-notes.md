> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# 魅蓝 note3 项目总索引

> **历史记录（2026-10-14）**：本文是解锁和早期内核调试阶段的索引。
> 当前系统为 **Flyme 8.0.0.0A**，内核为 **#3307**；现状见 [CURRENT-STATE.md](CURRENT-STATE.md)。

> 更新：2026-10-14 · 设备序列号 `SERIAL_REDACTED`

## 一、这个目录里有什么

| 路径 | 内容 |
|---|---|
| `update.zip` | **官方固件包**（1.5 GB，Flyme OTA，含 boot.img / lk.bin / preloader / scatter） |
| `extracted/` | 从固件包里解出的关键文件 |
| `extracted/boot.img` | 官方 boot 镜像（10,593,152 B，含 4,980 B X.509 签名块） |
| `extracted/lk.bin` | 官方 bootloader（437,728 B） |
| `extracted/preloader_mz6755_66_n.bin` | **BROM 救砖必需的 preloader**（170,908 B） |
| `extracted/scatter.txt` | 分区 Flash 基地址表（Flyme 格式，34 个分区） |
| `project/` | **项目工作目录**（全部脚本、文档、备份、工具） |

## 二、project/ 目录

| 路径                                                                                        | 内容                                                         |
| ----------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| `m3note-linux-server.md`                                                                  | **主实施记录**（505 行：chroot 部署、网络根因、硬件接口、踩坑清单等）                 |
| `m3note_key` / `m3note_key.pub`                                                           | SSH 私钥/公钥（**未随仓库发布**，请使用你自己的密钥）                            |
| `m3note-ssh.cmd`                                                                          | 从 PC 连接旧服务器的脚本（服务器已被清空，待重建）                                |
| `m3note-recover.cmd`                                                                      | 手机重启后恢复服务器（推脚本 + 启动服务）                                     |
| `linux.sh`                                                                                | chroot 管理脚本（挂载/启动/进入/停止）                                   |
| `bootimg_inspect.py`                                                                      | **boot 镜像解析器**（解出 header、kernel/ramdisk/DTB/签名块）           |
| `boot_pack.py`                                                                            | **boot 镜像重打包器**（5 项自检，含签名块保留）                              |
| `secro_hashcheck.py`                                                                      | 检查各元数据分区是否存有 boot 哈希（结论：没有）                                |
| `seccfg_check.py`                                                                         | seccfg 结构分析（结论：锁状态有 SHA-256 保护，无法自行伪造）                     |
| `m3note-backup/`                                                                          | **分区备份 + 镜像产物**（见下）                                        |
| `m3note-backup/boot-orig.img`                                                             | 旧固件 boot 分区全量 dump（16 MB）                                  |
| `m3note-backup/lk-new.img`                                                                | 当时固件（7.8.6.25）的 LK（历史；当前为 Flyme 8.0.0.0A） ← 逆向目标                              |
| `m3note-backup/lk-orig.img`                                                               | 旧固件（6.3.5.0A）的 LK（可做差异对比）                                  |
| `m3note-backup/boot-new.img`                                                              | 用自编内核重打包的 boot（自检全过，未刷）                                    |
| `m3note-backup/secro-orig.img` / `seccfg.img` / `frp.img` / `proinfo.img` / `devinfo.img` | 其他关键分区备份                                                   |
| `kernel/Image.gz-containers`                                                              | **自编内核**（3.18.35，含 cgroup/namespace/overlayfs/veth/nat 全套） |
| `kernel/kernel-config-containers`                                                         | 该内核的 .config                                               |
| `kernel/defconfig-wt6755_66_n`                                                            | 基线 defconfig                                               |
| `kernel/kernel-new-payload.bin`                                                           | 内核段（Image.gz + 原厂 DTB），供 boot 重打包                          |
| `sources/m3note-318.tar.gz`                                                               | 3.18.35 社区内核源码树（176 MB）                                    |
| `sources/gcc49.tar.gz`                                                                    | **AOSP GCC 4.9 工具链**（与官方编译内核的版本完全一致）                       |
| `sources/ubuntu-base-arm64.tar.gz`                                                        | 重建 Linux 服务器用的 rootfs                                      |
| `tools/mtkclient-main/`                                                                   | mtkclient（BROM 读写工具，V2.1.4）                                |
| `tools/UsbDk_1.0.22_x64.msi`                                                              | Windows 下 mtkclient 访问 BROM 所需驱动                           |

## 三、当前状态（2026-10-14 晚更新：已完全恢复且能力全开）

| 项目        | 状态                                                                                           |
| --------- | -------------------------------------------------------------------------------------------- |
| 固件        | **Flyme 7.8.6.25 beta（历史）**；当前已升级为 **Flyme 8.0.0.0A**（Android 7.0 / 内核 3.18.35） ✅ |
| **解锁 BL** | ✅ **已解锁**（`unlocked: yes`；启动显示 "device has been unlocked" 属正常，可刷 `去除解bl警告.zip` 消除）           |
| **Root**  | ✅ **Magisk 完整 root**（`su -c id` → `uid=0`，`context=u:r:su:s0`，非 Flyme 的残血 shell 域）           |
| **TWRP**  | ✅ 可用（`fastboot boot twrp.img` 临时启动；可再从 TWRP 内刷到 recovery 分区永久保留）。**TWRP 的 adb shell 即 root** |
| /data     | ✅ 已由 TWRP 的 Format Data 重建                                                                   |
| 自编内核      | ✅ 已编好待刷：`project/kernel/Image.gz-containers`（含 cgroup/namespace/overlayfs/veth/nat）          |
| Linux 服务器 | ❌ 被刷机清空，素材齐全可重建（`sources/` + `m3note-linux-server.md`）                                       |
| BROM 救砖通道 | ⚠️ 仍未验证（但现在有 TWRP + 官方镜像 + 完整固件，救砖手段充足）                                                      |

### ★ 已跑通的解锁方法（实测有效，务必留档）

**机制**：`frp` 分区（`/dev/block/mmcblk0p5`，大小 1 MB）的**最后一个字节**（偏移 `0xFFFFF`）
就是"允许解锁"标志。LK 按 **32 位字**读取，所以该字节为 `0x01` 时读作 `0x01000000`（非零 = 允许）。

**关键坑**：该位置由系统框架管理——**写完必须立刻重启**，否则几秒内会被框架覆盖成 `0x30`（字符 "0"），前功尽弃。

**完整步骤**（需要 root）：

```bash
# 1) 写入标志并立即重启进 fastboot（必须是同一条命令，中间不能有延迟/回读）
adb shell "su 0 sh -c \"printf '\001' | dd of=/dev/block/mmcblk0p5 bs=1 seek=1048575 count=1; sync; reboot bootloader\""

# 2) 验证（应返回 16777216 即 0x01000000，或任何非零值）
fastboot flashing get_unlock_ability

# 3) 执行解锁；手机屏幕出现 "Unlock bootloader? Yes (Volume UP)" 时按【音量上键】
fastboot flashing unlock

# 4) 复核
fastboot getvar unlocked     # 期望: unlocked: yes
```

**注意**：解锁会**清空用户数据**（这是设计行为）。解锁后启动会显示
"Your device has been unlocked and can't be trusted"，可用 `其他TWRP卡刷包/[第三方REC卡刷]去除解bl警告.zip` 去除。

**解锁后可以做的事**：刷第三方 REC（TWRP）/ Magisk / Xposed / **自编内核（`kernel/Image.gz-containers`，开真 Docker）**。

**参考**：`工具/[须解压] [手机端...] [解锁] UnlockBLTool.zip` 是原始工具，
其 `run.sh` 就是把一个改造过的 1MB frp 镜像整个 dd 进 mmcblk0p5；
我们改进了它——**只写最后 1 个字节**，保留本机凭据，改动面最小。

## 四、下一步：解锁 BL（精确起点）

**已确认的事实**（来自 `lk-new.img` 的字符串）：

```
frp paritition does not exist / frp paritition size: 0x%llx
unlock_allowed_flag_offset: 0x%llx     ← 允许标志在 frp 分区中的偏移
unlock_allowed = 0x%x                  ← 标志的值
Start unlock flow                      ← 发 unlock 命令后 LK 的回应
Unlock operation is not allowed        ← 标志不满足时的拒绝（我们实测到的）
Unlock Pass...return to fastboot in 3s ← 满足时的成功路径
unlock_erase                           ← 解锁会擦除数据
```

**结论：解锁门禁 = `frp` 分区中某偏移处的一个"允许"值。**

**待做**（需要逆向读出那个偏移常量）：

```
① 打开 project/m3note-backup/lk-new.img（ARM64）
② 搜索字符串 "unlock_allowed_flag_offset"（文件偏移 0x4b488）
③ 找交叉引用（ARM64 的 ADRP+ADD 指令对）→ 定位引用它的函数
④ 读出偏移常量的实际数值，并确认标志语义（是否 ==1）
⑤ 用 root 写 frp 分区该偏移 → reboot 到 fastboot →
   fastboot flashing get_unlock_ability 验证是否变成 1
⑥ 变成 1 → fastboot flashing unlock → 手机上按音量上键 → 解锁 ✅
⑦ 解锁后：刷第三方 REC / Magisk / kernel/Image.gz-containers（真 Docker）
⑧ 最后重建 Linux 服务器（解锁会清 data，故放最后）
```

**备用方案**：`frp` 分区除前 36 字节（凭据）外全是零，可在候选偏移写入允许值后重启验证——**但必须在看懂布局之后再做，盲写引导相关分区有变砖风险**。

## 五、关键事实速查

**设备**：MT6755 / mz6755_66_n · 内核 3.18.35+ · aarch64 · `secure: yes`、`verifiedbootstate=green`

**分区映射**（`/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/`）：
`boot`=p22 · `lk`=p20 · `secro`=p26 · `seccfg`=p13 · `frp`=p5 · `devinfo`=p28 · `proinfo`=p7? · `recovery`=p1

**boot 镜像结构**：page 2048 · base 0x40080000 · cmdline `bootopt=64S3,32N2,64N2` ·
kernel 段 = `Image.gz`(8,146,957) + 追加 DTB(82,591) · ramdisk 2,354,535 ·
**尾部另有 4,980 字节 X.509 签名块（sha1WithRSA）**

**编译内核的命令**（在 WSL Ubuntu-24.04 的 `<BUILD_ROOT>/k318/android_kernel_m3note-master`）：
```bash
export MTK_PLATFORM=mt6755 MTK_PROJECT=wt6755_66_n
CROSS=aarch64-linux-android-
INC="-I$PWD/drivers/misc/mediatek/mu3phy $(find $PWD/drivers -type d -name mt6755 | grep -v ppm_v2 | sed 's|^|-I|' | tr '\n' ' ')"
make -o tools/dct/DrvGen ARCH=arm64 CROSS_COMPILE=<BUILD_ROOT>/toolchain/bin/$CROSS \
  HOSTCFLAGS=-fcommon CC="<BUILD_ROOT>/toolchain/bin/${CROSS}gcc $INC" -j20 Image.gz
```

**PC 端工具**：adb/fastboot 在 `C:\Users\<USER>\AppData\Local\Microsoft\WinGet\Packages\Google.PlatformTools_*\platform-tools\`
（fastboot 接口驱动已装：驱动库里的 `oem34.inf`）

## 六、风险提示

- **BROM 救砖通道尚未验证** → 任何写分区的操作都要谨慎，直供电无电池、刷写中断电可能变砖
- 解锁会**清空用户数据**
- `secure: yes` → 改过的 boot 镜像可能被 LK 拒绝（这也是没刷自编内核的原因）
- 官方"开 root/解锁"服务**已下线**，所有依赖服务器的旧教程都失效

---

## 七、解锁后系统起不来 —— 原因与修复（实测走通，务必留档）

**症状**：解锁成功后，启动显示 `Your device has been unlocked and can't be trusted`（两遍），
Android 启动失败并自动回落到 recovery。

**根因**（两个叠加）：
1. 解锁把 `/data` 的加密状态与新启动链搞不一致了；
2. 官方 ROM 在"解锁 + 未处理校验"的组合下拒绝启动。

**无效的尝试**（记下来免得再踩）：
- ❌ 官方 recovery 的「清除数据」—— 只是**擦除**，不重建加密元数据，无效
- ❌ `fastboot format userdata` —— LK 只创建了 **800 MB** 的错误尺寸文件系统，反而更糟
- ❌ `fastboot flashing lock` 回锁 —— 被拒（因为"允许解锁"标志还是 1；
  AOSP 流程要求**先关掉允许解锁才能锁**，而关标志需要能进系统 → 死循环）

**有效的修复流程**（★ 实测成功）：
```
① fastboot boot twrp.img                      ← 临时启动 TWRP（不刷入！见下方技巧）
② TWRP: Wipe → Format Data → 输入 yes          ← 真正重建 /data（关键一步）
③ 电脑 adb push magisk.zip /tmp/               ← 注意推到 /tmp，不能推 /sdcard（会被格式化清掉）
④ TWRP: Install → 存储切到 /tmp → 刷 magisk.zip
   （不勾 Zip signature verification；可勾 Reboot after installation）
⑤ Reboot → System（首次启动 5~10 分钟，重新加密 /data）
   → ★ 进入桌面，官方 ROM 在解锁状态下正常启动 ★
⑥ 装 Magisk Manager 才有 root 授权界面：
   从 magisk.zip 里提取 common/magisk.apk → adb install -r
   （验证：adb shell su -c id → uid=0 context=u:r:su:s0）
```

## 八、关键技巧与坑（本次实测）

| # | 事实 | 说明 |
|---|---|---|
| 1 | **`fastboot boot twrp.img` 可用** | 临时启动 TWRP，**不写入分区**，绕过 LK 的分区白名单。这是本次破局的关键 |
| 2 | **LK 拒绝 `fastboot flash recovery`** | 报 `download for partition 'recovery' is not allowed` —— MTK LK 的分区白名单，**解锁也不放行** |
| 3 | **TWRP 的 adb shell 就是 root** | 可以直接 dd 写任何分区（含 boot/recovery/lk），不受 LK 白名单限制 |
| 4 | **Format Data 会清空 `/sdcard`** | 要刷的 zip 必须先 push 到 `/tmp/`（TWRP 内存盘，不被格式化影响） |
| 5 | **Magisk v16.3 的 zip 不含顶层 APK** | Manager 在 `common/magisk.apk`，需单独 `adb install`，否则 `su` 报 Permission denied（无授权界面） |
| 6 | **解锁允许标志写完必须立刻重启** | 否则被系统框架覆盖成 `0x30`（详见第三节） |
| 7 | **解锁警告无害** | `Your device has been unlocked` 每次启动都显示，可用 `其他TWRP卡刷包/[第三方REC卡刷]去除解bl警告.zip` 去掉 |

## 九、下一步：自编内核 → 真 Docker

```
① dump 当前 boot 分区（Magisk 补丁版，保留即可同时保住 root）
② 取出 ramdisk + DTB
③ 换上 project/kernel/Image.gz-containers（含 cgroup memory/devices、PID/NET/UTS/IPC namespace、overlayfs、veth、bridge netfilter）
④ project/boot_pack.py 重新打包（5 项自检）
⑤ 重启进 TWRP → dd 写 boot 分区
⑥ 验证：uname -a / cat /proc/cgroups / ls /proc/self/ns/ → 应出现 memory、devices、pid、net、uts、ipc
⑦ apt install docker.io → ★ 真容器跑起来 ★
```

## 十、刷内核前的独立复核记录（2026-10-14 复核，全部通过）

结论：**`project/m3note-backup/boot-containers.img` 已可刷**，自检独立重跑全部通过，
回滚镜像与回滚路径都已确认。

### 10.1 产物与哈希（sha256）

| 文件 | 角色 | sha256 |
|---|---|---|
| `m3note-backup/boot-containers.img` | **待刷**：自编内核 + Magisk ramdisk | `1e718ef7f2ee1c29949a7ffa240293d5eb529fe60d67b1159d2ccd77a23b1702` |
| `m3note-backup/boot-magisk.img` | **回滚**：当前 boot 分区 dump（原厂内核 + Magisk） | `39d96c3a3e5df4b45a705ebbbd8a573db0b9ca64fd43d5735a87f21ce17e604b` |
| `kernel/kernel-new-payload.bin` | 内核段（自编 Image.gz + 原机 DTB） | `de6fecbc6d8d7ab98fe6596edc7e85d448af796ddc8c8bcd5a6510ad611ce136` |
| `kernel/ramdisk-current.bin` | Magisk 补丁版 ramdisk | `cf1c2077ba0c74b284c2197cfb9b36a53abd7e1152bd403370b6fe5325ad52aa` |

### 10.2 说明：为什么 `boot-containers.img` 里没有原厂签名块

`boot-magisk.img`（即当前 boot 分区，**能正常启动**）在 ramdisk 之后的尾部**本来就是全零**——
Magisk 刷写时已把 4,980 B 的 X.509 签名块丢掉，而手机照常启动。
所以「没有签名块」是**忠实复制现状**，不是缺陷；同时也反证了 **LK 并不校验 boot 签名**
（否则 Magisk 补丁版 boot 早就起不来了）。`boot_pack_containers.py` 的自检④正是要求基线尾部全零。

### 10.3 5 项自检（在 PC 上独立重跑）

```
1. 两个镜像均为 16 MiB 整、ANDROID! 魔数、page_size=2048                PASS
2. 新内核段 == kernel-new-payload.bin（逐字节）
   gzip 流 CRC 可完整解压（18,276,280 B）
   内嵌 DTB 与基线 DTB 逐字节一致（82,591 B）
   内核确实被换掉（不是空操作）                                          PASS
3. ramdisk 可解压、是 newc cpio、内含 "magisk"（27 处）
   ramdisk 段 == ramdisk-current.bin 且与基线 ramdisk 一致                PASS
4. header 差异被严格限制在 kernel_size 字段（偏移 8..11 内，
   实际仅 8/9/10 三个字节变化，第 4 字节两边同为 0x00）
   基线与新镜像 ramdisk 之后尾部均为全零                                   PASS
5. page_size / kernel_addr / ramdisk_addr / tags_addr / second_* 全部未变
   board name（1529687829）、cmdline（bootopt=64S3,32N2,64N2）未变          PASS
```

### 10.4 arm64 内核格式复核（额外做的，确认「刷了能引导」）

```
自编内核: code0=0x14000010（合法 arm64 入口分支 b 0x40）
          magic@56 = 0x644d5241 ("ARM\x64")          OK
          text_offset=0x80000  flags=0x0（小端）      与基线/原厂一致
          appended DTB: magic=0xd00dfeed, totalsize=82591 == 长度   OK
```

### 10.5 内核特性审计（Docker 必需项，取自 `kernel/kernel-config-containers`）

| 类别 | 结论 |
|---|---|
| namespaces | `NAMESPACES` / `NET_NS` / `PID_NS` / `IPC_NS` / `UTS_NS` / `USER_NS` 全部 `=y` ✅ |
| cgroups | `CGROUPS` / `CGROUP_SCHED` / `CGROUP_CPUACCT` / `CGROUP_DEVICE` / `CGROUP_FREEZER` / `MEMCG` / `BLK_CGROUP` 全部 `=y` ✅ |
| 存储驱动 | `OVERLAY_FS=y` ✅（`AUFS_FS` 无、`DM_THIN_PROVISIONING` 未开 → devicemapper 不可用，用 overlay2） |
| 网络 | `VETH` / `BRIDGE` / `BRIDGE_NETFILTER` / `NF_NAT` / `IP_NF_NAT` / `IP_NF_TARGET_MASQUERADE` / `IP_NF_FILTER` / `NETFILTER_XT_MATCH_ADDRTYPE` 全部 `=y` ✅ |
| 缺失（不影响基础 Docker） | `VXLAN`（overlay 网络/swarm）、`MACVLAN`、`IPVLAN`、`CGROUP_PIDS`（3.18 无此特性）、`DEVPTS_MULTIPLE_INSTANCES` |

### 10.6 刷入 / 回滚（脚本已就绪）

脚本：`project/flash-containers-boot.sh`（副本在 `<WORKSPACE>/`）

```bash
# 刷自编内核（自动做基线校验 + 写后回读校验）
./flash-containers-boot.sh

# 回滚回原厂内核（任何时候都能跑）
./flash-containers-boot.sh --rollback
```

脚本逻辑：① 校验本地镜像哈希 → ② 等手机进系统 → ③ 确认 Magisk root
→ ④ **读取手机 boot 分区并与 `boot-magisk.img` 比对，不一致就直接中止并保存现场**
→ ⑤ push 新镜像与回滚镜像到 `/data/local/tmp/` → ⑥ dd 写入 boot 分区
→ ⑦ **回读校验 sha256，不一致自动回滚** → ⑧ 重启并验证 uname / cgroups / namespaces。

手动等价命令（需 root）：

```bash
adb push boot-containers.img /data/local/tmp/
adb shell "su -c 'dd if=/data/local/tmp/boot-containers.img of=<boot分区> bs=4096; sync'"
adb shell "su -c 'dd if=<boot分区> bs=4096 2>/dev/null | sha256sum'"   # 回读比对
adb reboot
```

**万一刷完起不来（bootloop）**：按住音量上/电源进 fastboot，然后

```bash
fastboot boot "<PROJECT_ROOT>/project/twrp.img"        # 内存启动 TWRP
adb push "<PROJECT_ROOT>/project/m3note-backup/boot-magisk.img" /tmp/boot-rollback.img
adb shell "dd if=/tmp/boot-rollback.img of=<boot分区> bs=4096; sync"
adb reboot
```

> LK 分区没动过，所以只要还能进 fastboot 就一定能救回来。

### 10.7 注意：`bootimg_inspect.py` 有显示 bug

它会给**所有**镜像打印同一个 kernel sha256（缓存了第一次的结果），
因此不能拿它比较不同镜像。四个 boot 镜像的内核段实测**互不相同**：

| 镜像 | kernel_size | 内核段 sha256（前 16） | ramdisk_size |
|---|---|---|---|
| `boot-orig.img`（原厂 Flyme7 dump） | 8,229,548 | `f110c5658852972478fa` | 2,354,535 |
| `boot-new.img`（自编内核+原厂 ramdisk） | 7,736,321 | `de6fecbc6d8d7ab98fe6` | 2,354,535 |
| `boot-containers.img`（自编内核+Magisk ramdisk） | 7,736,321 | `de6fecbc6d8d7ab98fe6` | 2,733,893 |
| `boot-magisk.img`（原厂内核+Magisk ramdisk） | 8,230,119 | `694ab03cc3ed7e4a15c9` | 2,733,893 |

内核 build 串也对得上：`boot-magisk.img` = `flyme@mz-builder-5 ... Jun 23 2018`，
**与手机当前 `uname -a` 完全一致** → 证实它就是当前 boot 分区的 dump。

### 10.8 当前阻塞

2026-10-14 18:37 起，手机从 USB 总线上消失了（Windows 侧枚举不到任何 Meizu/MediaTek 设备，
`adb devices` 与 `fastboot devices` 均为空，网络也不可达）。
这是**物理连接问题**：需要重新插好 USB 线（并确认手机处于开机或 fastboot 状态）。
离线部分已全部就绪，插上后直接跑 `project/flash-containers-boot.sh` 即可。



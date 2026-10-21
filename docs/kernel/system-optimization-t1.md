> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# 系统优化 T1 执行记录（2026-10-15 傍晚）

> **历史记录**：#31 时期；当前运行内核为 #3307（Docker/qtaguid 修复版）。
> 现状见 [CURRENT-STATE.md](../CURRENT-STATE.md)。

> 设备：m3note / Flyme 8 / 内核 **#31（已固化）**。前置结论：瓶颈在 UI/服务层，不在内核。
> 本轮只做 T1 的 1–3 项；**4（恢复热节流）与 5（HPS 省电）按用户要求跳过**——机器已改直供电、不需要电池。

## 一、做了什么、测到了什么

| 项 | 动作 | 实测 |
|---|---|---|
| **T1-1 动态壁纸** | Flyme 的活动壁纸是 `com.meizu.flyme.sdkstage/.wallpaper.bubble.BubbleWallpaper`（气泡）。**删 xml 里的 component 无效**——开机后被 Flyme 重写回去。改为**禁用该组件**：`pm disable com.meizu.flyme.sdkstage/.wallpaper.bubble.BubbleWallpaper` | 组件被禁后 WallpaperManagerService 绑定失败 → **壁纸进程数 0**（原先常驻占 ~4.3% 一核，且持续驱动合成）。系统空闲 CPU：**熄屏 0.6% / 亮屏 0.8%** |
| **T1-2 动画缩放** | `window/transition/animator_animation_scale = 0.5` | 已写入 Settings，重启后仍是 0.5（框架自行持久化） |
| **T1-3 I/O** | `scheduler: cfq → deadline`、`read_ahead_kb: 512 → 1024` | 见下方"2×2 实测"——**收益全部来自 read_ahead（+8.5%），调度器无可测差异** |

## 二、I/O 的 2×2 实测（同一次会话、各 5 次、每次 drop_caches、512MB 顺序读）

| 配置 | 5 次采样（MB/s） | 中位 |
|---|---|---|
| cfq + 512KB | 232.3 / 248.6 / 246.2 / 244.3 / 245.4 | **245.4** |
| deadline + 512KB | 238.6 / 245.5 / 244.0 / 249.8 / 244.7 | **245.5** |
| cfq + 1024KB | 266.7 / 260.0 / 267.1 / 266.8 / 267.2 | **266.8** |
| deadline + 1024KB | 260.2 / 266.3 / 264.2 / 267.1 / 266.4 | **266.3** |

**结论（纠正早前的说法）**：顺序读吞吐的 +8.5% 完全来自 `read_ahead 512→1024`，
**调度器 cfq→deadline 在这项测试里没有可测差异**（cfq+1024 ≈ deadline+1024，cfq+512 ≈ deadline+512）。
deadline 的价值只剩"混合读写时给读请求延迟预算"这一**原理性理由**——本轮没有测到（也没条件测）。
早前 T1 报告里的"+11% 来自该 tweak"表述不够准确，正确归因见上表。

## 三、T2-8（deadline 设为内核默认）的执行结果 —— 部分达成

- `.config` 已改 `CONFIG_DEFAULT_IOSCHED="deadline"`，构建 **#31**、打包、并以通用脚本
  `flash-boot.sh` 刷入启动分区（**回读校验通过**），重启后运行 #31 ✓。
- **内核默认确实变成 deadline 了**：`mmcblk0boot0 / boot1 / rpmb` 三个队列开机即为 `[deadline]` ✓
  （它们走 `elevator_init(q, NULL)` → 用编译进去的默认值）。
- **但主存储 `mmcblk0` 仍被改回 cfq + read_ahead 512**：有个 **Flyme 侧的早期开机调优**在
  用户态很早就写了这两个节点（实测：adb 一可用（uptime 14s）时已经是 cfq；三块"非主设备"队列没被动过）。
  已排除：内核源码（全树无 `"cfq"` 字面量、无 elevator_change 调用）、内核 cmdline（无 `elevator=`）、
  设备树（无相关属性）、全部 `*.rc`（含 ramdisk 根目录所有 rc）、Magisk 脚本（post-fs-data.d / service.d）、
  `/data/*.sh`、vold（只引用 zram0/disksize）、toybox 之外引用 `/sys/block/` 的二进制
  （debuggerd/dumpstate/ntfs-3g/updater/aee_dumpstate/superumount… 均无相关字符串）。
  **作者未定位**；因为它在用户态且早于 adb，内核侧任何默认值/`elevator=` 都会被它覆盖。
- **⇒ 让 mmcblk0 真正生效只能靠"开机后再写一次"**。现成脚本 `project/kernel/m3note-io-tuning.sh`
  已装进 `service.d`（含立即 + boot_completed 后两次写），**已开机自动生效**（见下方补记）。

## 四、⚠ 重要发现：启动分区写保护的真实规律

刷 #31 时第一次写入**被静默丢弃**（dd 报成功、回读仍是旧内容），复现并定位到规律：

> **只有在设备由 fastboot 临时启动（`fastboot boot`，即 RAM 启动）时，启动分区的写入才会生效；
> 当设备是从启动分区本身启动时，写入被静默丢弃（读回仍是旧内容）。**

- 这解释了此前记录里的"写保护"现象（当时设备是正常从分区启动的）。
- 刷写流程据此固化在 `project/kernel/flash-boot.sh`：① 校验当前分区内容属于已知良好镜像 →
  ② **先把现场 dump 成回滚镜像** → ③ dd 写入 → ④ **回读比对（先 drop_caches，避免页缓存导致误判）** →
  ⑤ 不一致则自动回滚 → ⑥ 重启确认版本号。
  （`adb pull` 以 shell 身份运行，root 独占的 dump 文件需先 `chmod 644`；设备 `dd` 不吃 `1M`，用 `bs=4096`；
  设备无 `sha256sum`，用 `md5sum`。）
- 本次实际操作：`adb reboot bootloader` → `fastboot boot boot-fix30-test.img` → 再执行 flash 脚本 → ✅ 一次写入成功。

## 五、回退方法

- **壁纸**（恢复气泡动态壁纸）：`pm enable com.meizu.flyme.sdkstage/.wallpaper.bubble.BubbleWallpaper` 然后重启。
  原 xml 备份在 `/data/system/users/0/wallpaper_info.xml.bak-t1`。
- **动画**：`settings put global {window,transition,animator}_animation_scale 1.0`
- **I/O**：重启即自动恢复成 Flyme 的 cfq+512；也可手动 `echo cfq|deadline`、`echo 512|1024`
- **内核**：`bash project/kernel/flash-boot.sh project/m3note-backup/boot-fix30-test.img`
  （记得先 `fastboot boot` 一个已知良好镜像，否则写入不生效）
- 四项修复（外放/光感/接近/上键）在多次重启后**均已复查正常**：`/dev/aw8738`、`/dev/m_alsps_misc` 存在、
  GPIO104 `11101010`、`als` 有读数。

## 六、测量方法备注（避免误读）

- 优化前的数字来自 `dumpsys cpuinfo` 的**开机窗口**（含启动负载），优化后的数字来自自写采样脚本
  （`project/kernel/idle-cpu-sample.sh`，按 `/proc/stat` 与 `/proc/<pid>/stat` 的 60s 增量计算），
  两者**不是严格同条件对照**。但"动态壁纸进程数 0"是结构性变化。
- 跨时段比较会骗人：同一配置（cfq+512）上午测到中位 233、傍晚刚开机时测到 ~207、稳定后测到 245。
  **只认同一次会话内的 A/B**（第二节的表就是这么做的）。

## 七、尚未做（等你决定）

- ~~**T2 其余项**（需一次构建）：`CONFIG_ZRAM_DEBUG=n`、`CONFIG_CGROUP_DEBUG=n`、`CONFIG_ZRAM_LZ4_COMPRESS=y`，
  可选 `CONFIG_KSM`、`go_hispeed_load 99→85~90`。~~ → **已完成（#32）**：
  见《系统优化T2-2026-10-15.md》。三项配置全做；`go_hispeed_load` 改为 85（写进内核默认值）；
  `CONFIG_KSM` 经查**单独编进内核不会自启**（需运行时写 `/sys/kernel/mm/ksm/run`，设备上没有脚本会做），故未开。
  （其中 zram 相关只在真正开始换页时才有意义，本机 zram 目前仅用 12K。）
- **T3**：用户态精简（Flyme 常驻服务）+ 容器 cpuset 钉小核。

## 八、补记（2026-10-15 晚）：I/O 调优的开机持久化已闭环

`m3note-io-tuning.sh` 装进 service.d 后**一开始开机不执行**——根因不是脚本，而是
**Magisk 串行执行 service.d、`waitpid` 每个脚本**，而 tailscale 脚本（rev2）尾部
`while :` 永不退出，把排在它后面的 io-tuning 堵死了。修复 = tailscale 升级 rev3
（入口派生看护进程后立即退出）+ 把同样死循环的 `.bak` 移出 service.d。
**重启实测：开机自动生效**（io 日志两条新记录、`[deadline]`/`1024`、tailscale 看护进程 ppid=1、docker 容器自起）。
详见《service.d串行阻塞修复-2026-10-15.md》。

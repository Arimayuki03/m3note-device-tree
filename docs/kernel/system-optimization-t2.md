> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# 系统优化 T2 执行记录（2026-10-15 晚）

> **历史记录**：#32 时期；当前运行内核为 #3307（#32 + Docker/qtaguid 补丁）。
> 现状见 [CURRENT-STATE.md](../CURRENT-STATE.md)。

> 设备：m3note / Flyme 8 / 内核 **#32（已刷入启动分区并回读校验通过）**。承接《系统优化T1-2026-10-15.md》第七节"T2 其余项"。
> 按要求**不涉及壁纸**（壁纸保持现状，未做任何改动）。

## 一、改了什么（一次构建、全部固化进内核、零开机脚本）

| 项 | 改动 | 理由 |
|---|---|---|
| **zram 换 lz4** | `CONFIG_ZRAM_LZ4_COMPRESS=y` **＋** `zram_drv.c: default_compressor "lzo"→"lz4"` | 只开配置没有用：全树 grep 确认**没有任何地方写 `comp_algorithm`**，编译进的默认压缩器是唯一生效入口。lz4 压缩/解压都比 lzo 快（比率略差），真正开始换页时 swap-in 延迟更低 |
| zram 调试 | `# CONFIG_ZRAM_DEBUG is not set` | 去掉调试插桩 |
| cgroup 调试 | `# CONFIG_CGROUP_DEBUG is not set` | 去掉调试子系统/文件（`/proc/cgroups` 里 debug 行消失） |
| 交互调速器 | `cpufreq_interactive.c: DEFAULT_GO_HISPEED_LOAD 99→85` | 负载到 **85%** 就上升到 hispeed_freq(=819MHz)，不再等 99%，升频更跟手；写进内核默认值，重启自然保持（运行时 `echo` 不持久） |
| （未做）`CONFIG_KSM` | **保持关闭** | 见第三节 |

固定基线不变：IRTX 关（上键）、aw8738（外放）、ltr579＋alsps 注册（光感/接近）、`DEFAULT_IOSCHED="deadline"`。

## 二、实测验证（#32，重启后；原始输出见 `verification-t2-2026-10-15.txt`）

| 检查项 | 实测 | 结论 |
|---|---|---|
| 版本 | `#32 SMP PREEMPT Thu Oct 15 19:02:02`，boot_completed=1 | ✅ |
| **zram 压缩器** | `lzo [lz4]`（方括号=生效中） | ✅ lz4 真正生效 |
| zram swap | 2GiB 活动，`orig_data_size=4096 / compr_data_size=64` | ✅ 压缩通路正常 |
| **cgroup 调试** | `/proc/cgroups` 不再有 `debug` 行 | ✅ CGROUP_DEBUG=n 生效 |
| **调速器** | `go_hispeed_load = 85`（其余 tunable 未变） | ✅ |
| 四项修复回归 | `/dev/aw8738`✓ `/dev/m_alsps_misc`✓ `104:11101010`✓ `/dev/irtx` 不存在✓ | ✅ |
| i2c / 稳定性 | `Adapter is busy`=0，`panic|BUG`=0 | ✅ |
| 传感器直读 | PART_ID=`b1`、ALS=`0x0036`、PS=`0x0097`；探测后 wedge 仍 0 | ✅ |
| 调度器 | `mmcblk0boot0=[deadline]`（内核默认生效）；`mmcblk0=[cfq]` 仍被 Flyme 用户态改回 | 已知问题（见下） |
| Tailscale | 节点 `m3note`(<TAILSCALE_IP>) 在线；5205 规则开机自动出现（boot log `11:07:40 rule installed`） | ✅ |
| Docker + 容器 | `beszel-agent: Up`（自启） | ✅ |
| 空闲 CPU | 30s 采样 busy **0.86%**（T1 基线 0.6~0.8%） | ✅ 无回归 |
| **启动分区持久化** | 分区回读 md5 = `712e4e65…` = `boot-fix32-test.img` | ✅ 已固化 |

**遗留（T1 已知，非本轮引入）**：主存储 `mmcblk0` 仍被某个 Flyme 早期用户态调优写回 `cfq + read_ahead 512`。
kernel 默认（deadline）动不了它；要压住需要开机后再写一次——现成脚本 `m3note-io-tuning.sh`（已放 `/data/local/tmp`，装不装你定）。

## 三、CONFIG_KSM 为什么不开（可选项）

KSM **单独编进内核不会自启**：需要运行时往 `/sys/kernel/mm/ksm/run` 写 1，而设备上没有任何 rc/脚本会这么做（已检查
`/init.rc`、`/init.*.rc` 等，无 ksm 引用）。开了 = 零效果；要生效还得再加一条开机写入，与"零开机脚本"冲突；
且 T1 已把瓶颈定位在 UI/服务层而非内存（zram 目前仅用 12K）。
⇒ 本期不开。**如需**：下一版一并打开并配一行开机启用即可，一句话的事。

## 四、回退方法

- 内核回退（#31）：先 `adb reboot bootloader && fastboot boot project/m3note-backup/boot-fix31-test.img`，
  再 `bash project/kernel/flash-boot.sh project/m3note-backup/boot-fix31-test.img`
  （**先 fastboot RAM 启动**，否则启动分区写入不生效——见 T1 第四节）。
- 本次现场回滚镜像：`project/m3note-backup/boot-live-1792062452.img`（= 刷入前的 #31 内容）。
- lz4 若异常：`flash-boot.sh` 回 #31 即可；或在运行中 `echo lzo > /sys/block/zram0/comp_algorithm`（需先 swapoff+reset）。

## 五、产物

| 文件 | 说明 |
|---|---|
| `Image.gz-fix32` / `kernel-config-fix32` | 构建产物 |
| `build_fix32.sh` | 构建脚本（含全部回归断言 + lz4/ispeed 断言） |
| `boot-fix32-test.img` | md5 `712e4e65b0ba1f36f005f03e817d8743`，sha256 `f288ccef507895e6…`（已刷入） |
| `verification-t2-2026-10-15.txt` | 原始验证输出 |
| `flash-boot.sh` | 已知良好镜像列表已追加 `boot-fix32-test.img` |

---
*记录：ZCode · 2026-10-15 19:1x*

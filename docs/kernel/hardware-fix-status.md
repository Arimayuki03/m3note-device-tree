> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# 修复状态（2026-10-15，历史）

> **历史记录**：本文写于当时的构建阶段（#20–#32）；当前运行内核为 #3307。
> 硬件修复的当前结论见 [CURRENT-STATE.md](../CURRENT-STATE.md)。

- #26（CM36686 兼容补丁 + 最低亮度保护）写入后启动循环，已通过临时 TWRP 回滚到 #22；回滚镜像回读 SHA256 与本地 `boot-fix22-test.img` 一致。
- 当时设备：`uname #22`，CPU `online=0-7`，`/proc/hps/enabled=0`，`PPM_POLICY_THERMAL=disabled`，zram `/dev/block/zram0` 约 2 GiB。
- `/sbin/.core/img/.core/service.d/m3note-performance.sh` 已存在并在重启后再次应用八核与软件温控设置。
- 音量上键：监听 `/dev/input/event0`（ACCDET）及 `event1`（mtk-kpd）均没有按键事件；系统 keylayout 有 `KEY_VOLUMEUP` 映射。因此当前证据指向硬件按键/排线或 keypad 中断，没有可由 Android 映射修复的事件。
- 光线/接近：HAL 能枚举 MTK Light/Proximity，但当前内核没有绑定 CM36686 I2C 驱动；#26 的直接兼容补丁导致启动循环，暂不再次刷写，需拆分为更小的安全补丁。

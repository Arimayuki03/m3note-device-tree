> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# m3note 输入、Wi-Fi、传感器、CPU 诊断（2026-10-15）

> **历史记录**：本文写于当时的构建阶段（#20–#32）；当前运行内核为 #3307。
> 硬件修复的当前结论见 [CURRENT-STATE.md](../CURRENT-STATE.md)。

- 音量上键：`/system/usr/keylayout/mtk-kpd.kl` 和 `ACCDET.kl` 均有 `KEY_VOLUMEUP` 映射；用户实按无反应，需继续抓取 `/dev/input/event0`、`event1` 的实体按键事件以区分硬件无事件和系统策略拦截。
- Wi-Fi：连接 `WIFI_SSID_REDACTED`，5180 MHz、RSSI 约 -41 至 -48 dBm，Android `Link speed: 135Mbps`，AP/驱动当前协商为 135，不是系统固定 150。
- 光线/接近：Sensor HAL 能枚举 `MTK Light`、`MTK Proximity`，但 `dumpsys sensorservice` 没有这两路最近事件；`msensord` 为 stopped，手动 start 后立即退出，说明 HAL/底层驱动初始化仍异常。
- CPU：当前 `/sys/devices/system/cpu/online=0-7`，`/proc/hps/enabled=0`，`/proc/ppm` 的 thermal policy 已临时关闭；内核紧急温度保护仍存在。
- 持久化：#23 启动镜像已生成，SHA256 `3459b10ad30645d40355c17d909c0d2a32a39498d760dcd94f970df84e6a5ead`，但当前设备启动分区写保护，写入读回仍是 #22 SHA256 `701a...68049`，未更改启动分区。

> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# Wi-Fi 服务器模式与 4 GiB zRAM

> **后续变更（2026-10-22）**：AstrBot 已删除；当前运行 DSH、DSHA、Magpie 和 Beszel。
> 本文的 AstrBot 记录为历史状态。

用户用途：不插 SIM 卡，使用 Wi-Fi 运行 Ubuntu、Docker 和服务。

## 应用与无线电配置

| 功能 | 包名 | 配置 |
| --- | --- | --- |
| 拨号 | com.android.dialer | 用户 0 禁用 |
| 通话界面 | com.android.incallui | 用户 0 禁用并隐藏冻结 |
| 短信 | com.android.mms | 用户 0 禁用 |
| 彩信后台 | com.android.mms.service | 用户 0 禁用 |
| 通话设置 | com.meizu.callsetting | 用户 0 禁用 |
| 手机激活 | com.activate.activatephone | 用户 0 禁用 |
| 虚拟 SIM 桥接 | com.android.flyme.bridge.softsim | 用户 0 禁用 |
| 虚拟 SIM | com.flyme.virtual.softsim | 用户 0 禁用 |
| 运营商流量服务 | com.flyme.telecom.usagedata.service | 用户 0 禁用 |
| 魅族云 | com.meizu.cloud | 用户 0 禁用并隐藏冻结 |
| 魅族账户 | com.meizu.account | 用户 0 禁用 |
| 魅族同步 | com.meizu.mzsyncservice | 用户 0 禁用 |
| 查找手机 | com.meizu.flyme.service.find | 用户 0 禁用 |

应用 APK 和数据保留。魅族云和通话界面带有 `FLAG_PERSISTENT`，第一次重启确认仅 `disable-user` 仍会生成常驻进程，因此进一步使用 `pm hide --user 0`，而非循环杀进程。

开启飞行模式（`airplane_mode_on=1`），并单独启用 Wi-Fi（飞行模式下 `wifi_on=2` 是正常值）。蜂窝语音及数据注册状态均为 `3`（POWER_OFF），移动数据和漫游设为 0，Wi-Fi 休眠策略为 2（始终保持）。保留 `com.android.phone`、Telecom、联系人及电话数据提供程序等底层框架，避免破坏系统服务依赖。电话、短信和上述魅族服务不能正常使用；需要恢复时执行撤销脚本。

## zRAM

- 操作前实际容量为 2,042,990,592 字节，约 1.90 GiB；旧 2 GiB 脚本权限为 0644，此次启动没有运行。
- 新容量为 **4,294,967,296 字节（4 GiB）**，`/proc/swaps` 为 4,194,300 KiB，差一页为 swap 头。
- 压缩算法：`lzo [lz4]`，实际采用 lz4。
- 仅扩大 zRAM 压缩交换的逻辑容量，未建立内部存储或 SD 卡 swap 文件；压缩数据按需占用物理 RAM。
- 开机执行器修复为可执行权限，早期入口和 service.d 都可触发；工作脚本以锁保证幂等。重设前检查内存余量，失败时尝试恢复原容量，避免直接丢弃活动 swap。
- 单容器仍受各自的资源限额约束；系统 4 GiB zRAM 不会自动扩大某个容器的 swap 配额。

## 实测与证据

首次重启 ID 为 `<UUID_REDACTED>`。未手动执行扩容脚本即自动到 4 GiB；早期和 service.d 两次触发的日志分别记录成功扩容、已经是目标容量。

受限临时容器使用原有本地镜像，内存上限 32 MiB、内存加 swap 总额 96 MiB，实际触碰 48 MiB，观测到 **17,428,480 字节（约 16.6 MiB）**进入 swap，18 秒后重新读写成功，退出码 0。没有尝试把整个 4 GiB 填满。临时容器已删除，证据为 `swap-verification.json`。

第一次重启后 Wi-Fi 自动连接，熄屏后外网 ping 两次均成功；AstrBot 容器内访问 HTTPS 返回 200。Docker 原有 4 个镜像、2 个容器及其 ID/镜像保持匹配；SD 卡三个业务路径仍为设备 179:129，AstrBot 本地 HTTP 200，八核在线。对应原始证据保留在 `first-reboot-verification.txt`、`first-reboot-docker-health.json`、`container-network.txt`。

最终隐藏冻结后再次重启，启动 ID 为 `<UUID_REDACTED>`。魅族云和通话界面均为 `installed=true hidden=true enabled=3`，目标进程检查为空；13 个应用禁用配置保留。Wi-Fi 自动连接并在熄屏时通过外网 ping，AstrBot 容器内 HTTPS 200，本地 HTTP 200；原有 4 个镜像和 2 个业务容器身份及 SD 卡绑定再次通过，CPU 0–7。zRAM 仍为 4 GiB、lz4，旧的后台限制守护也已自动运行。见 `final-verification.txt`、`post-wifi-server-health.json`、`container-network.txt`。

## 安装、日志与撤销

- `/data/m3note-wifi-server.sh`：开机后应用网络策略和禁用状态；独立进程运行，不阻塞其他 Magisk 开机脚本。
- `/data/m3note-zram-4g.sh`：zRAM 扩容工作脚本。
- `/sbin/.core/img/.core/service.d/m3note-wifi-server.sh` 和 `m3note-zram-4g.sh`：分离启动入口。
- `/sbin/.core/img/.core/post-fs-data.d/m3note-model.sh`：保留机型设置功能，将早期 zRAM 入口改为 4 GiB 新入口，并修正执行权限。旧 2 GiB 入口已移除，防止覆盖容量。
- `/data/m3note-wifi-server/`：原始设置及脚本备份、运行日志、验收记录和撤销脚本；目录权限 0700。日志各到 64 KiB 轮换，保留一份旧日志。

在 Android root shell 执行以下命令撤销；先等待开机配置工作脚本执行完毕。

```sh
/system/bin/sh /data/m3note-wifi-server/rollback.sh
```

撤销会取消两包隐藏状态，恢复这 13 个应用的原始默认启用状态、移动数据/漫游/休眠设置，关闭飞行模式并打开 Wi-Fi，恢复旧开机脚本。随后重启恢复原始 swap 启动行为；不会在内存压力高时强制在线 swapoff。旧配置本身在本次操作前没有成功执行 2 GiB 扩容，故撤销恢复的是原始行为，不能保证精确为 2 GiB。此前 QQ、应用商店、手机管家的后台限制独立保留。

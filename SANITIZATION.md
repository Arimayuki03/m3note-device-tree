# 脱敏与排除清单

本文件说明开源导出时做了哪些处理。原始工作目录未被修改。
完整的资源排除清单见 [EXCLUSIONS.md](EXCLUSIONS.md)。

本次发布以 **2026-10-22 的设备现状**为准（Flyme 8.0.0.0A、内核 #3307）。
当前状态摘要见 `docs/CURRENT-STATE.md`；旧文档已加“历史记录”标注。
会话记录只用于核对设备状态和版本号，没有复制原始对话、账号、令牌或日志。
现状数据另经 adb 只读查询核对（`getprop`、`uname`、`dumpsys`、`df`、
Docker 查询），仅保留版本号、容量和功能状态；序列号、IMEI、MAC、IP、
Wi-Fi SSID 等标识未写入文档。

## 已替换的标识

| 类别 | 处理 |
|---|---|
| 设备序列号 | 替换为 `SERIAL_REDACTED` |
| SD 卡 CID / 文件系统 UUID | 替换为 `SD_CID_REDACTED` / `SD_UUID_REDACTED` |
| 启动 ID、机器 ID 等 UUID | 替换为 `<UUID_REDACTED>` |
| 局域网 IPv4 | 统一改为 `192.0.2.x` 文档示例网段 |
| Tailscale IP / 账号 | 替换为 `<TAILSCALE_IP>` / `TAILSCALE_ACCOUNT_REDACTED` |
| Wi-Fi SSID | 替换为 `WIFI_SSID_REDACTED` |
| SSH 主机密钥 / 公钥 | 替换为 `HOST_KEY_REDACTED` / `PUBLIC_KEY_REDACTED` |
| 密码、签名口令 | 替换为 `PASSWORD_REDACTED` |
| 个人邮箱 | 替换为 `EMAIL_REDACTED` |
| 本机用户名与绝对路径 | 用户名 -> `<USER>`，工作目录 -> `<PROJECT_ROOT>` |
| 本机构建路径 | WSL 根目录构建路径 -> `<BUILD_ROOT>` |
| Docker 容器短 ID | 替换为 `<CONTAINER_ID_REDACTED>` |
| SD 卡分区几何 | 替换为 `<SD_SIZE_SECTORS>` / `<SD_PART_START_SECTOR>` / `<SD_PART_SIZE_SECTORS>` |
| SD 卷标 | 替换为 `<SD_VOLUME_LABEL>` |
| 工具工作区路径 | 替换为 `<WORKSPACE>` |

## 已排除的文件/目录

- `*.img`、`*.bin`、`*.zip`、`*.tar.gz`、`*.apk`、`*.msi`、`*.7z`
- `project/m3note_key`、`m3note_key.pub`、`authorized_keys`
- `<ARTIFACTS>/` 中的分区备份和 boot 镜像
- `project/astrbot/`（含登录信息、初始密码、运行日志）
- `project/dsha-install/`（含本地签名密钥、口令和第三方 APK）
- `project/dsh-ubuntu20/`（第三方运行时、凭据和日志）
- `project/device-cleanup-audit/`、`current-resource-audit/`、各 benchmark 的原始证据
- `project/kernel/docker-upgrade/` 的日志/JSON/二进制（仅保留补丁）
- `.mimosa/`、`.zcode/`、`.v2c/`（代理会话与扫描历史）
- 所有截图、日志、下载页面、QQ/应用数据和第三方 SDK

## 发布前建议

1. 运行 `git grep -nE '91[A-Z0-9]{12}|password|PRIVATE KEY|tskey-|ssh-ed25519'` 复核。
2. 用 `gitleaks` 或 `trufflehog` 扫描暂存区。
3. 确认 `sources/` 中没有把内核/工具链大文件误加入 Git。

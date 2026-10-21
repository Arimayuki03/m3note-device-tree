# 开源发布排除清单 / Open-Source Exclusion List

> 本清单列出**不随仓库发布**的资源类别与原因。文档不重复记录任何真实敏感值；
> 脱敏映射见 [SANITIZATION.md](SANITIZATION.md)，第三方许可与来源见
> [NOTICE.md](NOTICE.md)。

## 1. 凭据与密钥 / Credentials and keys

| 项目 | 处理 |
|---|---|
| SSH 私钥、公钥、`authorized_keys` | 不发布 |
| Android 签名 keystore / `.p12` / 证书私钥、签名口令 | 不发布 |
| 登录密码、passphrase、token、Cookie、Authorization/Bearer | 不发布 |
| API key、云厂商密钥、Tailscale auth key、SSH host key | 不发布 |
| AstrBot、DSH/DSHA、Magpie、Beszel 等服务的运行凭据 | 不发布 |

原因：这些内容会直接导致设备或服务被未授权访问。

## 2. 设备唯一标识与个人网络信息

| 类别 | 示例位置（仅类别，不含真实值） |
|---|---|
| 设备序列号、IMEI/MEID、IMSI/ICCID | 原始工作目录中的设备信息与日志 |
| MAC/BSSID、Wi-Fi SSID | 网络配置、日志、脚本注释 |
| SD 卡 CID、文件系统 UUID、启动 ID | SD64 迁移记录、健康检查脚本 |
| 局域网 IP、Tailscale IP/账号、主机名 | 连接脚本、部署记录、日志 |
| 本机用户名、家目录、绝对路径、容器短 ID | 脚本、文档、构建记录 |
| 个人邮箱、手机号、社交账号、姓名、位置 | 会话记录、服务配置 |

处理：发布版统一替换为 `SERIAL_REDACTED`、`SD_CID_REDACTED`、
`SD_UUID_REDACTED`、`<UUID_REDACTED>`、`192.0.2.x`、`<USER>`、
`<PROJECT_ROOT>`、`<BUILD_ROOT>`、`<CONTAINER_ID_REDACTED>` 等占位符。

## 3. 实机数据、日志与备份

| 项目 | 处理 |
|---|---|
| `project/m3note-backup/*.img`（boot、lk、secro、frp、proinfo、devinfo、persist、userdata 等） | 不发布 |
| `extracted/*.img`、`*.bin`、`update.zip`、官方 Flyme 固件包 | 不发布 |
| 设备日志、dmesg、截图、应用数据、QQ/聊天数据 | 不发布 |
| benchmark、资源审计、迁移验证的原始日志/JSON/截图 | 不发布 |
| `.mimosa/`、`.zcode/`、`.v2c/`、`.codex/` 会话与扫描历史 | 不发布 |

原因：含设备唯一标识、个人数据或第三方隐私；部分备份可直接泄露 IMEI/校准数据。

## 4. 官方/第三方二进制与大型资源

| 项目 | 处理 |
|---|---|
| Flyme 8.0.0.0A 固件、OTA、`boot.img`、`lk.bin`、`preloader` | 不发布；从官方或自有备份获取 |
| TWRP、Magisk、SuperSU、Xposed、各类 APK | 不发布；从上游获取 |
| mtkclient、UsbDk、Android SDK、Node modules | 不发布；从上游获取 |
| 3.18.35 内核源码、AOSP GCC 4.9 工具链、Ubuntu/Alpine rootfs | 不打包；获取方式与 SHA-256 见 [sources/README.md](sources/README.md) |

原因：版权/许可、体积、非本仓库授权分发。

## 5. 个人服务配置与运行时

| 项目 | 处理 |
|---|---|
| `project/astrbot/`、`project/dsh-ubuntu20/`、`project/dsha-install/` | 不发布 |
| AstrBot/DSH/DSHA/Magpie/Beszel 的数据、模型配置、隧道/防火墙/API 配置 | 不发布 |
| 运行时容器数据、日志、账号状态 | 不发布 |

原因：含凭据、个人服务配置和易变运行状态，不属于设备树核心。

## 6. 与设备树无关的个人资料

| 项目 | 处理 |
|---|---|
| 与 m3note 无关的计划、笔记、代理会话、临时文件 | 不发布 |
| 个人下载页面、QQ/应用安装包、聊天备份 | 不发布 |

## 7. 发布版如何替代

- **设备标识**：使用占位符，按自己的设备填写；不要提交自己的真实值。
- **固件/工具**：按 [NOTICE.md](NOTICE.md) 与 [sources/README.md](sources/README.md)
  从官方/上游获取；本仓库只保留名称、用途和校验值。
- **内核/工具链/rootfs**：不附带大文件；`sources/README.md` 提供文件名、大小和 SHA-256。
- **运行状态**：只写入 [docs/CURRENT-STATE.md](docs/CURRENT-STATE.md)，不写入凭据和容器数据。

## 8. 发布前检查

```bash
# 1. 校验发布清单
sha256sum -c SHA256SUMS

# 2. 确认没有常见凭据模式（按需替换/扩展）
git grep -nE 'BEGIN .*PRIVATE KEY|ssh-(ed25519|rsa) AAAA|tskey-|ghp_|xox[baprs]-|AKIA[0-9A-Z]{16}'

# 3. 建议再用专用工具扫描
gitleaks detect --source . --no-git
# 或 trufflehog filesystem .
```

发布前还应确认：没有 `.mimosa/`、`.zcode/`、`.v2c/`、`__pycache__/`；
没有 `.img`、`.bin`、`.apk`、`.zip`、`.tar.gz` 等二进制/大文件；
zip 与目录逐文件一致。

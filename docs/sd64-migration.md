> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# 64GB SD 卡 Docker 迁移与开机挂载验证

> **后续变更（2026-10-22）**：AstrBot 已删除；当前 Docker 仅运行 beszel-agent，
> DSH/DSHA/Magpie 在 Ubuntu/Android 侧运行。本文的 AstrBot 容器/数据记录为历史状态。

最新状态：内部旧副本已清理，详见同目录《内部旧副本清理-2026-10-16.md》。

日期：2026-10-16。已完成迁移，并通过一次正常重启验证自动挂载和 Docker/容器自动启动。

| 项目 | 结果 |
|---|---|
| Docker 镜像 | 原 4 个镜像 ID 全部保留 |
| AstrBot / Beszel | 原容器 ID、镜像、资源限制和重启策略保持，均正常运行 |
| Docker 数据、容器可写层、应用数据 | 实际设备 179:129，均在 SD 卡 |
| 内容与元数据校验 | 停机复制后，三个目录全部通过 rsync 全内容 checksum、权限、时间、硬链接和扩展属性校验 |
| 开机验证 | SD 自动挂载并绑定三个数据目录，Docker 自动启动，两个业务容器自动恢复 |
| 持久性验证 | 临时容器可写层文件、命名卷文件经历容器重启及手机正常重启，内容与设备均正确 |
| AstrBot 页面 | 手机与电脑转发访问均 HTTP 200 |
| SD 剩余空间 | 48.58 GiB |
| 资源限制 | AstrBot 8 核（0–7）、768 MiB 内存保持；CPU 0–7 在线 |
| 内部原数据 | 后续已按用户要求清理，释放约 9.51 GB；内部不再保留业务快照 |
| 验证临时容器/卷 | 已删除，最终仅保留原有业务容器 |

实际存放位置（Ubuntu 路径）：

- `/mnt/sd64/m3note-docker/engine` → `/var/lib/docker`
- `/mnt/sd64/m3note-docker/astrbot-data` → `/srv/astrbot/data`
- `/mnt/sd64/m3note-docker/beszel-data` → `/opt/beszel-agent/beszel_agent_data`

Android root 对应前缀为 `/data/ubuntu`。绑定挂载保持已有路径，因此不需要重建镜像或容器。数据父目录权限 0700，SD 根目录权限 0755；ext4 挂载为 rw,noatime,nosuid,nodev，保留执行能力。

启动流程：Magisk service.d/docker-server 准备 Ubuntu → m3note-sd64-mount.sh/Python 校验卡 CID、分区几何和 ext4 UUID → 未挂载时 e2fsck -p 检查（只接受 0/1）→ 挂载 SD → 校验离线复制标记 → 绑定三个数据目录 → 启动 Docker。启动器另做只读就绪检查。

本卡 CID：SD_CID_REDACTED；UUID：SD_UUID_REDACTED。设备号在每次启动动态读取。无自动格式化操作。卡缺失、卡身份不匹配、只读或检查失败时，脚本阻止 Docker 启动，不会默默启用内部旧快照；这是已安装的防护逻辑，本次没有实际拔卡测试。

重启前 boot ID：<UUID_REDACTED>；重启后：<UUID_REDACTED>。重启后没有手动挂载、手动启动 Docker 或业务容器；等待自动恢复后才进行验证。

后续清理更新：内部旧业务快照已按用户要求删除，释放约 9.51 GB；如需回迁，必须从 SD 复制最新数据。正常运行期间不要拔卡。回迁前需要先停止 Docker，将 SD 最新数据离线同步回内部并校验。具体步骤见同目录《回退说明.md》。原启动脚本备份同时保存在电脑本目录和手机 `/data/m3note-sd64-backup/`。

证据：baseline.json、copy-verification.json、installed-files.json、before-reboot-verification.json、after-reboot-verification.json、final-verification.json、completion.json、boot-mount.log、kernel-storage-after-reboot.log。校验明细在手机 `/var/tmp/m3note-sd64-migration/`，未输出应用配置、口令或原始业务日志。

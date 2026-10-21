# 主机与设备脚本

| 脚本 | 用途 |
|---|---|
| `bootimg_inspect.py` | 解析 MTK boot 镜像头、kernel/ramdisk/DTB/签名块 |
| `boot_pack.py` | 重打包 boot，保留原厂签名块 |
| `boot_pack_containers.py` | 把自编内核装入 Magisk 补丁版 boot |
| `secro_hashcheck.py` | 检查 secro 等分区是否存 boot 哈希 |
| `seccfg_check.py` | 分析 seccfg 锁状态结构 |
| `flash-containers-boot.sh` | 带基线校验、回读校验和自动回滚的刷写流程 |
| `linux.sh` | Android 上的 chroot 挂载/启动/进入 |
| `m3note-probe.sh` | 设备/内核/分区信息采集 |
| `99-android-nosandbox` | apt 在 Android 内核上的 sandbox 规避配置 |
| `policy-rc.d` | chroot 内阻止服务自动启动 |
| `m3note-ssh.cmd.template` | Windows SSH 连接模板（使用环境变量） |
| `wifi-server-mode/` | 飞行模式 + Wi-Fi、zRAM、应用禁用与回滚 |
| `battery-full/` | 固定电量显示为 100% |
| `ssh-repair/` | 修复 `/run/sshd` 权限的开机脚本 |
| `sd64-migration/` | SD 卡 CID/UUID 校验、挂载、Docker 启动看护 |

`ARTIFACTS.md` 说明 boot/分区工具的输入目录 `m3note-backup/`：这些转储不含在
仓库中，需要从你自己的设备读取，并注意 `proinfo`/`devinfo`/`persist` 等分区含
设备唯一标识，切勿公开。

所有脚本都假设已解锁、已 root、已安装 Magisk，并且路径/分区与 m3note 一致。
使用前请逐行阅读，先做只读探测，再执行写操作。

> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# SSH 连接拒绝修复

用户连接 `root@192.0.2.10:22` 返回 Connection refused。手机 Wi-Fi 地址未变，但没有 sshd 进程或 22 端口监听。

根因：开机脚本在 Android 默认 umask 000 下执行 `mkdir -p /data/ubuntu/run/sshd`，目录权限变为 0777。后面的 chroot bash 才执行 umask 022，无法修正已创建目录。`sshd -t` 明确报错：`/run/sshd must be owned by root and not group or world-writable.` `/run` 是每次启动重建的 tmpfs，因此该错误会随重启重现。原脚本还丢弃了 sshd 的错误输出。

已将当前目录改为 root:root 0755，配置检查通过后启动 sshd，恢复 IPv4/IPv6 的 22 端口监听。使用电脑上原有密钥、严格主机密钥校验及 BatchMode 实际登录 root 成功，`id -u` 返回 0。

持久修复已安装到 `/sbin/.core/img/.core/service.d/docker-server`：在创建目录前设置 umask 022，并明确执行 `/run/sshd` 的 chown 0:0 与 chmod 755；增加 sshd -t 检查，将启动错误和 sshd 日志留到 Ubuntu `/root/sshd-startup.log`。安装前 shell 语法检查通过，已核对已安装脚本 SHA256 与本地修复稿一致。此次没有再次重启手机。

原始脚本备份：手机 `/data/m3note-ssh-repair/docker-server.before`，本地 `docker-server.before.sh`；修复稿为 `docker-server.fixed.sh`。恢复原脚本会重新引入上述权限问题。

连接地址仍为 `192.0.2.10`，端口 `22`，用户 `root`。认证配置及主机密钥保持原配置。

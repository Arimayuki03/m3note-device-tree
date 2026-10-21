> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# Docker 开机未启动修复记录

- **日期**：2026-10-22 00:13 CST（设备时间）
- **设备**：Meizu m3 note（`m3note`），Android 7.0，Magisk 16.3
- **现象**：重启后 `dockerd` / `containerd` 均未运行，`docker ps` 无法连接；SSH 和电池脚本正常
- **结果**：已手动拉起 Docker，并新增开机重试看护；重启验证 Docker 与 beszel-agent 自动恢复

---

## 1. 现象与日志

重启后检查：

```bash
ps | grep -E "dockerd|containerd"
# 无输出
```

`/data/ubuntu/root/sd64-mount.log`：

```text
subprocess.CalledProcessError: Command '['blkid', '-p', '-s', 'TYPE', '-o', 'value',
'/dev/block/mmcblk1p1']' returned non-zero exit status 2.
SD64 unavailable or invalid: Docker startup blocked
```

`/data/ubuntu/root/dockerd.log` 没有本次开机的新记录，说明 `docker-server` 在挂载 SD 阶段就退出了。

随后检查 SD 卡，发现卡本身正常：

```text
/dev/block/mmcblk1p1: LABEL="<SD_VOLUME_LABEL>"
UUID="SD_UUID_REDACTED" TYPE="ext4"
```

SD 卡设备节点出现的时间晚于 `docker-server` 的启动尝试。结论：**开机时 SD 卡尚未就绪，`blkid` 失败，`docker-server` 按 fail-closed 设计拒绝启动 Docker，并且没有重试机制**。

---

## 2. 立即恢复

手动挂载 SD 和 Docker 数据目录：

```bash
/system/bin/sh /data/m3note-sd64-mount.sh
```

输出：

```text
<SD_VOLUME_LABEL>: clean, <INODES_USED>/<INODES_TOTAL> files, <BLOCKS_USED>/<BLOCKS_TOTAL> blocks
SD64_READY: identity, ext4 mount, and all required data bindings verified
```

拉起 Docker：

```bash
/system/bin/setsid /data/local/tmp/busybox unshare -m \
    /system/bin/sh /data/m3note-dockerd-launch.sh \
    > /data/ubuntu/root/dockerd.log 2>&1 < /dev/null &
```

验证：

```bash
chroot /data/ubuntu /usr/bin/env -i \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
  /usr/bin/docker ps
```

结果：`beszel-agent` 正常运行，Docker 版本 `26.1.3-m3note`，存储驱动 `vfs`。

---

## 3. 持久修复：Docker 开机重试看护

新增文件：

```text
/sbin/.core/img/.core/service.d/docker-watchdog
```

权限：`755 root:root`，无扩展名。

### 3.1 设计

- `service.d` 入口用 `/system/bin/setsid` 派生看护进程后立即 `exit 0`，不阻塞 Magisk 16.3 的串行启动链。
- 看护进程等待 `sys.boot_completed=1`，再等 180 秒，让正常 `docker-server` 先完成自己的尝试。
- 若 `dockerd` 未运行：
  1. 执行 `/data/m3note-sd64-mount.sh` 重新校验并挂载 SD；
  2. 用 `unshare -m` 启动 `/data/m3note-dockerd-launch.sh`；
  3. 等待 10 秒确认 `dockerd` 存活；
  4. 必要时补启 `m3note-docker-routes.py`；
  5. 退出。
- 最多重试 15 次，每次间隔 60 秒，覆盖 SD 卡初始化较慢的情况。
- 使用 `/data/local/tmp/docker-watchdog.pid` + `boot_id` 防止同一开机内重复运行。
- 看护日志：`/data/local/tmp/docker-watchdog.log`。

### 3.2 当前行为

- 这是**一次性的开机重试**：Docker 成功启动后看护进程退出。
- 如果运行期间 SD 卡被拔出或 Docker 意外退出，需要等下次重启才会再次拉起；当前没有做持续守护。
- 原有 `docker-server` 未修改，仍负责正常开机流程、SSH 和路由更新。

### 3.3 手动测试

为验证失败路径，执行了：

1. `docker stop beszel-agent`
2. `kill <dockerd pid>`，确认 `dockerd` / `containerd` 已退出
3. 卸载 `/data/ubuntu/opt/beszel-agent/beszel_agent_data`、`/data/ubuntu/var/lib/docker`、`/data/ubuntu/mnt/sd64`
4. 运行：
   ```bash
   DOCKER_WATCHDOG_WAIT=0 /system/bin/sh \
     /sbin/.core/img/.core/service.d/docker-watchdog --watchdog
   ```

看护日志：

```text
dockerd not running; SD mount attempt 1/15
<SD_VOLUME_LABEL>: clean, ...
SD64_READY: identity, ext4 mount, and all required data bindings verified
SD mount OK; starting dockerd
dockerd started; watchdog done
```

随后手动 `docker start beszel-agent` 恢复容器。

### 3.4 重启验证

重启后等待 240 秒检查：

```text
CONTAINER ID   IMAGE                         STATUS
<CONTAINER_ID_REDACTED>   henrygd/beszel-agent:latest   Up 3 minutes
```

进程：

```text
root  3786  1  /usr/bin/dockerd-cpusetfix
root  3811  3786  containerd
root  3966  1  /usr/bin/containerd-shim-runc-v2
```

看护日志：

```text
Wed Oct 21 16:10:07 GMT 2026 entry: detaching watchdog
===== Wed Oct 21 16:10:07 GMT 2026 watchdog start =====
Wed Oct 21 16:13:08 GMT 2026 dockerd already running; watchdog done
```

说明本次开机 `docker-server` 正常完成了启动，看护进程在 3 分钟后确认 Docker 已运行并退出。

同时电池脚本仍正常：

```text
AC powered: true
status: 2
level: 100
```

---

## 4. 文件与日志

| 路径 | 作用 |
|---|---|
| `/sbin/.core/img/.core/service.d/docker-watchdog` | 开机重试看护（无扩展名，755） |
| `/data/local/tmp/docker-watchdog.log` | 看护日志 |
| `/data/local/tmp/docker-watchdog.pid` | 运行中的看护 PID + boot_id |
| `/data/ubuntu/root/dockerd.log` | Docker 守护进程日志 |
| `/data/ubuntu/root/sd64-mount.log` | SD 挂载与校验日志 |
| `/data/ubuntu/root/docker-routes.log` | Docker 路由更新日志 |

本地留档：`project/sd64-migration/docker-watchdog.sh`

---

## 5. 停用/回退

删除看护脚本并重启：

```bash
adb shell "su -mm -c 'rm /sbin/.core/img/.core/service.d/docker-watchdog'"
adb reboot
```

原有 `docker-server` 不受影响，仍会在 SD 就绪时正常启动 Docker。

---

## 6. 备注

- `docker-server` 的 fail-closed 行为是正确的安全设计：SD 卡身份、分区几何、ext4 UUID 或数据绑定不匹配时，不会回退到内部旧数据。
- 本次问题是时序问题，不是 SD 卡或 Docker 本身损坏。
- 若后续需要 Docker 长期看护（退出后自动重启），可把看护循环改成常驻；当前版本只覆盖开机阶段。

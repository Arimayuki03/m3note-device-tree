> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# 手机电池满电脚本部署记录

- **日期**：2026-10-21
- **设备**：Meizu m3 note（`m3note`），Android 7.0，序列号 `SERIAL_REDACTED`
- **Root 环境**：Magisk 16.3（MagiskSU 16.3:1630），user build，`adb root` 不可用
- **目标**：让 Android 系统上报的电量一直为 100%，并显示为充电状态；重启后自动生效
- **结果**：已部署，并实际重启验证通过

---

## 1. 方案说明

Android 没有脚本能让电池“物理上”一直满电。本方案通过 `dumpsys battery set` 修改系统上报的电池状态：

- `level 100`：电量显示 100%
- `status 2`：状态为 charging
- `ac 1`：交流电充电中
- `usb 0`、`wireless 0`：关闭 USB / 无线充电标记

这些覆盖值会在重启后丢失，因此用 Magisk 的 `service.d` 开机脚本在每次启动后重新设置。

> 注意：这只是修改系统上报值，不会真的给电池充电。

---

## 2. 文件清单

| 路径 | 权限 | 作用 |
|---|---|---|
| `/sbin/.core/img/.core/service.d/battery-full` | `755 root:root` | Magisk 开机启动器；拉起后台循环后立即退出 |
| `/data/adb/battery-full-loop` | `755 root:root` | 常驻循环；每 30 秒重新设置一次电池状态 |
| `/data/local/tmp/battery-full.log` | root 可写 | 启动器和循环的运行日志 |

说明：

- 该设备是 Magisk 16.3，`service.d` 的实际路径是 `/sbin/.core/img/.core/service.d`（位于 `magisk.img` 内），不是新版 Magisk 的 `/data/adb/service.d`。
- 该设备的 `su -c` 在默认挂载命名空间下会报 `Cannot execute /system/bin/sh: No such file or directory`，所以所有 root 命令都使用 `su -mm -c`（全局挂载命名空间）。
- Magisk 16.3 会**串行执行** `service.d` 里的脚本并等待其退出。启动器必须立即退出，否则会阻塞后面的 `docker-server`、`m3note-tailscale.sh` 等开机脚本。因此常驻循环用 `setsid` 脱离父进程，启动器执行完 `exit 0`。

---

## 3. 工作原理

开机时：

1. Magisk 在 `late_start` 阶段执行 `/sbin/.core/img/.core/service.d/battery-full`。
2. 启动器写入日志，并用 `/system/bin/setsid` 启动：
   ```sh
   /system/bin/setsid /system/bin/sh /data/adb/battery-full-loop </dev/null >>/data/local/tmp/battery-full.log 2>&1 &
   ```
3. 启动器立即 `exit 0`，Magisk 继续执行后续开机脚本。
4. `/data/adb/battery-full-loop` 在独立会话中常驻，每 30 秒执行一次：
   ```sh
   /system/bin/dumpsys battery set level 100
   /system/bin/dumpsys battery set status 2
   /system/bin/dumpsys battery set ac 1
   /system/bin/dumpsys battery set usb 0
   /system/bin/dumpsys battery set wireless 0
   ```

---

## 4. 部署步骤（复现用）

### 4.1 推送脚本到临时目录

```bash
adb push battery-full-loop /data/local/tmp/battery-full-loop
adb push battery-full-launcher /data/local/tmp/battery-full-launcher
```

### 4.2 安装到设备（需要 root）

```bash
adb shell "su -mm -c 'cp /data/local/tmp/battery-full-loop /data/adb/battery-full-loop && chmod 755 /data/adb/battery-full-loop'"

adb shell "su -mm -c 'cp /data/local/tmp/battery-full-launcher /sbin/.core/img/.core/service.d/battery-full && chmod 755 /sbin/.core/img/.core/service.d/battery-full'"
```

### 4.3 立即测试（不重启）

```bash
adb shell "su -mm -c '/sbin/.core/img/.core/service.d/battery-full'"
adb shell "tail -n 10 /data/local/tmp/battery-full.log"
adb shell dumpsys battery | grep -E "AC powered|USB powered|status|level"
```

### 4.4 重启验证

```bash
adb reboot
# 等待 sys.boot_completed=1 后再等约 60 秒，让 late_start 服务完成
adb shell getprop sys.boot_completed
adb shell "tail -n 10 /data/local/tmp/battery-full.log"
adb shell dumpsys battery | grep -E "AC powered|USB powered|status|level"
```

---

## 5. 重启后的验证结果

日志：

```text
===== Wed Oct 21 13:10:17 GMT 2026 launcher =====
launcher: spawned pid 4300
```

电池状态：

```text
AC powered: true
USB powered: false
status: 2
level: 100
```

进程检查：

```text
PID 4300  /system/bin/sh /data/adb/battery-full-loop
```

说明：Android 的 `ps` 默认只显示进程名（`/system/bin/sh`），看不到完整参数。要确认循环进程，需要读取 `/proc/<pid>/cmdline`，或直接看日志中的 `spawned pid`。

---

## 6. 恢复真实电量显示

先删除两个脚本，再重启（否则 `dumpsys battery reset` 会在 30 秒内被循环重新覆盖）：

```bash
adb shell "su -mm -c 'rm /sbin/.core/img/.core/service.d/battery-full /data/adb/battery-full-loop'"
adb reboot
```

如果不想重启，也可以在删除脚本并结束循环进程后执行：

```bash
adb shell "su -mm -c 'dumpsys battery reset'"
```

---

## 7. 注意事项

1. **不是真实充电**：只修改系统上报值，电池实际电量不会因此增加。
2. **可能突然关机**：如果拔掉充电器，真实电量会继续下降，但系统一直显示 100%，可能在低电时毫无预警地关机。
3. **影响省电策略**：系统认为“一直在充电”，可能影响 Doze、JobScheduler、省电模式和部分 App 的省电/性能判断。
4. **伤电池**：真实电池长期保持 100% 并持续充电会加速老化。长期插电设备建议关闭系统的“充电上限/优化充电”，并注意散热。
5. **仅建议用于测试、展示机、长期插电设备**，不要用于虚标电池状态转卖。

---

## 8. 附录：脚本全文

### 8.1 `/sbin/.core/img/.core/service.d/battery-full`

```sh
#!/system/bin/sh
# Magisk service.d 启动器：后台拉起电量循环后立即退出，避免阻塞后续开机脚本

LOG=/data/local/tmp/battery-full.log
echo "===== $(date) launcher =====" >>"$LOG"
/system/bin/setsid /system/bin/sh /data/adb/battery-full-loop </dev/null >>"$LOG" 2>&1 &
echo "launcher: spawned pid $!" >>"$LOG"
exit 0
```

### 8.2 `/data/adb/battery-full-loop`

```sh
#!/system/bin/sh
# 持续把系统上报的电量固定为 100%

LOG=/data/local/tmp/battery-full.log
exec >>"$LOG" 2>&1

sleep 10

while true; do
    /system/bin/dumpsys battery set level 100
    /system/bin/dumpsys battery set status 2
    /system/bin/dumpsys battery set ac 1
    /system/bin/dumpsys battery set usb 0
    /system/bin/dumpsys battery set wireless 0
    sleep 30
done
```

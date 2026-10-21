> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# service.d 串行阻塞修复 —— 为什么 io-tuning 装了却开机不执行（2026-10-15 晚）

> **历史记录**：本文写于当时的构建阶段（#20–#32）；当前运行内核为 #3307。
> 硬件修复的当前结论见 [CURRENT-STATE.md](../CURRENT-STATE.md)。

> 承接《系统优化T1-2026-10-15.md》第三节（I/O 调优的开机持久化）。
> 本篇记录一个**差点一直查不出来的坑**：不是脚本坏了，是 **Magisk 执行 service.d 的方式**把整条链堵死了。

## 一、症状

用户已装好 `service.d/m3note-io-tuning.sh`（md5 `6cdbe4a3…`），但**每次开机它都不执行**：

- `m3note-io.log` 里没有开机时间的记录，只有手动运行的两条；
- `mmcblk0` 队列一直是 Flyme 的 `cfq` + `512`；
- 手动跑 `sh m3note-io-tuning.sh` 完全正常（deadline + 1024 立即生效）。

## 二、根因（读 Magisk v16.3 源码确认）

`native/jni/core/bootstages.c` 里 `exec_common_script()` 执行 service.d 的方式是
**逐个串行 + 等它退出**：

```c
while ((entry = xreaddir(dir))) {
    if (entry->d_type == DT_REG) {
        ...
        LOGI("%s.d: exec [%s]\n", stage, entry->d_name);
        int pid = exec_command(0, NULL, bb_setenv, "sh", buf2, NULL);
        if (pid != -1)
            waitpid(pid, NULL, 0);   // ← 等这个脚本退出才跑下一个
    }
}
```

而当时的 `m3note-tailscale.sh`（rev2）结尾是**永不退出的看护循环**：

```sh
while :; do ... sleep 30; done
```

它把整条链堵死。目录里排在它后面的脚本**永远不会被执行**——先是被移走前的
`m3note-tailscale.sh.bak`（同样是 `while :` 死循环，双重保险地再堵一次），
最后就是 **`m3note-io-tuning.sh`（排在 readdir 顺序最后）**。

现场证据完全吻合：

| 证据 | 内容 |
|---|---|
| 本次开机日志 | zram(11:33:30) → performance(11:33:30) → tailscale 规则(11:33:30)，**之后整条链静止**；io 日志零条目 |
| `ps` | tailscale 脚本进程（PID 4323）**从开机一直活着**，就是它在 waitpid 里被等 |
| 目录顺序 | `docker-server → zram → performance → tailscale.sh → tailscale.sh.bak → io-tuning.sh`（io 排最后） |
| 顺带解释 | `m3note-model.sh` 里"Magisk 执行 post-fs-data.d 可靠，而 service.d 目录不会被启动"的旧注释其实不对——service.d **启动了**，只是**被卡住**了 |

**规则（写给未来的自己）**：本机所有 service.d 脚本**必须快速退出**；
任何长期运行的东西必须 `setsid … &` 派生出去（docker-server 是慢脚本里唯一的例外：它 ~57 秒后退出，可以接受）。

## 三、修复

`m3note-tailscale.sh` 升级为 **rev3**（仓库 `m3note-tailscale-fixed.sh`）：

```sh
if [ "$1" != "--watchdog" ]; then
    # service.d 入口：派生看护进程后立即退出
    /system/bin/setsid /system/bin/sh "$0" --watchdog </dev/null >/dev/null 2>&1 &
    echo "$(date) service.d entry: watchdog detached, exiting"
    exit 0
fi
# 下面才是看护循环（带 boot_id + pidfile 防重复）
```

同时把 `m3note-tailscale.sh.bak` **移出 service.d**（移到 `/data/local/tmp/m3note-tailscale.sh.bak.old`），
否则修好入口后它还会再堵一次。rev2 备份在 `/data/local/tmp/m3note-tailscale.rev2.sh`。

## 四、验证（两步都做了）

### 4.1 现场解堵（不重启）

```sh
# 启动 rev3 看护进程，然后杀掉堵住的旧进程（PID 4323）
kill <old blocker>
```

结果：**12 秒内整条链走完**——`m3note-io.log` 出现 `20:34:02` / `20:34:07` 两条记录
（io-tuning 的"立即 + boot_completed 后"双保险执行），队列变为 `[deadline]` / `1024`。
⇒ 直接证实了根因与修复。

### 4.2 重启全自动验证（最终验收）

重启后**无人工干预**，各脚本按链顺序全部执行，落点时间戳（GMT）：

| 检查项 | 实测 | 结论 |
|---|---|---|
| perf | `12:42:59 applying` / `12:43:00 online=0-7` | ✅ |
| tailscale | `12:43:00 service.d entry: watchdog detached, exiting` + `watchdog started (pid 4304)` | ✅ rev3 入口立即退出 |
| **io-tuning** | **`20:43:00` / `20:43:05 CST` 两条 applied**（开机自动） | ✅ **本轮目标达成** |
| 队列 | `noop [deadline] cfq` / `read_ahead=1024` | ✅ 开机即为目标值 |
| 看护进程 | `sh …/m3note-tailscale.sh --watchdog`，**ppid=1**（完全脱离） | ✅ |
| 规则 | `5205: from all fwmark 0x80000/0xff0000 lookup wlan0` | ✅ 开机自动 |
| docker | `beszel-agent: Up` | ✅ |
| tailscale | 节点 `m3note`(<TAILSCALE_IP>) 在线 | ✅ |
| 四项修复回归 | `/dev/aw8738`✓ `/dev/m_alsps_misc`✓ `104:11101010`✓ i2c busy=0 / panic=0 | ✅ |
| 内核 | `#32` 未变 | ✅ |

## 五、产物与备份

| 文件 | 说明 |
|---|---|
| `m3note-tailscale-fixed.sh` | **rev3**，md5 `5a34ebcf85b2cd4a983c927cd33e3239`（已装在 service.d） |
| `install-ts-rev3.sh` | 一键安装脚本（含备份/校验，本机安全钩子下由用户执行） |
| `test-ts-rev3.sh` | rev3 派生机制的独立测试（不碰 service.d） |
| `live-unblock-io.sh` | 现场解堵验证脚本 |
| `diag-service-boot.sh` | 首次诊断脚本（进程/日志/目录顺序取证） |

**设备脚本全量备份**：`project/m3note-backup/device-scripts-2026-10-15/`
——设备上当前生效的全部 `service.d` + `post-fs-data.d` 脚本与关键日志的**原样拷贝（md5 已逐一核对）**，
含每个文件的作用说明与恢复命令，见该目录的 `README.md`。

## 六、回退

- tailscale：`cp /data/local/tmp/m3note-tailscale.rev2.sh <service.d>/m3note-tailscale.sh`（旧版会再次堵链，仅作对照）
- `.bak`：`mv /data/local/tmp/m3note-tailscale.sh.bak.old <service.d>/m3note-tailscale.sh.bak`
- io-tuning 本身无风险：删掉 service.d 里的 `m3note-io-tuning.sh` 即回到 Flyme 默认值

---
*记录：ZCode · 2026-10-15 20:4x*

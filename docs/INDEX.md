# 文档索引

> **版本说明**：除 `CURRENT-STATE.md` 外，`docs/` 下的“当前”均指该文档写作时的状态。
> 当前设备为 **Flyme 8.0.0.0A / 内核 #3307**；旧文档中的 #7/#8/#27/#31/#32 等均为历史构建。
> 硬件修复的当前结论也以 `CURRENT-STATE.md` 为准；旧文档里的“未解决”可能已在后续内核修复
> （例如音量上键、光线/接近传感器、水平仪）。

## 当前状态

- [当前状态（2026-10-22）](CURRENT-STATE.md) — Flyme 8.0.0.0A、内核 #3307、Docker/SD64/Wi-Fi 服务器模式

## 设备与系统

- [设备总记录（历史，2026-10-14）](device-notes.md) — 解锁、分区、boot 结构、早期内核调试
- [解锁与系统恢复](device-notes.md) — frp 标志、TWRP、Format Data
- [Linux chroot（历史）](linux-chroot.md) — 在 Android 上跑 Ubuntu、sshd、Docker
- [遗留问题与修复方案（历史）](open-issues.md) — 早期硬件问题的分析与修复尝试
- [SSH 修复](ssh-repair.md) — `/run/sshd` 权限与开机脚本
- [Wi-Fi 服务器模式](wifi-server-mode.md) — 飞行模式 + Wi-Fi、zRAM 4 GiB
- [电池满电脚本](battery-full.md) — 把系统上报电量固定为 100%
- [SD 卡 Docker 迁移](sd64-migration.md) — 64 GB SD、UUID/CID 校验、开机挂载
- [Docker 启动失败修复](sd64-docker-fix.md) — 重启后 dockerd 未启动

## 内核与硬件

- [内核与 Docker 部署（历史）](kernel-and-docker.md) — #7 时期的内核、cgroup/namespace、刷写
- [触摸与灯光修复（历史）](touch-and-light.md) — #10–#20 的触摸、手电筒、背光
- [硬件修复状态](kernel/hardware-fix-status.md)
- [I2C 与传感器地址](kernel/i2c-sensors.md)
- [PA122 驱动与 I2C](kernel/pa122-driver-i2c.md)
- [service.d 串行阻塞](kernel/service-d-blocking.md)
- [声音/光线/接近传感器](kernel/audio-light-proximity.md)
- [屏幕 60 Hz 与 zram](kernel/display-60hz-zram.md)
- [硬件修复验证记录](kernel/hardware-fix-verification.md)
- [系统优化 T1（历史 #31）](kernel/system-optimization-t1.md)
- [系统优化 T2（历史 #32）](kernel/system-optimization-t2.md)
- [输入/Wi-Fi/传感器/CPU 诊断](kernel/input-wifi-sensor-cpu.md)
- [音量上键修复](kernel/volume-up-key.md)

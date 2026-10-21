> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# 屏幕 60 Hz 与 zram / swap

> **历史记录**：本文写于当时的构建阶段（#20–#32）；当前运行内核为 #3307。
> 硬件修复的当前结论见 [CURRENT-STATE.md](../CURRENT-STATE.md)。

用户要求暂时搁置前摄偏色，优先修复屏幕 54 Hz，并确认 zram / swap。

## zram / swap 已启用

实机 #20 的 `/proc/swaps` 只有 `/dev/block/zram0`，容量 1,425,100 KiB，使用量在首次读取时为 0 KiB，优先级 -1。`disksize=1459306496` 字节，即约 1,391.7 MiB / 1.36 GiB（十进制 1.46 GB）。它是压缩内存的逻辑容量，不是预留了同等大小的物理内存。

算法为 LZO，swappiness=65。已有成功写入：`orig_data_size=4096`、`compr_data_size=81`、`mem_used_total=12288` 字节；`pswpout=1`。这证明不仅有 zram 节点，swap 也实际启用。少量临时页可能释放，因此 `/proc/swaps` 当前使用量为 0 并不表示未启用。

系统 init 已运行一次性 enableswap 服务；服务退出后属性 `init.svc.enableswap=stopped` 是正常现象。`/enableswap.sh` 设置 disksize=0，由此内核的默认容量逻辑选择约可用 RAM 的一半，再执行 mkswap/swapon。未重复启用、重建或调整容量。

原始证据：`zram-swap-verification.txt`。

## 54 Hz 原因与临时测试

面板为 `r63350_fhd_dsi_vdo_tcl_sharp_nt50358_drv`，1080×1920，SYNC_PULSE_VDO_MODE。驱动配置 PLL=450 MHz；PanelMaster 读回同值。启动 DT 的 combined `atag,videolfb` 中 fps 为 0x152b=5419；独立 fps 属性虽然为 6000，但内核优先使用 combined tag。

因此内核 `lcm_fps=5419`，Android DisplayManager 报 54.190002 Hz，SurfaceFlinger nominal period=18453589 ns，既有帧时间间隔约 18.476 ms（约 54.12 Hz）。LFR 未启用，vsync_drop=0。不是单个应用掉帧计数。

通过现有 fbconfig PanelMaster ioctl 临时将 PLL 改到驱动已用的 500 MHz 配置；用户确认“画面正常，滑动正常”。debug dump 的 MIPITX Clock 字段从 448 到 494，这是只使用 PLL 整数高位的近似读数，不能把 494 当作精确物理时钟。

在暂时禁用显示 idle manager 的测量窗口，用 RDMA0 frame-start/end 硬件计数测得 60.21、60.23 Hz，underflow=0。测量后已恢复 idle manager。保留旧 HWC 模式时，SurfaceFlinger 仍按原 54.19 Hz 节奏调度，因此需同时修内核上报与实际时钟。

## #21 实现与验证计划

保持 #20 触摸、背光、双 LED、相机闪光、ST480 等修复，仅更改对应面板的 video PLL=500，以及该面板的 nominal fps=6000。LK 已初始化的 MIPITX 会被常规 DSI init 保留，所以在 primary display 初始化后复用既有 PanelMaster stop/config/start 事务完成一次 500 MHz 时钟交接，随后退出 PanelMaster 模式。面板参数同时覆盖熄屏/亮屏 resume。

`display_fix21.py` 保存两份源文件的 pre21 备份后修改，禁止重复应用。#21 已编译完成并临时启动成功：uname #21、sys.boot_completed=1、型号 m91。DisplayManager 报 60.000004 Hz，SurfaceFlinger nominal period=16666666 ns；kernel lcm_fps=6000，LFR/drop 均关闭，underflow=0。RDMA0 frame-start/end 实测两窗 60.02、60.08 Hz，测量后恢复 idle manager。证据：`display-fix21-frame-rate.txt`、`display-fix21-temporary-boot.txt`。正在等待用户完成画面、熄屏/亮屏、亮度、工具箱三档和水平仪回归反馈。

镜像 `boot-fix21-test.img` SHA256=`cb90eada5f7f39aec8016f3a476821e8c9c6655667ca9f414841553ef50b8f40`，保持原 header/DTB/Magisk ramdisk/其余区域不变，16 MiB。源码归档 `source-hardware-fix21.tar.gz` SHA256=`052f26d07d67da4dd04464377f0b6eb9f8b947f9fa5577be1cec2b7d86719ba1`。

已准备 `install_fix21.sh`：仅在 live boot 与 #20 哈希完全一致时写入 #21，写后读取整个启动分区验证哈希；写入失败或哈希不符自动恢复 #20，成功后才正常重启。#20 回退副本在 PC 和 `/data/local/tmp/boot-rollback-fix21.img` 中保留。

用户确认 #21 临时启动后的画面、熄屏/亮屏、亮度、工具箱手电筒三档和水平仪“全部正常”。随后 #21 已固化到启动分区；脚本回读哈希为 `cb90eada5f7f39aec8016f3a476821e8c9c6655667ca9f414841553ef50b8f40`，与 PC 镜像一致。

普通重启后的最终验证：uname `#21`，启动分区哈希仍为上述值；DisplayManager 仍报 `60.000004 Hz`；zram swap 仍为 `/dev/block/zram0`、`1425100 KiB`、LZO，当前 Used=0 KiB；zram 统计 `orig=4096`、`compressed=81`、`mem_used=12288` 字节；`msensor_type=1`，型号 `m91`。#20 回退镜像仍保留在 PC 与手机临时目录。

## #22：zram 容量增加并固化

用户要求增加 zram/swap。实测旧版 Magisk 的 `service.d` 不会自动执行，运行时手动 `swapoff`、重设 `disksize`、`mkswap`、`swapon` 可成功，但不适合作为唯一持久方案。因此将内核 `drivers/block/zram/zram_drv.h` 的 `default_disksize_perc_ram` 从 50 改为 70。该值由内核默认逻辑在 `enableswap.sh` 写入 `disksize=0` 时使用；本机 2,850,204 KiB RAM 对应逻辑容量 2,043,027,456 字节，`/proc/swaps` 显示可用容量 1,995,140 KiB（约 1.90 GiB）。zram 只按压缩后的实际页面消耗内存，不会预先占满逻辑容量。

实机临时 #22 验证：uname `#22`，swap 1,995,140 KiB、LZO、Used=0，屏幕仍报 60.000004 Hz，型号 m91、msensor_type=1。随后 #22 已写入启动分区；写入脚本以 #21 启动分区哈希为前置条件，完整回读哈希 `701a215d503d976c41212179919413ee8097a7a26c8dd324bcb905f2dcd68049` 与镜像一致，失败会自动恢复 #21。

普通重启后确认：uname `#22`，启动分区哈希仍为 `701a215d503d976c41212179919413ee8097a7a26c8dd324bcb905f2dcd68049`；`/proc/swaps` 为 `/dev/block/zram0`、1,995,140 KiB、Used=0、Priority=-1；`disksize=2043027456` 字节，算法 LZO；DisplayManager 仍为 60.000004 Hz。#21 回退镜像保留在 PC 和手机临时目录。

#22 镜像 SHA256=`701a215d503d976c41212179919413ee8097a7a26c8dd324bcb905f2dcd68049`；源码归档 `source-hardware-fix22.tar.gz` SHA256=`fb79db406ee0eba5bc21c767ed68c2e9d8911ffc1f1d29498c484a82fa69e2f8`。zram 默认改动源码归档已包含，辅助脚本 `m3note-zram-2g.sh` SHA256=`a241d5d5d460a8e8e9afcc93db0cfe6d3be5efa6bc440da822414e71c2535f49`。

> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# 音量上键修复方案（2026-10-15）

> **历史记录**：本文写于当时的构建阶段（#20–#32）；当前运行内核为 #3307。
> 硬件修复的当前结论见 [CURRENT-STATE.md](../CURRENT-STATE.md)。

> **结论修订：上键不是硬件损坏。** 开关与"开机检测通路"完好（可用"上键+电源"进官方恢复模式）；
> 问题出在**进入 Linux 之后**：上键所在的键盘列线 **GPIO104(KPCOL1)** 被 DTB 中遗留的**红外(IRTX)节点**占用，
> IRTX 驱动按 DTB 把它配成"普通 GPIO、输出低"，键盘控制器从此扫不到上键 → Android 里按上键完全无反应。

## 一、证据链（全部为实机/源码实测）

1. **运行时引脚实测**（`cat /sys/devices/virtual/misc/mtgpio/pin`；格式 `模式 上拉选择 输入 输出 上拉使能 方向 IES SMT`）：
   - `102:10001110` = MODE1(KROW0)，键盘模式 ✓
   - `103:11101010` = MODE1(KPCOL0)，输入+上拉、DIN=1，键盘模式 ✓（下键走 102×103，所以下键一直正常）
   - `104:01000110` = **普通 GPIO、输出、低电平** ← 与 DTB 红外 `en_def`（output-low）一致，被红外占用 ✗
   - `101:00001010` = 普通 GPIO、输入+下拉（KROW1，无占用者，默认态）
2. **引脚复用对照**（`arch/arm64/boot/dts/mt6755-pinfunc.h`）：`KROW1=GPIO101、KROW0=GPIO102、KPCOL0=GPIO103、KPCOL1=GPIO104`（与实测的 102/103 处于键盘模式吻合）。
3. **原机 DTB（stock.dts，未被改动）**：
   - `irtx@1100d000 { compatible="mediatek,irtx"; status="okay"; pinctrl-2=<irtx_gpio_en_def@gpio104>; }`
   - `irtx_gpio_en_def@gpio104 { pins=<0x6800>（GPIO104 功能0）; output-low; bias-disable; }`
4. **内核配置**：`CONFIG_MTK_IRTX_SUPPORT=y`（驱动内置）；该符号无其它配置 select（可以安全关闭）。
5. **系统侧**：`/dev/irtx` 每轮开机都被创建（驱动在跑）；魅蓝note3 无红外发射头 = DTB 遗留配置。
6. **行为学对照**：下键 7 次实测全链路正常（KP 中断 + 驱动打印 + evdev + 音量 19→0）；上键在 KP 层 0 中断、0 位变化；开机阶段（LK）配置齐全，故恢复模式组合键可用。
7. **已排除**：EVIOCGRAB 独占（探针显示 5 个输入设备全部自由）；键位表映射（hw0→114 下键 / hw1→115 上键，均正确）；驱动本身只写 `KP_EN`+`KP_DEBOUNCE`，不做扫描配置（3.10 参考版里的 KP_SEL 列配置仅在 LDVT 实验配置下编译，与量产无关）。

> 备注（推断等级说明）："上键=GPIO104"为由"2×2 键盘布局 + 引脚状态"推得的第一嫌疑（有明确占用者、状态吻合）；
> 备选是 GPIO101（无占用者）。**#28 的实机验证即是对该推断的直接判定**。另：KP 按下时出现的 8 位同发签名（0/9/18/27/36/45/54/63）是下键的正常硬件表现，其余 7 位未映射属正常。

## 二、修复（最小内核改动；脚本已备好）

构建编号 **#28**（#27 已被光线/接近传感器版本占用，勿混用）。

- **`project/kernel/build_fix28.sh`**（已写好）：
  1. `sed` 关闭 `CONFIG_MTK_IRTX_SUPPORT` → `olddefconfig` → **双重校验**（关掉失败或被重新打开则中止）；
  2. 与历次一致的工具链/INC 编译 `KBUILD_BUILD_VERSION=28`；
  3. 产出 `Image.gz-fix28` + `kernel-config-fix28`，日志在 `<BUILD_ROOT>/fix-20261015/build28.log`。
  运行方式（WSL）：`bash <PROJECT_ROOT>/project/kernel/build_fix28.sh`
- **`project/kernel/pack_fix28.py`**（已写好）：沿用 #25→#26 打包逻辑（原 header、Magisk ramdisk、内嵌 DTB 逐字节不动，仅替换内核段）；base 自动优先取 `boot-fix27-test.img`，否则回退 `boot-fix22-test.img`；输出 `boot-fix28-test.img` 并打印 SHA256。
  运行方式：在 `<PROJECT_ROOT>` 目录下 `python3 project/kernel/pack_fix28.py`

**执行前置条件**：确认主对话的 #27 构建/测试已结束、树空闲（无 `make` 在跑），再运行以上脚本。

## 三、验证与固化流程

1. `fastboot boot boot-fix28-test.img` 临时启动；`uname` 应为 `#28`。
2. **上键验证**：按音量上 → 音量条弹出、音量 +4；
   并复查 `grep 104 /sys/devices/virtual/misc/mtgpio/pin` → 应变为 **MODE=1 且输入+上拉**（不再被红外改掉）。
3. 回归检查：下键、mBack、电源、触摸、背光、手电筒（与 IRTX 无关，预期无影响）。
4. 通过后按既有惯例固化（写启动分区 + 整分区回读哈希校验，沿用 TWRP 写入流程）。

## 四、备选方案（不动内核）

- 开机后把 GPIO104 写回键盘模式的 Magisk `service.d` 小脚本（`echo -wmode 104 1` 等 4 条 sysfs 写；重启自动应用、随时删）。
- 若 #28 后上键仍无反应：复查 104 是否恢复 MODE1；若已恢复仍无效，再对比 LK 阶段配置（用 KP_MEM 寄存器快照继续定位，工具链已在侧对话验证可用）。

## 五、现场档案

- PC 证据存档：`project/kernel/volume-key-evidence/`（kmsg 驱动打印 / evdev 事件 / 中断记账 / 基线）。
- 设备侧残留（可留可删）：`/sdcard/volkey-evidence/`、`/sdcard/volkey_all*.log`、`/sdcard/kmsg_capture.log`。
- 本方案配套：`build_fix28.sh`、`pack_fix28.py`（同目录）。

---
*记录：2026-10-15 08:5x · 侧对话整理 · 执行前请确认构建树空闲，避免与 #27 流程并行冲突*

---

## 六、执行结果（2026-10-15 10:0x 补记）

**已执行完毕并通过引脚级验证。**

- **#28 已构建**：`build_fix28.sh` 现只做本方案（关闭 `CONFIG_MTK_IRTX_SUPPORT`，双重复核），
  并额外断言 i2c 驱动未被改动。配置与 #27 的 diff **只有** IRTX 这一行。
- 产物：`Image.gz-fix28`、`kernel-config-fix28`、`boot-fix28-test.img`
  SHA256 `43515f259e6cfe7352a683fd99a1cab098903ad3c23dfa616819cba3d7d93419`。
- **实机（fastboot RAM 启动）**：`#28` 正常启动（`boot_completed=1`，无循环/无 panic）。
- **引脚验证通过**：`104:11101010` —— MODE1 键盘列 + 输入 + 上拉 + DIN=1，
  与正常工作的 KPCOL0(`103:11101010`) 完全一致（修复前为 `01000110` = 普通 GPIO 输出低）。
  同时 `/dev/irtx` 不再出现、dmesg 无 IRTX、GPIO102/103 未受影响。
- **人工按键验证：已通过（用户实按确认）✅** 音量上键恢复正常（音量条出现、音量提升）。
  客观旁证：本机此前测得"上键在 KP 层 **0 中断**"，而修复后同一次 #28 启动中
  `mtk-kpd` 中断计数已从全 0 变为非 0（`196: 1 0 0 0 6 1 2 2`），即键盘控制器
  **确实收到了按键**；GPIO104 保持 `11101010`（MODE1 + 上拉）不再被改回普通 GPIO。
- **固化（写启动分区）已完成 ✅**（2026-10-15 16:5x）：按既有流程「基线哈希核对 → dd 写入 → 整分区回读校验 → 重启确认」执行，
  写入 `boot-fix30-test.img`（md5 `171769c9f101f8f0cc59207cfc13285b`），回读一致、重启后内核为 `#30`，
  当前启动分区内容即该镜像；脚本见 `project/kernel/flash-fix30.sh`（支持 `--rollback` 回退到 #22）。
  注：本次未遇到写保护问题，写入一次即生效。
- 另：本文档第一节关于 i2c 的"波及"判断已被新证据纠正，详见
  《i2c总线真相与传感器地址纠正-2026-10-15.md》——上键失效**只**由 IRTX 占用 GPIO104 引起。


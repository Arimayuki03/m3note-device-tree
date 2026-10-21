> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# 声音、光线、接近三项修复：缺失驱动（2026-10-15 下午）

> **历史记录**：本文写于当时的构建阶段（#20–#32）；当前运行内核为 #3307。
> 硬件修复的当前结论见 [CURRENT-STATE.md](../CURRENT-STATE.md)。

> 承接《i2c总线真相与传感器地址纠正-2026-10-15.md》。
> 本轮把三个问题**全部定位到"内核缺少厂商内核里已有的驱动"**，并已构建 **#29** 实机验证到寄存器/引脚级。

## 零、结论（TL;DR）

| 问题 | 根因 | 修复 | 验证状态 |
|---|---|---|---|
| **外放无声** | 内核**缺少 `aw8738` 功放驱动**。外放由 AWINIC **AW8738** 功放驱动，**Android 音频 HAL 通过 `/dev/aw8738` 的 ioctl 直接开功放**；本内核既无该驱动也无该节点，HAL 调不动功放 → PMIC lineout 有信号但功放不工作 → 静音 | 移植 aw8738 驱动（EN=GPIO100，ioctl `0x0703`/`0x0704`） | ✅ 驱动/节点/引脚全部与厂商内核一致（GPIO100 播放时拉高）；**待你听**
| **光线不工作** | 实装芯片是 **LTR-579 @ i2c-1 0x53**，而树里只有 **PA122**（0x1e，本机无此芯片）。厂商内核里有 `ltr579` 驱动，本内核没有 | 移植 `ltr579` 驱动（绑定节点 + 地址用板级 0x53） | ✅ 芯片寄存器与驱动读数**逐寄存器一致** |
| **接近不工作** | 同上（光线/接近是**同一颗** LTR-579） | 同上 | ✅ PS 读数与芯片 PS_DATA 寄存器一致 |

回归项全部保持：音量上键（GPIO104 仍为 MODE1 键盘列）、`/dev/irtx` 不存在、i2c 无 wedge、无 panic。

---

## 一、本轮的关键方法论：直接与**厂商内核**对答案

上一轮之所以能定位 i2c 真相，是因为拿到了"原机启动镜像"作基准。本轮把这个方法用到底：

1. 从 `<ARTIFACTS>/boot-orig.img` 解出**原厂 Flyme8 内核**
   （`Linux version 3.18.35+ (flyme@mz-builder-9) #1 SMP PREEMPT Wed Sep 23 11:55:40 CST 2020`）。
2. **`fastboot boot boot-orig.img` 临时启动原厂内核**（RAM 启动，不动启动分区），
   并且发现该镜像里**自带可用的 `su`：`su 0 <命令>` 即 root** → 于是可以在原厂内核上做各种只读对比。
3. 在原厂内核上直接观察"正常工作时长什么样"，再与我们的内核逐项比对。

> 这一步是本轮所有结论的来源。**凡是"某功能不工作"，先问：原厂内核里它是怎么工作的？**

---

## 二、外放无声：缺 `aw8738` 功放驱动

### 2.1 证据链

**(a) 我们的内核：数字链路完全正常，卡在功放**

- `dumpsys media.audio_flinger`：输出线程正常、`writeErrors=0`，`Output device: SPEAKER`；
- 播放时 `pcm8p` 处于 **RUNNING**，AFE 的 DL 使能（`AFE_UL_DL_CON0 = 0x1`）；
- PMIC 模拟部分**完全按"外放播放"配置**（debugfs `/sys/kernel/debug/mtksocanaaudio` 实测）：
  `AUDDEC_ANA_CON3 = 0x4234`（LO MUX→DAC、LOL 使能）、`CON_A9 = 0xA255`、`CON_A10 = 0x0100`（capless LDO 1.6V）、`CON0 = 0xe009`（Audio DAC 使能）
  —— 与 `Speaker_Amp_Change()` 源码里写的期望值**逐条吻合**；
- 内核侧还驱动了 GPIO118（codec 的 "extamp"）——**但没有声音**。

**(b) 原厂内核：同样播放时，日志里出现一个我们完全没有的东西**

```
[46.375191] (7)[783:AudioOut_D] aw8738+aw8738_ops_open
[46.375227] (7)[783:AudioOut_D] aw8738+aw8738_ops_ioctl, cmd = 1795, arg = 4
[46.375237] (7)[783:AudioOut_D] aw8738+aw8738_set_mode mode 4
[50.604164] (7)[783:AudioOut_D] aw8738+aw8738_ops_ioctl, cmd = 1796, arg = 5
[50.604181] (7)[783:AudioOut_D] aw8738+aw8738_set_mode mode 5
```

即：**音频 HAL（AudioOut_D 线程）直接打开 `/dev/aw8738` 并用 ioctl 开/关外放功放**，模式号 = 脉冲数（4=外放模式，5=关闭）。

**(c) 双方对照**

| | 原厂内核 | 本内核（#28 及之前） |
|---|---|---|
| `/dev/aw8738` | `crw-rw---- media media 243,0` | **不存在** |
| `/proc/devices` | `243 aw8738` | **无** |
| 内核二进制里 "aw8738" 字符串 | 36 处 | **0 处** |
| 播放时 GPIO100 | `00110110`（拉高） | `00000110`（一直低） |

**(d) 系统侧早就为它准备好了**

- ramdisk 的 `/ueventd.mt6755.rc` 第 50-51 行：
  `/dev/aw8738               0660   media      media`；
- sepolicy 里已有 `u:object_r:aw8738_device:s0` + `/dev/aw8738(/.*)?` 标签；
- 设备树有它的节点：`ext_pa_aw8738 { compatible = "mediatek,aw8738-pa"; pinctrl-names = "default","en_pin"; }`，
  其使能脚 `papins@0 { pins = <0x6400>; output-high; }` → **0x6400>>8 = GPIO100**。

**⇒ 结论：不是音频配置错，是内核根本没有这个功放驱动。**

### 2.2 修复

新增 `drivers/misc/mediatek/aw8738/`（`aw8738.c` + Kconfig + Makefile，`CONFIG_MTK_AW8738=y`），
以厂商 3.10 树里的兄弟驱动 `aw8737.c`（同一协议：`_IOC(_IOC_NONE,0x07,0x03/0x04,0)`、
EN 脚按模式号发脉冲、`CLOSE` 拉低）为模板，要点：

- **设备名必须是 `aw8738`**（chrdev 区/class/device 同名），这样 ueventd 才会按上面的规则建出
  `/dev/aw8738 media:media 0660`；
- **EN = GPIO100**，用 3.18 的 `mt_set_gpio_mode/dir/out`（`GPIO100|0x80000000` 的写法沿用原厂，
  因为 3.18 的 `mt_gpio_pin_decrypt()` 认这个标志位）；
- 用 **DT 绑定**（`.of_match_table = {"mediatek,aw8738-pa"}`）挂到已有设备树节点，不再手工注册 platform_device；
- 保留 ioctl 语义与脉冲时序（1ms 复位 → n×(2us 低/2us 高) → 45ms 建立；CLOSE 拉低+1ms）。

### 2.3 实机结果（#29）

```
/dev/aw8738          crw-rw---- media media 242,0     ← 与原厂一致（动态主设备号不同不影响）
/proc/devices        242 aw8738
/sys/class/aw8738/aw8738
播放中 GPIO100        00110110                        ← 与原厂内核完全相同
播放中 pcm8p          RUNNING
```

**⇒ 功放已被 HAL 正常打开。是否真的出声，只差你听一下**（我已在设备上循环播放铃声）。

**补充（更强的证据）**：打开该驱动的 dynamic debug 后，播放时报文与原厂内核**逐字段一致**：

```
我们的 #29： (1)[836:AudioOut_D][name:aw8738&]aw8738: +aw8738_ops_ioctl, cmd = 1795, arg = 4
             (1)[836:AudioOut_D][name:aw8738&]aw8738: +aw8738_set_mode mode 4
原厂内核：   (7)[783:AudioOut_D]aw8738+aw8738_ops_ioctl, cmd = 1795, arg = 4
             (7)[783:AudioOut_D]aw8738+aw8738_set_mode mode 4
```

即：同一个 `AudioOut_D` 线程、同一个 ioctl 号、同一个模式号 4（= 4 个使能脉冲 → 外放模式）。
软件侧已与原厂完全对齐，剩下只有"是否真的出声"需要耳朵确认。

---

## 三、光线/接近：装的是 LTR-579，树里却是 PA122

### 3.1 证据链

- **设备树（本机自带）**：`cust_alsps@0 { compatible = "mediatek,ltr579"; i2c_num=<1>; i2c_addr=<0x53>; ... }`
  （`cust_alsps@1` 才是 pa122@0x1e，属另一批次）。
- **硬件实测**：0x53 有应答，0x1e / 0x60 都无应答；0x53 的 `PART_ID(0x06) = 0xb1`，寄存器布局与 LTR-579 一致。
- **内核对照**：原厂内核对 `ltr579` 有 8 处字符串，本内核 **0 处**；原厂内核里
  `ltr579` 驱动**绑定在 `1-0060`**（即设备树的通用节点 `alsps@60 { compatible="mediatek,alsps" }`），
  而实际芯片流量走**板级地址 0x53**（驱动用自己的 `write_addr`，与 3.10 驱动源码一致）。
- 原厂内核上可直接读到工作值：`als = 0x000C(12)`、`ps = 0x0067(103)`，
  且其 `alslv`/`alsval` 表与本机 DTB 的 `als_level`/`als_value` **完全一致**。

### 3.2 修复

从 3.10 树移植 `drivers/misc/mediatek/alsps/ltr579/`（`ltr579.c/h` + Kconfig + Makefile，`CONFIG_MTK_LTR579=y`），
照本树里已完成的 **PA122 移植**逐项改写（EINT 改 pinctrl + `"mediatek, als-eint"` + `irq_of_parse_and_map`、
去掉 mach/cust_eint 头、`hwPowerOn/Down` 改 no-op、`-Werror` 逐条清理）。关键两点：

- **绑定**：`of_match_table = {"mediatek,alsps"}` → 挂到 `alsps@60` 通用节点（与原厂内核一致）；
  在 probe 里 **`client->addr = hw->i2c_addr[0]`（= 0x53，来自板级数据）**，芯片流量落在真实地址上。
- **板级数据**：`get_alsps_dts_func("mediatek,ltr579", &内置默认)`，取不到 DT 时用内置默认（总线 1、地址 0x53、与本机 DTB 相同的 als 表与 PS 阈值）。

### 3.3 实机结果（#29）——逐寄存器对齐

```
驱动绑定：/sys/bus/i2c/devices/1-0060/driver -> .../drivers/LTR_579ALS   ← 与原厂同构
驱动读数：als=0x0002   ps=0x0064
芯片实测（同一时刻直读 0x53）：
  reg 0x0D/0x0E/0x0F = 02 00 00  → ALS = 0x0002   ← 与驱动一致 ✅
  reg 0x08/0x09      = 64 00     → PS  = 0x0064   ← 与驱动一致 ✅
  reg 0x06           = b1        → PART_ID（LTR-579）
```

同时 `dmesg` 里能看到系统服务 **`AALLightSensor` 每 200ms 调一次 `ltr579_als_operate`**（自动亮度在用这颗光感），
`dumpsys sensorservice` 里 `MTK Light` / `MTK Proximity` 均处于 running。

**⇒ 待你物理确认**：用手遮住屏幕上方（听筒左侧）→ 光感数值应下降、接近应跳到"near"（通话时屏幕自动熄灭）；
屏幕自动亮度勾选后应随光线变化。

> 备注（次要）：日志里每 200ms 有一条 `<ALS/PS> alsps_aal_get_data: aal:get_data not exsit`，
> 是 AAL（自适应背光）自身的回调未注册。它不影响传感器数据本身（数据已逐寄存器验证），
> 若要一并消除需再看 AAL 驱动是否在我们的配置里缺失——留待下一轮。

---

## 三·补、第二层缺口：驱动没向 alsps 框架注册（#30 修复）

上面"逐寄存器一致"只证明**驱动把芯片读对了**，但数据并没有到 Android。原因是本项目 3.18 框架要求
**每个 alsps 驱动自己向框架注册 control / data 路径**，而 3.10 版的 ltr579 驱动（移植来源）根本没有这套注册
（它只用 `hwmsen_attach`）。缺了它会连锁三件事：

1. `alsps.c: als_work_func()` 开头 `if (NULL == cxt->als_data.get_data) return;` —— **框架直接放弃轮询**，
   也就不会调用 `als_data_report()` 把数据推到 `m_alsps_input` 输入设备 → **Android 层的光线传感器收不到任何事件**（接近同理）；
2. `alsps.c: alsps_aal_get_data()` 失败 → 内核 AAL（自适应背光）拿不到光感值，每 200ms 刷一条
   `aal:get_data not exsit`；
3. `/dev/m_alsps_misc` **根本没有被创建**——它是在 `als_register_control_path()` 里 `alsps_misc_init()` 时才建的
   （源码注释：*add misc dev for sensor hal control cmd*），也就是**传感器 HAL 的控制通道**。

**修复（#30）**：在 ltr579 的 probe 里补上四件注册
（`als_register_control_path` / `als_register_data_path` / `ps_register_control_path` / `ps_register_data_path`），
回调包装驱动内部已有的 `ltr579_als_enable/disable/read`、`ltr579_ps_enable/disable/read`；
另外发现 **PS 中断模式下还缺一次上报**：`ltr579_eint_work()` 只调了 `hwmsen_get_interrupt_data()`，
需要像本树原生 `cm36686.c` 那样**再调 `ps_report_interrupt_data(intr_flag)`**（已补）。

> 教训记录：最初参考 `pa122` 的注册块，后来核对发现 **pa122 那段是死代码**
> （在 `#ifdef OLD_ARCH` 里，而 pa122 只定义 `NEW_ARCH`），于是改以本树**原生在用**的
> `cm36686-new` 为模板，并按 `alsps.c` 的注册校验（`set_delay/open_report_data/enable_nodata/get_data`
> 必须非空）确认契约。**不要盲抄兄弟驱动，先确认它真的在执行。**

几个按板级数据设置的标志：`is_polling_mode = polling_mode_als(1) / polling_mode_ps(0)`、
`is_support_batch = false`（本驱动无 FIFO/批量通路，声明支持会让框架停止轮询）、
`vender_div = 1`（该值不下除、只是给 HAL 的缩放提示；本驱动上报的就是 lux 量级，
原生驱动用 100 是因为它们的原始计数是 lux 的 100 倍）。

---

## 四、产物与设备状态

### 4.1 #30 实机验证结果（三项全部通过）

`boot-fix30-test.img`（含 aw8738 + ltr579 + 框架注册）实机验证：

| 检查项 | 实测 | 结论 |
|---|---|---|
| 版本 | `#30 SMP PREEMPT ... 16:30` | ✅ 启动正常、无 panic |
| **外放功放** | `/dev/aw8738` = `media media 0660`；播放时 `ioctl 1795 arg 4 → set_mode 4`（与原厂逐字段一致）；GPIO100 拉高 | ✅ 软件链路与原厂完全一致 |
| **光线（HAL 层）** | 临时打开自动亮度后 `dumpsys sensorservice` 出现 **`MTK Light: last 10 events`**，值 10.00 / 9.00…（与驱动 `als=0x000A→0x0009` 一致且会变化） | ✅ 端到端打通（验证后已把自动亮度改回原值 0） |
| **接近（HAL 层）** | **`MTK Proximity: last 1 events` 值 1.00**（与原厂内核同样形式） | ✅ 上报正常（遮住应变 0.00=near） |
| HAL 控制通道 | `/dev/m_alsps_misc` 已创建 | ✅ 注册生效 |
| AAL 报错 | `get_data not exsit` 计数 **0**（#29 时为 5 条/秒） | ✅ 自适应背光拿到数据 |
| 音量上键回归 | GPIO104 `11101010`（MODE1 键盘列） | ✅ 未受影响 |
| i2c / 稳定性 | `Adapter is busy` = 0；`panic|BUG` = 0 | ✅ |

> 仍未做的是**纯物理确认**：外放是否真的出声（耳朵）、手遮住上方时接近是否变 near / 光感是否下降。

### 4.1b 用户实测确认（2026-10-15 16:5x）

**用户实机确认：三项全部正常**——外放出声正常；光线/接近正常；**耳机音量与调节也正常**
（这一条同时**实测否定了上一条"缺 5 个耳机校准控件"的顾虑**：它们在实机上确实无害，无需补）。

至此本轮三项目标全部闭环：定位 → 修复 → 实机验证 → 用户确认。

**附带核查（音频残余差异）**：与原厂内核对比 mixer 控件名，本内核缺 5 个且都与耳机有关
（`Audio_HpSpkl_Offset_Get/Set`、`Audio_HpSpkr_Offset_Get/Set`、`Audio_always_hd_Switch`）。
它们用于耳机输出偏移/校准，**不是外放通路**；实测音频 HAL 在 logcat 里**没有任何找不到控件的报错**，
故判定对本次三项问题无影响（若将来耳机音量/偏移异常，再回来补这几个控件）。

### 4.2 产物

- 构建 **#30**：`Image.gz-fix30`、`kernel-config-fix30`、`boot-fix30-test.img`
  SHA256 `fa49d0fedf38fe21bd57bcaa903f7d763b7dd3b80c5eef94bb625852f2e7d177`
  （对象：`boot-fix29-test.img`，`build_fix30.sh` 前置断言含四项修复 + 框架注册）
- 上一版 **#29**：`boot-fix29-test.img` SHA256 `611f8b26d2f4294ba129a2ee7822e2a7697d67b5acecb8ef0d25c1519568c9b7`
- 新增源码：`drivers/misc/mediatek/aw8738/`、`drivers/misc/mediatek/alsps/ltr579/`
  （+ `drivers/misc/mediatek/{Kconfig,Makefile}` 与 `alsps/{Kconfig,Makefile}` 各加一行）
- 配置：`CONFIG_MTK_AW8738=y`、`CONFIG_MTK_LTR579=y`、`CONFIG_MTK_IRTX_SUPPORT` 关闭、`CONFIG_MTK_PA12200001=y`（保留，本机无 0x1e 芯片，不绑定、无害）
- 当时设备以 **#31 固化运行**（写入启动分区、整分区回读校验通过；历史）。
  **⚠ 刷写前提**：启动分区**只在设备由 `fastboot boot`（RAM 启动）时接受写入**，
  从分区正常启动时写入会被静默丢弃（2026-10-15 傍晚复现并定案；详见
  《系统优化T1-2026-10-15.md》第四节）。通用刷写脚本：`kernel/scripts/flash-boot.sh`
  （基线校验→现场 dump 作回滚→写入→drop_caches 后回读→自动回滚→重启确认）。
  回退示例：先 `fastboot boot boot-fix30-test.img`，再 `bash flash-boot.sh .../boot-fix30-test.img`。

---
*记录：2026-10-15 16:4x · 方法：与厂商内核逐项对照（RAM 启动原厂镜像 + `su 0` 取证）*


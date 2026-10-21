> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# i2c-1 真相、传感器地址纠正与音量上键 #28 执行结果（2026-10-15 上午）

> **历史记录**：本文写于当时的构建阶段（#20–#32）；当前运行内核为 #3307。
> 硬件修复的当前结论见 [CURRENT-STATE.md](../CURRENT-STATE.md)。

> 承接《音量上键修复方案-2026-10-15.md》《PA122 光线/接近驱动移植与 i2c 总线问题-2026-10-15.md》。
> 本文纠正了前一份文档中**关于 i2c-1 的两处关键判断**，并给出实机复核结果。

## 零、三条结论（TL;DR）

1. **i2c-1 总线本身没有故障。** 所谓"第一次成功、之后全部 EINVAL、2 秒不恢复"是**用户态工具的结构体布局错误**造成的：
   本内核开了 `CONFIG_MTK_I2C_EXTENSION`，内核里的 `struct i2c_msg` 是 **24 字节**（多了 `timing`/`ext_flag`），
   而用户态按标准 16 字节布局传参 → 内核把**下一条消息的头 8 字节**当成 MTK 扩展标志读 → 解析出垃圾 `ext_flag`
   （含 3D-CAMERA 位）→ 适配器被"挂起"（`g_i2c[]`），此后**所有**传输（内核态/用户态）都以
   `mt-i2cN: Current I2C Adapter is busy` 失败。**用 24 字节布局即完全正常。**
2. **光线/接近芯片不是 PA122，而是 LTR-579（0x53）。** DTB 里 `cust_alsps@0 = ltr579@0x53`、
   `cust_alsps@1 = pa122@0x1e` 是**两个批次**的条目；本机实测 **0x53 有应答、0x1e 完全无应答**。
   上一轮把 PA122 驱动移植过来，方向选错了（详见第四节）。
3. **音量上键修复已在 #28 落地并实机验证到引脚层**：`#28` 正常启动，GPIO104 从
   `01000110`（普通 GPIO 输出低，被红外占用）变回 `11101010`（MODE1 键盘列 + 上拉，与正常工作的
   KPCOL0/GPIO103 完全一致），`/dev/irtx` 不再出现。**只差"人手按一下音量上键"的最终确认。**

---

## 一、i2c-1 "异常"的真正根因（用户态结构体布局）

### 1.1 现役驱动与内核结构体

- 现役驱动是 `drivers/misc/mediatek/i2c/mt6755/i2c.c`（平台驱动名 `mt-i2c`），
  **不是** `drivers/i2c/busses/i2c-mtk.c`（后者 of_match 只匹配 mt6735/6797/6757/elbrus，本机根本没绑定）。
  运行时可确认：`/sys/bus/platform/devices/11008000.i2c/driver -> .../drivers/mt-i2c`。
- `CONFIG_MTK_I2C_EXTENSION=y` 时，`include/uapi/linux/i2c.h` 里的结构体被扩展：

```c
struct i2c_msg {                    /* 内核态：24 字节 */
        __u16 addr; __u16 flags; __u16 len; __u8 *buf;
        __u32 timing;               /* MTK: 速率(kHz)/模式 */
        __u32 ext_flag;             /* MTK: WRRD / HS / DMA / 3D-CAMERA ... */
};
```

- 而 `drivers/i2c/i2c-dev.c` 的 `I2C_RDWR` 处理是 `memdup_user(msgs, nmsgs * sizeof(struct i2c_msg))`
  ——内核按 **24 字节/条** 从用户区拷贝。用户态若按标准 16 字节布局传，内核就会读到**越界 8 字节**。

### 1.2 越界读到的垃圾如何把总线搞死

`_i2c_translate_msg()` 直接使用 `msg->timing` / `msg->ext_flag`：

| 垃圾位 | 后果 |
|---|---|
| `I2C_3DCAMERA_FLAG`（3D 相机）| 适配器地址被记入 `g_i2c[0..1]` 并**直接返回**；此后任何传输都被 `i2c.c:1014/1139` 判为 `Current I2C Adapter is busy` → `-EINVAL_I2C`(=EINVAL)。**只有 `mt_wait4_i2c_complete()` 会清，而它只在 3D 相机流程里被调用**→ 一次踩中就基本到重启为止 |
| `timing` 高 16 位非 0 且过大 | `i2c_set_speed()` 判 `khz > 400`(FS) → EINVAL |
| `I2C_DMA_FLAG` | `virt_addr_valid(ptr)` 检查失败 → EINVAL |

对应实机证据（#22 上，内核态线程也在报）：

```
[ 3149.119904] (4)[223:bat_routine_thr]ERROR,1014: mt-i2c1: Current I2C Adapter is busy.
[ 3150.519767] (4)[1232:system_server]ERROR,1014: mt-i2c1: Current I2C Adapter is busy.
```

用 16 字节布局的工具复现（`project/kernel/i2c_probe*`）：

```
== trace bus 1 addr 0x1e
  I2C_FUNCS -> 0 OK  funcs=0x0eff0009
  SMBUS byte-data read -> -22 EINVAL
  RDWR read1 -> -22 EINVAL
  RDWR wr+rd1 -> -14 EFAULT
```

（`dt=0ms`：参数层就被拒，根本没上总线；`EFAULT` 来自后续 `copy_to_user`。）

### 1.3 正确的用户态做法 → 总线立刻正常

把用户态结构体改成与内核一致（`timing=0, ext_flag=0`），同一条总线、同一个地址段：

```
0x0d:  -> 2 OK data=02        ← 指南针 AKM09911（DTB: cust_mag）
0x53:  -> 2 OK data=01        ← 光线/接近（见第四节）
0x69:  -> 2 OK data=b9        ← G-sensor
```

并且整轮探测后 `dmesg | grep -c "Adapter is busy"` = **0**，说明**没有再踩挂适配器**。

> 工具与源码：`project/kernel/i2c_probe3.c`（24 字节布局，freestanding 静态编译，随包提供）、
> `project/kernel/i2c_probe_nostdlib.c` / `i2c_probe2.c`（16 字节布局，用于复现问题）。
> 编译方式见第七节。

### 1.4 i2c-1 上"实际存在"的器件（写寄存器+读 1 字节实测）

| 地址 | DTB 期望 | 实测 |
|---|---|---|
| 0x0d | cust_mag = akm09911 | ✅ 应答 (0x02) |
| 0x53 | cust_alsps@0 = ltr579 | ✅ 应答 (0x01) |
| 0x69 | gsensor / accel | ✅ 应答 (0xb9) |
| 0x1e | alsps_pa122 | ❌ 无应答 |
| 0x60 | alsps(其它批次) | ❌ 无应答 |
| 0x68 | icm20608 gyro | ❌ 无应答 |
| 0x2e / 0x77 / 0x6b / 0x75 / 0x30 / 0x10 / 0x55 / 0x63 / 0x0c | msensor/气压/充电器/ext buck/strobe/camera… | ❌ 无应答 |

（0x6b 的充电器/`SWITHING_CHARGER` 驱动持续报 `I2C_ACKERR`，即该地址确实无芯片响应——
属于 DTB 里另一批次的遗留条目，与总线无关。）

### 1.5 一次失败的内核改动（重要教训，已回滚）

曾按"内核 vs 驱动结构体不匹配"的思路把

```c
.master_xfer = (pmaster_xfer)mtk_i2c_transfer,   /* 走 struct mt_i2c_msg */
```

改成 `.master_xfer = standard_i2c_transfer`。**这个改动是错的**：内核态调用方（i2c-core、各驱动）
用的正是扩展后的 24 字节 `struct i2c_msg`，与 `struct mt_i2c_msg` 布局一致，本来就自洽；
改成 standard 路径后 `msg_ext.ext_flag = 0; msg_ext.timing = i2c->default_speed;`
（`#else` 分支，`COMPATIBLE_WITH_AOSP` 未定义）**把 MTK 扩展标志全部丢掉**，
于是 mt6311 的 `I2C_WR_FLAG`(写后读) + `timing=3400`(HS) 传输被当成普通写 → 外部 buck 探测失败：

```
[    1.112813] [Power/cpufreq] [ERROR]get_cur_volt_extbuck(), can not use ext buck!
[    1.112826] BUG: failure at .../mt_cpufreq.c:3346/__set_cpuhvfs_init_sta()!
[    1.112842] Unable to handle kernel paging request at virtual address ffffff7fffffdead
[    3.172097] Kernel panic - not syncing: Fatal exception
```

→ 启动 1.1 秒即 panic、随后 LK 回落到正常分区（`/proc/last_kmsg` 已存档：
`project/kernel/last_kmsg-fix28-attempt.txt`）。**已完整回滚**（`git` 不适用，用逐处 Edit 反向改回，
已核验 `#ifndef CONFIG_MTK_I2C_EXTENSION` 与 `master_xfer = (pmaster_xfer)mtk_i2c_transfer` 均恢复原状，
`System.map` 中 `standard_i2c_*` 符号数 = 0、`mtk_i2c_transfer` 存在）。

**结论：mt6755 i2c 驱动保持原样，不要动 `master_xfer`。**

---

## 二、音量上键修复：构建 #28 与实机结果

- `build_fix28.sh` 已更新为**只做音量上键这一项**（关闭 `CONFIG_MTK_IRTX_SUPPORT`，双重复核），
  并在构建前**断言 i2c 驱动未被改动**（防止误带上一节的实验改动）。
- 产物：`Image.gz-fix28`、`kernel-config-fix28`、`boot-fix28-test.img`
  SHA256 `43515f259e6cfe7352a683fd99a1cab098903ad3c23dfa616819cba3d7d93419`。
- 配置差异（与 #27 逐行 diff）：**只有**
  `CONFIG_MTK_IRTX_SUPPORT=y` → `# CONFIG_MTK_IRTX_SUPPORT is not set`；
  `CONFIG_MTK_PA12200001=y` 等既有项均保留。
- `fastboot boot boot-fix28-test.img` 实机结果：

| 检查项 | #28 实测 | 结论 |
|---|---|---|
| 启动 | `sys.boot_completed=1`，`Linux version 3.18.35 ... #28` | ✅ 不循环、不 panic |
| GPIO104 | `104:11101010`（MODE1 + 输入 + 上拉 + DIN=1）| ✅ 与 KPCOL0(103) 完全一致，回到键盘列 |
| GPIO102/103 | `102:10001110` / `103:11101010`（未变化）| ✅ 回归无影响 |
| `/dev/irtx` | 不存在；dmesg 无 IRTX 信息 | ✅ 驱动已不加载 |
| mtk-kpd 中断 | `196: ... GIC 196 mtk-kpd` 已注册 | ✅ |
| i2c 回归 | `Adapter is busy` = 0；0x0d/0x53/0x69 正常应答 | ✅ 与 IRTX 无关，未被影响 |

**实按验证：已通过 ✅** —— 用户实按音量上键，音量正常提升。旁证：修复后 `mtk-kpd`
中断计数由全 0 变为非 0（`196: 1 0 0 0 6 1 2 2`），即键盘控制器确实收键；GPIO104 仍为
`11101010`（MODE1 + 上拉）。**启动分区未写**，重启会回到 #22，需固化时走既有 TWRP 流程。

---

## 三、传感器地址纠正：光线/接近是 LTR-579@0x53，不是 PA122@0x1e

### 3.1 证据

1. **DTB（未改动、三份 boot 一致）**：
   ```
   cust_alsps@0 { compatible = "mediatek,ltr579"; i2c_addr = <0x53 ...>; }   ← 本机批次
   cust_alsps@1 { compatible = "mediatek,pa122";  i2c_addr = <0x1e ...>; }   ← 另一批次
   ```
   两条的 `als_level`/`als_value`/`ps_threshold` 表**完全相同**——即校准数据一致，只是芯片不同。
2. **实测**：0x53 有稳定应答；0x1e 在写、写后读两种模式下**都无应答**（ACKERR）。
3. **寄存器指纹（0x53）**：`00=01 01=36 02=20 03=5a 04=31 05=04 06=b1 07=29/01
   09=00 0a=24 0b=00 0c=00 0d=07 0e=00 0f=00`，其中 0x0a 附近为阈值/数据寄存器，
   与 LTR-5xx 系列布局基本吻合。
4. **驱动有无**：3.18 树里 `drivers/misc/mediatek/alsps/` **没有 ltr579**（只有 pa12200001、
   cm36558/cm36652/cm36686、APDS9930、EPL2182、stk3x1x）；
   而 **3.10 参考树 `m681-master` 里恰好有 `alsps/ltr579`** —— 与本批次"血脉"一致。
5. 上一轮判 PA122 的依据是"原厂内核二进制里 `pa122` 出现 72 次、`cm36686` 为 0"，
   但**字符串计数不能替代芯片应答**：本机 0x1e 无应答，说明 PA122 不在这条总线上。

### 3.2 建议的下一步（供决策）

- **移植 3.10 树的 `alsps/ltr579` 驱动到 3.18**（方法与 PA122 那次完全相同：去掉
  `i2c_register_board_info`、补 `of_match_table`、EINT 改 pinctrl+`irq_of_parse_and_map`、
  去掉 mach 头文件），配置 `CONFIG_MTK_LTR579`（或对应符号），
  并把 alsps 的板级选择从 "pa122/0x1e" 切到 "ltr579/0x53"。
- 已移植的 **PA122 驱动可以保留但不生效**（0x1e 无器件，绑定会失败，属无害）。
- 校准表可直接沿用 DTB 里 `cust_alsps@0` 的 `als_level/als_value`（反正两条一致）。

> 注：本次未改动任何 alsps 代码；第四节只做总线与地址的复核。

---

## 四、可复用的用户态 i2c 工具（本项目自用）

因为内核是 24 字节布局，**标准 i2c-tools 在本机会得到 EINVAL 甚至挂死总线**，
所以自备了静态工具（无 libc，直接用 `svc` 系统调用，交叉编译自内核工具链）：

```
# 编译（WSL）
cd <PROJECT_ROOT>/project/kernel
<BUILD_ROOT>/toolchain/bin/aarch64-linux-android-gcc \
  -static -nostdlib -O2 -fno-stack-protector -ffreestanding \
  -o i2c_probe3 i2c_probe3.c i2c_probe_start.S -lgcc

# 设备上使用
adb push i2c_probe3 /data/local/tmp/ && adb shell su -c "chmod 755 /data/local/tmp/i2c_probe3"
i2c_probe3 funcs 1
i2c_probe3 rdwr 1 53 00 1 1      # 写寄存器 0x00 再读 1 字节
i2c_probe3 wrd  1 53 00 01 1     # 写 2 字节
i2c_probe3 rd   1 53 1 1         # 纯读（注意：很多芯片会 NACK 这种无寄存器地址的读）
i2c_probe3 scan 1
```

说明：输出里 `-> 2 OK` 表示 2 条消息全部发送成功（成功时返回值是**消息条数**，不是数据）；
负值才是 errno。`i2c_probe2.c`（16 字节布局）保留用于复现上文的问题。

---

## 五、设备与文件现状

- 设备当前：`#28`（RAM 启动）运行中；**启动分区未改动**，重启即回 #22。
- 新增/更新文件：
  - `project/kernel/build_fix28.sh`（只含音量上键修复 + i2c 未改动断言）
  - `project/kernel/pack_fix28.py`（未变）
  - `project/kernel/Image.gz-fix28` / `kernel-config-fix28`
  - `project/m3note-backup/boot-fix28-test.img`（SHA256 见第二节）
  - `project/kernel/i2c_probe3.c` + `i2c_probe3`（正确布局工具）
  - `project/kernel/i2c_probe_nostdlib.c` / `i2c_probe2.c` / `i2c_probe_start.S`（复现用）
  - `project/kernel/last_kmsg-fix28-attempt.txt`（失败实验的 panic 现场）
  - `project/kernel/i2c-busy-evidence-2026-10-15.txt`（"Adapter is busy" 证据）
  - `project/kernel/i2c-verification-fix28-2026-10-15.txt`（#28 复核记录）

---
*记录：ZCode · 2026-10-15 10:2x · 内核树现处于"仅音量上键修复"状态，可安全继续构建*

> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# 遗留问题与修复方案（2026-10-15 凌晨）

> **历史记录**：部分问题已在后续内核中修复。当前状态见 [CURRENT-STATE.md](CURRENT-STATE.md)。

> 后续实机证据已纠正本文部分结论：桌面点击存在 Protocol A 抬手/压力轴问题；手电筒底层芯片也不匹配；通用 PWM 匹配方案不适用于原机设备树。最新修改与验证见《桌面触摸与灯光修复-2026-10-15.md》，不要直接照本文方案刷写。

> 承接《内核修复与Docker部署-2026-10-14.md》。
> 当时内核 **#8**（触摸 config1 版）已刷入并在运行（历史）。

## 零、最重要的方法论结论（本夜重大发现）

**魅蓝 note3 有两个硬件批次，本机属于"早期批次"：**

| 部件 | 本机（早期批次）| 另一批次 |
|---|---|---|
| 屏幕面板 | **r63350_fhd_dsi_vdo_tcl_sharp**（已修复✅）| nt35695_fhd_dsi_cmd_truly |
| 触摸 IC 配置 | **config1 / config2** | config8 |
| 参考源码树 | **xiaocheng20/kernel_meizu_m3note**（Flyme 5 时代，3.10.72）| 99degree/android_kernel_m3note（Flyme 6 时代，3.18.35）= 我们编译用的 |

**⇒ 凡遇硬件驱动不匹配，优先从 xiaocheng20 树找"现成答案"：**
- 该树 = 本批次硬件的官方血脉，含我们缺的 r63350 面板驱动（已移植✅）、config1/2 触摸配置、flash1/2 闪光灯 sysfs 等
- 拉文件方式：`curl -s https://raw.githubusercontent.com/xiaocheng20/kernel_meizu_m3note/5/<路径>`
- 注意：该树是 3.10 内核，**代码不能直接编译进 3.18**，但配置数据、寄存器序列、sysfs 接口定义可以直接抄

## 一、手电筒不亮（根因已定位到函数行，修复方案=现成的）

### 证据链
1. `Fatal signal 11 (SIGSEGV), fault addr 0x30 in tid 390 (cameraserver)`
2. 崩溃栈（tombstone_02）：
   ```
   #00 vfprintf+5 ← #01 fprintf+30
   #02 DefaultMeizuPlatform::controlFlashLevel(int,int)+60
   #03 MZ_CamClient::openFlashLight(int)+204
   ```
   = 魅族相机 HAL 打开闪光灯设备失败（文件指针=NULL），随后向 NULL 指针 fprintf 崩溃
3. tombstone_00/01/02 三次都是 cameraserver
4. `.so` 里字符串 = HAL 期望的路径：
   ```
   /sys/class/flashlightdrv/kd_camera_flashlight/flash1
   /sys/class/flashlightdrv/kd_camera_flashlight/flash2
   ```
5. 实测本机 sysfs：`/sys/class/flashlightdrv/kd_camera_flashlight/` 下**只有 dev/power/subsystem/uevent**（缺 flash1/flash2）

### 根因
`drivers/misc/mediatek/flashlight/src/mt6755/kd_flashlightlist.c`（我们 945 行版本）
在 probe 里只做了 `class_create("flashlightdrv")` + `device_create(...)`，
**没有创建 flash1/flash2 属性文件**（缺少 `device_create_file()` 调用）。

### 修复方案（从 xiaocheng20 树移植，1258 行版本）
该树同路径文件包含完整实现：
```c
/* 大约 680-900 行区域 */
int flashduty1;                                    /* flash1 的 0-5 档 */
int flashduty[]={1,3,4,5,7,8};                     /* 档位映射 */
int flashduty_part2[]={16,35,53,70,89,106};
static ssize_t show_flashduty1/store_flashduty1(...)  /* 调 hight_cct_led_storbe_setduty() */
static ssize_t show_flashduty2/store_flashduty2(...)  /* flash2 开关 */
static DEVICE_ATTR(flash1, S_IWUGO|S_IRUGO, ...);
static DEVICE_ATTR(flash2, 0666, ...);
/* probe 里追加（约 1127-1145 行）：*/
device_create_file(flashlight_device, &dev_attr_flash1);
device_create_file(flashlight_device, &dev_attr_flash2);
```
**移植注意**：他们 store 函数里调用的 `hight_cct_led_storbe_setduty()` 及其底层
（闪光灯 IC 的占空比设置）也要一并移植——或改写为我们驱动的
`FLASHLIGHT_FUNCTION_STRUCT` 里的对应 ops（我们 301 行有 `defaultFlashlightFunc`）。
移植后重新编译（#9）→ TWRP 刷入（写保护注意）→ 测试手电筒。

## 二、亮度调节无效（三层问题，部分已定位）

### 已知事实
- 背光由 `leds-mt65xx` 驱动控制（sysfs 写入成功，寄存器值随亮度变化 ✅）
- **但物理亮度不变**；`/sys/kernel/debug/disp/dump` 显示 `pwm clock=0`（PWM 无时钟=无输出）
- `/sys/bus/platform/devices/1100e000.disp_pwm/driver` = 无驱动绑定！
- 树内 `drivers/pwm/pwm-mtk-disp.c` 只匹配 `mt8173/mt6595/mt2701`
  （DTB 用的是 `compatible = "mediatek,disp_pwm"` → 不匹配 → 没 probe → 时钟没使能）
- DTB 的 `led@6`：`led_mode = <0x5>` = **CUST_BLS_PWM**（自定义背光服务模式）

### 修复方案（优先级从高到低）
1. **给 `pwm-mtk-disp.c` 的 of_match_table 加上 `"mediatek,disp_pwm"`** +
   打开 `CONFIG_PWM=y` / `CONFIG_PWM_MTK_DISP=y` → 驱动 probe 时会 `clk_prepare_enable`
   → PWM 时钟使能 → 背光控制生效（很可能一步到位）
   - 注意：该驱动是主线 PWM 框架版，probe 时可能重配 PWM 默认状态（需观察）
2. 若还不行：对比 xiaocheng20 树 `drivers/misc/mediatek/video/.../ddp_pwm.c` 与
   `ddp_pwm_mux.c` 的时钟处理差异（3.10 版本的数据可抄）
3. 最后手段：写一个最小的平台驱动只做
   `clk_get("disp_pwm") + clk_prepare_enable + clk_set_parent`，绑定 `mediatek,disp_pwm`

## 三、搜索 App 闪退（非内核问题，可忽略或清数据）

```
Process: com.meizu.net.search (v8003001)
java.lang.ArrayIndexOutOfBoundsException: length=2; index=2
  at com.meizu.flyme.media.news.lite.f.a(...)
```
= 魅族搜索 App 自身的数组越界 bug（新闻栏目数据），与内核无关。
处理：清除该应用数据 / 不理会（不影响其他功能）。

## 四、诊断过程中的重要澄清

1. **"点应用打不开"的真相**：
   - 合成点击（`input tap 919 795`）**成功打开设置页面**，且设置界面渲染完美（截图验证）
   - = 系统层的点击→窗口→渲染链路完全正常
   - 结合手电筒的 cameraserver 崩溃 + 搜索 App 越界 bug，用户遇到的现象
     很可能是"点开的 App 恰好崩了"而非触控问题
2. **触控 config1 的效果待用户最终确认**（长按/滑动本就正常，慢点击可测）
3. 日志抓取要点（供下次）：
   - `/data/tombstones/`（原生崩溃+寄存器现场，本次的关键证据！）
   - `/data/system/dropbox/`（Java 崩溃 + SYSTEM_TOMBSTONE + AUDIT）
   - `logcat -b crash -d`
   - AVC 拒绝在 logcat 的 auditd 标签里（不在 dmesg）

## 五、当时系统状态快照（历史）

- 当时内核 #8 运行中（触摸 config1）；`boot_completed=1`、Permissive（已永久化）
- 屏幕 ✅ 触控（大概率✅）+ 长按/滑动 ✅；Wi-Fi ✅；Docker ✅（hello-world 跑通）
- 开机自启：`/sbin/.core/img/.core/service.d/docker-server` + `post-fs-data.d/selinux-permissive`
- 手电筒 ❌（修复方案见一）；亮度 ❌（修复方案见二）；搜索 App ❌（非内核）

---
*记录：ZCode · 2026-10-15 01:00*

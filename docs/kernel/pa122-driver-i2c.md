> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# PA122 光线/接近驱动移植与 i2c 总线问题（2026-10-15 上午）

> **历史记录**：本文写于当时的构建阶段（#20–#32）；当前运行内核为 #3307。
> 硬件修复的当前结论见 [CURRENT-STATE.md](../CURRENT-STATE.md)。

> **⚠ 本文第三节的两处判断已被后续实机复核纠正（2026-10-15 10:0x），请勿据此继续排查：**
> 1. "现役 I2C 驱动 = drivers/i2c/busses/i2c-mtk.c" **错误**：运行时绑定的是
>    `drivers/misc/mediatek/i2c/mt6755/i2c.c`（平台驱动名 `mt-i2c`，见
>    `/sys/bus/platform/devices/11008000.i2c/driver`）。
> 2. "i2c-1 总线级异常、PA122 无问题" **错误**：EINVAL/"2 秒不恢复"是**用户态工具结构体布局错误**
>    （内核 `CONFIG_MTK_I2C_EXTENSION=y` → `struct i2c_msg` 24 字节，标准工具按 16 字节传参 →
>    垃圾 `ext_flag` 命中 3D-CAMERA 位 → 适配器被挂起）。用 24 字节布局后 i2c-1 完全正常。
> 3. 另外：本机光线/接近芯片实测是 **LTR-579@0x53**（DTB `cust_alsps@0`），
>    **0x1e 完全无应答** —— PA122 方向需重新评估。
>
> 详见《i2c总线真相与传感器地址纠正-2026-10-15.md》。


## 一、重大方向纠正：芯片是 PA122，不是 CM36686

- 原厂 Flyme8 内核二进制内 `pa122` 出现 72 次、`cm36686` 为 0；构建路径为
  `NewFlyme/Code/Marshmallow_M1621-6.0/kernel-3.18/...`。
- 设备 DTB（三份 boot 镜像内完全一致，82591 字节）中：
  - `alsps@1e { compatible = "mediatek,alsps_pa122"; }`（i2c-1 @0x1e，芯片实际位置，实测有应答）
  - `cust_alsps@1 = pa122@0x1e`（含完整光感曲线/阈值）
  - `alsps@60 (mediatek,alsps)` 与 `cust_alsps@0 (ltr579@0x53)` 为其它批次配置
  - 中断节点 = `als { compatible = "mediatek, als-eint"; interrupts=<6 2>; debounce=<6 0> }`
- **#24/#26 的 "CM36686 兼容补丁" 方向错误**（该驱动在本机无处可绑）；#26 启动循环的
  确切原因未最终定位（组合补丁 + 刷写异常都可能），已回滚 #22。

## 二、PA122 驱动移植（已完成代码，产出 #27）

从 `<BUILD_ROOT>/m681-master`（3.10.72）移植 `pa12200001` 驱动到 k318（3.18.35）树：

| 适配点 | 处理 |
|---|---|
| `get_cust_alsps_hw()` 板级机制 | 保留本地 default，init 里经 `get_alsps_dts_func("mediatek,pa122")` 用 DTB 覆盖 |
| `i2c_register_board_info` | 删除；补 `of_match_table = {"mediatek,alsps_pa122"}` 走 DT 绑定 |
| EINT 获取（3.10 mach API） | 重写为 cm36686 风格：pinctrl(alsps 平台设备) + `"mediatek, als-eint"`(小写!) 节点 + `irq_of_parse_and_map` |
| `isl29125` 外部 ALS（芯片不存在） | 全部 10 处调用改回 PA122 自带 ALS（`pa122_read_als` + `pa122_get_als_value`） |
| `hwPowerOn/hwPowerDown`（本树无此 API） | pa122_power 改为 no-op（本机 power_id=-1 不走 LDO） |
| 头文件（linux/ 前缀缺、mach 缺、cust_eint 缺） | 去前缀走 hwmon/include；mach 全部移除；cust_eint 移除 |
| `p_sensor_info`（原在 isl29125 中定义） | 本地定义 |
| `meizu_class` | inv_mpu_core.c 去 static |
| 编译规范（-Werror 群） | 未用函数加 `__maybe_unused`；for 初始化/括号/声明位置/死标签逐一处 理；sysfs 0666→0644（内核 VERIFY_OCTAL_PERMISSIONS 禁 world-writable）；`hwm_sensor_data` 加 struct 前缀；write_block 参数 void*；fops.write 加 const |

- 产物：`Image.gz-fix27`（uname #27）、`kernel-config-fix27`（含 `CONFIG_MTK_PA12200001=y`，
  已关 `CONFIG_MTK_CM36686_NEW`）、`boot-fix27-test.img`
  SHA256 `0371403e0954aacec8a00923727a31dd7d7e365a863e61e7ab58ee8f02db7b0f`。
- **fastboot 临时启动验证通过：无启动循环，`sys.boot_completed=1`。**
- 驱动注册成功：`/sys/bus/i2c/drivers/pa122` 存在；手动 `echo 1-001e > bind` 能触发 probe。

## 三、当前唯一阻塞：i2c-1 总线的异常行为（非驱动问题）

probe 失败于第一步 I2C 写（`hwmsen_write_byte` → `-EFAULT`）。实测（chroot python + i2c-dev）：

- 对 0x1e 的"写寄存器号+读1字节"组合传输：**同一次会话内第一次必成功，此后全部 EINVAL**，
  且 2 秒不恢复；期间对任何地址都一样。
- 现役 I2C 驱动 = `drivers/i2c/busses/i2c-mtk.c`（不是 i2c-mt65xx.c，后者 of_match 无 mt6755）。
  `__mt_i2c_transfer` 的 EINVAL 来源只有三处：`len > MAX_DMA_TRANS_SIZE`、`addr == 0`、
  `buf == NULL`（我们的参数均合法）。
- i2c-1 上的充电器 bq25890（0x6b）在同一时段 **429 次 I2C_ACKERR**（每约 5 秒一组）——
  佐证这是总线级/驱动级问题，与 PA122 无关。
- `i2c_sel` 时钟 = 68.25 MHz，`infra_i2c1` 门控计数为 0（传输时门控）。
- **下一步排查建议**：
  1. DTB i2c 节点是否有 `mediatek,have-dcm` 等属性缺失（DCM 配置影响时序裕量）；
  2. 对比原厂内核（`/tmp/sk.bin` 可从 boot-flyme8.img 解出）中 i2c-mtk.c 行为，或寻找
     "i2c transfer buffer copy"（`mt_i2c_copy_to_dma` 内部 dma_buf 长度上限）是否有已知差异；
  3. 在 #27 上直接触发 `msgs->addr==0`/`len` 检查路径的日志（临时打开 dev_dbg 或打补丁）；
  4. 若确认总线时序问题，优先从 xiaocheng20/m681 侧找 i2c 相关修正补丁。

## 四、当前设备状态

- 设备在 **#27（fastboot RAM 启动）**运行中；重启即回到 #22（启动分区未动）。
- 音量上键：硬件断路结论已定案（见 volume-key-evidence/）。
- 亮度最小保护（#25 的补丁）：**不在 #27 内**（已回退），需要时单独重测。

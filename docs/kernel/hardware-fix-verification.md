> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# 硬件修复验证记录

> **历史记录**：本文写于当时的构建阶段（#20–#32）；当前运行内核为 #3307。
> 硬件修复的当前结论见 [CURRENT-STATE.md](../CURRENT-STATE.md)。

## 已由用户确认

- 桌面真实点击和重复打开应用：#12 已恢复。
- 屏幕亮度：#12 已恢复。
- 快捷手电筒：#12 双 LED 暖白光已恢复。
- 工具箱强度：#15 补齐 `ro.meizu.product.model=m91` 并重启 Android 框架后，用户确认 1–3 档有变化。此前只重开工具箱不生效。
- 拍照闪光灯：#15 用户确认拍照时闪亮。尚未验证自动闪光、所有色温/强度组合。
- 水平仪：#15 加速度有真实变化，但 MPL Orientation 全零，用户确认角度不变化。
- 前摄：#15 仍偏粉紫；临时 Bayer 参数 2→1 后用户仍见偏粉紫，随后恢复 2。该测试未证实 Bayer 是根因，未采用颜色排列永久改动。

## 已定位的兼容缺口

1. 工具箱检查 BuildExt 的型号属性。仅设 ro.product.model 不足，BuildExt 读取 ro.meizu.product.model；框架缓存必须重新初始化。Magisk 16.3 的早期脚本目录在 `/sbin/.core/img/.core/post-fs-data.d`，现代 `/data/adb/post-fs-data.d` 不执行。旧目录一次性脚本在 #16 已执行并自删除，启动后型号为 m91。
2. 水平仪只接受 Android TYPE_ORIENTATION，直接使用 pitch/roll。当前厂商 HAL 的 orienHandler 会把融合输出覆盖为磁力计方向事件缓存；仅修复加速度/DMP 不足。HAL 需要 `/sys/class/meizu/msensor/msensor_type=2` 选择 MTK 输入事件接口。#16 已提供此接口。
3. 原内核 YAS 驱动可注册并不证明芯片存在，它在启用时才检查硬件，#15 实际启用失败。早期板参考及用户态 AKMD 均使用 AK09916（WIA 48,09、10 字节 GETDATA），不能直接照 AK09911 的 9 字节 ABI 使用。
4. 旧 AKM I2C 读取把负返回值当作成功，并修改 client->addr。#16 读出的 00,3c 因此无效，不能当芯片身份。#17 改用严格检查的标准 I2C 转移；只有真实身份匹配才绑定。
5. Flyme libcameracustom 明确包含 `s5k5e8_eeprom` 设备名，内核却只提供其他传感器的 CAM_CAL_DRV1/2。#17 新增只读缓存 OTP 接口，兼容旧/新、32/64 位结构，按参考提供模块 ID 与 12 字节白平衡数据；无效缓存返回错误，未写 OTP 或 EEPROM。

## 测试镜像

原备份：`project/m3note-backup/boot-before-fix10.img`，SHA256 `85e2f8f0fd7339b833f34b1290b8f9b7dafdcb48cfbf9c763bb74bd09150431f`。

#15：`boot-fix15-test.img`，SHA256 `ad896b04c695197d03f0652d667d24571676b4f3c04054e1500b92c270fe76cb`。

#16：`boot-fix16-test.img`，SHA256 `d207eb277cd7c7fef3a6ee5507e84dc2fe02f0ce806bef11d61c8da441011ee8`。

打包器保持 16 MiB、原 header/DTB/Magisk ramdisk/其余区域逐字节不变，仅替换压缩内核。测试内核不会在普通重启后保留；原启动分区仍为 #9。永久安装尚未授权。

## 待验证（以文末最新实机结果为准）

- AK09916 真实身份、正确绑定和 AKMD 持续运行、磁场与方向角实时事件。
- s5k5e8_eeprom 实际被相机读取，OTP 数值有效，前摄颜色恢复。
- 在最终版本回归桌面点击、亮度、双 LED、工具箱强度、前后摄和拍照闪光。
- 前摄/后摄完整校准、自动对焦、自动闪光等尚未全面验证。

## #17 实机结果与 #18 修正

#17 临时启动成功，SHA256 `141ec1c1a8787aff73e9cfeb5934c5f81735bc02f8a10e72a9a190a52362647c`。用户确认前摄仍偏粉紫。新增 `/dev/s5k5e8_eeprom` 权限自动为 system:camera 0660；本机 Python 64 位旧 ABI 读取模块 ID 返回 0a00，12 字节白平衡读取因 golden G 为零返回 ENODATA，没有向 HAL 输出无效样本。

真实前摄寄存器 mirror=0；四路数字增益均为 0x0100。通过 read-only OTP 模式读取 page4：group1 有效，module=10，年月日为16/6/7；unit 数据位于 0a0e..0a13，为 R=635、B=635、G=126；golden 数据位于 0a15..0a1a，为 R=620、B=570、G=131。

发现移植日志的副作用错误：原 `LOG_INF("OB...", read_cmos_sensor(temp_address++))` 中的 mandatory 地址递增随着 pr_debug 关闭而不执行，导致 cache 实际解析为 R=4098、B=31490、G=31488。golden 样本读取又在参考实现中被注释，使 golden G=0。#18 将 OB 读取与递增移到日志外，恢复真实 golden 样本读取；不猜测 Bayer 或写入 OTP。

磁力计 #17 标准读取在1/0c失败，按 DT cust_mag 候选1/0d读取返回 WIA01,ff，非AK09916身份，拒绝绑定。该结果不支持此前 AK09916 已匹配硬件的假设。#18 增加 root-only 只读识别接口，限定 DT/参考已知的0c、0d、2e地址及4个身份相关寄存器，用于分辨实际型号。未启动不匹配的AKM daemon。

## #18–#20：磁力计身份确认与前摄调用边界

#18 启动、型号 m91 与校准读取正常：12 字节为 `027b027b007e026c023a0083`，与物理 OTP 相符。用户明确反馈前摄偏粉紫没有改善，因此不能把校准解析修正当作颜色已恢复。

#19 临时加入 CONFIG_I2C_CHARDEV，节点 root:root 0600；专用校准设备加入 open/ioctl 调用日志。镜像 SHA256 `c10571c8259929a4b179a8b8ef1447a79ca68d5a466ec0dd084e4731a13fca9a`。按 ST480 协议在 I2C1/0x0d 发送只读身份命令 `50 00`，连续三次成功完成两条 I2C 消息，回应 `00 00 7c`；真实磁力计已确认 ST480，此前 AKM/YAS 驱动方向不适用。

#20 正在接回 ST480 raw compass 接口和 msensor_type=1。厂商 64 位传感器 HAL 自带磁场校准和姿态计算，不需外部磁力计 daemon；原 3.18 通用 ST480 驱动的 ASCII ioctl/input ABI 不匹配，已针对参考 raw ABI 移植。绑定由 IIO init 在 bus1/0x0d 创建 st480 client，保留原 DTB。旧通用寄存器诊断节点已移除，避免向已确认的命令型芯片发送不适用的寄存器查询。水平仪尚待实机验证。

前摄诊断：#19 重启 cameraserver 后重新获取 OTP/info，缓存正常，但未观察到 s5k5e8_eeprom 的 open/ioctl。传感器色条测试能显示正常红绿蓝/黄青紫/白，黑色条偏紫；测试模式已关闭。此现象可用于继续排查 ISP/调校，但单次色条不足以断定根因。

实际 maps 证明 cameraserver 使用 `/system/vendor/lib/libcameracustom.so` 等 32 位库，此前校准静态分析使用了 64 位副本，不能直接视为实际运行证据；已提取 runtime32 三个库重新核对。system_server 则实际使用 `/system/lib64/libinvensense_hal.so`，ST480 HAL 静态分析目标与实际加载路径一致。实际调用和视觉改善仍需分别验证。

## #20 用户确认与重启后手电筒回退

用户已确认 #20 水平仪角度随倾斜变化。最终 #20 镜像 SHA256 为 `a539160db0ef042eacabe0b0e077a5098b39cc57956570b3598f2cebcef30240`，源码归档 SHA256 为 `45d989389a2c987e19ae4482d1dabe1d3440244ce7a956faa5d9829397eba659`。

前摄仍偏粉紫。再次临时改 Bayer 并重启相机服务后用户仍确认无改善，已恢复 Bayer=2。实际 runtime32 ImgSensorDrv::getInfo2 使用新 204 字节 INFO2，与当前内核结构匹配，不能改回参考 192 字节旧结构。

用户反馈重启后工具箱三档再次失效。此次实机 uname 为 #20，启动分区 `/dev/block/mmcblk0p22` 的 SHA256 也与上述 #20 镜像一致，证明内核已保留。`ro.meizu.product.device=m91`，但 `ro.meizu.product.model` 为空，早期目录中只剩 selinux-permissive。原因是之前的型号修补脚本是执行后自删除的一次性测试脚本，未持久化。

本次安装 `m3note-model-persistent.sh` 到 Magisk 16.3 的 `/sbin/.core/img/.core/post-fs-data.d/m3note-model.sh`，root:root 0755。仅在 device=m91 且 model 为空/unknown 时补 model=m91，在 zygote 初始化前执行，不再自删除。未重写启动分区。最终脚本 SHA256 为 `341e1e2b4aac3b9e22db5ac6a297bcb2d83868732f83d1dcd4f96563bd8dedf4`。开机日志 `/data/local/tmp/m3note-model-boot.txt` 记录 boot_id、内核和属性，便于核对实际执行。属性读取使用系统 getprop，设置用 `resetprop -n` 直接更新属性，避免早期默认 init 属性触发路径的异步设置：前两次重启后型号虽为 m91，但 hook 即时日志仍读空，因此最终改用 -n。

回退此项：删除 `/sbin/.core/img/.core/post-fs-data.d/m3note-model.sh` 后重启；保留原 selinux-permissive 等脚本。持久化的重启实测结果见后续记录。

最终脚本重启验证：boot_id=`<UUID_REDACTED>`，与早期 hook 日志一致；hook 即时日志 `model=m91`，进入系统后属性仍为 m91，`sys.boot_completed=1`，脚本仍存在且 SHA256 正确，uname/启动分区均为 #20，msensor_type=1。证据保存于 `model-persistent-boot-verification.txt`。

用户已回复“三档亮度已恢复变化”，确认持久化修复后，普通重启进入系统的工具箱 1、2、3 档实际亮度恢复变化。此次手电筒重启回退问题已解决。前摄偏粉紫仍未解决，不能据此宣称全部硬件问题已修复。

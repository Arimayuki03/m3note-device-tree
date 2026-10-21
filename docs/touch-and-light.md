> 说明：本文是原始工作记录的脱敏版本。文中出现的串号、IP、UUID、账号、
> 密钥和密码均已替换为占位符；`<PROJECT_ROOT>` 代表原工作目录。
> 固件、分区备份、第三方 APK、日志和个人服务数据未随本仓库发布。

# 桌面点击、手电筒和亮度修复（2026-10-15）

> **历史记录**：本文记录 #10–#20 的硬件调试。当前内核为 #3307；
> 前摄偏粉紫仍未解决，现状见 [CURRENT-STATE.md](CURRENT-STATE.md)。

> 最新跟进：下面的 #10–#12 内容是历史记录。#15 用户已确认工具箱强度可调、拍照有闪光灯；水平仪仍无角度、前摄仍偏粉紫。#16 为磁力计/前摄诊断版本；#17 正在构建。所有测试仍为 fastboot boot，未永久写入启动分区。

当时手机临时运行内核 **#12**（01:33:10 编译，历史）。通过 fastboot boot 加载到内存，尚未写入 boot 分区；下次正常重启会回到原内核 #9。用户已确认 #10 中应用可正常打开、亮度条正常；手电筒能亮，但仅呈暖黄光，原来使用的是冷暖 LED 同亮的暖白光。#12 修正通道映射并恢复默认双 LED 混光，等待用户确认实际色温。

## 手电筒色温跟进

参考源码 strobe_main_sid1_part2.c 的生效 `#if 1` 分支明确将高色温通道对应到电流寄存器 0x06、使能位 0x02，低色温通道对应到 0x05、使能位 0x01。#10 使用了另一分支的相反映射，导致 HAL 默认通道实际点亮暖黄 LED。

已编译、打包 #11：修正两路映射；每次 HWEN 后重写两路电流，避免关闭后重新开启时芯片复位使另一通道电流丢失；保持两路使能位按各自状态合并。尚待临时启动验证及读取新系统默认档位。

#11 测试镜像：<ARTIFACTS>/boot-fix11-test.img，SHA256 92998297f729911bd7dd82551ada5429a25a81d26106e68147e178c71ff1de4f。

用户进一步说明原来是两颗 LED 同亮的暖白光，新系统没有找到调色入口。在用户从系统快捷开关开启手电筒后，实际读取到 flash1=5、flash2=-1，证明新系统默认只启用第一路。#11 仅修正映射，尚未临时启动；后续直接构建 #12，默认将单独冷白请求混入同档位暖黄通道，恢复用户原来的暖白输出。新增 warm_white 布尔参数，默认开启；关闭该参数后，flash1/flash2 可分别控制原始冷暖通道。两路都为负值时仍关闭全部 LED。

#12 已编译、打包、临时启动成功；sys.boot_completed=1，disppwm_sel enable_count=1，触点释放后 pointerCount=0，压力轴可用，1-0063 绑定 m3note-torch，crash buffer 暂无新崩溃。warm_white 参数读取为 Y。

#12 测试镜像：<ARTIFACTS>/boot-fix12-test.img，SHA256 2d4cd9bfca5ce7bb6eedf268306b976fea5c217f4ba4859beffd923ed9f40ec9。

独立控制说明：默认暖白混光针对新系统仅请求 flash1 的快捷开关。需要独立设置冷暖比例时，先关闭手电筒，再以 root 将 /sys/module/m3note_torch_compat/parameters/warm_white 写入 N，随后 flash1 控制冷白、flash2 控制暖黄，各 -1 关闭、0..5 调档。这个设置在重启后恢复默认，不意味着新系统有内置的调色界面。

## 已纠正的诊断

旧记录把“ADB input tap 可以打开设置”当作真实手指点击正常的证据，这个结论不成立。ADB 合成事件绕开了触摸驱动，不能用于验证驱动的触点释放。

真实 getevent 和 dumpsys input 显示：旧 #9 在 Protocol A 的抬手帧中发送 Protocol B 的 tracking_id=-1，Android 在手指抬起后仍报告 pointerCount=1、isHovering=true。触摸设备没有 ABS_MT_SLOT，是 Protocol A；声明 ABS_MT_TRACKING_ID 不等于 Protocol B。另外驱动发送 ABS_MT_PRESSURE，却未在 input device 中注册该轴。

修复：Protocol A 抬手发送空 MT 帧；注册 ABS_MT_PRESSURE 0..255。#10 实机已有 pointerCount=0 的抬手结果，压力轴也能被 Android 正确识别。

旧记录建议给通用 pwm-mtk-disp 增加匹配并启用，实际不适用：原机 disp_pwm 节点只有 reg，没有通用 PWM 驱动所需的 main/mm 时钟绑定；通用驱动 probe 也只 prepare，不会自动 enable。因此没有采用该方案。现有厂商 ddp_pwm 已管理背光寄存器，但 power_on/power_off 未持续开关 MUX_PWM。修复是在厂商链路中配对 enable/disable MUX_PWM。#10 的 clk_summary 显示 disppwm_sel enable_count 从 0 变为 1。

手电筒不仅缺 flash1/flash2，现有 constant_flashlight 使用的是 RT4505；早期批次参考源码使用 SGM3784 或 SY7806/NT50572。原机 DTB 列出 0x30 与 0x63 两个候选地址，只有存在节点不能证明芯片存在。新 m3note_torch_compat 驱动读取 0x63 的设备 ID，仅匹配 ID 0x02/0x18，再使用参考源码的 GPIO99/9/89 和双通道 torch 寄存器。#10 中 1-0063 已实际绑定 m3note-torch，sysfs 控制命令成功返回；保持 flash1/flash2 的负值关闭、0..5 档位 ABI。未把相机高亮闪光模式移植到新驱动。

## 修改与验证

- 源码树：WSL <BUILD_ROOT>/k318/android_kernel_m3note-master
- 原文件备份：WSL <BUILD_ROOT>/fix-20261015
- 修改：GT1151/gt1x_tpd.c、aal20/ddp_pwm.c、mt6755/kd_flashlightlist.c、mt6755/Makefile；新增 m3note_torch_compat.c
- 编译：build_fix10.sh，结果成功；build-fix10.log 留存。日志中的原有编译器警告不影响生成。
- 镜像：<ARTIFACTS>/boot-fix10-test.img，16 MiB
- 打包：pack_fix10.py；原机 header、DTB、Magisk ramdisk 与余下区域逐字节不变，只替换固定布局的内核压缩段
- 系统：临时镜像成功启动，uname=#10、sys.boot_completed=1
- 触摸：增加压力轴；空闲 pointerCount=0
- 背光：disppwm_sel enable_count=1
- 手电筒：设备绑定，两个 sysfs 节点存在并能读写；测试后已关闭
- 新启动后的 crash buffer 暂无 cameraserver 崩溃

## 镜像校验

原启动分区只读备份：<ARTIFACTS>/boot-before-fix10.img

SHA256：85e2f8f0fd7339b833f34b1290b8f9b7dafdcb48cfbf9c763bb74bd09150431f

测试镜像 SHA256：9984475aedec28f07d5036cc799de71ac891642043197b207a61a56491f61701

永久安装应在用户确认实机效果后进行。现有设备写保护会让 Android 内 dd 静默失败，安装需采用已有的临时 TWRP 流程，并回读 16 MiB 镜像比对校验；不得把 dd 返回成功当作安装成功。

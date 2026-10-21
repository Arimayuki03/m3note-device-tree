# MT6755 / wt6755_66_n 设备树

这些文件从 Linux 3.18.35 内核源码（`android_kernel_m3note-master`）的
`arch/arm64/boot/dts/` 和 `include/dt-bindings/` 提取，供阅读和比对。

| 文件 | 作用 |
|---|---|
| `wt6755_66_n.dts` | m3note（MT6755 / wt6755_66_n）整机设备树 |
| `mt6755.dtsi` | MT6755 SoC 顶层描述 |
| `mt6755-pinfunc.h` | MT6755 pinmux 定义 |
| `mt6351.dtsi` / `mt6353.dtsi` / `mt6392.dtsi` | PMIC 描述 |
| `cust_*.dtsi` | 客户板级 ADC/EINT/I2C/KPD/MSDC 配置 |
| `trusty.dtsi` | Trusty TEE 保留内存 |
| `include/dt-bindings/` | 设备树编译所需的 clock/irq/mmc/pinctrl 头文件 |

## 编译说明

`wt6755_66_n.dts` 第 5 行 `#include "cust.dtsi"` 指向联发科 DCT/构建系统
生成的 `cust.dtsi`；该文件不在上游源码树中，通常由 `cust_*.dtsi` 片段在
厂商构建流程中合并生成。若要单独编译这份 DTS，需要：

1. 使用完整的 3.18.35 内核源码树（包含 `scripts/dtc`、`include/` 和
   `arch/arm64/boot/dts/Makefile`）；
2. 把本目录的 `*.dts` / `*.dtsi` / `*.h` 放回 `arch/arm64/boot/dts/`，
   `include/dt-bindings/` 放回源码树同名位置；
3. 按厂商 DCT 流程生成 `cust.dtsi`，或自行编写等价的板级配置；
4. 使用内核的 `make dtbs` 编译。

这份目录的主要用途是记录本机的硬件描述和引脚/PMIC 配置，而不是提供一个
脱离内核源码即可独立编译的 DTS 工程。

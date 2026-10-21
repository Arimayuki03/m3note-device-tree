# 内核：配置、设备树、补丁与构建

## 目录

| 路径 | 内容 |
|---|---|
| `configs/defconfig-wt6755_66_n` | 原厂基线 defconfig |
| `configs/kernel-config-containers` | 打开 cgroup/namespace/overlayfs/veth 的容器内核配置 |
| `configs/kernel-config-fix32` | 硬件修复最终构建（#32，回滚基线）配置 |
| `dts/` | MT6755 / wt6755_66_n 设备树源（来自 3.18.35 内核；说明见 `dts/README.md`） |
| `patches/` | 显示、触摸、手电筒、传感器等补丁 |
| `patches/docker/` | dockerd/runc/CLI/qtaguid/cpuset 兼容补丁 |
| `scripts/build_fix*.sh` | 从基线到 #32 的构建脚本（按需取用） |
| `scripts/flash-*.sh` | 带哈希校验和回滚的刷写示例 |
| `scripts/m3note-performance-module/` | Magisk 性能模块（8 核、关 HPS） |

## 当前运行内核

设备当前运行 **3.18.35-docker-qtaguid #3307**，不是 #32。两者关系：

- #32 = 硬件修复最终版（触摸、亮度、手电筒、传感器、音量键、lz4 zram 等），
  仍作为 boot 分区回滚基线。
- #3307 = #32 + `patches/docker/` 中的 route/cpuset/qtaguid 补丁，并新增
  `CFS_BANDWIDTH`、`BLK_DEV_THROTTLING`、`MEMCG_SWAP`、`MEMCG_SWAP_ENABLED`、
  `DEVPTS_MULTIPLE_INSTANCES` 五个配置项（见 `patches/docker/config-changes.patch`）。
- 用户空间配套：`runc-rootfix`、`dockerd-cpusetfix`、`docker-throttlefix`；
  对应补丁在 `patches/docker/`。

## 构建要点

1. 获取 3.18.35 源码（见 `../sources/README.md`），把 `dts/` 放回
   `arch/arm64/boot/dts/`，或者直接用源码中同名文件对照。`wt6755_66_n.dts`
   依赖的 `cust.dtsi` 由厂商 DCT 流程生成，不在上游源码树中，详见 `dts/README.md`。
2. 使用 AOSP GCC 4.9 aarch64 工具链。
3. 以 `configs/defconfig-wt6755_66_n` 为基线，合并 `configs/kernel-config-containers`
   或 `kernel-config-fix32`。
4. 应用 `patches/` 中的补丁；`scripts/build_fix32.sh` 展示了 preflight 检查和
   完整编译命令。
5. 产物 `Image.gz` 需要与原厂 DTB 一起打包进 boot（见 `../scripts/boot_pack*.py`）。

## 注意

- 构建脚本中的路径、工具链位置和输出目录是原作者环境的示例，必须修改。
- 刷写前确认 `boot` 分区基线哈希，并保留可回滚镜像。
- 不要刷 `lk` / `preloader`；救砖通道未验证时风险极高。

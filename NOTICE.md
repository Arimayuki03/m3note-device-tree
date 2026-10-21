# 第三方组件与未包含内容

本仓库只包含项目作者编写的文档、脚本、配置和补丁，以及从 GPL-2.0 内核源码
提取的设备树文件，和厂商固件衍生的配置/分区表参考。

| 组件 | 状态 | 说明 |
|---|---|---|
| Linux 3.18.35 内核源码（`android_kernel_m3note-master`） | 未包含 | 约 177 MB，按 `sources/README.md` 获取；内核及其衍生物为 GPL-2.0 |
| AOSP GCC 4.9 工具链 | 未包含 | 按 `sources/README.md` 获取 |
| Ubuntu/Alpine arm64 rootfs | 未包含 | 按 `sources/README.md` 获取 |
| 官方 Flyme 固件 / OTA / boot / lk / preloader | 未包含 | 版权归魅族/联发科；请从官方或自有备份获取 |
| TWRP、Magisk、SuperSU、Xposed | 未包含 | 第三方项目，遵循各自许可 |
| mtkclient、UsbDk | 未包含 | 第三方工具，请从上游获取 |
| 实机分区备份与应用数据 | 未包含 | 含设备唯一标识/个人数据，禁止公开 |
| 教程与部分资源链接 | 参考 | <https://www.juyifx.cn/article/518488655.html>；本仓库不重新分发其二进制资源 |

`kernel/dts/` 中的文件来自 `android_kernel_m3note-master` 的
`arch/arm64/boot/dts/` 和 `include/dt-bindings/`，仅提取了与 wt6755_66_n
相关的文件。这些文件保留了上游版权头和作者邮箱（`@mediatek.com` 等），
属于 GPL-2.0 源码的版权声明，不是项目作者的个人信息。若上游许可要求，
请同时保留内核源码中的完整版权声明。

## 补充说明

- `defconfig-wt6755_66_n` 和 `device/scatter.txt` 是厂商/固件衍生物，仅作研究参考，
  权利归原厂或原发布者。
- `kernel/patches/docker/` 中针对 Docker/Moby、runc、dockerd 和 CLI 的补丁，
  源自相应上游项目，遵循其上游许可（Docker/Moby 等为 Apache-2.0）；本仓库仅
  提供兼容性补丁，不重新分发上游二进制。
- 早期硬件参考使用了 `xiaocheng20/kernel_meizu_m3note` 社区内核树，在此致谢；
  相关代码/说明的许可归其原作者。
- `kernel/dts/` 中部分文件没有显式 SPDX 头，但仍来源于上述 GPL-2.0 内核树；
  有版权头的文件已保留原声明。

> 发布范围与排除项见 [EXCLUSIONS.md](EXCLUSIONS.md)。

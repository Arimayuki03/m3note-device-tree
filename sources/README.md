# 源码与工具链

以下大文件未包含在仓库中（版权/体积原因）。下载或从原工作目录复制后，
可用 SHA-256 校验：

| 文件 | 大小 (bytes) | SHA-256 |
|---|---:|---|
| `m3note-318.tar.gz` | 176,951,573 | `8fd1cd6f515887121e930dbb2cddddfb3af69e4040fcb529558458f7f44d1e45` |
| `gcc49.tar.gz` | 30,202,377 | `ff31b16d15d422fb8f6a9a06fe075cf3c2c7bb8bb57b5ee8b432936b1149c844` |
| `ubuntu-base-arm64.tar.gz` | 26,257,800 | `f9b999afb4c4b10193087ea8c11be36d688f19e609b05179b571f29357954b52` |
| `alpine-aarch64.tar.gz` | 3,947,906 | `041fa34a81788242df9e78fa69b97ab45b8ec47ddbf88864755610414a7bf3de` |

## 获取方式

- **内核**：`android_kernel_m3note-master`，Linux 3.18.35 联发科 BSP 的社区镜像；
  解压后目录名应与 `kernel/scripts/build_fix32.sh` 中的源码目录一致。
- **工具链**：AOSP GCC 4.9 aarch64（`aarch64-linux-android-*`），与官方内核
  编译版本一致。
- **Ubuntu rootfs**：`ubuntu-base-arm64.tar.gz`，用于在 chroot 中部署 Ubuntu。
- **Alpine rootfs**：`alpine-aarch64.tar.gz`，轻量替代方案。

## 设备树

`kernel/dts/` 中的文件已从内核源码提取，可直接阅读；重新构建内核时请使用
源码树中的同名文件，避免版本不一致。

## 参考教程

部分固件、刷机工具和资源链接来自以下教程文章：

<https://www.juyifx.cn/article/518488655.html>

本仓库不重新分发这些二进制资源；请从原文章提供的链接获取，并自行核对来源、
版本和文件哈希。

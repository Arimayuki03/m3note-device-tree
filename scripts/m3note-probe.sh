#!/usr/bin/env bash
# 魅蓝 note3 (Flyme 6.3.5.0A–8.0.0.0A / Android 7.0) 能力探测
# 几乎全是只读操作。唯一的写入是在 /data 下建一个临时目录做 tmpfs 挂载测试，用完立刻删除。
# 不会改 /system、不会重挂分区、不会动 boot。

ADB="/c/Users/<USER>/AppData/Local/Microsoft/WinGet/Packages/Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe/platform-tools/adb.exe"

dev() { "$ADB" shell "$@" 2>&1; }

echo "=== 0. 设备连接状态 ==="
"$ADB" devices -l
if ! "$ADB" devices | grep -qE "device$|device[[:space:]]"; then
  echo
  echo "!! 没有可用设备。请确认："
  echo "   1) 已在手机上打开 USB 调试"
  echo "   2) 数据线已插上（连接方式选「传输文件/MTP」）"
  echo "   3) 手机屏幕上的「允许 USB 调试」弹窗已点「允许」"
  exit 1
fi

echo
echo "=== 1. 系统身份（不需要 root）==="
echo "-- model:      $(dev getprop ro.product.model)"
echo "-- rom:        $(dev getprop ro.build.display.id)"
echo "-- android:    $(dev getprop ro.build.version.release)"
echo "-- kernel:     $(dev uname -r)"
echo "-- uname -m:   $(dev uname -m)"
echo "-- abilist:    $(dev getprop ro.product.cpu.abilist)"
echo "-- linker64:   $(dev ls -l /system/bin/linker64)"
echo "   (linker64 存在 = ROM 有 64 位支持，可用 aarch64 根文件系统)"

echo
echo "=== 2. root 与 SELinux（手机会弹 Flyme 授权框，请点允许）==="
echo "-- su -c id  : $(dev su -c id)"
echo "-- getenforce: $(dev getenforce)"
echo "-- 尝试放松:  $(dev 'setenforce 0; getenforce')"

echo
echo "=== 3. mount 能力（决定性的一项）==="
echo "-- tmpfs:     $(dev 'mkdir -p /data/probe_t && mount -t tmpfs none /data/probe_t && echo TMPFS_OK && umount /data/probe_t && rmdir /data/probe_t')"
echo "   TMPFS_OK = 能挂载；出现 not permitted / Permission denied = 被 SELinux 拦死"

echo
echo "=== 4. 工具与 loop 设备（信息性）==="
echo "-- loop dev:  $(dev 'ls /dev/block/loop* 2>&1 | head -3')"
echo "-- which:     $(dev 'which losetup mke2fs mkfs.ext4 busybox 2>&1 | tr "\n" " "')"

echo
echo "=== 5. 存储余量 ==="
dev df -h /data 2>&1 | tail -2

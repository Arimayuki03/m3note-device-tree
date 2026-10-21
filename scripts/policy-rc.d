#!/bin/sh
# Android chroot 内没有 init 系统（systemd/sysvinit）。
# 返回 101 让 invoke-rc.d 跳过服务启动，安装过程不会卡住，
# 所有服务统一由 /data/linux.sh start 启动。
exit 101

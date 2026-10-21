#!/system/bin/sh
# Magisk service.d 启动器：后台拉起电量循环后立即退出，避免阻塞后续开机脚本

LOG=/data/local/tmp/battery-full.log
echo "===== $(date) launcher =====" >>"$LOG"
/system/bin/setsid /system/bin/sh /data/adb/battery-full-loop </dev/null >>"$LOG" 2>&1 &
echo "launcher: spawned pid $!" >>"$LOG"
exit 0

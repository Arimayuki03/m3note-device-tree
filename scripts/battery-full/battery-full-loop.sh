#!/system/bin/sh
# 持续把系统上报的电量固定为 100%

LOG=/data/local/tmp/battery-full.log
exec >>"$LOG" 2>&1

sleep 10

while true; do
    /system/bin/dumpsys battery set level 100
    /system/bin/dumpsys battery set status 2
    /system/bin/dumpsys battery set ac 1
    /system/bin/dumpsys battery set usb 0
    /system/bin/dumpsys battery set wireless 0
    sleep 30
done

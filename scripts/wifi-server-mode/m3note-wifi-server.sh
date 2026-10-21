#!/system/bin/sh
unset LD_PRELOAD LD_LIBRARY_PATH
BB=/data/local/tmp/busybox
STATE=/data/m3note-wifi-server
mkdir -p "$STATE"
chmod 700 "$STATE"
while [ "$(getprop sys.boot_completed)" != 1 ]; do "$BB" sleep 5; done
LOG=$STATE/server-mode.log
size=$("$BB" stat -c %s "$LOG" 2>/dev/null)
if [ "${size:-0}" -gt 65536 ]; then mv -f "$LOG" "$STATE/server-mode.previous.log"; fi
exec >>"$LOG" 2>&1
echo "[$(date '+%F %T')] apply boot=$(cat /proc/sys/kernel/random/boot_id)"
settings put global wifi_sleep_policy 2
settings put global mobile_data 0
settings put global data_roaming 0
if [ "$(settings get global airplane_mode_on)" != 1 ]; then
    settings put global airplane_mode_on 1
    am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true
    "$BB" sleep 3
fi
# Android permits Wi-Fi in airplane mode; enable it after radio shutdown.
svc wifi enable
for pkg in com.android.dialer com.android.incallui com.android.mms com.android.mms.service com.meizu.callsetting com.activate.activatephone com.android.flyme.bridge.softsim com.flyme.virtual.softsim com.flyme.telecom.usagedata.service com.meizu.cloud com.meizu.account com.meizu.mzsyncservice com.meizu.flyme.service.find; do
    pm disable-user --user 0 "$pkg"
    am force-stop --user 0 "$pkg"
done
# Flyme starts FLAG_PERSISTENT apps even when merely disabled for this user.
# Hidden packages retain their APK/data but are unavailable to normal startup.
pm hide --user 0 com.meizu.cloud
pm hide --user 0 com.android.incallui
i=0
while [ "$(cat /sys/class/net/wlan0/operstate 2>/dev/null)" != up ] && [ "$i" -lt 30 ]; do
    "$BB" sleep 1
    i=$((i + 1))
done
if [ "$(cat /sys/class/net/wlan0/operstate 2>/dev/null)" != up ]; then
    # One bounded retry through Android's Wi-Fi service using the saved network.
    svc wifi disable
    "$BB" sleep 2
    svc wifi enable
    i=0
    while [ "$(cat /sys/class/net/wlan0/operstate 2>/dev/null)" != up ] && [ "$i" -lt 30 ]; do
        "$BB" sleep 1
        i=$((i + 1))
    done
fi
echo "[$(date '+%F %T')] completed airplane=$(settings get global airplane_mode_on) wifi=$(settings get global wifi_on)"
echo "wlan0=$(cat /sys/class/net/wlan0/operstate 2>/dev/null)"

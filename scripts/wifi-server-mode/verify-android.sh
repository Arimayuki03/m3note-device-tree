#!/system/bin/sh
unset LD_PRELOAD LD_LIBRARY_PATH
BB=/data/local/tmp/busybox
echo '=== Boot ==='
cat /proc/sys/kernel/random/boot_id
getprop sys.boot_completed
echo '=== Network settings ==='
for k in airplane_mode_on wifi_on wifi_sleep_policy mobile_data data_roaming; do echo "$k=$(settings get global $k)"; done
echo '=== Wi-Fi ==='
cat /sys/class/net/wlan0/operstate
dumpsys wifi | "$BB" grep -E 'Wi-Fi is|curState=|mAirplaneModeOn' | "$BB" head -8
ip route show table wlan0
ping -I wlan0 -c 2 -W 3 1.1.1.1
echo '=== Cellular state (3 = power off) ==='
dumpsys telephony.registry | "$BB" grep -E 'mServiceState=|mDataConnectionState='
echo '=== Disabled packages ==='
pm list packages -d -u
echo '=== Persistent packages frozen ==='
dumpsys package com.meizu.cloud | "$BB" grep '^    User 0:'
dumpsys package com.android.incallui | "$BB" grep '^    User 0:'
echo '=== Target processes ==='
"$BB" pgrep -af '^(com\.android\.(dialer|incallui|mms)|com\.activate\.activatephone|com\.meizu\.(callsetting|cloud|account|mzsyncservice|flyme\.service\.find)|com\.flyme\.(virtual\.softsim|telecom\.usagedata\.service))(:|[[:space:]]|$)'
echo '=== Swap ==='
cat /proc/swaps
cat /sys/block/zram0/disksize
cat /sys/block/zram0/comp_algorithm
for name in orig_data_size compr_data_size mem_used_total; do echo "$name=$(cat /sys/block/zram0/$name)"; done
cat /proc/meminfo | "$BB" grep -E '^MemTotal:|^MemAvailable:|^SwapTotal:|^SwapFree:'
echo '=== Startup logs ==='
cat /data/m3note-wifi-server/zram.log
tail -18 /data/m3note-wifi-server/server-mode.log
echo '=== Previous background guard ==='
"$BB" pgrep -af '^/system/bin/sh /data/m3note-app-background.sh'
echo '=== SD ==='
/system/bin/sh /data/m3note-sd64-mount.sh --check

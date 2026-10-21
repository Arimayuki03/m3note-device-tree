#!/system/bin/sh
# Magisk 16.3 service.d hook. Do not change battery or emergency reset protection.
LOG=/data/local/tmp/m3note-performance.log
echo "$(date) applying eight-core / CPU software thermal policy" >> "$LOG"
apply_policy() {
    echo 0 > /proc/hps/enabled
    echo '3 0' > /proc/ppm/policy_status
    echo '0 4' > /proc/ppm/policy/userlimit_min_cpu_core
    echo '1 4' > /proc/ppm/policy/userlimit_min_cpu_core
    for cpu in 0 1 2 3 4 5 6 7; do
        node=/sys/devices/system/cpu/cpu${cpu}/online
        [ ! -e "$node" ] || echo 1 > "$node"
    done
}
apply_policy >> "$LOG" 2>&1
# Apply again after Flyme's startup policies have finished.
while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 2; done
apply_policy >> "$LOG" 2>&1
echo "$(date) online=$(cat /sys/devices/system/cpu/online) hps=$(cat /proc/hps/enabled)" >> "$LOG"

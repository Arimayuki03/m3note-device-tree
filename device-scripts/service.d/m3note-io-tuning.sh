#!/system/bin/sh
# Magisk service.d hook: eMMC I/O tuning for the m3 note.
#
# WHY
#   Flyme's early-boot tuning leaves the boot device at the cfq scheduler and
#   512 KB read-ahead.  Measured on this device (512 MB buffered sequential read
#   of /data, page cache dropped before every run, five samples each, same
#   session):
#
#     cfq +  512 KB : 232.3 / 248.6 / 246.2 / 244.3 / 245.4 MB/s   (median 245.4)
#     deadline +  512 KB : 238.6 / 245.5 / 244.0 / 249.8 / 244.7   (median 245.5)
#     cfq + 1024 KB : 266.7 / 260.0 / 267.1 / 266.8 / 267.2 MB/s   (median 266.8)
#     deadline + 1024 KB : 260.2 / 266.3 / 264.2 / 267.1 / 266.4   (median 266.3)
#
#   => the whole ~+8.5% throughput gain comes from read-ahead 512 -> 1024 KB.
#      The scheduler shows no measurable difference in this test; deadline is
#      kept for its read-latency-under-mixed-load behaviour (unmeasured here).
#
# NOTES
#   * The boot device's scheduler/read-ahead are queue parameters: they reset on
#     every boot, and Flyme rewrites them early in boot, so this hook applies the
#     values twice - immediately, and again after sys.boot_completed.
#   * Nothing here depends on PATH: only shell builtins and absolute paths are
#     used.  (A previous boot hook in this project silently did nothing because
#     Magisk puts its busybox first in PATH and busybox's `ip` rejects masked
#     fwmark specs - see m3note-tailscale-fixed.sh.)
#   * Reverting: delete this file (values return to Flyme's on the next boot),
#     or write cfq / 512 by hand.
#
# Install:
#   adb push device-scripts/service.d/m3note-io-tuning.sh /data/local/tmp/
#   adb shell "su -c 'cp /data/local/tmp/m3note-io-tuning.sh /sbin/.core/img/.core/service.d/; chmod 755 /sbin/.core/img/.core/service.d/m3note-io-tuning.sh'"

TAG=/data/local/tmp/m3note-io.log
Q=/sys/block/mmcblk0/queue
GETPROP=/system/bin/getprop

log() { echo "$(/system/bin/date '+%F %T %Z') $*" >> "$TAG"; }

apply() {
    if [ ! -w "$Q/scheduler" ]; then
        log "FAIL: $Q/scheduler not writable"
        return 1
    fi
    echo deadline > "$Q/scheduler"
    echo 1024     > "$Q/read_ahead_kb"
    # cover the boot partitions too when their queues exist
    for q in /sys/block/mmcblk0boot0/queue /sys/block/mmcblk0boot1/queue; do
        [ -w "$q/scheduler" ] || continue
        echo deadline > "$q/scheduler"
        echo 512      > "$q/read_ahead_kb"
    done
    log "applied: sched=$(cat $Q/scheduler) read_ahead=$(cat $Q/read_ahead_kb) KB"
    return 0
}

apply

# Flyme's storage init rewrites these nodes early in boot; re-apply once the
# system reports boot_completed so our values are the ones that stick.
i=0
while [ "$("$GETPROP" sys.boot_completed 2>/dev/null)" != "1" ] && [ "$i" -lt 150 ]; do
    sleep 2
    i=$((i + 1))
done
sleep 5
apply

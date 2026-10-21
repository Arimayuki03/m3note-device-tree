#!/system/bin/sh
# Magisk 16.3 service.d hook: enlarge the already-created zram swap.
# 2 GiB logical compressed-swap capacity for this 2.85 GiB RAM device.
set -u
TAG=/data/local/tmp/m3note-zram-2g.log
Z=/dev/block/zram0
SYS=/sys/block/zram0
BB=/sbin/.core/busybox/busybox
TARGET=2147483648

log() { echo "[$(date '+%F %T')] $*" >> "$TAG"; }
log "start target=$TARGET"

# Wait for init's enableswap service to create and activate zram.
i=0
while { [ ! -e "$SYS/disksize" ] || ! grep -q '/dev/block/zram0' /proc/swaps; } && [ "$i" -lt 60 ]; do
    sleep 1
    i=$((i + 1))
done
[ -e "$SYS/disksize" ] || { log "no zram sysfs"; exit 0; }

current=$(cat "$SYS/disksize")
if [ "$current" = "$TARGET" ]; then
    log "already target; swaps=$(cat /proc/swaps)"
    exit 0
fi

# The device is active at this point. Release the old swap before reset.
/system/bin/swapoff "$Z" 2>>"$TAG" || { log "swapoff failed"; exit 1; }
echo 1 > "$SYS/reset" 2>>"$TAG" || true
echo "$TARGET" > "$SYS/disksize" 2>>"$TAG" || { log "disksize write failed"; exit 1; }
/system/bin/mkswap "$Z" >>"$TAG" 2>&1 || { log "mkswap failed"; exit 1; }
/system/bin/swapon "$Z" 2>>"$TAG" || { log "swapon failed"; exit 1; }
log "done disksize=$(cat "$SYS/disksize")"

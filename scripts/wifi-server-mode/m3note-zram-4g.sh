#!/system/bin/sh
unset LD_PRELOAD LD_LIBRARY_PATH
BB=/data/local/tmp/busybox
STATE=/data/m3note-wifi-server
LOCK=$STATE/zram-running
SYS=/sys/block/zram0
Z=/dev/block/zram0
TARGET=4294967296
mkdir -p "$STATE"
chmod 700 "$STATE"
if ! mkdir "$LOCK" 2>/dev/null; then
    oldpid=$(cat "$LOCK/pid" 2>/dev/null)
    case "$oldpid" in
        ''|*[!0-9]*) ;;
        *) if [ -r "/proc/$oldpid/cmdline" ] && "$BB" tr '\000' ' ' < "/proc/$oldpid/cmdline" | "$BB" grep -q '/data/m3note-zram-4g.sh'; then exit 0; fi ;;
    esac
    rm -f "$LOCK/pid"
    rmdir "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null || exit 1
fi
echo $$ > "$LOCK/pid"
trap 'rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null' EXIT
trap 'exit 1' TERM INT
LOG=$STATE/zram.log
size=$("$BB" stat -c %s "$LOG" 2>/dev/null)
if [ "${size:-0}" -gt 65536 ]; then mv -f "$LOG" "$STATE/zram.previous.log"; fi
exec >>"$LOG" 2>&1
log() { echo "[$(date '+%F %T')] $*"; }
log "start boot=$(cat /proc/sys/kernel/random/boot_id) target=$TARGET"
i=0
while ! "$BB" grep -q '^/dev/block/zram0[[:space:]]' /proc/swaps; do
    [ "$i" -lt 60 ] || { log 'FAIL: init did not activate zram; left unchanged'; exit 1; }
    "$BB" sleep 1
    i=$((i + 1))
done
current=$(cat "$SYS/disksize")
if [ "$current" = "$TARGET" ]; then log 'PASS: already 4 GiB and active'; exit 0; fi
available=$("$BB" awk '/^MemAvailable:/{print $2}' /proc/meminfo)
used=$("$BB" awk '$1=="/dev/block/zram0"{print $4}' /proc/swaps)
if [ "${available:-0}" -lt "$(( ${used:-0} + 131072 ))" ]; then
    log "FAIL: insufficient headroom for swapoff; available_KiB=$available used_KiB=$used; left unchanged"
    exit 1
fi
restore() {
    log "FAIL: restore previous capacity=$current"
    echo 1 > "$SYS/reset" && echo "$current" > "$SYS/disksize" && /system/bin/mkswap "$Z" && /system/bin/swapon "$Z"
    log "restore_status=$?"
    exit 1
}
/system/bin/swapoff "$Z" || { log 'FAIL: swapoff failed; did not reset'; exit 1; }
echo 1 > "$SYS/reset" || { /system/bin/swapon "$Z"; log 'FAIL: reset failed'; exit 1; }
echo "$TARGET" > "$SYS/disksize" || restore
/system/bin/mkswap "$Z" || restore
/system/bin/swapon "$Z" || restore
[ "$(cat "$SYS/disksize")" = "$TARGET" ] && "$BB" grep -q '^/dev/block/zram0[[:space:]]' /proc/swaps || restore
log 'PASS: 4 GiB active'
cat /proc/swaps
cat "$SYS/comp_algorithm"

#!/system/bin/sh
# Magisk service.d hook: run a Linux Tailscale node alongside the Ubuntu/Docker
# service.
#
# ===========================================================================
# REV 3 (2026-10-15 evening): split entry / watchdog so service.d can advance
# ===========================================================================
# Magisk v16.3 executes service.d entries SERIALLY and waitpid()s each one
# before starting the next (native/jni/core/bootstages.c, exec_common_script()).
# REV 2 ended in `while :; do ... sleep 30; done`, so it never exited, and no
# script after it in the directory ever ran - in particular
# service.d/m3note-io-tuning.sh never executed at boot (its log had no boot
# entries while `ps` showed this script still alive minutes after boot).
#
# REV 3 keeps the same runtime behaviour but: the service.d entry point
# detaches the persistent loop with setsid and exits IMMEDIATELY.
# RULE FOR THIS DEVICE: every service.d script must exit promptly; anything
# long-running has to detach (setsid ... &). A never-exiting script blocks the
# whole chain (docker-server is the only other slow one: ~60 s, then it exits).
#
# ===========================================================================
# REV 2 (2026-10-15): the busybox-`ip` masked-fwmark bug (kept)
# ===========================================================================
# Symptom: after every reboot, tailscaled could not reach the control plane
# ("dial tcp ...: network is unreachable") and the node showed offline, while
# `ssh` over the LAN still worked.  The corrective rule
#     ip rule add pref 5205 fwmark 0x80000/0xff0000 lookup <iface>
# was simply never present after a boot - even though the boot script's loop is
# alive and sleeping normally.
#
# Root cause (reproduced on hardware by running this script with two different
# PATHs, same device, rule deleted beforehand):
#   * Magisk 16.3 puts its internal busybox first in PATH for service.d hooks,
#     so `ip` resolves to busybox's `ip`, not toybox's /system/bin/ip.
#   * busybox's `ip rule show` renders the mark WITHOUT its mask:
#         busybox: 5210: from all fwmark 0x80000 lookup main
#         toybox : 5210: from all fwmark 0x80000/0xff0000 lookup main
#     and its `ip rule add` with a masked fwmark spec does not take effect.
#   * Result with the plain `ip` name:
#         PATH=busybox:/system/bin  -> rule NOT added   (this is boot)
#         PATH=/system/bin:busybox  -> rule added       (manual test)
#
# Fix (kept in REV 3): never rely on PATH here - call toybox's ip by absolute
# path, and match the mark without requiring the mask suffix.
#
# Install (PC; the device-side step runs as root):
#   adb push project/kernel/m3note-tailscale-fixed.sh /data/local/tmp/
#   adb shell "su -c 'cp /data/local/tmp/m3note-tailscale-fixed.sh /sbin/.core/img/.core/service.d/m3note-tailscale.sh; chmod 755 /sbin/.core/img/.core/service.d/m3note-tailscale.sh'"
#   adb shell "su -c 'mv -f /sbin/.core/img/.core/service.d/m3note-tailscale.sh.bak /data/local/tmp/m3note-tailscale.sh.bak.old'"

exec >>/data/local/tmp/m3note-tailscale-boot.log 2>&1 </dev/null
UB=/data/ubuntu
IP=/system/bin/ip                 # toybox ip - do NOT use the bare name (busybox!)
MARK=0x80000/0xff0000
PREF=5205
PIDFILE=/data/local/tmp/m3note-tailscale-watchdog.pid

if [ "$1" != "--watchdog" ]; then
    # service.d entry point: detach the persistent watchdog, then exit at once
    # so Magisk's serial runner immediately starts the next script.
    /system/bin/setsid /system/bin/sh "$0" --watchdog </dev/null >/dev/null 2>&1 &
    echo "$(date) service.d entry: watchdog detached, exiting"
    exit 0
fi

# ================== watchdog (detached, long-running) ======================
BOOTID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
if [ -f "$PIDFILE" ]; then
    read -r W_BOOTID W_PID < "$PIDFILE"
fi
if [ -n "$W_BOOTID" ] && [ "$W_BOOTID" = "$BOOTID" ] && [ -n "$W_PID" ] \
        && kill -0 "$W_PID" 2>/dev/null; then
    case "$(cat /proc/$W_PID/cmdline 2>/dev/null | tr '\0' ' ')" in
        *m3note-tailscale*)
            echo "$(date) watchdog already running (pid $W_PID), exiting"
            exit 0
            ;;
    esac
fi
echo "$BOOTID $$" > "$PIDFILE"
echo "$(date) watchdog started (pid $$)"

while [ ! -r "$UB/proc/uptime" ]; do sleep 2; done
mkdir -p /dev/net "$UB/run/tailscale" "$UB/var/lib/tailscale"
[ -e /dev/net/tun ] || ln -s /dev/tun /dev/net/tun
chmod 700 "$UB/var/lib/tailscale"

# Android keeps its default route in a table named after the network interface.
# Tailscale marks its own transport packets and normally looks in Linux's main
# table, so route only those packets through Android's active network table.
last_iface=
while :; do
    iface=$("$IP" -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)
    case "$iface" in
        ""|tailscale0|lo) ;;
        *)
            if "$IP" -4 route show table "$iface" 2>/dev/null | grep -q '^default '; then
                # match the mark without demanding the /mask suffix (format tolerant)
                rule_ok=$("$IP" rule show | grep -cE "^$PREF:.*fwmark 0x80000.*lookup $iface")
                if [ "$iface" != "$last_iface" ] || [ "$rule_ok" != "1" ]; then
                    # drop stale/duplicate copies, then install exactly one
                    while "$IP" rule del pref $PREF fwmark $MARK lookup "$iface" 2>/dev/null; do :; done
                    "$IP" rule del pref $PREF fwmark $MARK 2>/dev/null
                    if "$IP" rule add pref $PREF fwmark $MARK lookup "$iface"; then
                        last_iface=$iface
                        echo "$(date) Tailscale transport route: $iface (rule installed)"
                    else
                        echo "$(date) ip rule add FAILED for $iface" >&2
                    fi
                fi
            fi
            ;;
    esac
    if ! pidof tailscaled >/dev/null 2>&1; then
        chroot "$UB" /usr/bin/env -u LD_PRELOAD PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/sh -c 'nohup tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock >> /var/log/tailscaled.log 2>&1 < /dev/null &'
    fi
    sleep 30
done

#!/system/bin/sh
# Run in a root Android shell. Keep app data; restore this task's original state.
unset LD_PRELOAD LD_LIBRARY_PATH
STATE=/data/m3note-wifi-server
BACKUP=$STATE/backup
BB=/data/local/tmp/busybox
[ -f "$BACKUP/network-settings.before" ] && [ -f "$BACKUP/server-network-extra.before" ] || exit 1
rm -f /sbin/.core/img/.core/service.d/m3note-wifi-server.sh
# Do not race a still-running application of server mode.
if "$BB" pgrep -f '^/system/bin/sh /data/m3note-wifi-server.sh([[:space:]]|$)' >/dev/null; then
    echo 'Server-mode startup is still running. Wait for completion and rerun rollback.'
    exit 1
fi
pm unhide --user 0 com.meizu.cloud
pm unhide --user 0 com.android.incallui
for pkg in com.android.dialer com.android.incallui com.android.mms com.android.mms.service com.meizu.callsetting com.activate.activatephone com.android.flyme.bridge.softsim com.flyme.virtual.softsim com.flyme.telecom.usagedata.service com.meizu.cloud com.meizu.account com.meizu.mzsyncservice com.meizu.flyme.service.find; do
    pm default-state --user 0 "$pkg"
done
while IFS='=' read -r key value; do
    case "$key" in wifi_sleep_policy|mobile_data|data_roaming) ;; *) continue ;; esac
    if [ "$value" = null ]; then settings delete global "$key"; else settings put global "$key" "$value"; fi
done < "$BACKUP/server-network-extra.before"
settings put global airplane_mode_on 0
am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false
"$BB" sleep 3
svc wifi enable
# Restore the previous capacity hooks. Reboot applies it without forcing a
# potentially large live swapoff. The old hook had mode 0644; preserve its mode.
cp -p "$BACKUP/m3note-model.sh" /sbin/.core/img/.core/post-fs-data.d/m3note-model.sh
cp -p "$BACKUP/m3note-zram-2g.sh" /sbin/.core/img/.core/service.d/m3note-zram-2g.sh
rm -f /sbin/.core/img/.core/service.d/m3note-zram-4g.sh
echo 'Restored original package and network settings. Reboot to restore original swap startup behavior.'

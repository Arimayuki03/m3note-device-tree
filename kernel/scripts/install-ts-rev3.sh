#!/system/bin/sh
# One-shot installer (run as root; service.d writes must come from you):
#   1. back up the current (rev2) tailscale hook
#   2. install rev3 - its service.d entry detaches the watchdog and EXITS,
#      so Magisk's serial service.d chain (waitpid after every script) can
#      finally reach the scripts that come after it, i.e. m3note-io-tuning.sh
#   3. move m3note-tailscale.sh.bak OUT of service.d - it is another
#      never-exiting script and would block the chain all over again
#
# Run:  adb shell "su -c 'sh /data/local/tmp/install-ts-rev3.sh'"
SD=/sbin/.core/img/.core/service.d
DST=$SD/m3note-tailscale.sh
SRC=/data/local/tmp/m3note-tailscale-fixed.sh
WANT_MD5=5a34ebcf85b2cd4a983c927cd33e3239

echo "== preflight =="
[ -f "$SRC" ] || { echo "FAIL: missing $SRC"; exit 1; }
[ -f "$DST" ] || { echo "FAIL: missing $DST"; exit 1; }
set -- $(md5sum "$SRC")
SRC_MD5=$1
echo "src md5 = $SRC_MD5"
echo "want    = $WANT_MD5"
[ "$SRC_MD5" = "$WANT_MD5" ] || { echo "FAIL: source is not the tested rev3"; exit 1; }

echo "== 1) backup the current (rev2) hook =="
if [ -f /data/local/tmp/m3note-tailscale.rev2.sh ]; then
    echo "backup already exists, keeping it"
else
    cp -f "$DST" /data/local/tmp/m3note-tailscale.rev2.sh \
        && echo "backup -> /data/local/tmp/m3note-tailscale.rev2.sh"
fi

echo "== 2) install rev3 =="
cp -f "$SRC" "$DST" && chmod 755 "$DST" && echo installed

echo "== 3) move the old .bak out of service.d =="
if [ -f "$SD/m3note-tailscale.sh.bak" ]; then
    mv -f "$SD/m3note-tailscale.sh.bak" /data/local/tmp/m3note-tailscale.sh.bak.old \
        && echo "moved -> /data/local/tmp/m3note-tailscale.sh.bak.old"
else
    echo "no .bak present"
fi

echo "== 4) verify =="
sync
md5sum "$DST"
ls -la "$SD/"
echo "== done =="

#!/usr/bin/env bash
# =============================================================================
# m3note: swap the container-enabled kernel into the boot partition
# =============================================================================
# What this does
#   1. waits for the phone over adb, confirms it is booted into Flyme
#   2. confirms Magisk root (uid=0)
#   3. hashes the LIVE boot partition and compares it with the known-good
#      baseline dump (boot-magisk.img). Mismatch => abort (nothing written).
#   4. copies the rollback image + the new image to the phone
#   5. writes the chosen image to the boot partition, then READS IT BACK and
#      compares sha256 (write verification); on mismatch it auto-restores.
#   6. reboots and verifies: kernel build string, cgroups, namespaces
#
# Safety
#   * nothing is written before step 3 proves the baseline matches
#   * the write is a single 16 MiB dd, verified by read-back
#   * rollback image stays on both PC and phone
#   * rollback:  ./flash-containers-boot.sh --rollback
#   * do NOT flash lk/preloader (BROM rescue unverified)
#
# If the phone fails to boot after the swap (bootloop):
#   hold Vol+ (and/or Power) to reach fastboot, then on the PC:
#       fastboot boot "<PROJECT_ROOT>/project/twrp.img"
#       adb push "<PROJECT_ROOT>/project/m3note-backup/boot-magisk.img" /tmp/boot-rollback.img
#       adb shell "dd if=/tmp/boot-rollback.img of=/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/boot bs=4096; sync"
#       adb reboot
#
# Usage:  ./flash-containers-boot.sh [--rollback]
# =============================================================================
set -uo pipefail

export MSYS_NO_PATHCONV=1
ADB_DIR="/c/Users/<USER>/AppData/Local/Microsoft/WinGet/Packages/Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe/platform-tools"
ADB="$ADB_DIR/adb.exe"
FB="$ADB_DIR/fastboot.exe"
[ -x "$ADB" ] || ADB=adb
[ -x "$FB" ]  || FB=fastboot

# <PROJECT_ROOT>\project is the canonical, durable location for all artifacts
PROJ="<PROJECT_ROOT>/project"
NEW_IMG="$PROJ/m3note-backup/boot-containers.img"
ROLLBACK_IMG="$PROJ/m3note-backup/boot-magisk.img"

# content hashes re-verified on the PC (sha256)
NEW_SHA="1e718ef7f2ee1c29949a7ffa240293d5eb529fe60d67b1159d2ccd77a23b1702"
ROLLBACK_SHA="39d96c3a3e5df4b45a705ebbbd8a573db0b9ca64fd43d5735a87f21ce17e604b"

PART="/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/boot"
TMP="/data/local/tmp"

say() { printf '\n=== %s ===\n' "$*"; }
die() { printf '\n!!! ABORT: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight
say "0. PC-side preflight"
[ -f "$NEW_IMG" ]      || die "missing $NEW_IMG"
[ -f "$ROLLBACK_IMG" ] || die "missing $ROLLBACK_IMG"
got_new=$(sha256sum "$NEW_IMG"      | cut -d' ' -f1)
got_rb=$(sha256sum  "$ROLLBACK_IMG" | cut -d' ' -f1)
printf '  boot-containers.img  %s\n' "$got_new"
printf '  boot-magisk.img      %s\n' "$got_rb"
[ "$got_new" = "$NEW_SHA" ] || die "boot-containers.img hash drifted from the validated artifact"
[ "$got_rb"  = "$ROLLBACK_SHA" ] || die "rollback image hash drifted"
echo "  local artifacts match the validated hashes"

# ---------------------------------------------------------------- device
say "1. waiting for the phone (adb)"
"$ADB" wait-for-device
bc=""
for i in $(seq 1 60); do
  st=$("$ADB" get-state 2>&1 | tr -d '\r')
  bc=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
  [ "$st" = "device" ] && [ "$bc" = "1" ] && break
  printf '  [%s] state=%s boot_completed=%s\n' "$i" "$st" "${bc:-?}"
  sleep 5
done
[ "${bc:-}" = "1" ] || die "phone never reported boot_completed=1 (still in recovery/bootloader?)"
echo "  device booted; state=$st"

say "2. checking Magisk root"
id_out=$("$ADB" shell "su -c id" 2>&1 | tr -d '\r')
case "$id_out" in
  *uid=0*) ;;
  *) id_out=$("$ADB" shell "su 0 id" 2>&1 | tr -d '\r') ;;
esac
echo "  root probe -> $id_out"
case "$id_out" in
  *uid=0*) echo "  root confirmed" ;;
  *) die "no root (uid=0 not returned). Install the Manager first: adb install \"\$PROJ/MagiskManager-5.6.4.apk\" and grant root" ;;
esac

say "3. verifying the LIVE boot partition against the baseline dump"
live_sha=$("$ADB" shell "su -c 'dd if=$PART bs=4096 2>/dev/null | sha256sum'" 2>&1 | tr -d '\r' | awk '{print $1}')
[ -n "$live_sha" ] || live_sha=$("$ADB" shell "su 0 sh -c 'dd if=$PART bs=4096 2>/dev/null | sha256sum'" 2>&1 | tr -d '\r' | awk '{print $1}')
echo "  live boot sha256 = ${live_sha:-<empty>}"
echo "  baseline sha256  = $ROLLBACK_SHA"
if [ "$live_sha" != "$ROLLBACK_SHA" ]; then
  save="$PROJ/m3note-backup/boot-live-$(date +%s).img"
  echo "  !! live boot partition does NOT match the baseline dump."
  echo "  !! saving the live dump to $save"
  "$ADB" exec-out "su -c 'dd if=$PART bs=4096 2>/dev/null'" > "$save" 2>/dev/null
  die "re-run boot_pack_containers.py against this new dump before flashing anything"
fi
echo "  match: boot-magisk.img is a valid rollback for what is currently flashed"

# ---------------------------------------------------------------- choose image
if [ "${1:-}" = "--rollback" ]; then
  SRC="$ROLLBACK_IMG"; SRC_NAME="boot-magisk.img  (ROLLBACK to stock kernel)"; SRC_SHA="$ROLLBACK_SHA"
else
  SRC="$NEW_IMG";      SRC_NAME="boot-containers.img (custom container kernel)";  SRC_SHA="$NEW_SHA"
fi
BASE=$(basename "$SRC")

say "4. copying images to the phone"
"$ADB" push "$SRC"          "$TMP/$BASE"              || die "push failed"
"$ADB" push "$ROLLBACK_IMG" "$TMP/boot-rollback.img"  || die "push failed"
"$ADB" shell "su -c 'sha256sum $TMP/$BASE'" | tr -d '\r'

say "5. writing $SRC_NAME to the boot partition"
echo "  target: $PART"
"$ADB" shell "su -c 'dd if=$TMP/$BASE of=$PART bs=4096 2>&1; sync'" | tr -d '\r'

say "6. read-back verification"
back=$("$ADB" shell "su -c 'dd if=$PART bs=4096 2>/dev/null | sha256sum'" 2>&1 | tr -d '\r' | awk '{print $1}')
echo "  read back = ${back:-<empty>}"
echo "  expected  = $SRC_SHA"
if [ "$back" != "$SRC_SHA" ]; then
  echo "  !! read-back MISMATCH -- restoring the rollback image now"
  "$ADB" shell "su -c 'dd if=$TMP/boot-rollback.img of=$PART bs=4096 2>&1; sync'" | tr -d '\r'
  rb=$("$ADB" shell "su -c 'dd if=$PART bs=4096 2>/dev/null | sha256sum'" 2>&1 | tr -d '\r' | awk '{print $1}')
  echo "  after restore, boot partition = ${rb:-<empty>}"
  die "write did not verify; rollback image restored"
fi
echo "  write verified byte-for-byte"

say "7. rebooting into Flyme (first boot may take 5-10 min)"
"$ADB" reboot
sleep 20
"$ADB" wait-for-device
bc=""
for i in $(seq 1 90); do
  bc=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
  [ "$bc" = "1" ] && break
  printf '  [%s] boot_completed=%s\n' "$i" "${bc:-?}"
  sleep 10
done
[ "${bc:-}" = "1" ] || die "did not reach boot_completed=1. Recover via fastboot boot twrp.img, then dd boot-rollback.img back to $PART (see header comment)"

say "8. verifying the new kernel and container features"
"$ADB" shell "su -c 'uname -a'" | tr -d '\r'
echo "--- cgroup controllers (/proc/cgroups) ---"
"$ADB" shell "su -c 'cat /proc/cgroups'" | tr -d '\r'
echo "--- namespaces (/proc/self/ns/) ---"
"$ADB" shell "su -c 'ls -l /proc/self/ns/'" | tr -d '\r'
echo "--- cgroup mounts ---"
"$ADB" shell "su -c 'mount | grep -i cgroup'" | tr -d '\r'
echo "--- overlayfs present? ---"
"$ADB" shell "su -c 'cat /proc/filesystems | grep -i overlay'" | tr -d '\r'

say "DONE"
cat <<'EOT'
Expected in the output above:
  * uname shows:  3.18.35 (root@builder) (gcc version 4.9.x ...) #3 SMP PREEMPT Wed Oct 14 ... 2026
    (i.e. NOT "flyme@mz-builder-5 ... Jun 23 2018" anymore)
  * /proc/cgroups lists memory, devices, freezer, cpu, cpuacct, blkio
  * /proc/self/ns/ contains mnt net ipc uts pid user
  * overlayfs appears in /proc/filesystems
Next: rebuild the Linux chroot (project/sources/ + project/m3note-linux-server.md),
then install docker.io and run a real container.
EOT

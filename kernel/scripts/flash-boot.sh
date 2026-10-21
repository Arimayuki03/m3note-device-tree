#!/usr/bin/env bash
# =============================================================================
# m3note: write a kernel image into the boot partition, with rollback.
# =============================================================================
# Generalized version of the per-build flash scripts (flash-fix30.sh).
#
#   1. PC preflight: the new image exists and its hash is computed
#   2. wait for adb + sys.boot_completed=1, confirm root
#   3. dump the LIVE boot partition to m3note-backup/boot-live-<ts>.img and
#      refuse to continue unless it matches one of the known-good images
#      (that dump becomes the rollback image, so whatever is really there is
#      what gets restored)
#   4. push, dd-write, then READ BACK the whole partition and compare hashes
#   5. on mismatch: restore the dumped rollback image and verify it
#   6. reboot and print the running kernel version
#
# Usage:  bash flash-boot.sh <path-to-new-image> [--no-reboot]
# Rollback afterwards:  point the script at any known-good image, e.g.
#         bash kernel/scripts/flash-boot.sh <ARTIFACTS>/boot-fix30-test.img
#
#   * the device's sha256sum is absent -> md5sum is used (present)
#   * the device's dd rejects "1M" -> block size is given in bytes
#   * do NOT flash lk/preloader (BROM rescue unverified)
# =============================================================================
set -uo pipefail

export MSYS_NO_PATHCONV=1
ADB_DIR="/c/Users/<USER>/AppData/Local/Microsoft/WinGet/Packages/Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe/platform-tools"
ADB="$ADB_DIR/adb.exe"
[ -x "$ADB" ] || ADB=adb

PROJ="<PROJECT_ROOT>"          # git-bash form for local tools
PROJ_W="<PROJECT_ROOT>"        # windows form for adb.exe
BACKUP="$PROJ/m3note-backup"
BACKUP_W="$PROJ_W/m3note-backup"

PART="/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/boot"
TMP="/data/local/tmp"

NEW_IMG_IN="${1:-}"
NO_REBOOT="${2:-}"
[ -n "$NEW_IMG_IN" ] || { echo "usage: bash flash-boot.sh <path-to-new-image> [--no-reboot]"; exit 2; }
case "$NEW_IMG_IN" in
  /*|[A-Za-z]:*) NEW_IMG="$NEW_IMG_IN"; NEW_IMG_W="$NEW_IMG_IN" ;;
  *)            NEW_IMG="$(cd "$(dirname "$NEW_IMG_IN")" && pwd)/$(basename "$NEW_IMG_IN")"
                NEW_IMG_W="$NEW_IMG" ;;
esac
# normalise to the windows form adb needs
NEW_IMG_W="$(printf '%s' "$NEW_IMG" | sed 's#^/d/#D:/#')"

say() { printf '\n=== %s ===\n' "$*"; }
die() { printf '\n!!! ABORT: %s\n' "$*" >&2; exit 1; }

devsh() {
  local cmd="$1" out
  out=$("$ADB" shell "su -c '$cmd'" 2>&1 | tr -d '\r')
  case "$out" in
    *"not found"*|*"Permission denied"*|*"invalid option"*)
      out=$("$ADB" shell "su 0 sh -c '$cmd'" 2>&1 | tr -d '\r') ;;
  esac
  printf '%s' "$out"
}

md5_of() { md5sum "$1" | cut -d' ' -f1; }

# Read the boot partition with the page cache dropped first: a buffered read can
# otherwise serve stale pages of the *previous* content and make a successful
# write look like it was rejected (observed on this device).
part_md5() {
  devsh "echo 3 > /proc/sys/vm/drop_caches; dd if=$PART bs=4096 2>/dev/null | md5sum" | awk '{print $1}'
}

# ---------------------------------------------------------------- preflight
say "0. PC-side preflight"
[ -f "$NEW_IMG" ] || die "missing image: $NEW_IMG"
NEW_MD5=$(md5_of "$NEW_IMG")
printf '  %s\n  md5 %s\n' "$NEW_IMG" "$NEW_MD5"
printf '  adb push source: %s\n' "$NEW_IMG_W"

say "1. waiting for the phone"
"$ADB" wait-for-device
for i in $(seq 1 60); do
  st=$("$ADB" get-state 2>&1 | tr -d '\r')
  bc=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
  [ "$st" = "device" ] && [ "$bc" = "1" ] && break
  printf '  [%s] state=%s boot_completed=%s\n' "$i" "$st" "${bc:-?}"
  sleep 5
done
[ "${bc:-}" = "1" ] || die "phone never reported boot_completed=1"
echo "  device booted"

say "2. root check"
id_out=$(devsh id)
echo "  root probe -> $id_out"
case "$id_out" in *uid=0*) echo "  root confirmed" ;; *) die "no root" ;; esac

say "3. dumping + validating the LIVE boot partition"
LIVE_MD5=$(part_md5)
[ -n "$LIVE_MD5" ] || die "could not read the live boot partition"
printf '  live md5 = %s\n' "$LIVE_MD5"

# the live partition must be one of the images we trust
known_ok=0
for img in "$BACKUP"/boot-fix22-test.img "$BACKUP"/boot-fix27-test.img \
           "$BACKUP"/boot-fix28-test.img "$BACKUP"/boot-fix29-test.img \
           "$BACKUP"/boot-fix30-test.img "$BACKUP"/boot-fix31-test.img \
           "$BACKUP"/boot-fix32-test.img; do
  [ -f "$img" ] || continue
  if [ "$(md5_of "$img")" = "$LIVE_MD5" ]; then
    printf '  live partition matches %s\n' "$(basename "$img")"
    known_ok=1
    break
  fi
done
[ "$known_ok" = "1" ] || die "live boot partition is not a known-good image; refusing to overwrite it"

ROLLBACK_IMG="$BACKUP/boot-live-$(date +%s).img"
ROLLBACK_IMG_W=$(printf '%s' "$ROLLBACK_IMG" | sed 's#^/d/#D:/#')
devsh "dd if=$PART of=$TMP/boot-live.img bs=4096" >/dev/null
# adb pull runs as the `shell` user, so the root-owned dump must be made readable
devsh "chmod 644 $TMP/boot-live.img" >/dev/null
"$ADB" pull "$TMP/boot-live.img" "$ROLLBACK_IMG_W" >/dev/null 2>&1 || die "could not save the rollback dump"
[ "$(md5_of "$ROLLBACK_IMG")" = "$LIVE_MD5" ] || die "rollback dump hash mismatch"
printf '  rollback dump saved: %s\n' "$ROLLBACK_IMG"

say "4. writing the new kernel"
"$ADB" push "$NEW_IMG_W" "$TMP/boot-new.img" >/dev/null || die "push failed"
devsh "dd if=$TMP/boot-new.img of=$PART bs=4096" | tail -2
devsh "sync" >/dev/null

say "5. read-back verification"
RB_MD5=$(part_md5)
printf '  read-back md5 = %s\n  expected  md5 = %s\n' "${RB_MD5:-<empty>}" "$NEW_MD5"
if [ "$RB_MD5" != "$NEW_MD5" ]; then
  echo "  !!! write did not take - restoring the rollback image"
  "$ADB" push "$(printf '%s' "$ROLLBACK_IMG" | sed 's#^/d/#D:/#')" "$TMP/boot-rb.img" >/dev/null 2>&1 || die "rollback push failed"
  devsh "dd if=$TMP/boot-rb.img of=$PART bs=4096" | tail -1
  RB2=$(part_md5)
  [ "$RB2" = "$LIVE_MD5" ] && echo "  rollback restored and verified" || echo "  !!! restore unverified: $RB2"
  die "boot partition write rejected by the device"
fi
echo "  write verified"

if [ "$NO_REBOOT" = "--no-reboot" ]; then
  echo "  (--no-reboot: not rebooting; the new kernel takes effect on the next boot)"
  exit 0
fi

say "6. rebooting"
"$ADB" reboot
sleep 25
"$ADB" wait-for-device
for i in $(seq 1 45); do
  bc=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
  [ "$bc" = "1" ] && break
  sleep 5
done
echo "  $("$ADB" shell cat /proc/version 2>/dev/null | tr -d '\r')"

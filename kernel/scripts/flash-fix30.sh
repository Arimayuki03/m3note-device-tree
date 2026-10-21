#!/usr/bin/env bash
# =============================================================================
# m3note: persist build #30 into the boot partition
# =============================================================================
# #30 carries: aw8738 speaker-amp driver, ltr579 light/proximity driver (+ alsps
# framework registration), IRTX disabled (volume-up key).  Verified on hardware
# in RAM-boot mode; this script makes it survive reboots.
#
# Safety, mirroring the project's existing flash flow:
#   1. PC-side hash preflight against the validated artifacts
#   2. wait for adb + sys.boot_completed=1
#   3. root check (Magisk: `su -c` then `su 0`)
#   4. verify the LIVE boot partition matches the known-good baseline
#      (boot-fix22-test.img = what the phone boots today); mismatch -> dump the
#      live partition to a timestamped file and ABORT without writing
#   5. dd the new image, then READ IT BACK and compare hashes; on mismatch
#      automatically restore the baseline image
#   6. reboot and verify the running kernel reports #30
#
# Notes
#   * the device's sha256sum is absent, so verification uses md5sum (present).
#   * the device's dd rejects "1M"; block size is given in bytes.
#   * rollback by hand at any time:  bash flash-fix30.sh --rollback
#   * do NOT flash lk/preloader (BROM rescue unverified)
#
# Usage:  bash flash-fix30.sh [--rollback]
# =============================================================================
set -uo pipefail

export MSYS_NO_PATHCONV=1
ADB_DIR="/c/Users/<USER>/AppData/Local/Microsoft/WinGet/Packages/Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe/platform-tools"
ADB="$ADB_DIR/adb.exe"
[ -x "$ADB" ] || ADB=adb

PROJ="<PROJECT_ROOT>"        # git-bash form, for local tools (md5sum, test)
PROJ_W="<PROJECT_ROOT>"      # windows form, for adb.exe (MSYS_NO_PATHCONV=1)
NEW_IMG="$PROJ/m3note-backup/boot-fix30-test.img"
BASE_IMG="$PROJ/m3note-backup/boot-fix22-test.img"
NEW_IMG_W="$PROJ_W/m3note-backup/boot-fix30-test.img"
BASE_IMG_W="$PROJ_W/m3note-backup/boot-fix22-test.img"

NEW_MD5="171769c9f101f8f0cc59207cfc13285b"
BASE_MD5="cc71e4768a1bad046aa428c8b702276c"

PART="/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/boot"
TMP="/data/local/tmp"

say() { printf '\n=== %s ===\n' "$*"; }
die() { printf '\n!!! ABORT: %s\n' "$*" >&2; exit 1; }

# sh wrapper that works with both Magisk su forms
devsh() {
  local cmd="$1" out
  out=$("$ADB" shell "su -c '$cmd'" 2>&1 | tr -d '\r')
  case "$out" in
    *"not found"*|*"Permission denied"*|*"invalid option"*)
      out=$("$ADB" shell "su 0 sh -c '$cmd'" 2>&1 | tr -d '\r') ;;
  esac
  printf '%s' "$out"
}

if [ "${1:-}" = "--rollback" ]; then
  say "rollback to the known-good baseline"
  [ -f "$BASE_IMG" ] || die "missing $BASE_IMG"
  got=$(md5sum "$BASE_IMG" | cut -d' ' -f1)
  [ "$got" = "$BASE_MD5" ] || die "baseline image hash drifted: $got"
  "$ADB" wait-for-device
  "$ADB" push "$BASE_IMG_W" "$TMP/boot-rollback.img" >/dev/null || die "push failed"
  out=$(devsh "dd if=$TMP/boot-rollback.img of=$PART bs=4096; sync")
  echo "$out" | tail -2
  live=$(devsh "dd if=$PART bs=4096 2>/dev/null | md5sum" | awk '{print $1}')
  [ "$live" = "$BASE_MD5" ] || die "rollback read-back mismatch: $live"
  echo "  rollback written and verified"
  "$ADB" reboot
  exit 0
fi

# ---------------------------------------------------------------- preflight
say "0. PC-side preflight"
for f in "$NEW_IMG" "$BASE_IMG"; do [ -f "$f" ] || die "missing $f"; done
got_new=$(md5sum "$NEW_IMG"  | cut -d' ' -f1)
got_base=$(md5sum "$BASE_IMG" | cut -d' ' -f1)
printf '  boot-fix30-test.img  md5 %s\n' "$got_new"
printf '  boot-fix22-test.img  md5 %s\n' "$got_base"
[ "$got_new"  = "$NEW_MD5"  ] || die "new image hash drifted from the validated artifact"
[ "$got_base" = "$BASE_MD5" ] || die "baseline image hash drifted"
echo "  local artifacts match the validated hashes"

# ---------------------------------------------------------------- device
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

say "3. verifying the LIVE boot partition against the baseline"
live=$(devsh "dd if=$PART bs=4096 2>/dev/null | md5sum" | awk '{print $1}')
printf '  live     md5 = %s\n  baseline md5 = %s\n' "${live:-<empty>}" "$BASE_MD5"
if [ "$live" != "$BASE_MD5" ]; then
  save="$PROJ/m3note-backup/boot-live-$(date +%s).img"
  save_w="$PROJ_W/m3note-backup/boot-live-$(date +%s).img"
  echo "  live partition differs from the baseline; saving a copy to $save"
  devsh "dd if=$PART of=$TMP/boot-live.img bs=4096" >/dev/null
  "$ADB" pull "$TMP/boot-live.img" "$save_w" >/dev/null 2>&1 || die "could not save the live partition"
  die "refusing to write over an unknown boot partition (copy saved: $save)"
fi
echo "  live partition matches the known-good baseline (#22)"

say "4. pushing and writing #30"
"$ADB" push "$NEW_IMG_W" "$TMP/boot-fix30.img" >/dev/null || die "push failed"
out=$(devsh "dd if=$TMP/boot-fix30.img of=$PART bs=4096")
echo "$out" | tail -2
devsh "sync" >/dev/null

say "5. read-back verification"
live2=$(devsh "dd if=$PART bs=4096 2>/dev/null | md5sum" | awk '{print $1}')
printf '  read-back md5 = %s\n  expected  md5 = %s\n' "${live2:-<empty>}" "$NEW_MD5"
if [ "$live2" != "$NEW_MD5" ]; then
  echo "  !!! write did not take (write protection?) - restoring the baseline"
  "$ADB" push "$BASE_IMG_W" "$TMP/boot-rollback.img" >/dev/null 2>&1 || die "rollback push failed"
  out=$(devsh "dd if=$TMP/boot-rollback.img of=$PART bs=4096")
  echo "$out" | tail -2
  rb=$(devsh "dd if=$PART bs=4096 2>/dev/null | md5sum" | awk '{print $1}')
  [ "$rb" = "$BASE_MD5" ] && echo "  baseline restored and verified" || echo "  !!! restore unverified: $rb"
  die "boot partition write rejected"
fi
echo "  write verified"

say "6. rebooting into the persisted kernel"
"$ADB" reboot
sleep 25
"$ADB" wait-for-device
for i in $(seq 1 40); do
  bc=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
  [ "$bc" = "1" ] && break
  sleep 5
done
ver=$("$ADB" shell cat /proc/version 2>/dev/null | tr -d '\r')
echo "  $ver"
case "$ver" in
  *#30*) echo "  PERSISTED: the phone now boots #30 from its own boot partition" ;;
  *) echo "  !!! unexpected kernel after reboot; rollback: bash flash-fix30.sh --rollback" ;;
esac

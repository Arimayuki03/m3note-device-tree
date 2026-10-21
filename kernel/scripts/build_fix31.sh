#!/bin/bash
# Build #31 for the Meizu m3 note (mt6755, 3.18.35).
#
# Contents = #30 plus one config change:
#   CONFIG_DEFAULT_IOSCHED="deadline"  (was "cfq")
#   -> the eMMC queue starts on the deadline scheduler at boot, so the T1 I/O
#      tuning no longer needs a root boot script.  Measured on this device with
#      the scheduler switched at runtime: 512 MB buffered sequential read went
#      from a 233 MB/s median (cfq) to 258 MB/s (deadline); the main benefit is
#      read latency under mixed read/write load, which is what keeps the UI
#      responsive while a container build hammers the same eMMC.
#
# Everything from #30 is carried unchanged:
#   volume-up key : CONFIG_MTK_IRTX_SUPPORT off          (GPIO104 stays KPCOL1)
#   speaker audio : aw8738 external-PA driver
#   light/proximity: ltr579 driver + alsps framework registration
#
# Usage:  bash <PROJECT_ROOT>/kernel/scripts/build_fix31.sh
set -eu

cd <BUILD_ROOT>/k318/android_kernel_m3note-master
export MTK_PLATFORM=mt6755 MTK_PROJECT=wt6755_66_n
CROSS=<BUILD_ROOT>/toolchain/bin/aarch64-linux-android-
INC="-I$PWD/drivers/misc/mediatek/mu3phy $(find "$PWD/drivers" -type d -name mt6755 | grep -v ppm_v2 | sed 's|^|-I|' | tr '\n' ' ')"
LOGDIR=<BUILD_ROOT>/fix-20261015
LTR=drivers/misc/mediatek/alsps/ltr579/ltr579.c

fail() { echo "PREFLIGHT_FAIL: $1"; exit 1; }

# --- carried fixes -----------------------------------------------------------
grep -q '^# CONFIG_MTK_IRTX_SUPPORT is not set' .config || fail "IRTX still enabled"
grep -q '^CONFIG_MTK_AW8738=y' .config                 || fail "aw8738 not enabled"
grep -q '^CONFIG_MTK_LTR579=y' .config                 || fail "ltr579 not enabled"
grep -q 'compatible = "mediatek,aw8738-pa"' drivers/misc/mediatek/aw8738/aw8738.c \
	|| fail "aw8738 DT compatible missing"
grep -q 'als_register_control_path' "$LTR" || fail "alsps framework registration missing"
grep -q 'i2c_addr		= {0x53' "$LTR"        || fail "ltr579 default address is not 0x53"

# --- this build: deadline as the default I/O scheduler -----------------------
grep -q '^CONFIG_DEFAULT_DEADLINE=y' .config          || fail "DEFAULT_DEADLINE not set"
grep -q '^CONFIG_DEFAULT_IOSCHED="deadline"' .config  || fail "DEFAULT_IOSCHED is not deadline"
grep -q '^CONFIG_IOSCHED_DEADLINE=y' .config          || fail "deadline scheduler not built in"

make ARCH=arm64 CROSS_COMPILE="$CROSS" olddefconfig > "$LOGDIR/olddef31.log" 2>&1

# olddefconfig must not silently revert the choice or the carried fixes
grep -q '^CONFIG_DEFAULT_IOSCHED="deadline"' .config || fail "deadline default lost during olddefconfig"
grep -q '^CONFIG_DEFAULT_DEADLINE=y' .config         || fail "DEFAULT_DEADLINE lost during olddefconfig"
grep -q '^CONFIG_MTK_AW8738=y' .config               || fail "aw8738 lost during olddefconfig"
grep -q '^CONFIG_MTK_LTR579=y' .config               || fail "ltr579 lost during olddefconfig"
grep -q '^# CONFIG_MTK_IRTX_SUPPORT is not set' .config || fail "IRTX re-enabled"

# --- build -------------------------------------------------------------------
make KBUILD_BUILD_VERSION=31 -o tools/dct/DrvGen ARCH=arm64 CROSS_COMPILE="$CROSS" \
	HOSTCFLAGS=-fcommon CC="${CROSS}gcc $INC" -j20 Image.gz > "$LOGDIR/build31.log" 2>&1

cp arch/arm64/boot/Image.gz <PROJECT_ROOT>/kernel/Image.gz-fix31
cp .config <PROJECT_ROOT>/kernel/kernel-config-fix31

echo "PREFLIGHT_OK"
grep '^CONFIG_DEFAULT_IOSCHED' .config
echo BUILD31_DONE

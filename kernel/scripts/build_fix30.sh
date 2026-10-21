#!/bin/bash
# Build #30 for the Meizu m3 note (mt6755, 3.18.35).
#
# Carried fixes (same as #29) plus one addition:
#   1. volume-up key  : CONFIG_MTK_IRTX_SUPPORT disabled (GPIO104 stays KPCOL1)
#   2. speaker audio  : aw8738 external-PA driver (HAL drives /dev/aw8738)
#   3. light/proximity: ltr579 alsps driver for the fitted LTR-579 at 0x53
#   4. (#30) light/prox framework registration: the ltr579 driver now registers
#      als/ps control+data paths, without which alsps.c never polls the driver
#      and never reports to m_alsps_input (so the Android light/proximity
#      sensors produced no events, and the AAL logged "aal:get_data not exsit").
#
# Usage:  bash <PROJECT_ROOT>/kernel/scripts/build_fix30.sh
set -eu

cd <BUILD_ROOT>/k318/android_kernel_m3note-master
export MTK_PLATFORM=mt6755 MTK_PROJECT=wt6755_66_n
CROSS=<BUILD_ROOT>/toolchain/bin/aarch64-linux-android-
INC="-I$PWD/drivers/misc/mediatek/mu3phy $(find "$PWD/drivers" -type d -name mt6755 | grep -v ppm_v2 | sed 's|^|-I|' | tr '\n' ' ')"
LOGDIR=<BUILD_ROOT>/fix-20261015
LTR=drivers/misc/mediatek/alsps/ltr579/ltr579.c

fail() { echo "PREFLIGHT_FAIL: $1"; exit 1; }

# --- fixes 1-3 (carried over) -------------------------------------------------
grep -q '^# CONFIG_MTK_IRTX_SUPPORT is not set' .config || fail "IRTX still enabled"
grep -q '^CONFIG_MTK_AW8738=y' .config                 || fail "aw8738 not enabled"
grep -q '^CONFIG_MTK_LTR579=y' .config                 || fail "ltr579 not enabled"
grep -q 'compatible = "mediatek,aw8738-pa"' drivers/misc/mediatek/aw8738/aw8738.c \
	|| fail "aw8738 DT compatible missing"
grep -q 'i2c_addr		= {0x53' "$LTR" || fail "ltr579 default address is not 0x53"

# --- fix 4 (this build): framework path registration -------------------------
grep -q 'als_register_control_path' "$LTR" || fail "als_register_control_path missing"
grep -q 'als_register_data_path'    "$LTR" || fail "als_register_data_path missing"
grep -q 'ps_register_control_path'  "$LTR" || fail "ps_register_control_path missing"
grep -q 'ps_register_data_path'     "$LTR" || fail "ps_register_data_path missing"

make ARCH=arm64 CROSS_COMPILE="$CROSS" olddefconfig > "$LOGDIR/olddef30.log" 2>&1

grep -q '^CONFIG_MTK_AW8738=y' .config || fail "aw8738 lost during olddefconfig"
grep -q '^CONFIG_MTK_LTR579=y' .config || fail "ltr579 lost during olddefconfig"
grep -q '^# CONFIG_MTK_IRTX_SUPPORT is not set' .config || fail "IRTX re-enabled"

# --- build -------------------------------------------------------------------
make KBUILD_BUILD_VERSION=30 -o tools/dct/DrvGen ARCH=arm64 CROSS_COMPILE="$CROSS" \
	HOSTCFLAGS=-fcommon CC="${CROSS}gcc $INC" -j20 Image.gz > "$LOGDIR/build30.log" 2>&1

cp arch/arm64/boot/Image.gz <PROJECT_ROOT>/kernel/Image.gz-fix30
cp .config <PROJECT_ROOT>/kernel/kernel-config-fix30

echo "PREFLIGHT_OK"
echo BUILD30_DONE

#!/bin/bash
# Build #29 for the Meizu m3 note (mt6755, 3.18.35).
#
# Fixes carried in this build
#   1. volume-up key  : CONFIG_MTK_IRTX_SUPPORT disabled (GPIO104 stays KPCOL1)
#   2. speaker audio  : new aw8738 external-PA driver (missing before, the stock
#                       HAL drives /dev/aw8738; without it the speaker is silent)
#   3. light/proximity: new ltr579 alsps driver (the chip actually fitted is an
#                       LTR-579 at i2c-1 0x53; the tree only had the PA122 driver)
#
# Usage:  bash <PROJECT_ROOT>/kernel/scripts/build_fix29.sh
set -eu

cd <BUILD_ROOT>/k318/android_kernel_m3note-master
export MTK_PLATFORM=mt6755 MTK_PROJECT=wt6755_66_n
CROSS=<BUILD_ROOT>/toolchain/bin/aarch64-linux-android-
INC="-I$PWD/drivers/misc/mediatek/mu3phy $(find "$PWD/drivers" -type d -name mt6755 | grep -v ppm_v2 | sed 's|^|-I|' | tr '\n' ' ')"
LOGDIR=<BUILD_ROOT>/fix-20261015

# --- pre-flight: every fix must be present in the tree/config -----------------
fail() { echo "PREFLIGHT_FAIL: $1"; exit 1; }

grep -q '^# CONFIG_MTK_IRTX_SUPPORT is not set' .config || fail "IRTX still enabled"
grep -q '^CONFIG_MTK_AW8738=y' .config                 || fail "aw8738 not enabled"
grep -q '^CONFIG_MTK_LTR579=y' .config                 || fail "ltr579 not enabled"
test -f drivers/misc/mediatek/aw8738/aw8738.c          || fail "aw8738.c missing"
test -f drivers/misc/mediatek/alsps/ltr579/ltr579.c    || fail "ltr579.c missing"
grep -q 'compatible = "mediatek,aw8738-pa"' drivers/misc/mediatek/aw8738/aw8738.c \
	|| fail "aw8738 DT compatible missing"
grep -q '0x07, 0x03' drivers/misc/mediatek/aw8738/aw8738.c || fail "aw8738 open ioctl missing"
grep -q 'i2c_addr		= {0x53' drivers/misc/mediatek/alsps/ltr579/ltr579.c \
	|| fail "ltr579 default address is not 0x53"

make ARCH=arm64 CROSS_COMPILE="$CROSS" olddefconfig > "$LOGDIR/olddef29.log" 2>&1

# olddefconfig must not silently drop the new symbols
grep -q '^CONFIG_MTK_AW8738=y' .config || fail "aw8738 lost during olddefconfig"
grep -q '^CONFIG_MTK_LTR579=y' .config || fail "ltr579 lost during olddefconfig"
grep -q '^# CONFIG_MTK_IRTX_SUPPORT is not set' .config || fail "IRTX re-enabled by olddefconfig"

# --- build -------------------------------------------------------------------
make KBUILD_BUILD_VERSION=29 -o tools/dct/DrvGen ARCH=arm64 CROSS_COMPILE="$CROSS" \
	HOSTCFLAGS=-fcommon CC="${CROSS}gcc $INC" -j20 Image.gz > "$LOGDIR/build29.log" 2>&1

cp arch/arm64/boot/Image.gz <PROJECT_ROOT>/kernel/Image.gz-fix29
cp .config <PROJECT_ROOT>/kernel/kernel-config-fix29

echo "PREFLIGHT_OK"
echo BUILD29_DONE

#!/bin/bash
# Build #28 for the Meizu m3 note (mt6755, 3.18.35).
#
# Scope: volume-up key fix only.
#
#   Disable the consumer-IR transmitter driver so it stops claiming GPIO104
#   (KPCOL1, the volume-up keyboard column) from the DTB and re-driving it as a
#   plain GPIO output.  Nothing selects CONFIG_MTK_IRTX_SUPPORT, so turning it
#   off is safe.  See 音量上键修复方案-2026-10-15.md.
#
# NOT included: any change to the mt6755 I2C driver.  An earlier attempt to
# switch .master_xfer from mtk_i2c_transfer() to standard_i2c_transfer() broke
# every in-kernel MTK-style client (mt6311 ext-buck detection failed, cpuhvfs
# panicked at mt_cpufreq.c:3346).  See i2c总线真相-2026-10-15.md.
#
# Usage:  bash <PROJECT_ROOT>/kernel/scripts/build_fix28.sh
set -eu

cd <BUILD_ROOT>/k318/android_kernel_m3note-master
export MTK_PLATFORM=mt6755 MTK_PROJECT=wt6755_66_n
CROSS=<BUILD_ROOT>/toolchain/bin/aarch64-linux-android-
INC="-I$PWD/drivers/misc/mediatek/mu3phy $(find "$PWD/drivers" -type d -name mt6755 | grep -v ppm_v2 | sed 's|^|-I|' | tr '\n' ' ')"
LOGDIR=<BUILD_ROOT>/fix-20261015
I2C_SRC=drivers/misc/mediatek/i2c/mt6755/i2c.c

# --- volume-up key fix (IRTX -> GPIO104) ---------------------------------
sed -i 's/^CONFIG_MTK_IRTX_SUPPORT=y/# CONFIG_MTK_IRTX_SUPPORT is not set/' .config
grep -q '^# CONFIG_MTK_IRTX_SUPPORT is not set' .config || { echo "IRTX_DISABLE_FAILED"; exit 2; }
make ARCH=arm64 CROSS_COMPILE="$CROSS" olddefconfig > "$LOGDIR/olddef28.log" 2>&1
grep -q '^# CONFIG_MTK_IRTX_SUPPORT is not set' .config || { echo "IRTX_REENABLED_BY_CONFIG"; exit 3; }

# The I2C driver must stay untouched.
if ! grep -q '\.master_xfer = (pmaster_xfer)mtk_i2c_transfer,' "$I2C_SRC"; then
	echo "I2C_DRIVER_UNEXPECTEDLY_MODIFIED"
	exit 4
fi

# --- build ---------------------------------------------------------------
make KBUILD_BUILD_VERSION=28 -o tools/dct/DrvGen ARCH=arm64 CROSS_COMPILE="$CROSS" \
	HOSTCFLAGS=-fcommon CC="${CROSS}gcc $INC" -j20 Image.gz > "$LOGDIR/build28b.log" 2>&1

cp arch/arm64/boot/Image.gz <PROJECT_ROOT>/kernel/Image.gz-fix28
cp .config <PROJECT_ROOT>/kernel/kernel-config-fix28

echo "IRTX_DISABLED_OK  I2C_DRIVER_UNTOUCHED_OK"
echo BUILD28_DONE

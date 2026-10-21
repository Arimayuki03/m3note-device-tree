#!/bin/bash
set -eu
cd <BUILD_ROOT>/k318/android_kernel_m3note-master
export MTK_PLATFORM=mt6755 MTK_PROJECT=wt6755_66_n
CROSS=<BUILD_ROOT>/toolchain/bin/aarch64-linux-android-
INC="-I$PWD/drivers/misc/mediatek/mu3phy $(find "$PWD/drivers" -type d -name mt6755 | grep -v ppm_v2 | sed 's|^|-I|' | tr '\n' ' ')"
make -o tools/dct/DrvGen ARCH=arm64 CROSS_COMPILE="$CROSS" HOSTCFLAGS=-fcommon CC="${CROSS}gcc $INC" -j20 Image.gz > <BUILD_ROOT>/fix-20261015/build12.log 2>&1
cp arch/arm64/boot/Image.gz <PROJECT_ROOT>/project/kernel/Image.gz-fix12
cp .config <PROJECT_ROOT>/project/kernel/kernel-config-fix12


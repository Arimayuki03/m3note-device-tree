#!/bin/bash
# Build #32 for the Meizu m3 note (mt6755, 3.18.35).
#
# Contents = #31 plus the T2 "one rebuild, no boot scripts" items:
#   CONFIG_ZRAM_LZ4_COMPRESS=y + zram_drv.c default_compressor "lzo" -> "lz4"
#       lz4 compresses/decompresses faster than lzo at a slightly worse ratio,
#       so swap-in latency drops once the device actually starts paging.
#       The default is changed in the source because nothing in this tree writes
#       comp_algorithm; only the compiled-in default can take effect without a
#       boot script.
#   CONFIG_ZRAM_DEBUG=n          drops the zram debug instrumentation
#   CONFIG_CGROUP_DEBUG=n        drops the cgroup debug files
#   cpufreq_interactive.c DEFAULT_GO_HISPEED_LOAD 99 -> 85
#       the interactive governor now jumps to hispeed_freq from 85% load
#       instead of 99%, which ramps up sooner; set in the source so it survives
#       reboot without a boot script (a runtime `echo` would not).
#
# Everything from #30/#31 is carried unchanged:
#   volume-up key : CONFIG_MTK_IRTX_SUPPORT off          (GPIO104 stays KPCOL1)
#   speaker audio : aw8738 external-PA driver
#   light/proximity: ltr579 driver + alsps framework registration
#   I/O           : CONFIG_DEFAULT_IOSCHED="deadline"
#
# Usage:  bash <PROJECT_ROOT>/kernel/scripts/build_fix32.sh
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
grep -qE 'i2c_addr[[:space:]]+= \{0x53' "$LTR" || fail "ltr579 default address is not 0x53"

grep -q '^CONFIG_DEFAULT_DEADLINE=y' .config          || fail "DEFAULT_DEADLINE not set"
grep -q '^CONFIG_DEFAULT_IOSCHED="deadline"' .config  || fail "DEFAULT_IOSCHED is not deadline"
grep -q '^CONFIG_IOSCHED_DEADLINE=y' .config          || fail "deadline scheduler not built in"

# --- this build: T2 items ----------------------------------------------------
grep -q '^CONFIG_ZRAM=y' .config                      || fail "zram not enabled"
grep -q '^CONFIG_ZRAM_LZ4_COMPRESS=y' .config         || fail "ZRAM_LZ4_COMPRESS not set"
grep -q '^# CONFIG_ZRAM_DEBUG is not set' .config     || fail "ZRAM_DEBUG still on"
grep -q '^# CONFIG_CGROUP_DEBUG is not set' .config   || fail "CGROUP_DEBUG still on"
grep -q 'static const char \*default_compressor = "lz4"' drivers/block/zram/zram_drv.c \
	|| fail "zram default compressor is not lz4"
grep -q '^#define DEFAULT_GO_HISPEED_LOAD 85' drivers/cpufreq/cpufreq_interactive.c \
	|| fail "DEFAULT_GO_HISPEED_LOAD is not 85"

make ARCH=arm64 CROSS_COMPILE="$CROSS" olddefconfig > "$LOGDIR/olddef32.log" 2>&1

# olddefconfig must not silently revert anything, and must select the lz4 lib
grep -q '^CONFIG_ZRAM_LZ4_COMPRESS=y' .config         || fail "ZRAM_LZ4_COMPRESS lost during olddefconfig"
grep -q '^CONFIG_LZ4_COMPRESS=y' .config              || fail "LZ4_COMPRESS not selected"
grep -q '^CONFIG_LZ4_DECOMPRESS=y' .config            || fail "LZ4_DECOMPRESS not selected"
grep -q '^# CONFIG_ZRAM_DEBUG is not set' .config     || fail "ZRAM_DEBUG came back"
grep -q '^# CONFIG_CGROUP_DEBUG is not set' .config   || fail "CGROUP_DEBUG came back"
grep -q '^CONFIG_DEFAULT_IOSCHED="deadline"' .config  || fail "deadline default lost during olddefconfig"
grep -q '^CONFIG_DEFAULT_DEADLINE=y' .config          || fail "DEFAULT_DEADLINE lost during olddefconfig"
grep -q '^CONFIG_MTK_AW8738=y' .config                || fail "aw8738 lost during olddefconfig"
grep -q '^CONFIG_MTK_LTR579=y' .config                || fail "ltr579 lost during olddefconfig"
grep -q '^# CONFIG_MTK_IRTX_SUPPORT is not set' .config || fail "IRTX re-enabled"

# --- build -------------------------------------------------------------------
make KBUILD_BUILD_VERSION=32 -o tools/dct/DrvGen ARCH=arm64 CROSS_COMPILE="$CROSS" \
	HOSTCFLAGS=-fcommon CC="${CROSS}gcc $INC" -j20 Image.gz > "$LOGDIR/build32.log" 2>&1

cp arch/arm64/boot/Image.gz <PROJECT_ROOT>/kernel/Image.gz-fix32
cp .config <PROJECT_ROOT>/kernel/kernel-config-fix32

echo "PREFLIGHT_OK"
grep '^CONFIG_DEFAULT_IOSCHED' .config
grep '^CONFIG_ZRAM_LZ4_COMPRESS' .config
echo BUILD32_DONE

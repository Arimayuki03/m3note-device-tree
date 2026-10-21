#!/system/bin/sh
# Magisk 16.3 early hook. Run before zygote caches BuildExt.MZ_MODEL.
# Install as /sbin/.core/img/.core/post-fs-data.d/m3note-model.sh.
device=$(/system/bin/getprop ro.meizu.product.device)
model=$(/system/bin/getprop ro.meizu.product.model)
if [ "$device" = "m91" ]; then
    case "$model" in
        ""|unknown) /sbin/resetprop -n ro.meizu.product.model m91 ;;
    esac
fi
umask 077
{
    echo "hook=post-fs-data persistent"
    cat /proc/sys/kernel/random/boot_id
    uname -a
    echo "device=$device"
    echo "model=$(/system/bin/getprop ro.meizu.product.model)"
} > /data/local/tmp/m3note-model-boot.txt

# Also trigger the idempotent, detached zram resize early in boot.
# The worker waits for init to activate its default swap device.
/system/bin/setsid /system/bin/sh -c 'sleep 20; /sbin/.core/img/.core/service.d/m3note-zram-4g.sh' \
    </dev/null >/dev/null 2>&1 &

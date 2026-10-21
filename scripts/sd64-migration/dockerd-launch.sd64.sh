#!/system/bin/sh
set -e
unset LD_PRELOAD LD_LIBRARY_PATH
# Refuse startup unless the enrolled SD and every data binding are ready.
/system/bin/sh /data/m3note-sd64-mount.sh --check
# Apply the user's persistent eight-core policy before restoring containers.
CORE_HOOK=/sbin/.core/img/.core/service.d/m3note-eight-core.sh
if [ -x "$CORE_HOOK" ]; then
    /system/bin/sh "$CORE_HOOK" --apply
fi
BB=/data/local/tmp/busybox
$BB mount -o rprivate / /
$BB mount -o rbind /data/ubuntu /data/ubuntu
# containerd/cgroups v1 infers the hierarchy from the FIRST cgroup mount.
# This Android alias precedes /sys/fs/cgroup and falsely makes /dev its root.
# Detach only the alias in our private, recursively bound chroot. Android's
# namespace and the canonical /sys/fs/cgroup/cpuset mount remain unchanged.
$BB umount /data/ubuntu/dev/cpuset
test -r /data/ubuntu/sys/fs/cgroup/cpuset/cpus
test -r /data/ubuntu/sys/fs/cgroup/memory/memory.usage_in_bytes
echo 1 > /proc/sys/net/ipv4/ip_forward
exec chroot /data/ubuntu /usr/bin/env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
    /usr/bin/dockerd-cpusetfix --storage-driver=vfs --iptables=true --ip6tables=false --ip-forward=false

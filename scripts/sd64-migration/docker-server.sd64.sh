#!/system/bin/sh
# Android preload libraries do not exist inside Ubuntu.
unset LD_PRELOAD LD_LIBRARY_PATH
# Magisk service.d 开机服务：自动拉起 Ubuntu 容器服务器（chroot 挂载 + dockerd + sshd）
# 由 magiskinit 在 late_start 阶段执行，父进程为 init，不随任何 adb 会话死亡。
sleep 45
UB=/data/ubuntu

# /run is volatile: persistent containerd PID files can refer to Android
# processes after reboot and prevent Docker from starting.
mkdir -p $UB/run
/data/local/tmp/busybox mountpoint -q $UB/run || /system/bin/mount -t tmpfs -o mode=755,nosuid,nodev tmpfs $UB/run
# Tailscale's saved resolver links here; recreate it in volatile /run.
mkdir -p $UB/run/systemd/resolve
cp $UB/etc/m3note-underlay-resolv.conf $UB/run/systemd/resolve/stub-resolv.conf
/system/bin/mount --bind /dev $UB/dev 2>/dev/null
# Expose Android cpuset so containerd can resolve all process cgroup paths.
/system/bin/mount --bind /dev/cpuset $UB/dev/cpuset 2>/dev/null
/system/bin/mount --bind /proc $UB/proc 2>/dev/null
/system/bin/mount --bind /sys $UB/sys 2>/dev/null
/system/bin/mount -t tmpfs tmpfs $UB/sys/fs/cgroup 2>/dev/null
mkdir -p $UB/sys/fs/cgroup/cpu $UB/sys/fs/cgroup/cpuacct $UB/sys/fs/cgroup/memory \
         $UB/sys/fs/cgroup/devices $UB/sys/fs/cgroup/freezer $UB/sys/fs/cgroup/blkio $UB/sys/fs/cgroup/cpuset
/system/bin/mount --bind /dev/cpuset $UB/sys/fs/cgroup/cpuset 2>/dev/null
/system/bin/mount --bind /dev/cpuctl $UB/sys/fs/cgroup/cpu 2>/dev/null
/system/bin/mount --bind /acct $UB/sys/fs/cgroup/cpuacct 2>/dev/null
/system/bin/mount --bind /dev/memcg $UB/sys/fs/cgroup/memory 2>/dev/null
/system/bin/mount -t cgroup -o devices devices $UB/sys/fs/cgroup/devices 2>/dev/null
/system/bin/mount -t cgroup -o freezer freezer $UB/sys/fs/cgroup/freezer 2>/dev/null
/system/bin/mount -t cgroup -o blkio blkio $UB/sys/fs/cgroup/blkio 2>/dev/null

chroot $UB /bin/sh -c "PATH=/usr/bin:/bin; rm -f /var/run/docker.pid" 2>/dev/null
# Mount and verify the SD before Docker; never silently use old internal data.
if /system/bin/sh /data/m3note-sd64-mount.sh > $UB/root/sd64-mount.log 2>&1; then
    /data/local/tmp/busybox unshare -m /system/bin/sh /data/m3note-dockerd-launch.sh > $UB/root/dockerd.log 2>&1 < /dev/null &
else
    echo "SD64 unavailable or invalid: Docker startup blocked" >> $UB/root/sd64-mount.log
fi
sleep 12

mkdir -p $UB/run/sshd
chroot $UB /bin/bash -c "export PATH=/usr/bin:/bin; umask 022; test -f /etc/ssh/ssh_host_rsa_key || ssh-keygen -A >/dev/null 2>&1; /usr/sbin/sshd 2>/dev/null"

# Maintain destination rules only for active Docker bridge subnets.
chroot $UB /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root /usr/bin/python3 -u /usr/local/sbin/m3note-docker-routes.py > $UB/root/docker-routes.log 2>&1 < /dev/null &

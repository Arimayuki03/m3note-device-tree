#!/system/bin/sh
# 魅蓝 note3 (Flyme 6.3.5.0A–8.0.0.0A / Android 7.0, aarch64) 上的 Linux chroot 管理脚本
# 用法（需 root）：  su 0 /data/linux.sh {mount|umount|run <cmd>|enter|start|status}
ROOT=/data/linux
BB=/data/busybox
LP=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

mnt() {
  mount -t proc proc $ROOT/proc 2>/dev/null
  mount --bind /sys $ROOT/sys 2>/dev/null
  mount --bind /dev $ROOT/dev 2>/dev/null
  mount --bind /dev/pts $ROOT/dev/pts 2>/dev/null
}
umnt() {
  umount $ROOT/dev/pts 2>/dev/null
  umount $ROOT/dev 2>/dev/null
  umount $ROOT/sys 2>/dev/null
  umount $ROOT/proc 2>/dev/null
}
rexec() {
  $BB chroot $ROOT /usr/bin/env -i PATH=$LP HOME=/root TERM=xterm LANG=C.UTF-8 /bin/bash -c "$1"
}
case "$1" in
  mount)   mnt; echo "mounted=$(mount | grep -c $ROOT/)" ;;
  umount)  umnt; echo "umounted" ;;
  run)     shift; rexec "$*" ;;
  enter)   mnt; exec $BB chroot $ROOT /usr/bin/env -i PATH=$LP HOME=/root TERM=xterm LANG=C.UTF-8 /bin/bash -i -l ;;
  start)   mnt
           rexec "mkdir -p /run/sshd; test -x /usr/sbin/sshd && /usr/sbin/sshd; true"
           test -x $ROOT/etc/rc.local && rexec "/bin/sh /etc/rc.local"
           echo "started" ;;
  status)  echo "mounts=$(mount | grep -c $ROOT/)"
           rexec "test -x /usr/sbin/sshd && pgrep -x sshd | tr '\n' ' '; true" | sed 's/^/sshd_pids=/'
           ;;
  *)       echo "usage: $0 {mount|umount|run <cmd>|enter|start|status}" ;;
esac

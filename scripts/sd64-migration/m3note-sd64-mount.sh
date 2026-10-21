#!/system/bin/sh
set -e
unset LD_PRELOAD LD_LIBRARY_PATH
exec chroot /data/ubuntu /usr/bin/env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
    /usr/bin/python3 /usr/local/sbin/m3note-sd64-mount.py "$@"

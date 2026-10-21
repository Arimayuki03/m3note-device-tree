#!/system/bin/sh
# Docker 开机重试看护：docker-server 失败后，等 SD 卡就绪再挂载并拉起 Docker。
# service.d 入口必须快速退出；实际重试逻辑在 setsid 派生出的子进程中。

LOG=/data/local/tmp/docker-watchdog.log
PIDFILE=/data/local/tmp/docker-watchdog.pid

if [ "$1" != "--watchdog" ]; then
    echo "$(date) entry: detaching watchdog" >>"$LOG"
    /system/bin/setsid /system/bin/sh "$0" --watchdog </dev/null >/dev/null 2>&1 &
    exit 0
fi

exec >>"$LOG" 2>&1
echo "===== $(date) watchdog start ====="

BOOTID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
if [ -f "$PIDFILE" ]; then
    read -r old_boot old_pid < "$PIDFILE"
    if [ "$old_boot" = "$BOOTID" ] && [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        echo "watchdog already running (pid $old_pid), exit"
        exit 0
    fi
fi
echo "$BOOTID $$" > "$PIDFILE"

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 5
done

# 给 docker-server 的正常启动流程留出时间
WAIT=${DOCKER_WATCHDOG_WAIT:-180}
sleep "$WAIT"

dockerd_running() {
    for p in /proc/[0-9]*; do
        cmd=$(tr '\0' ' ' 2>/dev/null < "$p/cmdline")
        case "$cmd" in
            *"/usr/bin/dockerd-cpusetfix"*) return 0 ;;
        esac
    done
    return 1
}

route_updater_running() {
    for p in /proc/[0-9]*; do
        cmd=$(tr '\0' ' ' 2>/dev/null < "$p/cmdline")
        case "$cmd" in
            *m3note-docker-routes.py*) return 0 ;;
        esac
    done
    return 1
}

start_routes() {
    if route_updater_running; then
        return 0
    fi
    /system/bin/setsid /system/bin/chroot /data/ubuntu /usr/bin/env -i \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
        /usr/bin/python3 -u /usr/local/sbin/m3note-docker-routes.py \
        > /data/ubuntu/root/docker-routes.log 2>&1 < /dev/null &
    echo "$(date) route updater started"
}

attempt=1
while [ "$attempt" -le 15 ]; do
    if dockerd_running; then
        echo "$(date) dockerd already running; watchdog done"
        rm -f "$PIDFILE"
        exit 0
    fi

    echo "$(date) dockerd not running; SD mount attempt $attempt/15"
    if /system/bin/sh /data/m3note-sd64-mount.sh; then
        echo "$(date) SD mount OK; starting dockerd"
        /system/bin/chroot /data/ubuntu /bin/sh -c \
            'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; rm -f /var/run/docker.pid' \
            >/dev/null 2>&1
        /system/bin/setsid /data/local/tmp/busybox unshare -m \
            /system/bin/sh /data/m3note-dockerd-launch.sh \
            > /data/ubuntu/root/dockerd.log 2>&1 < /dev/null &
        sleep 10
        if dockerd_running; then
            echo "$(date) dockerd started; watchdog done"
            start_routes
            rm -f "$PIDFILE"
            exit 0
        fi
        echo "$(date) dockerd did not stay running"
    else
        echo "$(date) SD mount failed"
    fi

    attempt=$((attempt + 1))
    sleep 60
done

echo "$(date) watchdog gave up after 15 attempts"
rm -f "$PIDFILE"
exit 1

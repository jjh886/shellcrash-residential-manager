#!/bin/ash
# 作用：启动或停止 ShellCrash 管理页。默认端口 19999。
# 独立运行在 /data/other_vol/shellcrash-manager，不依赖 ShellCrash 是否已安装。

APP_DIR=$(cd "$(dirname "$0")/.." && pwd)
PORT=${RESIDENTIAL_UI_PORT:-19999}
BIND_HOST=${RESIDENTIAL_UI_HOST:-192.168.31.1}
PID_FILE="$APP_DIR/uhttpd.pid"
LOG_FILE="$APP_DIR/uhttpd.log"
WWW_DIR="$APP_DIR/www"

find_running_pids() {
    ps w 2>/dev/null | awk -v dir="$WWW_DIR" '$0 ~ /uhttpd/ && $0 ~ dir { print $1 }'
}

pid_file_alive() {
    [ -f "$PID_FILE" ] || return 1
    kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

stop_server() {
    if [ -f "$PID_FILE" ]; then
        kill "$(cat "$PID_FILE")" 2>/dev/null
        rm -f "$PID_FILE"
    fi

    for pid in $(find_running_pids); do
        kill "$pid" 2>/dev/null
    done
}

start_server() {
    mkdir -p "$APP_DIR"
    stop_server

    # -f 让 uhttpd 不自行 fork，再由本脚本放到后台，pid 更准确。
    uhttpd -f -p "$BIND_HOST:$PORT" -h "$WWW_DIR" -x /cgi-bin -I index.html -t 120 -T 30 -D >"$LOG_FILE" 2>&1 &
    echo "$!" > "$PID_FILE"
}

case "$1" in
    stop)
        stop_server
        ;;
    restart)
        start_server
        ;;
    status)
        if pid_file_alive || [ -n "$(find_running_pids)" ]; then
            echo "running"
        else
            echo "stopped"
        fi
        ;;
    *)
        start_server
        ;;
esac

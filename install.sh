#!/bin/ash
# 作用：把管理器安装到小米路由器持久化目录，并配置自启动。
# 可直接 SSH 执行，也可由小米插件 start_script 的 RUN 调用。

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET_DIR=${TARGET_DIR:-/data/other_vol/shellcrash-manager}
START_SCRIPT="$TARGET_DIR/scripts/residential-ui-start.sh"
LAN_SCRIPT="$TARGET_DIR/scripts/configure-router-lan.sh"

copy_manager_files() {
    mkdir -p "$TARGET_DIR"
    rm -rf "$TARGET_DIR/www" "$TARGET_DIR/scripts"
    cp -R "$SRC_DIR/www" "$TARGET_DIR/www"
    cp -R "$SRC_DIR/scripts" "$TARGET_DIR/scripts"
    chmod 755 "$TARGET_DIR/scripts"/*.sh "$TARGET_DIR/www/cgi-bin"/* 2>/dev/null
}

setup_firewall_autostart() {
    command -v uci >/dev/null 2>&1 || return 0

    # 小米/OpenWrt 启动时会加载 firewall include，用它拉起管理页更稳。
    uci set firewall.shellcrash_manager=include
    uci set firewall.shellcrash_manager.type='script'
    uci set firewall.shellcrash_manager.path="$START_SCRIPT"
    uci set firewall.shellcrash_manager.enabled='1'
    uci commit firewall
}

setup_shellcrash_custom() {
    [ -x "$TARGET_DIR/scripts/setup-shellcrash-custom.sh" ] || return 0
    "$TARGET_DIR/scripts/setup-shellcrash-custom.sh" >/dev/null 2>&1
}

configure_router_lan() {
    local code

    [ -x "$LAN_SCRIPT" ] || return 0
    MANAGER_START_SCRIPT="$START_SCRIPT" "$LAN_SCRIPT"
    code=$?
    case "$code" in
        0) return 0 ;;
        2) return 2 ;;
        *) return "$code" ;;
    esac
}

copy_manager_files
setup_firewall_autostart
setup_shellcrash_custom

configure_router_lan
lan_status=$?
case "$lan_status" in
    0)
        "$START_SCRIPT" restart
        ;;
    2)
        # LAN 地址切换会断开当前连接，管理页会在网络重启后由临时脚本拉起。
        ;;
    *)
        echo "路由器 LAN/DHCP 配置失败，已停止安装。"
        exit "$lan_status"
        ;;
esac

echo "ShellCrash 管理器已安装：http://192.168.0.1:19999/"

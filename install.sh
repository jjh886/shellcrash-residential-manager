#!/bin/ash
# 作用：把管理器安装到小米路由器持久化目录，并配置自启动。
# 可直接 SSH 执行，也可由小米插件 start_script 的 RUN 调用。

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET_DIR=${TARGET_DIR:-/data/other_vol/shellcrash-manager}
START_SCRIPT="$TARGET_DIR/scripts/residential-ui-start.sh"

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

copy_manager_files
setup_firewall_autostart
"$START_SCRIPT" restart

if [ -x "$TARGET_DIR/scripts/setup-shellcrash-custom.sh" ]; then
    "$TARGET_DIR/scripts/setup-shellcrash-custom.sh" >/dev/null 2>&1
fi

echo "ShellCrash 管理器已安装：http://192.168.31.1:19999/"

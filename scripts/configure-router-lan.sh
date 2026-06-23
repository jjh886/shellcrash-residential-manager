#!/bin/ash
# 作用：把路由器 LAN 地址和 DHCP 地址池调整到管理器默认网段。
# 默认会设置为 192.168.0.1，并把 DHCP 分配范围设为 192.168.0.5 - 192.168.0.254。

LAN_IP=${ROUTER_LAN_IP:-192.168.0.1}
LAN_NETMASK=${ROUTER_LAN_NETMASK:-255.255.255.0}
DHCP_START=${ROUTER_DHCP_START:-5}
DHCP_END=${ROUTER_DHCP_END:-254}
DHCP_LIMIT=${ROUTER_DHCP_LIMIT:-}
APPLY_NOW=${ROUTER_LAN_APPLY_NOW:-ON}
RESTART_DELAY=${ROUTER_LAN_RESTART_DELAY:-3}
START_AFTER_APPLY=${MANAGER_START_SCRIPT:-}
CHANGED=0

fail() {
    echo "$1" >&2
    exit 1
}

is_uint() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

validate_number() {
    is_uint "$2" || fail "$1 只能填写数字。"
}

validate_number "DHCP 起始地址" "$DHCP_START"
validate_number "DHCP 结束地址" "$DHCP_END"
validate_number "重启延迟" "$RESTART_DELAY"

[ "$DHCP_START" -ge 1 ] || fail "DHCP 起始地址不能小于 1。"
[ "$DHCP_END" -le 254 ] || fail "DHCP 结束地址不能大于 254。"
[ "$DHCP_END" -ge "$DHCP_START" ] || fail "DHCP 结束地址不能小于起始地址。"

if [ -z "$DHCP_LIMIT" ]; then
    # OpenWrt 的 limit 是“可分配数量”，不是最后一个 IP，所以 5-254 等于 250 个地址。
    DHCP_LIMIT=$((DHCP_END - DHCP_START + 1))
else
    validate_number "DHCP 地址数量" "$DHCP_LIMIT"
fi

command -v uci >/dev/null 2>&1 || {
    echo "未找到 uci，已跳过路由器 LAN/DHCP 配置。"
    exit 0
}

ensure_section() {
    local section="$1"
    local type="$2"

    uci -q get "$section" >/dev/null 2>&1 && return 0
    uci set "$section=$type"
    CHANGED=1
}

set_uci_if_changed() {
    local key="$1"
    local value="$2"
    local current

    current=$(uci -q get "$key" 2>/dev/null)
    [ "$current" = "$value" ] && return 0
    uci set "$key=$value"
    CHANGED=1
}

schedule_network_apply() {
    local job="/tmp/shellcrash-manager-apply-lan.sh"

    # 改 LAN IP 会断开当前 SSH 连接，所以放到临时脚本里延迟执行，让安装脚本先把提示输出完。
    cat > "$job" <<EOF
#!/bin/ash
sleep "$RESTART_DELAY"
/etc/init.d/network restart >/dev/null 2>&1
/etc/init.d/dnsmasq restart >/dev/null 2>&1
[ -x "$START_AFTER_APPLY" ] && "$START_AFTER_APPLY" restart >/dev/null 2>&1
rm -f "$job"
EOF
    chmod 700 "$job"
    if command -v nohup >/dev/null 2>&1; then
        nohup "$job" >/dev/null 2>&1 &
    else
        "$job" >/dev/null 2>&1 &
    fi
}

ensure_section network.lan interface
ensure_section dhcp.lan dhcp

set_uci_if_changed network.lan.proto static
set_uci_if_changed network.lan.ipaddr "$LAN_IP"
set_uci_if_changed network.lan.netmask "$LAN_NETMASK"
set_uci_if_changed dhcp.lan.interface lan
set_uci_if_changed dhcp.lan.start "$DHCP_START"
set_uci_if_changed dhcp.lan.limit "$DHCP_LIMIT"
set_uci_if_changed dhcp.lan.ignore 0

if [ "$CHANGED" -eq 1 ]; then
    uci commit network
    uci commit dhcp
    echo "已写入路由器地址：${LAN_IP}，DHCP 范围：${LAN_IP%.*}.${DHCP_START} - ${LAN_IP%.*}.${DHCP_END}。"

    if [ "$APPLY_NOW" = "ON" ]; then
        schedule_network_apply
        echo "网络将在 ${RESTART_DELAY} 秒后自动重启，请稍后用 http://${LAN_IP}:19999/ 访问管理页。"
        exit 2
    fi
else
    echo "路由器 LAN/DHCP 已经是目标配置。"
fi

exit 0

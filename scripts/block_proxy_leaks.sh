#!/bin/ash
# 作用：拦截容易绕过透明代理的协议，降低真实出口泄露风险。
# 范围：HTTP/3/QUIC、WebRTC/STUN、DoT/DoQ、IPv6 转发。
# 说明：开启中国地址排除后，只拦国外目的地址，尽量保留国内 App 的直连体验。

LAN_IFACE=${LAN_IFACE:-br-lan}
COMMENT_PREFIX=shellcrash-leak-guard
CRASHDIR=${CRASHDIR:-/data/other_vol/ShellCrash}
CN_EXCLUDE=
CN6_EXCLUDE=
CONF_FILE=${LEAK_GUARD_CONF:-/data/other_vol/shellcrash-manager/leak-guard.conf}

# 页面里的防泄露设置会写到这个文件；不存在时使用推荐默认值。
[ -f "$CONF_FILE" ] && . "$CONF_FILE"
BLOCK_QUIC=${BLOCK_QUIC:-ON}
BLOCK_STUN=${BLOCK_STUN:-ON}
BLOCK_DOT=${BLOCK_DOT:-ON}
BLOCK_IPV6=${BLOCK_IPV6:-ON}
EXCLUDE_CHINA=${EXCLUDE_CHINA:-ON}

cleanup_rules() {
    local cmd="$1"
    local marker="$2"
    local rule=

    while $cmd -S FORWARD 2>/dev/null | grep -q "$marker"; do
        rule=$($cmd -S FORWARD 2>/dev/null | grep "$marker" | head -n 1 | sed 's/^-A /-D /')
        $cmd $rule 2>/dev/null || break
    done
}

prepare_cn_exclude() {
    [ "$EXCLUDE_CHINA" = "ON" ] || return 0
    command -v ipset >/dev/null 2>&1 || return 0
    ipset list cn_ip >/dev/null 2>&1 && CN_EXCLUDE='-m set ! --match-set cn_ip dst'

    # ShellCrash 有中国 IPv6 列表时，生成 cn_ip6，用来只拦国外 IPv6。
    if ! ipset list cn_ip6 >/dev/null 2>&1 && [ -s "$CRASHDIR/cn_ipv6.txt" ]; then
        {
            echo "create cn_ip6 hash:net family inet6 hashsize 5120 maxelem 5120"
            awk '!/^$/&&!/^#/{printf("add cn_ip6 %s\n",$0)}' "$CRASHDIR/cn_ipv6.txt"
        } | ipset -! restore >/dev/null 2>&1
    fi
    ipset list cn_ip6 >/dev/null 2>&1 && CN6_EXCLUDE='-m set ! --match-set cn_ip6 dst'
}

add_ipv4_udp_block() {
    local ports="$1"
    local name="$2"
    local comment="$COMMENT_PREFIX-$name"
    local rule="-i $LAN_IFACE -p udp -m multiport --dports $ports $CN_EXCLUDE -m comment --comment $comment"

    iptables -C FORWARD $rule -j REJECT --reject-with icmp-port-unreachable 2>/dev/null && return 0
    iptables -I FORWARD 1 $rule -j REJECT --reject-with icmp-port-unreachable 2>/dev/null && return 0
    iptables -I FORWARD 1 $rule -j DROP 2>/dev/null
}

add_ipv4_tcp_block() {
    local ports="$1"
    local name="$2"
    local comment="$COMMENT_PREFIX-$name"
    local rule="-i $LAN_IFACE -p tcp -m multiport --dports $ports $CN_EXCLUDE -m comment --comment $comment"

    iptables -C FORWARD $rule -j REJECT --reject-with tcp-reset 2>/dev/null && return 0
    iptables -I FORWARD 1 $rule -j REJECT --reject-with tcp-reset 2>/dev/null && return 0
    iptables -I FORWARD 1 $rule -j DROP 2>/dev/null
}

add_ipv6_block() {
    command -v ip6tables >/dev/null 2>&1 || return 0

    local comment="$COMMENT_PREFIX-ipv6"
    local rule="-i $LAN_IFACE $CN6_EXCLUDE -m comment --comment $comment"

    # 没有中国 IPv6 集合时，不在“排除中国地址”模式下硬拦 IPv6，避免国内 App 首连等待。
    [ "$EXCLUDE_CHINA" = "ON" ] && [ -z "$CN6_EXCLUDE" ] && return 0

    ip6tables -C FORWARD $rule -j REJECT 2>/dev/null && return 0
    ip6tables -I FORWARD 1 $rule -j REJECT 2>/dev/null && return 0
    ip6tables -I FORWARD 1 $rule -j DROP 2>/dev/null
}

cleanup_rules iptables "$COMMENT_PREFIX"
cleanup_rules iptables shellcrash-block-quic
cleanup_rules ip6tables "$COMMENT_PREFIX"
cleanup_rules ip6tables shellcrash-block-quic
prepare_cn_exclude

# QUIC/HTTP3 使用 UDP 443，浏览器会自动降级到 TCP 443。
[ "$BLOCK_QUIC" = "ON" ] && add_ipv4_udp_block 443 quic

# WebRTC/STUN 常见端口，避免浏览器实时连接探测到本地公网出口。
[ "$BLOCK_STUN" = "ON" ] && add_ipv4_udp_block 3478,5349,19302:19309 stun

# DoT/DoQ 常用 853，避免客户端绕过路由器 DNS。
[ "$BLOCK_DOT" = "ON" ] && add_ipv4_udp_block 853 doq
[ "$BLOCK_DOT" = "ON" ] && add_ipv4_tcp_block 853 dot

# IPv6 有 cn_ip6 时只阻断国外 IPv6；没有 cn_ip6 时不误伤国内 App。
[ "$BLOCK_IPV6" = "ON" ] && add_ipv6_block

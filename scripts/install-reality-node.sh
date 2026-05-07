#!/bin/sh
# Debian Reality/XUDP 节点安装脚本。
# 默认直接出站；可选把这台服务器的出口再接到另一个 VLESS Reality 上游。

set -eu

NODE_NAME=${NODE_NAME:-VLESS-Reality-XUDP}
NODE_DOMAIN=${NODE_DOMAIN:-}
NODE_PORT=${NODE_PORT:-443}
NODE_SNI=${NODE_SNI:-www.microsoft.com}
NODE_DEST=${NODE_DEST:-www.microsoft.com:443}
NODE_UUID=${NODE_UUID:-}
NODE_PRIVATE_KEY=${NODE_PRIVATE_KEY:-}
NODE_PUBLIC_KEY=${NODE_PUBLIC_KEY:-}
NODE_SHORT_ID=${NODE_SHORT_ID:-}
UPSTREAM_SERVER=${UPSTREAM_SERVER:-}
UPSTREAM_PORT=${UPSTREAM_PORT:-443}
UPSTREAM_UUID=${UPSTREAM_UUID:-}
UPSTREAM_SNI=${UPSTREAM_SNI:-www.microsoft.com}
UPSTREAM_FLOW=${UPSTREAM_FLOW:-xtls-rprx-vision}
UPSTREAM_PUBLIC_KEY=${UPSTREAM_PUBLIC_KEY:-}
UPSTREAM_SHORT_ID=${UPSTREAM_SHORT_ID:-}
XRAY_CONFIG=/usr/local/etc/xray/config.json
INFO_DIR=/root/shellcrash-node
INFO_FILE=$INFO_DIR/node-info.txt

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
    log "错误：$*"
    exit 1
}

valid_port() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

yaml_quote() {
    printf '%s' "$1" | sed "s/'/''/g"
}

public_ip() {
    curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}'
}

ensure_root() {
    [ "$(id -u)" = "0" ] || fail "请使用 root 用户运行。"
    valid_port "$NODE_PORT" || fail "NODE_PORT 必须是 1-65535。"
    valid_port "$UPSTREAM_PORT" || fail "UPSTREAM_PORT 必须是 1-65535。"
    if [ -n "$UPSTREAM_SERVER" ]; then
        [ -n "$UPSTREAM_UUID" ] || fail "配置上游时必须填写 UPSTREAM_UUID。"
        [ -n "$UPSTREAM_PUBLIC_KEY" ] || fail "配置上游时必须填写 UPSTREAM_PUBLIC_KEY。"
    fi
}

fix_debian10_sources() {
    [ -r /etc/os-release ] || return 0
    . /etc/os-release
    [ "${ID:-}" = "debian" ] && [ "${VERSION_ID:-}" = "10" ] || return 0
    cp /etc/apt/sources.list "/etc/apt/sources.list.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    cat > /etc/apt/sources.list <<'EOF'
deb http://archive.debian.org/debian buster main contrib non-free
deb http://archive.debian.org/debian buster-updates main contrib non-free
deb http://archive.debian.org/debian-security buster/updates main contrib non-free
EOF
    printf '%s\n' 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99shellcrash-node-archive
}

install_packages() {
    export DEBIAN_FRONTEND=noninteractive
    if ! apt-get update; then
        fix_debian10_sources
        apt-get update
    fi
    apt-get install -y ca-certificates curl unzip openssl
}

download_xray_zip() {
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) asset=Xray-linux-64.zip ;;
        aarch64|arm64) asset=Xray-linux-arm64-v8a.zip ;;
        armv7l) asset=Xray-linux-arm32-v7a.zip ;;
        *) fail "暂不支持这个 CPU 架构：$arch" ;;
    esac
    tmp=/tmp/xray-node-install
    rm -rf "$tmp"
    mkdir -p "$tmp"
    curl -L --connect-timeout 20 -o "$tmp/xray.zip" "https://github.com/XTLS/Xray-core/releases/latest/download/$asset"
    unzip -o "$tmp/xray.zip" -d "$tmp"
    install -m 755 "$tmp/xray" /usr/local/bin/xray
}

install_xray() {
    command -v xray >/dev/null 2>&1 && return
    installer=/tmp/xray-install-release.sh
    if curl -L --connect-timeout 20 -o "$installer" https://github.com/XTLS/Xray-install/raw/main/install-release.sh &&
        bash "$installer" install &&
        command -v xray >/dev/null 2>&1; then
        return
    fi
    download_xray_zip
    cat > /etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

generate_keys() {
    [ -n "$NODE_UUID" ] || NODE_UUID=$(xray uuid 2>/dev/null | head -n 1)
    [ -n "$NODE_UUID" ] || NODE_UUID=$(cat /proc/sys/kernel/random/uuid)
    if [ -z "$NODE_PRIVATE_KEY" ] || [ -z "$NODE_PUBLIC_KEY" ]; then
        keys=$(xray x25519)
        NODE_PRIVATE_KEY=$(printf '%s\n' "$keys" | awk -F': ' '/PrivateKey/ {print $2}')
        NODE_PUBLIC_KEY=$(printf '%s\n' "$keys" | awk -F': ' '/PublicKey/ {print $2}')
    fi
    [ -n "$NODE_SHORT_ID" ] || NODE_SHORT_ID=$(openssl rand -hex 8)
}

outbound_json() {
    if [ -z "$UPSTREAM_SERVER" ]; then
        echo '{"tag":"exit","protocol":"freedom"}'
        return
    fi
    server=$(json_escape "$UPSTREAM_SERVER")
    uuid=$(json_escape "$UPSTREAM_UUID")
    sni=$(json_escape "$UPSTREAM_SNI")
    flow=$(json_escape "$UPSTREAM_FLOW")
    key=$(json_escape "$UPSTREAM_PUBLIC_KEY")
    sid=$(json_escape "$UPSTREAM_SHORT_ID")
    printf '{"tag":"exit","protocol":"vless","settings":{"vnext":[{"address":"%s","port":%s,"users":[{"id":"%s","encryption":"none","flow":"%s"}]}]},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"%s","fingerprint":"chrome","publicKey":"%s","shortId":"%s","spiderX":"/"}}}\n' \
        "$server" "$UPSTREAM_PORT" "$uuid" "$flow" "$sni" "$key" "$sid"
}

write_xray_config() {
    mkdir -p "$(dirname "$XRAY_CONFIG")"
    uuid=$(json_escape "$NODE_UUID")
    private=$(json_escape "$NODE_PRIVATE_KEY")
    sni=$(json_escape "$NODE_SNI")
    dest=$(json_escape "$NODE_DEST")
    short=$(json_escape "$NODE_SHORT_ID")
    outbound=$(outbound_json)
    cat > "$XRAY_CONFIG" <<EOF
{"log":{"loglevel":"warning"},"inbounds":[{"tag":"vless-reality-in","listen":"0.0.0.0","port":$NODE_PORT,"protocol":"vless","settings":{"clients":[{"id":"$uuid","flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"show":false,"dest":"$dest","xver":0,"serverNames":["$sni"],"privateKey":"$private","shortIds":["$short"]}}}],"outbounds":[$outbound],"routing":{"rules":[{"type":"field","inboundTag":["vless-reality-in"],"outboundTag":"exit"}]}}
EOF
    chmod 644 "$XRAY_CONFIG"
}

enable_bbr() {
    cat > /etc/sysctl.d/99-shellcrash-node.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
EOF
    sysctl --system >/dev/null 2>&1 || true
}

restart_xray() {
    systemctl daemon-reload
    systemctl enable xray >/dev/null 2>&1 || true
    systemctl restart xray
    sleep 1
    systemctl is-active --quiet xray || {
        journalctl -u xray -n 50 --no-pager 2>/dev/null || true
        fail "Xray 没有启动成功。"
    }
}

write_node_info() {
    mkdir -p "$INFO_DIR"
    server=${NODE_DOMAIN:-$(public_ip)}
    name_q=$(yaml_quote "$NODE_NAME")
    server_q=$(yaml_quote "$server")
    uuid_q=$(yaml_quote "$NODE_UUID")
    sni_q=$(yaml_quote "$NODE_SNI")
    public_q=$(yaml_quote "$NODE_PUBLIC_KEY")
    short_q=$(yaml_quote "$NODE_SHORT_ID")
    upstream=direct
    [ -n "$UPSTREAM_SERVER" ] && upstream="$UPSTREAM_SERVER"
    cat > "$INFO_FILE" <<EOF
name=$NODE_NAME
type=vless-reality
server=$server
port=$NODE_PORT
uuid=$NODE_UUID
sni=$NODE_SNI
flow=xtls-rprx-vision
public_key=$NODE_PUBLIC_KEY
short_id=$NODE_SHORT_ID
packet_encoding=xudp
upstream=$upstream

mihomo:
- { name: '$name_q', type: vless, server: '$server_q', port: $NODE_PORT, uuid: '$uuid_q', network: tcp, tls: true, udp: true, packet-encoding: xudp, flow: 'xtls-rprx-vision', servername: '$sni_q', client-fingerprint: chrome, reality-opts: { public-key: '$public_q', short-id: '$short_q' } }
EOF
    chmod 600 "$INFO_FILE"
}

main() {
    ensure_root
    install_packages
    install_xray
    generate_keys
    write_xray_config
    enable_bbr
    restart_xray
    write_node_info
    log "Reality/XUDP 节点安装完成：$INFO_FILE"
}

main "$@"

#!/bin/sh
# Debian Hysteria2 节点安装脚本。
# 默认使用 UDP 443，可和现有 Xray TCP 443 同时存在。

set -eu

NODE_NAME=${NODE_NAME:-Hysteria2-Node}
NODE_SERVER=${NODE_SERVER:-}
HY2_PORT=${HY2_PORT:-443}
HY2_PASSWORD=${HY2_PASSWORD:-}
HY2_SNI=${HY2_SNI:-www.apple.com}
HY2_MASQUERADE_URL=${HY2_MASQUERADE_URL:-https://www.apple.com}
CONFIG_DIR=/etc/hysteria
CONFIG_FILE=$CONFIG_DIR/config.yaml
CERT_FILE=$CONFIG_DIR/server.crt
KEY_FILE=$CONFIG_DIR/server.key
INFO_DIR=/root/shellcrash-node
INFO_FILE=$INFO_DIR/hysteria2-node-info.txt

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

yaml_quote() {
    printf '%s' "$1" | sed "s/'/''/g"
}

public_ip() {
    curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}'
}

ensure_root() {
    [ "$(id -u)" = "0" ] || fail "请使用 root 用户运行。"
    valid_port "$HY2_PORT" || fail "HY2_PORT 必须是 1-65535。"
}

install_hysteria() {
    command -v hysteria >/dev/null 2>&1 && return
    installer=/tmp/hysteria2-install.sh
    curl -fsSL --connect-timeout 20 -o "$installer" https://get.hy2.sh/
    bash "$installer"
    command -v hysteria >/dev/null 2>&1 || fail "Hysteria2 安装失败。"
}

generate_password() {
    [ -n "$HY2_PASSWORD" ] && return
    HY2_PASSWORD=$(openssl rand -hex 24)
}

write_cert() {
    mkdir -p "$CONFIG_DIR"
    [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ] && return
    openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 3650 \
        -subj "/CN=$HY2_SNI" -keyout "$KEY_FILE" -out "$CERT_FILE"
    chmod 600 "$KEY_FILE"
}

write_config() {
    password_q=$(yaml_quote "$HY2_PASSWORD")
    cat > "$CONFIG_FILE" <<EOF
listen: :$HY2_PORT
tls:
  cert: $CERT_FILE
  key: $KEY_FILE
auth:
  type: password
  password: '$password_q'
EOF
    if [ -n "$HY2_MASQUERADE_URL" ]; then
        cat >> "$CONFIG_FILE" <<EOF
masquerade:
  type: proxy
  proxy:
    url: $HY2_MASQUERADE_URL
    rewriteHost: true
EOF
    fi
    chmod 600 "$CONFIG_FILE"
}

write_service() {
    bin=$(command -v hysteria)
    cat > /etc/systemd/system/hysteria-server.service <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=$bin server -c $CONFIG_FILE
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

open_firewall() {
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q active; then
        ufw allow "$HY2_PORT"/udp >/dev/null 2>&1 || true
    fi
}

restart_service() {
    systemctl daemon-reload
    systemctl enable hysteria-server >/dev/null 2>&1 || true
    systemctl restart hysteria-server
    sleep 1
    systemctl is-active --quiet hysteria-server || {
        journalctl -u hysteria-server -n 50 --no-pager 2>/dev/null || true
        fail "Hysteria2 没有启动成功。"
    }
}

write_node_info() {
    mkdir -p "$INFO_DIR"
    server=${NODE_SERVER:-$(public_ip)}
    name_q=$(yaml_quote "$NODE_NAME")
    server_q=$(yaml_quote "$server")
    password_q=$(yaml_quote "$HY2_PASSWORD")
    sni_q=$(yaml_quote "$HY2_SNI")
    cat > "$INFO_FILE" <<EOF
name=$NODE_NAME
type=hysteria2
server=$server
port=$HY2_PORT
password=$HY2_PASSWORD
sni=$HY2_SNI
skip_cert_verify=true

mihomo:
- { name: '$name_q', type: hysteria2, server: '$server_q', port: $HY2_PORT, udp: true, password: '$password_q', sni: '$sni_q', skip-cert-verify: true }
EOF
    chmod 600 "$INFO_FILE"
}

main() {
    ensure_root
    install_hysteria
    generate_password
    write_cert
    write_config
    write_service
    open_firewall
    restart_service
    write_node_info
    log "Hysteria2 节点安装完成：$INFO_FILE"
}

main "$@"

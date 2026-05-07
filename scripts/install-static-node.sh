#!/bin/sh
# Debian 自建节点安装脚本。
# 支持 Shadowsocks，或 VLESS + WebSocket + TLS + Nginx 普通网页伪装。

set -eu

NODE_NAME=${NODE_NAME:-云服务器自建节点}
NODE_PROTOCOL=${NODE_PROTOCOL:-shadowsocks}
NODE_PORT=${NODE_PORT:-443}
NODE_DOMAIN=${NODE_DOMAIN:-}
NODE_LOCAL_PORT=${NODE_LOCAL_PORT:-10000}
NODE_UUID=${NODE_UUID:-}
WS_PATH=${WS_PATH:-}
ACME_EMAIL=${ACME_EMAIL:-}
SS_METHOD=${SS_METHOD:-aes-128-gcm}
SS_PASSWORD=${SS_PASSWORD:-}
UPSTREAM_TYPE=${UPSTREAM_TYPE:-}
UPSTREAM_HOST=${UPSTREAM_HOST:-}
UPSTREAM_PORT=${UPSTREAM_PORT:-}
UPSTREAM_USER=${UPSTREAM_USER:-}
UPSTREAM_PASS=${UPSTREAM_PASS:-}
XRAY_CONFIG=/usr/local/etc/xray/config.json
INFO_DIR=/root/shellcrash-node
INFO_FILE=$INFO_DIR/node-info.txt
WEB_ROOT=/var/www/shellcrash-node
NGINX_SITE=/etc/nginx/sites-available/shellcrash-node.conf

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

mask_value() {
    value=$1
    [ -n "$value" ] || { echo ""; return; }
    len=${#value}
    [ "$len" -le 6 ] && { echo "***"; return; }
    first=$(printf '%s' "$value" | cut -c 1-2)
    last=$(printf '%s' "$value" | sed 's/.*\(..\)$/\1/')
    printf '%s***%s' "$first" "$last"
}

ensure_root() {
    [ "$(id -u)" = "0" ] || fail "请使用 root 用户运行。"
    valid_port "$NODE_PORT" || fail "NODE_PORT 必须是 1-65535。"
    case "$NODE_PROTOCOL" in
        shadowsocks|vless-ws-tls) ;;
        *) fail "NODE_PROTOCOL 只能是 shadowsocks 或 vless-ws-tls。" ;;
    esac
    if [ "$NODE_PROTOCOL" = "vless-ws-tls" ]; then
        [ -n "$NODE_DOMAIN" ] || fail "vless-ws-tls 模式必须设置 NODE_DOMAIN。"
        valid_port "$NODE_LOCAL_PORT" || fail "NODE_LOCAL_PORT 必须是 1-65535。"
    fi
}

fix_debian10_sources() {
    [ -r /etc/os-release ] || return 0
    . /etc/os-release
    [ "${ID:-}" = "debian" ] && [ "${VERSION_ID:-}" = "10" ] || return 0

    log "检测到 Debian 10，切换到 archive 源以兼容旧系统。"
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
    log "安装依赖。"
    if ! apt-get update; then
        fix_debian10_sources
        apt-get update
    fi
    base_pkgs="ca-certificates curl unzip openssl"
    web_pkgs=""
    [ "$NODE_PROTOCOL" = "vless-ws-tls" ] && web_pkgs="nginx certbot"
    apt-get install -y $base_pkgs $web_pkgs
}

download_xray_zip() {
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) asset=Xray-linux-64.zip ;;
        aarch64|arm64) asset=Xray-linux-arm64-v8a.zip ;;
        armv7l) asset=Xray-linux-arm32-v7a.zip ;;
        *) fail "暂不支持这个 CPU 架构：$arch" ;;
    esac
    url="https://github.com/XTLS/Xray-core/releases/latest/download/$asset"
    tmp=/tmp/xray-node-install
    rm -rf "$tmp"
    mkdir -p "$tmp"
    curl -L --connect-timeout 20 -o "$tmp/xray.zip" "$url"
    unzip -o "$tmp/xray.zip" -d "$tmp"
    install -m 755 "$tmp/xray" /usr/local/bin/xray
}

install_xray() {
    installer=/tmp/xray-install-release.sh
    if command -v xray >/dev/null 2>&1; then
        log "已检测到 Xray，跳过二进制安装。"
        return
    fi

    log "安装 Xray。"
    if curl -L --connect-timeout 20 -o "$installer" https://github.com/XTLS/Xray-install/raw/main/install-release.sh &&
        bash "$installer" install &&
        command -v xray >/dev/null 2>&1; then
        return
    fi

    log "官方安装脚本失败，改用 release 压缩包安装。"
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

generate_password() {
    [ -n "$SS_PASSWORD" ] && return
    SS_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')
}

generate_uuid() {
    [ -n "$NODE_UUID" ] && return
    if command -v xray >/dev/null 2>&1; then
        NODE_UUID=$(xray uuid 2>/dev/null | head -n 1)
    fi
    [ -n "$NODE_UUID" ] || NODE_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null)
    [ -n "$NODE_UUID" ] || NODE_UUID=$(openssl rand -hex 16 | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\)$/\1-\2-\3-\4-\5/')
}

generate_ws_path() {
    [ -n "$WS_PATH" ] && return
    token=$(openssl rand -hex 10)
    WS_PATH="/assets/$token"
}

public_ip() {
    curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}'
}

build_outbound() {
    if [ -z "$UPSTREAM_HOST" ]; then
        printf '%s\n' '{"tag":"exit","protocol":"freedom"}'
        return
    fi

    valid_port "$UPSTREAM_PORT" || fail "UPSTREAM_PORT 必须是 1-65535。"
    case "$UPSTREAM_TYPE" in
        ''|socks|socks5) upstream_protocol=socks ;;
        http) upstream_protocol=http ;;
        *) fail "UPSTREAM_TYPE 目前支持 socks5 或 http。" ;;
    esac

    host_j=$(json_escape "$UPSTREAM_HOST")
    user_j=$(json_escape "$UPSTREAM_USER")
    pass_j=$(json_escape "$UPSTREAM_PASS")
    users=''
    if [ -n "$UPSTREAM_USER$UPSTREAM_PASS" ]; then
        users=",\"users\":[{\"user\":\"$user_j\",\"pass\":\"$pass_j\"}]"
    fi
    printf '{"tag":"exit","protocol":"%s","settings":{"servers":[{"address":"%s","port":%s%s}]}}\n' \
        "$upstream_protocol" "$host_j" "$UPSTREAM_PORT" "$users"
}

write_xray_config() {
    mkdir -p "$(dirname "$XRAY_CONFIG")"
    outbound=$(build_outbound)
    if [ "$NODE_PROTOCOL" = "vless-ws-tls" ]; then
        uuid_j=$(json_escape "$NODE_UUID")
        ws_j=$(json_escape "$WS_PATH")
        cat > "$XRAY_CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-ws-in",
      "listen": "127.0.0.1",
      "port": $NODE_LOCAL_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid_j",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "$ws_j"
        }
      }
    }
  ],
  "outbounds": [
    $outbound
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["vless-ws-in"],
        "outboundTag": "exit"
      }
    ]
  }
}
EOF
    else
        password_j=$(json_escape "$SS_PASSWORD")
        method_j=$(json_escape "$SS_METHOD")
        cat > "$XRAY_CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "ss-in",
      "listen": "0.0.0.0",
      "port": $NODE_PORT,
      "protocol": "shadowsocks",
      "settings": {
        "method": "$method_j",
        "password": "$password_j",
        "network": "tcp,udp"
      }
    }
  ],
  "outbounds": [
    $outbound
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["ss-in"],
        "outboundTag": "exit"
      }
    ]
  }
}
EOF
    fi
    chmod 644 "$XRAY_CONFIG"
}

write_web_page() {
    [ "$NODE_PROTOCOL" = "vless-ws-tls" ] || return 0
    mkdir -p "$WEB_ROOT/.well-known/acme-challenge"
    cat > "$WEB_ROOT/index.html" <<EOF
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>$NODE_DOMAIN</title><style>body{margin:0;font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#f7f8fa;color:#1f2937}main{max-width:720px;margin:12vh auto;padding:0 24px;line-height:1.7}h1{font-size:28px;font-weight:650;margin:0 0 12px}p{color:#4b5563}</style></head>
<body><main><h1>Service is running</h1><p>This endpoint is healthy. Please contact the site administrator if you need access.</p></main></body></html>
EOF
}

write_http_nginx() {
    [ "$NODE_PROTOCOL" = "vless-ws-tls" ] || return 0
    domain_j=$(json_escape "$NODE_DOMAIN")
    cat > "$NGINX_SITE" <<EOF
server {
    listen 80;
    server_name $domain_j;
    root $WEB_ROOT;
    index index.html;
    location /.well-known/acme-challenge/ {
        root $WEB_ROOT;
    }
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
    ln -sf "$NGINX_SITE" /etc/nginx/sites-enabled/shellcrash-node.conf
    rm -f /etc/nginx/sites-enabled/default
    nginx -t
    systemctl enable nginx >/dev/null 2>&1 || true
    systemctl restart nginx
}

obtain_cert() {
    [ "$NODE_PROTOCOL" = "vless-ws-tls" ] || return 0
    log "申请 HTTPS 证书：$NODE_DOMAIN"
    email_args="--register-unsafely-without-email"
    [ -n "$ACME_EMAIL" ] && email_args="-m $ACME_EMAIL"
    certbot certonly --webroot -w "$WEB_ROOT" -d "$NODE_DOMAIN" \
        --non-interactive --agree-tos $email_args --keep-until-expiring
}

write_tls_nginx() {
    [ "$NODE_PROTOCOL" = "vless-ws-tls" ] || return 0
    domain_j=$(json_escape "$NODE_DOMAIN")
    ws_j=$(json_escape "$WS_PATH")
    cat > "$NGINX_SITE" <<EOF
server {
    listen 80;
    server_name $domain_j;
    location /.well-known/acme-challenge/ {
        root $WEB_ROOT;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $domain_j;
    root $WEB_ROOT;
    index index.html;

    ssl_certificate /etc/letsencrypt/live/$domain_j/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain_j/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;

    location = $ws_j {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:$NODE_LOCAL_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
    nginx -t
    systemctl reload nginx
}

enable_bbr() {
    cat > /etc/sysctl.d/99-shellcrash-node.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
EOF
    sysctl --system >/dev/null 2>&1 || true
}

open_firewall() {
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q active; then
        ufw allow "$NODE_PORT"/tcp >/dev/null 2>&1 || true
        ufw allow "$NODE_PORT"/udp >/dev/null 2>&1 || true
    fi
}

setup_web() {
    [ "$NODE_PROTOCOL" = "vless-ws-tls" ] || return 0
    write_web_page
    write_http_nginx
    obtain_cert
    write_tls_nginx
}

restart_xray() {
    systemctl daemon-reload
    systemctl enable xray >/dev/null 2>&1 || true
    systemctl restart xray
    sleep 1
    systemctl is-active --quiet xray || {
        journalctl -u xray -n 40 --no-pager 2>/dev/null || true
        fail "Xray 没有启动成功，请查看上面的日志。"
    }
}

write_node_info() {
    mkdir -p "$INFO_DIR"
    server=${NODE_DOMAIN:-$(public_ip)}
    name_q=$(yaml_quote "$NODE_NAME")
    server_q=$(yaml_quote "$server")
    upstream=direct
    [ -n "$UPSTREAM_HOST" ] && upstream="$UPSTREAM_TYPE://$UPSTREAM_HOST:$UPSTREAM_PORT"
    if [ "$NODE_PROTOCOL" = "vless-ws-tls" ]; then
        uuid_q=$(yaml_quote "$NODE_UUID")
        sni_q=$(yaml_quote "$NODE_DOMAIN")
        path_q=$(yaml_quote "$WS_PATH")
        cat > "$INFO_FILE" <<EOF
# ShellCrash 管理器静态节点信息
# 这个文件包含真实 UUID 和路径，请不要发给陌生人。
name=$NODE_NAME
type=vless-ws-tls
server=$server
port=$NODE_PORT
uuid=$NODE_UUID
sni=$NODE_DOMAIN
ws_path=$WS_PATH
upstream=$upstream

mihomo:
- name: '$name_q'
  type: vless
  server: '$server_q'
  port: $NODE_PORT
  uuid: '$uuid_q'
  network: ws
  tls: true
  udp: true
  packet-encoding: xudp
  servername: '$sni_q'
  client-fingerprint: chrome
  ws-opts:
    path: '$path_q'
    headers:
      Host: '$sni_q'
EOF
    else
        password_q=$(yaml_quote "$SS_PASSWORD")
        cat > "$INFO_FILE" <<EOF
# ShellCrash 管理器静态节点信息
# 这个文件包含真实密码，请不要发给陌生人。
name=$NODE_NAME
type=shadowsocks
server=$server
port=$NODE_PORT
cipher=$SS_METHOD
password=$SS_PASSWORD
upstream=$upstream

mihomo:
- { name: '$name_q', type: ss, server: '$server_q', port: $NODE_PORT, cipher: '$SS_METHOD', password: '$password_q', udp: true }
EOF
    fi
    chmod 600 "$INFO_FILE"
}

main() {
    ensure_root
    install_packages
    install_xray
    if [ "$NODE_PROTOCOL" = "vless-ws-tls" ]; then
        generate_uuid
        generate_ws_path
        setup_web
    else
        generate_password
    fi
    write_xray_config
    enable_bbr
    open_firewall
    restart_xray
    write_node_info

    log "自建节点安装完成。"
    log "节点信息已保存：$INFO_FILE"
    if [ "$NODE_PROTOCOL" = "vless-ws-tls" ]; then
        log "协议：VLESS WS TLS，域名：$NODE_DOMAIN，端口：$NODE_PORT，路径：$WS_PATH"
    else
        log "协议：Shadowsocks，端口：$NODE_PORT，加密：$SS_METHOD，密码：$(mask_value "$SS_PASSWORD")"
    fi
}

main "$@"

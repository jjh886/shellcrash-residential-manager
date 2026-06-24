#!/bin/ash
# 自建节点：统一生成 ShellCrash 可识别的 proxies YAML。
# 调用方需要设置 APP_DIR；可选设置 CUSTOM_NODES_FILE。

CUSTOM_NODES_FILE=${CUSTOM_NODES_FILE:-$APP_DIR/custom-nodes.db}

clean_field() {
    # 单行配置文件使用 | 分隔，字段内不允许换行和 |。
    printf '%s' "$1" | tr -d '\r\n|' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

yaml_quote() {
    printf '%s' "$1" | sed "s/'/''/g"
}

valid_port_value() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

node_line() {
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$(clean_field "$1")" "$(clean_field "$2")" "$(clean_field "$3")" \
        "$(clean_field "$4")" "$(clean_field "$5")" "$(clean_field "$6")" \
        "$(clean_field "$7")" "$(clean_field "$8")" "$(clean_field "$9")" \
        "$(clean_field "${10}")" "$(clean_field "${11}")" "$(clean_field "${12}")" \
        "$(clean_field "${13}")" "$(clean_field "${14}")" "$(clean_field "${15}")"
}

find_node_line() {
    local id="$1"
    [ -f "$CUSTOM_NODES_FILE" ] || return 0
    awk -F'|' -v id="$id" '$1 == id {print; exit}' "$CUSTOM_NODES_FILE"
}

custom_node_names_inline() {
    [ -f "$CUSTOM_NODES_FILE" ] || return 0
    awk -F'|' '
        $2 == "ON" && $3 != "" && $15 != "ON" {
            name = $3
            gsub(/\047/, "\047\047", name)
            printf "%s\047%s\047", sep, name
            sep = ", "
        }
    ' "$CUSTOM_NODES_FILE"
}

custom_isp_final_node_names_inline() {
    [ -f "$CUSTOM_NODES_FILE" ] || return 0
    awk -F'|' '
        $2 == "ON" && $3 != "" && $15 == "ON" {
            name = $3
            gsub(/\047/, "\047\047", name)
            printf "%s\047%s\047", sep, name
            sep = ", "
        }
    ' "$CUSTOM_NODES_FILE"
}

emit_custom_nodes_yaml() {
    [ -f "$CUSTOM_NODES_FILE" ] || return 0
    while IFS='|' read -r id enabled name proto server port username password cipher uuid sni flow public_key short_id use_residential; do
        [ "$enabled" = "ON" ] || continue
        [ -n "$name" ] && [ -n "$server" ] && valid_port_value "$port" || continue
        name=$(yaml_quote "$name")
        server=$(yaml_quote "$server")
        username=$(yaml_quote "$username")
        password=$(yaml_quote "$password")
        cipher=$(yaml_quote "$cipher")
        uuid=$(yaml_quote "$uuid")
        sni=$(yaml_quote "$sni")
        flow=$(yaml_quote "$flow")
        public_key=$(yaml_quote "$public_key")
        short_id=$(yaml_quote "$short_id")
        dialer=""
        # 勾选“这个节点就是最终出口 IP”后，默认允许它接在前置链路后面。
        # Hysteria2 作为 UDP 最终出口时更适合直连，避免再被 TCP 前置链路影响稳定性。
        [ "$use_residential" = "ON" ] && [ "$proto" != "hysteria2" ] && dialer=", dialer-proxy: '自建节点'"

        case "$proto" in
            shadowsocks|ss)
                [ -n "$cipher" ] || cipher=aes-128-gcm
                echo "- { name: '$name', type: ss, server: '$server', port: $port, cipher: '$cipher', password: '$password', udp: true$dialer }"
                ;;
            socks5)
                echo "- { name: '$name', type: socks5, server: '$server', port: $port, username: '$username', password: '$password', udp: true$dialer }"
                ;;
            http)
                echo "- { name: '$name', type: http, server: '$server', port: $port, username: '$username', password: '$password'$dialer }"
                ;;
            vless)
                [ -n "$sni" ] || sni="$server"
                [ -n "$flow" ] || flow=xtls-rprx-vision
                # 订阅里的稳定 Reality 节点多数使用 iOS 指纹；这里只影响客户端握手特征。
                line="- { name: '$name', type: vless, server: '$server', port: $port, uuid: '$uuid', network: tcp, tls: true, udp: true, packet-encoding: xudp, flow: '$flow', servername: '$sni', client-fingerprint: ios"
                [ -n "$public_key" ] && {
                    line="$line, reality-opts: { public-key: '$public_key'"
                    [ -n "$short_id" ] && line="$line, short-id: '$short_id'"
                    line="$line }"
                }
                echo "$line$dialer }"
                ;;
            vless-ws-tls)
                [ -n "$sni" ] || sni="$server"
                [ -n "$flow" ] || flow="/assets/ws"
                echo "- { name: '$name', type: vless, server: '$server', port: $port, uuid: '$uuid', network: ws, tls: true, udp: true, packet-encoding: xudp, servername: '$sni', client-fingerprint: chrome, ws-opts: { path: '$flow', headers: { Host: '$sni' } }$dialer }"
                ;;
            hysteria2)
                line="- { name: '$name', type: hysteria2, server: '$server', port: $port, udp: true, password: '$password', sni: '$sni', skip-cert-verify: true"
                [ -n "$flow" ] && line="$line, ports: '$flow', mport: '$flow'"
                echo "$line$dialer }"
                ;;
        esac
    done < "$CUSTOM_NODES_FILE"
}

#!/bin/ash
# 多个静态住宅 SOCKS5 出口：负责保存格式和生成 proxies YAML。
# 调用方需要设置 APP_DIR；可选设置 RESIDENTIAL_NODES_FILE。

RESIDENTIAL_NODES_FILE=${RESIDENTIAL_NODES_FILE:-$APP_DIR/residential-nodes.db}

res_clean_field() {
    printf '%s' "$1" | tr -d '\r\n|' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

res_yaml_quote() {
    printf '%s' "$1" | sed "s/'/''/g"
}

res_valid_port() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

res_node_line() {
    printf '%s|%s|%s|%s|%s|%s|%s\n' \
        "$(res_clean_field "$1")" "$(res_clean_field "$2")" "$(res_clean_field "$3")" \
        "$(res_clean_field "$4")" "$(res_clean_field "$5")" "$(res_clean_field "$6")" \
        "$(res_clean_field "$7")"
}

res_find_node_line() {
    local id="$1"
    [ -f "$RESIDENTIAL_NODES_FILE" ] || return 0
    awk -F'|' -v id="$id" '$1 == id {print; exit}' "$RESIDENTIAL_NODES_FILE"
}

ensure_residential_nodes() {
    local old_file="$1"
    local server port username password
    # 只在首次安装、数据库文件不存在时迁移旧配置。
    # 如果文件存在但为空，表示用户已经删除了全部住宅出口，不能再从旧 YAML 里复活。
    [ -e "$RESIDENTIAL_NODES_FILE" ] && return 0

    server=$(sed -n "s/.*server: '\([^']*\)'.*/\1/p" "$old_file" 2>/dev/null | head -n 1)
    port=$(sed -n "s/.*port: \([0-9][0-9]*\).*/\1/p" "$old_file" 2>/dev/null | head -n 1)
    username=$(sed -n "s/.*username: '\([^']*\)'.*/\1/p" "$old_file" 2>/dev/null | head -n 1)
    password=$(sed -n "s/.*password: '\([^']*\)'.*/\1/p" "$old_file" 2>/dev/null | head -n 1)
    [ -n "$server" ] || server=IP
    [ -n "$port" ] || port=443
    [ -n "$username" ] || username=用户名
    [ -n "$password" ] || password=密码

    mkdir -p "$(dirname "$RESIDENTIAL_NODES_FILE")"
    res_node_line default ON 静态住宅IP-出口 "$server" "$port" "$username" "$password" > "$RESIDENTIAL_NODES_FILE"
    chmod 600 "$RESIDENTIAL_NODES_FILE" 2>/dev/null
}

residential_node_names_inline() {
    [ -f "$RESIDENTIAL_NODES_FILE" ] || return 0
    awk -F'|' '
        $2 == "ON" && $3 != "" {
            name = $3
            gsub(/\047/, "\047\047", name)
            printf "%s\047%s\047", sep, name
            sep = ", "
        }
    ' "$RESIDENTIAL_NODES_FILE"
}

emit_residential_nodes_yaml() {
    local dialer_group="$1"
    [ -f "$RESIDENTIAL_NODES_FILE" ] || return 0
    while IFS='|' read -r id enabled name server port username password; do
        [ "$enabled" = "ON" ] || continue
        [ -n "$name" ] && [ -n "$server" ] && res_valid_port "$port" || continue
        name=$(res_yaml_quote "$name")
        server=$(res_yaml_quote "$server")
        username=$(res_yaml_quote "$username")
        password=$(res_yaml_quote "$password")
        echo "- { name: '$name', type: socks5, server: '$server', port: $port, username: '$username', password: '$password', udp: true, dialer-proxy: '$dialer_group' }"
    done < "$RESIDENTIAL_NODES_FILE"
}

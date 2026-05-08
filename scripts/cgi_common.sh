#!/bin/ash
# CGI 通用工具：统一处理表单参数、JSON 输出和简单文本清洗。
# 路由器环境通常只有 busybox/ash，所以这里保持实现朴素、少依赖。

cgi_read_params() {
    PARAMS="${QUERY_STRING:-}"
    if [ "${REQUEST_METHOD:-}" = "POST" ] && [ "${CONTENT_LENGTH:-0}" -gt 0 ]; then
        PARAMS="$PARAMS&$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)"
    fi
}

send_json() {
    printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n'
    printf '%s\n' "$1"
    exit 0
}

json_escape() {
    printf '%s' "$1" | awk '{
        gsub(/\\/,"\\\\")
        gsub(/"/,"\\\"")
        gsub(/\t/,"\\t")
        gsub(/\r/,"")
        if (NR > 1) printf "\\n"
        printf "%s", $0
    }'
}

ok() {
    local message
    message=$(json_escape "$1")
    send_json "{\"ok\":true,\"message\":\"$message\"}"
}

fail() {
    local message
    message=$(json_escape "$1")
    send_json "{\"ok\":false,\"message\":\"$message\"}"
}

urldecode() {
    local value
    value=$(printf '%s' "$1" | sed 's/+/ /g; s/%/\\x/g')
    printf '%b' "$value"
}

param() {
    local key="$1"
    local raw
    raw=$(printf '%s' "$PARAMS" | tr '&' '\n' | sed -n "s/^$key=//p" | tail -n 1)
    urldecode "$raw"
}

has_param() {
    local key="$1"
    printf '%s' "$PARAMS" | tr '&' '\n' | grep -q "^$key="
}

one_line() {
    # 配置值只允许单行，避免表单里的换行把 Shell 配置写坏。
    printf '%s' "$1" | tr -d '\r\n'
}

shell_quote() {
    # Shell 单引号字符串中遇到单引号，需要拆开再拼回去。
    printf '%s' "$1" | sed "s/'/'\\\\''/g"
}

backup_file() {
    local file="$1"
    [ -f "$file" ] || return 0
    mkdir -p "$BACKUP_DIR"
    cp "$file" "$BACKUP_DIR/$(basename "$file").$(date +%Y%m%d-%H%M%S)" 2>/dev/null
}

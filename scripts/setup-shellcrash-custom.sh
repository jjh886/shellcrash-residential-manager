#!/bin/ash
# 作用：把住宅出口、自定义规则、防泄露脚本恢复到 ShellCrash 持久化目录。
# 这个脚本可以反复执行；已有的住宅账号密码不会被默认覆盖。

BASE=${SHELLCRASH_HOME:-/data/other_vol/ShellCrash}
APP_DIR=$(cd "$(dirname "$0")/.." && pwd)
YAML_DIR="$BASE/yamls"
RULES_FILE="$YAML_DIR/rules.yaml"
CFG_FILE="$BASE/configs/ShellCrash.cfg"
RULE_HELPERS="$APP_DIR/scripts/rule_helpers.sh"
NODE_HELPERS="$APP_DIR/scripts/custom_nodes.sh"
LEAK_GUARD_SRC="$APP_DIR/scripts/block_proxy_leaks.sh"
LEAK_GUARD_DST="$BASE/task/block_proxy_leaks.sh"
WRAPPER_DST="$BASE/task/residential_runtime_wrapper.sh"
MODIFY_FILE="$BASE/starts/clash_modify.sh"
BFSTART_FILE="$BASE/starts/bfstart.sh"
AFSTART="$BASE/task/afstart"
RES_GROUP="美国静态住宅IP"
RES_NODE="美国静态住宅IP-出口"
CHAIN_GROUP="♻️自动选择"
FALLBACK_CHAIN_GROUP="🚀节点选择"
[ -f "$RULE_HELPERS" ] && . "$RULE_HELPERS"
[ -f "$NODE_HELPERS" ] && . "$NODE_HELPERS"

set_cfg_plain() {
    local key="$1"
    local value="$2"
    local tmp="$CFG_FILE.tmp.$$"
    local found=0

    mkdir -p "$(dirname "$CFG_FILE")"
    touch "$CFG_FILE"
    while IFS= read -r line; do
        case "$line" in
            "$key="*)
                echo "$key=$value"
                found=1
                ;;
            *)
                echo "$line"
                ;;
        esac
    done < "$CFG_FILE" > "$tmp"
    [ "$found" -eq 0 ] && echo "$key=$value" >> "$tmp"
    mv "$tmp" "$CFG_FILE"
}

write_default_proxy() {
    local server port username password chain
    server=$(get_proxy_field server)
    port=$(get_proxy_field port)
    username=$(get_proxy_field username)
    password=$(get_proxy_field password)
    chain=$(choose_chain_group)
    [ -n "$server" ] || server=IP
    [ -n "$port" ] || port=443
    [ -n "$username" ] || username=用户名
    [ -n "$password" ] || password=密码

    cat > "$YAML_DIR/proxies.yaml" <<EOF
# 住宅出口节点：订阅更新不会覆盖这里。
- { name: '$RES_NODE', type: socks5, server: '$server', port: $port, username: '$username', password: '$password', dialer-proxy: '$chain' }
# shellcrash-manager:custom-nodes-begin
$(emit_custom_nodes_yaml)
# shellcrash-manager:custom-nodes-end
# shellcrash-manager:custom-residential-begin
$(emit_custom_residential_yaml "$server" "$port" "$username" "$password")
# shellcrash-manager:custom-residential-end
# shellcrash-manager:custom-targets-begin
$(emit_custom_target_comments)
# shellcrash-manager:custom-targets-end
EOF
    chmod 600 "$YAML_DIR/proxies.yaml" 2>/dev/null
}

write_default_group() {
    local custom_nodes items
    custom_nodes=$(custom_node_names_inline)
    items="'$RES_NODE'"
    [ -n "$custom_nodes" ] && items="$items, $custom_nodes"
    cat > "$YAML_DIR/proxy-groups.yaml" <<EOF
# 住宅出口分组：订阅更新不会覆盖这里。
- { name: '$RES_GROUP', type: select, proxies: [$items] }
EOF
    chmod 600 "$YAML_DIR/proxy-groups.yaml" 2>/dev/null
}

write_default_rules() {
    local direct_domains proxy_domains direct_keywords proxy_keywords
    direct_domains=$(extract_domains direct-domains DIRECT)
    proxy_domains=$(extract_domains proxy-domains "$RES_GROUP")
    direct_keywords=$(extract_keywords direct-keywords DIRECT)
    proxy_keywords=$(extract_keywords proxy-keywords "$RES_GROUP")
    [ -f "$YAML_DIR/rules.yaml" ] && cp "$YAML_DIR/rules.yaml" "$YAML_DIR/rules.yaml.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null
    {
        echo "# 少量手动分流补丁：默认留空，不接管订阅规则。"
        echo "# shellcrash-manager:direct-domains-begin"
        emit_domain_rules "$direct_domains" DIRECT
        echo "# shellcrash-manager:direct-domains-end"
        echo "# shellcrash-manager:direct-keywords-begin"
        emit_keyword_rules "$direct_keywords" DIRECT
        echo "# shellcrash-manager:direct-keywords-end"
        echo "# shellcrash-manager:proxy-domains-begin"
        emit_domain_rules "$proxy_domains" "$RES_GROUP"
        echo "# shellcrash-manager:proxy-domains-end"
        echo "# shellcrash-manager:proxy-keywords-begin"
        emit_keyword_rules "$proxy_keywords" "$RES_GROUP"
        echo "# shellcrash-manager:proxy-keywords-end"
    } > "$YAML_DIR/rules.yaml"
    chmod 600 "$YAML_DIR/rules.yaml" 2>/dev/null
}

get_proxy_field() {
    local field="$1"
    [ -f "$YAML_DIR/proxies.yaml" ] || return 0
    case "$field" in
        port) sed -n "s/.*port: \([0-9][0-9]*\).*/\1/p" "$YAML_DIR/proxies.yaml" | head -n 1 ;;
        *) sed -n "s/.*$field: '\([^']*\)'.*/\1/p" "$YAML_DIR/proxies.yaml" | head -n 1 ;;
    esac
}

choose_chain_group() {
    if grep -q "name: .*自动选择" "$YAML_DIR/config.yaml" 2>/dev/null; then
        echo "$CHAIN_GROUP"
    else
        echo "$FALLBACK_CHAIN_GROUP"
    fi
}

install_leak_guard() {
    [ -f "$LEAK_GUARD_SRC" ] || return 0

    mkdir -p "$BASE/task"
    cp "$LEAK_GUARD_SRC" "$LEAK_GUARD_DST"
    chmod 755 "$LEAK_GUARD_DST"

    # ShellCrash 会 source task/afstart；如果里面有 exit，后面的任务会被提前跳过。
    touch "$AFSTART"
    sed -i '/block_proxy_leaks\.sh/d; /^exit$/d' "$AFSTART"
    echo "$LEAK_GUARD_DST # 服务启动后阻断常见代理绕过协议" >> "$AFSTART"
}

install_runtime_wrapper() {
    mkdir -p "$BASE/task"
    cat > "$WRAPPER_DST" <<'EOF'
#!/bin/ash
# 运行时住宅出口封装：只改 ShellCrash 临时配置，不改订阅原始 config.yaml。
# 做法：保留原始分组可选节点，给规则目标额外生成“住宅封装组”。
RES_GROUP="美国静态住宅IP"
CONFIG_FILE="$TMPDIR/config.yaml"
PROXY_FILE="$CRASHDIR/yamls/proxies.yaml"

[ -s "$CONFIG_FILE" ] || return 0

server=$(sed -n "s/.*server: '\([^']*\)'.*/\1/p" "$PROXY_FILE" 2>/dev/null | head -n 1)
port=$(sed -n "s/.*port: \([0-9][0-9]*\).*/\1/p" "$PROXY_FILE" 2>/dev/null | head -n 1)
username=$(sed -n "s/.*username: '\([^']*\)'.*/\1/p" "$PROXY_FILE" 2>/dev/null | head -n 1)
password=$(sed -n "s/.*password: '\([^']*\)'.*/\1/p" "$PROXY_FILE" 2>/dev/null | head -n 1)
custom_targets=$(sed -n "/# shellcrash-manager:custom-targets-begin/,/# shellcrash-manager:custom-targets-end/p" "$PROXY_FILE" 2>/dev/null |
    sed -n "s/^# target: '\([^']*\)'.*/\1/p" | awk 'BEGIN{sep=""} {printf "%s%s", sep, $0; sep="|"}')
[ -n "$server" ] || return 0
[ -n "$port" ] || port=443

backup="$CONFIG_FILE.before-residential.$$"
tmp="$CONFIG_FILE.residential.$$"
cp "$CONFIG_FILE" "$backup" 2>/dev/null || return 0

awk \
    -v res="$RES_GROUP" \
    -v server="$server" \
    -v port="$port" \
    -v username="$username" \
    -v password="$password" \
    -v custom_csv="$custom_targets" '
    function trim(s) {
        sub(/^[[:space:]]+/, "", s)
        sub(/[[:space:]]+$/, "", s)
        return s
    }
    function yamlq(s) {
        gsub(/\047/, "\047\047", s)
        return s
    }
    function is_plain_target(t) {
        return t == "DIRECT" || t == "REJECT" || t == "REJECT-DROP" || t == "PASS"
    }
    function group_name(line, part) {
        part = line
        sub(/^.*name:[[:space:]]*/, "", part)
        sub(/,[[:space:]].*$/, "", part)
        gsub(/^[\047"]|[\047"]$/, "", part)
        return trim(part)
    }
    function rule_target(line, rule, n, parts, target) {
        rule = line
        sub(/^[[:space:]]*-[[:space:]]*/, "", rule)
        sub(/[[:space:]]*#.*$/, "", rule)
        gsub(/^[\047"]|[\047"]$/, "", rule)
        n = split(rule, parts, ",")
        target = ""
        if (parts[1] == "AND" || parts[1] == "OR" || parts[1] == "NOT") {
            return ""
        } else if (parts[1] == "MATCH" || parts[1] == "FINAL") {
            target = parts[2]
        } else if (n >= 3) {
            target = parts[3]
        }
        gsub(/^[\047"]|[\047"]$/, "", target)
        return trim(target)
    }
    function rewrite_rule(line, repl, raw, comment, indent, body, quote, n, parts, i, rebuilt) {
        raw = line
        comment = ""
        if (match(raw, /[[:space:]]+#/)) {
            comment = substr(raw, RSTART)
            raw = substr(raw, 1, RSTART - 1)
        }
        indent = raw
        sub(/-.*/, "", indent)
        body = raw
        sub(/^[[:space:]]*-[[:space:]]*/, "", body)
        quote = ""
        if (body ~ /^\047/) {
            quote = "\047"
            sub(/^\047/, "", body)
            sub(/\047[[:space:]]*$/, "", body)
        } else if (body ~ /^"/) {
            quote = "\""
            sub(/^"/, "", body)
            sub(/"[[:space:]]*$/, "", body)
        }
        n = split(body, parts, ",")
        if ((parts[1] == "MATCH" || parts[1] == "FINAL") && n >= 2) {
            parts[2] = repl
        } else if (n >= 3) {
            parts[3] = repl
        } else {
            return line
        }
        rebuilt = parts[1]
        for (i = 2; i <= n; i++) {
            rebuilt = rebuilt "," parts[i]
        }
        return indent "- " quote rebuilt quote comment
    }
    function wrap_group(t) {
        return res "-" t
    }
    function wrap_node(t) {
        return res "-出口-" t
    }
    function proxy_list(t, s, k) {
        s = "\047" yamlq(wrap_node(t)) "\047"
        for (k = 1; k <= custom_count; k++) {
            if (custom_nodes[k] != "") {
                s = s ", \047" yamlq(custom_nodes[k]) "\047"
            }
        }
        return s
    }
    function remember_target(t) {
        if (t == "" || is_plain_target(t) || index(t, res) == 1 || direct_only[t]) {
            return
        }
        if (!targets[t]) {
            targets[t] = 1
            order[++target_count] = t
        }
    }
    {
        lines[NR] = $0
        if (NR == 1 && custom_csv != "") {
            custom_count = split(custom_csv, custom_nodes, "|")
        }
        if ($0 ~ /^proxies:/) section = "proxies"
        else if ($0 ~ /^proxy-groups:/) section = "groups"
        else if ($0 ~ /^rules:/) section = "rules"
        else if ($0 ~ /^[A-Za-z0-9_-]+:/) section = ""

        if (section == "groups" && $0 ~ /^[[:space:]]*-[[:space:]]*\{?[[:space:]]*name:/ && $0 ~ /proxies:[[:space:]]*\[/) {
            name = group_name($0)
            list = $0
            sub(/^.*proxies:[[:space:]]*\[/, "", list)
            sub(/\].*$/, "", list)
            clean = list
            gsub(/[\047" ,]/, "", clean)
            if (clean ~ /^(DIRECT|REJECT|REJECT-DROP|PASS)+$/) {
                direct_only[name] = 1
            }
        }
    }
    END {
        section = ""
        for (i = 1; i <= NR; i++) {
            line = lines[i]
            if (line ~ /^rules:/) {
                section = "rules"
            } else if (line ~ /^[A-Za-z0-9_-]+:/ && line !~ /^rules:/) {
                section = ""
            }
            if (section == "rules" && line ~ /^[[:space:]]*-[[:space:]]*/) {
                remember_target(rule_target(line))
            }
        }

        section = ""
        for (i = 1; i <= NR; i++) {
            line = lines[i]
            if (line ~ /^proxies:/) section = "proxies"
            else if (line ~ /^proxy-groups:/) {
                if (section == "proxies") {
                    for (j = 1; j <= target_count; j++) {
                        target = order[j]
                        printf "    - { name: \047%s\047, type: socks5, server: \047%s\047, port: %s, username: \047%s\047, password: \047%s\047, dialer-proxy: \047%s\047 }\n", yamlq(wrap_node(target)), yamlq(server), port, yamlq(username), yamlq(password), yamlq(target)
                    }
                }
                section = "groups"
            } else if (line ~ /^rules:/) {
                if (section == "groups") {
                    for (j = 1; j <= target_count; j++) {
                        target = order[j]
                        printf "    - { name: \047%s\047, type: select, proxies: [%s] }\n", yamlq(wrap_group(target)), proxy_list(target)
                    }
                }
                section = "rules"
            } else if (line ~ /^[A-Za-z0-9_-]+:/) {
                section = ""
            }

            if (section == "rules" && line ~ /^[[:space:]]*-[[:space:]]*/) {
                target = rule_target(line)
                if (targets[target]) {
                    line = rewrite_rule(line, wrap_group(target))
                }
            }
            print line
        }
    }
' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"

# 如果封装后的配置无法通过内核校验，立刻回滚到 ShellCrash 原始生成结果。
if [ -x "$TMPDIR/CrashCore" ]; then
    "$TMPDIR/CrashCore" -t -d "$BINDIR" -f "$CONFIG_FILE" >/dev/null 2>&1 || mv "$backup" "$CONFIG_FILE"
else
    rm -f "$backup"
fi
EOF
    chmod 755 "$WRAPPER_DST"

    # 清理旧版曾经插到 clash_modify.sh 的运行时补丁；新版只挂在 bfstart.sh 后处理最终配置。
    [ -f "$MODIFY_FILE" ] && sed -i '/shellcrash-manager:residential-wrapper/d; /residential_runtime_wrapper\.sh/d' "$MODIFY_FILE"

    [ -f "$BFSTART_FILE" ] || return 0
    grep -q 'residential_runtime_wrapper.sh' "$BFSTART_FILE" && return 0

    tmp="$BFSTART_FILE.tmp.$$"
    awk -v wrapper="$WRAPPER_DST" '
        {
            print
            if ($0 ~ /clash_modify\.sh/ && $0 ~ /modify_yaml/) {
                print "# shellcrash-manager:residential-runtime-wrapper"
                print "[ -x \"" wrapper "\" ] && . \"" wrapper "\""
            }
        }
    ' "$BFSTART_FILE" > "$tmp" && mv "$tmp" "$BFSTART_FILE"
    chmod 755 "$BFSTART_FILE" 2>/dev/null
}

[ -d "$BASE" ] || {
    echo "ShellCrash 目录不存在：$BASE"
    exit 0
}

mkdir -p "$YAML_DIR" "$BASE/configs"
write_default_proxy
write_default_group
write_default_rules
install_leak_guard
install_runtime_wrapper

# 这些开关是我们管理页需要的默认安全设置。
set_cfg_plain common_ports OFF
set_cfg_plain sniffer ON
set_cfg_plain ipv6_dns OFF
set_cfg_plain cn_ip_route ON

[ -x "$LEAK_GUARD_DST" ] && "$LEAK_GUARD_DST" >/dev/null 2>&1
echo "ShellCrash 自定义配置已恢复。"

#!/bin/ash
# 作用：把静态住宅出口、自定义规则、防泄露脚本恢复到 ShellCrash 持久化目录。
# 这个脚本可以反复执行；已有的住宅账号密码不会被默认覆盖。

BASE=${SHELLCRASH_HOME:-/data/other_vol/ShellCrash}
APP_DIR=$(cd "$(dirname "$0")/.." && pwd)
YAML_DIR="$BASE/yamls"
RULES_FILE="$YAML_DIR/rules.yaml"
CFG_FILE="$BASE/configs/ShellCrash.cfg"
RULE_HELPERS="$APP_DIR/scripts/rule_helpers.sh"
NODE_HELPERS="$APP_DIR/scripts/custom_nodes.sh"
RES_HELPERS="$APP_DIR/scripts/residential_nodes.sh"
GROUP_HELPERS="$APP_DIR/scripts/group_helpers.sh"
LEAK_GUARD_SRC="$APP_DIR/scripts/block_proxy_leaks.sh"
LEAK_GUARD_DST="$BASE/task/block_proxy_leaks.sh"
WRAPPER_DST="$BASE/task/residential_runtime_wrapper.sh"
MODIFY_FILE="$BASE/starts/clash_modify.sh"
BFSTART_FILE="$BASE/starts/bfstart.sh"
AFSTART="$BASE/task/afstart"
RES_GROUP="静态住宅IP"
NO_RES_NODE="不使用静态住宅IP"
SELF_GROUP="自建节点"
NO_SELF_NODE="使用订阅节点"
DIRECT_EXIT_NODE="直接使用静态住宅IP"
AUTO_RES_NODE="自动住宅出口"
AUTO_SELF_NODE="自动前置链路"
JP_RULE_GROUP="日本专用节点"
JP_SUB_GROUP="🇯🇵日本节点"
HEALTH_CHECK_URL="https://www.gstatic.com/generate_204"
[ -f "$RULE_HELPERS" ] && . "$RULE_HELPERS"
[ -f "$NODE_HELPERS" ] && . "$NODE_HELPERS"
[ -f "$RES_HELPERS" ] && . "$RES_HELPERS"
[ -f "$GROUP_HELPERS" ] && . "$GROUP_HELPERS"

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
    ensure_residential_nodes "$YAML_DIR/proxies.yaml"

    cat > "$YAML_DIR/proxies.yaml" <<EOF
# 静态住宅出口节点：订阅更新不会覆盖这里。
$(emit_residential_nodes_yaml "$SELF_GROUP")
# shellcrash-manager:custom-nodes-begin
$(emit_custom_nodes_yaml)
# shellcrash-manager:custom-nodes-end
EOF
    chmod 600 "$YAML_DIR/proxies.yaml" 2>/dev/null
}

write_default_group() {
    local custom_nodes isp_nodes residential_nodes chain_items self_items res_items final_items auto_self_items jp_items
    custom_nodes=$(custom_node_names_inline)
    isp_nodes=$(custom_isp_final_node_names_inline)
    residential_nodes=$(residential_node_names_inline)
    chain_items=$(subscription_group_names_inline "$YAML_DIR/config.yaml")
    case "$chain_items" in *"'$JP_SUB_GROUP'"*) jp_items="'$JP_SUB_GROUP'" ;; *) jp_items="DIRECT" ;; esac
    auto_self_items="'$DIRECT_EXIT_NODE'"
    [ -n "$custom_nodes" ] && auto_self_items="$auto_self_items, $custom_nodes"
    auto_self_items="$auto_self_items, '$NO_SELF_NODE'"
    self_items="'$AUTO_SELF_NODE', '$DIRECT_EXIT_NODE'"
    [ -n "$custom_nodes" ] && self_items="$self_items, $custom_nodes"
    self_items="$self_items, '$NO_SELF_NODE'"
    final_items="$residential_nodes"
    [ -n "$final_items" ] && [ -n "$isp_nodes" ] && final_items="$final_items, $isp_nodes"
    [ -z "$final_items" ] && final_items="$isp_nodes"
    [ -n "$final_items" ] && res_items="'$AUTO_RES_NODE', $final_items, '$NO_RES_NODE'" || res_items="'$NO_RES_NODE'"
    {
        # 这是“自建节点”里的订阅中转选项，隐藏成内部组，避免面板多一个可操作分组。
        echo "- { name: '$NO_SELF_NODE', type: select, hidden: true, proxies: [$chain_items] }"
        echo "- { name: '$DIRECT_EXIT_NODE', type: select, hidden: true, proxies: [DIRECT] }"
        # 自动前置只负责“怎么连到住宅出口”：直连优先，再自建中转，最后订阅中转。
        echo "- { name: '$AUTO_SELF_NODE', type: fallback, hidden: true, url: '$HEALTH_CHECK_URL', interval: 300, proxies: [$auto_self_items] }"
        echo "- { name: '$NO_RES_NODE', type: select, hidden: true, proxies: ['$SELF_GROUP'] }"
        echo "- { name: '$SELF_GROUP', type: select, proxies: [$self_items] }"
        echo "- { name: '$JP_RULE_GROUP', type: select, hidden: true, proxies: [$jp_items] }"
        # 自动住宅出口只放最终住宅/ISP 节点，避免自动兜底到非住宅 IP。
        [ -n "$final_items" ] && echo "- { name: '$AUTO_RES_NODE', type: fallback, hidden: true, url: '$HEALTH_CHECK_URL', interval: 300, proxies: [$final_items] }"
        cat <<EOF
# 静态住宅IP分组：订阅更新不会覆盖这里。
- { name: '$RES_GROUP', type: select, proxies: [$res_items] }
EOF
    } > "$YAML_DIR/proxy-groups.yaml"
    chmod 600 "$YAML_DIR/proxy-groups.yaml" 2>/dev/null
}

write_default_rules() {
    local direct_domains proxy_domains direct_keywords proxy_keywords jp_domains
    direct_domains=$(extract_domains direct-domains DIRECT)
    jp_domains=$(extract_domains jp-domains "$JP_RULE_GROUP")
    proxy_domains=$(extract_domains proxy-domains "$RES_GROUP")
    [ -n "$proxy_domains" ] || proxy_domains=$(extract_domains proxy-domains "美国静态住宅IP")
    direct_keywords=$(extract_keywords direct-keywords DIRECT)
    proxy_keywords=$(extract_keywords proxy-keywords "$RES_GROUP")
    [ -n "$proxy_keywords" ] || proxy_keywords=$(extract_keywords proxy-keywords "美国静态住宅IP")
    [ -f "$YAML_DIR/rules.yaml" ] && cp "$YAML_DIR/rules.yaml" "$YAML_DIR/rules.yaml.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null
    {
        echo "# 少量手动分流补丁：默认留空，不接管订阅规则。"
        echo "# shellcrash-manager:direct-domains-begin"
        emit_domain_rules "$direct_domains" DIRECT
        echo "# shellcrash-manager:direct-domains-end"
        echo "# shellcrash-manager:direct-keywords-begin"
        emit_keyword_rules "$direct_keywords" DIRECT
        echo "# shellcrash-manager:direct-keywords-end"
        echo "# shellcrash-manager:jp-domains-begin"
        emit_domain_rules "$jp_domains" "$JP_RULE_GROUP"
        echo "# shellcrash-manager:jp-domains-end"
        echo "# shellcrash-manager:jp-keywords-begin"
        emit_keyword_rules "bycsi
bybit
bytick" "$JP_RULE_GROUP"
        echo "# shellcrash-manager:jp-keywords-end"
        echo "# shellcrash-manager:proxy-domains-begin"
        emit_domain_rules "$proxy_domains" "$RES_GROUP"
        echo "# shellcrash-manager:proxy-domains-end"
        echo "# shellcrash-manager:proxy-keywords-begin"
        emit_keyword_rules "$proxy_keywords" "$RES_GROUP"
        echo "# shellcrash-manager:proxy-keywords-end"
    } > "$YAML_DIR/rules.yaml"
    chmod 600 "$YAML_DIR/rules.yaml" 2>/dev/null
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
# 运行时静态住宅出口封装：只改 ShellCrash 临时配置，不改订阅原始 config.yaml。
# 做法：只把原本需要代理的规则指向总出口分组，避免新增一堆可见分组。
RES_GROUP="静态住宅IP"
NO_SELF_NODE="使用订阅节点"
NO_RES_NODE="不使用静态住宅IP"
SELF_GROUP="自建节点"
DIRECT_EXIT_NODE="直接使用静态住宅IP"
AUTO_RES_NODE="自动住宅出口"
AUTO_SELF_NODE="自动前置链路"
JP_RULE_GROUP="日本专用节点"
CONFIG_FILE="$TMPDIR/config.yaml"

[ -s "$CONFIG_FILE" ] || return 0

backup="$CONFIG_FILE.before-residential.$$"
tmp="$CONFIG_FILE.residential.$$"
cp "$CONFIG_FILE" "$backup" 2>/dev/null || return 0

awk \
    -v res="$RES_GROUP" \
    -v no_self="$NO_SELF_NODE" \
    -v no_res="$NO_RES_NODE" \
    -v self="$SELF_GROUP" \
    -v direct_exit="$DIRECT_EXIT_NODE" \
    -v auto_res="$AUTO_RES_NODE" \
    -v auto_self="$AUTO_SELF_NODE" \
    -v jp_group="$JP_RULE_GROUP" '
    function trim(s) {
        sub(/^[[:space:]]+/, "", s)
        sub(/[[:space:]]+$/, "", s)
        return s
    }
    function unquote(s) {
        s = trim(s)
        sub(/[[:space:]]*#.*$/, "", s)
        gsub(/^[\047"]|[\047"]$/, "", s)
        return trim(s)
    }
    function is_plain_target(t) {
        return t == "DIRECT" || t == "REJECT" || t == "REJECT-DROP" || t == "REJECT-TINYGIF" || t == "REJECT-DICT" || t == "REJECT-ARRAY" || t == "PASS" || t == "GLOBAL" || t == "COMPATIBLE"
    }
    function is_manager_group(t) {
        return t == res || t == no_self || t == no_res || t == self || t == direct_exit || t == auto_res || t == auto_self || t == jp_group || t == "美国静态住宅IP"
    }
    function is_direct_group(t, first, seen, depth) {
        seen = SUBSEP t SUBSEP
        while (group_has_proxy[t] && depth++ < 20) {
            first = group_first_proxy[t]
            if (is_plain_target(first)) return 1
            if (!group_has_proxy[first] || index(seen, SUBSEP first SUBSEP)) return 0
            seen = seen first SUBSEP
            t = first
        }
        return 0
    }
    function yamlq(s) {
        gsub(/\047/, "\047\047", s)
        return "\047" s "\047"
    }
    function group_name(line, part) {
        part = line
        sub(/^[[:space:]]*-[[:space:]]*/, "", part)
        sub(/^\{?[[:space:]]*name:[[:space:]]*/, "", part)
        sub(/^[[:space:]]*name:[[:space:]]*/, "", part)
        sub(/,[[:space:]].*$/, "", part)
        return unquote(part)
    }
    function remember_group(name) {
        name = trim(name)
        if (name == "" || group_seen[name]) return
        group_seen[name] = 1
        group_order[++group_count] = name
    }
    function remember_proxy(group, item) {
        item = unquote(item)
        if (group == "" || item == "") return
        if (!group_has_proxy[group]) group_first_proxy[group] = item
        group_has_proxy[group] = 1
    }
    function remember_proxy_list(group, list, n, parts, i) {
        n = split(list, parts, ",")
        for (i = 1; i <= n; i++) remember_proxy(group, parts[i])
    }
    function scan_inline_proxies(group, line, list) {
        if (group == "" || line !~ /proxies:[[:space:]]*\[/) return 0
        list = line
        sub(/^.*proxies:[[:space:]]*\[/, "", list)
        sub(/\].*$/, "", list)
        remember_proxy_list(group, list)
        return 1
    }
    function scan_group_line(line, item) {
        if (line ~ /^proxy-groups:/) {
            group_section = 1
            current_group = ""
            pending_group = 0
            in_proxy_list = 0
            return
        }
        if (group_section && line ~ /^[A-Za-z0-9_-]+:/ && line !~ /^proxy-groups:/) {
            group_section = 0
            current_group = ""
            pending_group = 0
            in_proxy_list = 0
            return
        }
        if (!group_section) return

        # 订阅分组格式不统一：这里同时兼容单行对象和多行对象。
        if (line ~ /^[[:space:]]*-[[:space:]]*$/) {
            current_group = ""
            pending_group = 1
            in_proxy_list = 0
            return
        }
        if (line ~ /^[[:space:]]*-[[:space:]]*\{?[[:space:]]*name:/ || (pending_group && line ~ /^[[:space:]]*name:/)) {
            current_group = group_name(line)
            remember_group(current_group)
            pending_group = 0
            in_proxy_list = 0
            scan_inline_proxies(current_group, line)
            return
        }
        if (current_group != "" && line ~ /^[[:space:]]*proxies:[[:space:]]*\[/) {
            scan_inline_proxies(current_group, line)
            in_proxy_list = 0
            return
        }
        if (current_group != "" && line ~ /^[[:space:]]*proxies:[[:space:]]*$/) {
            in_proxy_list = 1
            return
        }
        if (in_proxy_list && line ~ /^[[:space:]]*-[[:space:]]*/) {
            item = line
            sub(/^[[:space:]]*-[[:space:]]*/, "", item)
            remember_proxy(current_group, item)
            return
        }
        if (in_proxy_list && line ~ /^[[:space:]]*[A-Za-z0-9_-]+:/) in_proxy_list = 0
    }
    function rule_target(line, rule, n, parts, target) {
        rule = line
        sub(/^[[:space:]]*-[[:space:]]*/, "", rule)
        sub(/[[:space:]]*#.*$/, "", rule)
        gsub(/^[\047"]|[\047"]$/, "", rule)
        n = split(rule, parts, ",")
        target = ""
        parts[1] = trim(parts[1])
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
    function rewrite_group_proxies(line, list, before, after) {
        before = line
        sub(/proxies:[[:space:]]*\[.*/, "", before)
        after = line
        sub(/^.*proxies:[[:space:]]*\[[^]]*\]/, "", after)
        return before "proxies: [" list "]" after
    }
    function add_front_candidate(t) {
        if (t == "" || is_plain_target(t) || is_manager_group(t) || is_direct_group(t) || front_seen[t]) {
            return
        }
        front_seen[t] = 1
        front_list = front_list front_sep yamlq(t)
        front_sep = ", "
    }
    function remember_target(t) {
        if (t == "" || is_plain_target(t) || is_manager_group(t) || is_direct_group(t)) {
            return
        }
        if (!targets[t]) {
            targets[t] = 1
            order[++target_count] = t
        }
    }
    {
        lines[NR] = $0
        scan_group_line($0)
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
        for (j = 1; j <= target_count; j++) {
            add_front_candidate(order[j])
        }
        for (j = 1; j <= group_count; j++) {
            target = group_order[j]
            add_front_candidate(target)
        }
        if (front_list == "") front_list = "DIRECT"

        section = ""
        for (i = 1; i <= NR; i++) {
            line = lines[i]
            if (line ~ /^proxy-groups:/) {
                section = "groups"
            } else if (line ~ /^rules:/) {
                section = "rules"
            } else if (line ~ /^[A-Za-z0-9_-]+:/) {
                section = ""
            }

            if (section == "groups" && line ~ /^[[:space:]]*-[[:space:]]*\{?[[:space:]]*name:/ && group_name(line) == no_self) {
                line = rewrite_group_proxies(line, front_list)
            }
            if (section == "rules" && line ~ /^[[:space:]]*-[[:space:]]*/) {
                target = rule_target(line)
                if (targets[target]) {
                    line = rewrite_rule(line, res)
                }
            }
            print line
        }
    }
' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"

# ShellCrash 只关闭 DNS IPv6 时，内核仍可能对双栈网站发起 IPv6 连接；
# 这里跟随管理器默认策略关闭内核 IPv6，避免最终出口显示 IPv6。
[ "${ipv6_dns:-OFF}" = "OFF" ] && sed -i 's/^ipv6: true$/ipv6: false/' "$CONFIG_FILE"

# 如果封装后的配置无法通过内核校验，立刻回滚到 ShellCrash 原始生成结果。
if [ -x "$TMPDIR/CrashCore" ]; then
    "$TMPDIR/CrashCore" -t -d "$BINDIR" -f "$CONFIG_FILE" >/dev/null 2>&1 || mv "$backup" "$CONFIG_FILE"
else
    rm -f "$backup"
fi

# 如果配置了客户端订阅发布，运行时配置每次生成后都会自动同步到公网服务器。
PUBLISH_SCRIPT="/data/other_vol/shellcrash-manager/scripts/client_subscription_publish.sh"
PUBLISH_CONFIG="$TMPDIR/client-subscription-config.yaml"
[ -x "$PUBLISH_SCRIPT" ] && cp "$CONFIG_FILE" "$PUBLISH_CONFIG" 2>/dev/null && ( "$PUBLISH_SCRIPT" "$PUBLISH_CONFIG" >/data/other_vol/shellcrash-manager/last-client-subscription.log 2>&1 & )
EOF
    chmod 755 "$WRAPPER_DST"

    # hotupdate 只调用 clash_modify.sh，不经过 bfstart.sh；这里也挂一次，保证热更新会套上封装。
    if [ -f "$MODIFY_FILE" ]; then
        sed -i '/shellcrash-manager:residential-runtime-wrapper/d; /shellcrash-manager:residential-wrapper/d; /residential_runtime_wrapper\.sh/d' "$MODIFY_FILE"
        tmp="$MODIFY_FILE.tmp.$$"
        awk -v wrapper="$WRAPPER_DST" '
            {
                print
                if (!added && $0 ~ /cut -c 1-.*config\.yaml/) {
                    print "    # shellcrash-manager:residential-runtime-wrapper"
                    print "    [ -x \"" wrapper "\" ] && . \"" wrapper "\""
                    added = 1
                }
            }
        ' "$MODIFY_FILE" > "$tmp" && mv "$tmp" "$MODIFY_FILE"
        chmod 755 "$MODIFY_FILE" 2>/dev/null
    fi

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

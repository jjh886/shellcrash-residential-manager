#!/bin/ash
# 代理分组小工具：从订阅 YAML 里提取可作为前置链路的分组名。
# 调用方可提前设置 SELF_GROUP、RES_GROUP、NO_RES_NODE、NO_SELF_NODE、DIRECT_EXIT_NODE 和自动分组名。

subscription_group_names_inline() {
    local file="$1"
    [ -f "$file" ] || { echo "DIRECT"; return 0; }
    awk \
        -v self="${SELF_GROUP:-自建节点}" \
        -v res="${RES_GROUP:-静态住宅IP}" \
        -v nores="${NO_RES_NODE:-不使用静态住宅IP}" \
        -v noself="${NO_SELF_NODE:-使用订阅节点}" \
        -v direct_exit="${DIRECT_EXIT_NODE:-直接使用静态住宅IP}" \
        -v auto_res="${AUTO_RES_NODE:-自动住宅出口}" \
        -v auto_self="${AUTO_SELF_NODE:-自动前置链路}" '
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
        function yamlq(s) {
            gsub(/\047/, "\047\047", s)
            return "\047" s "\047"
        }
        function manager_group(name) {
            return name == self || name == res || name == nores || name == noself || name == direct_exit || name == auto_res || name == auto_self || name == "美国静态住宅IP"
        }
        function plain_target(name) {
            return name == "DIRECT" || name == "REJECT" || name == "REJECT-DROP" || name == "REJECT-TINYGIF" || name == "REJECT-DICT" || name == "REJECT-ARRAY" || name == "PASS" || name == "GLOBAL" || name == "COMPATIBLE"
        }
        function direct_group(name, first, seen, depth) {
            seen = SUBSEP name SUBSEP
            while (group_has_proxy[name] && depth++ < 20) {
                first = group_first_proxy[name]
                if (plain_target(first)) return 1
                if (!group_has_proxy[first] || index(seen, SUBSEP first SUBSEP)) return 0
                seen = seen first SUBSEP
                name = first
            }
            return 0
        }
        function parse_group_name(line, part) {
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
        /^proxy-groups:/ {
            section = 1
            current = ""
            pending_group = 0
            in_proxies = 0
            next
        }
        section && /^[A-Za-z0-9_-]+:/ {
            section = 0
            current = ""
            pending_group = 0
            in_proxies = 0
        }
        section {
            # 兼容两种常见订阅：单行 "- { name: ... }" 和多行 "- / name: / proxies:"。
            if ($0 ~ /^[[:space:]]*-[[:space:]]*$/) {
                current = ""
                pending_group = 1
                in_proxies = 0
                next
            }
            if ($0 ~ /^[[:space:]]*-[[:space:]]*\{?[[:space:]]*name:/ || (pending_group && $0 ~ /^[[:space:]]*name:/)) {
                current = parse_group_name($0)
                remember_group(current)
                pending_group = 0
                in_proxies = 0
                scan_inline_proxies(current, $0)
                next
            }
            if (current != "" && $0 ~ /^[[:space:]]*proxies:[[:space:]]*\[/) {
                scan_inline_proxies(current, $0)
                in_proxies = 0
                next
            }
            if (current != "" && $0 ~ /^[[:space:]]*proxies:[[:space:]]*$/) {
                in_proxies = 1
                next
            }
            if (in_proxies && $0 ~ /^[[:space:]]*-[[:space:]]*/) {
                item = $0
                sub(/^[[:space:]]*-[[:space:]]*/, "", item)
                remember_proxy(current, item)
                next
            }
            if (in_proxies && $0 ~ /^[[:space:]]*[A-Za-z0-9_-]+:/) in_proxies = 0
        }
        END {
            for (i = 1; i <= group_count; i++) {
                name = group_order[i]
                # 沿着第一项向下看；最终落到 DIRECT/REJECT/PASS 的，默认就是直连或阻断分组。
                if (manager_group(name) || seen[name] || direct_group(name)) continue
                seen[name] = 1
                out = out sep yamlq(name)
                sep = ", "
            }
            if (out == "") print "DIRECT"
            else print out
        }
    ' "$file"
}

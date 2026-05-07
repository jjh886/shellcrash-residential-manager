#!/bin/ash
# 代理分组小工具：从订阅 YAML 里提取可作为前置链路的分组名。
# 调用方可提前设置 SELF_GROUP、RES_GROUP、NO_RES_NODE、NO_SELF_NODE、DIRECT_EXIT_NODE。

subscription_group_names_inline() {
    local file="$1"
    [ -f "$file" ] || { echo "DIRECT"; return 0; }
    awk \
        -v self="${SELF_GROUP:-自建节点}" \
        -v res="${RES_GROUP:-静态住宅IP}" \
        -v nores="${NO_RES_NODE:-不使用静态住宅IP}" \
        -v noself="${NO_SELF_NODE:-使用订阅节点}" \
        -v direct_exit="${DIRECT_EXIT_NODE:-直接使用静态住宅IP}" '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        function yamlq(s) {
            gsub(/\047/, "\047\047", s)
            return "\047" s "\047"
        }
        function group_name(line, part) {
            part = line
            sub(/^.*name:[[:space:]]*/, "", part)
            sub(/,[[:space:]].*$/, "", part)
            gsub(/^[\047"]|[\047"]$/, "", part)
            return trim(part)
        }
        function manager_group(name) {
            return name == self || name == res || name == nores || name == noself || name == direct_exit || name == "美国静态住宅IP"
        }
        function direct_only(line, list) {
            if (line !~ /proxies:[[:space:]]*\[/) return 0
            list = line
            sub(/^.*proxies:[[:space:]]*\[/, "", list)
            sub(/\].*$/, "", list)
            gsub(/[\047" ,]/, "", list)
            return list ~ /^(DIRECT|REJECT|REJECT-DROP|PASS)+$/
        }
        function add(name) {
            if (name == "" || manager_group(name) || direct_only($0) || seen[name]) return
            seen[name] = 1
            out = out sep yamlq(name)
            sep = ", "
        }
        /^proxy-groups:/ { section = 1; next }
        section && /^[A-Za-z0-9_-]+:/ { section = 0 }
        section && /^[[:space:]]*-[[:space:]]*\{?[[:space:]]*name:/ { add(group_name($0)) }
        END {
            if (out == "") print "DIRECT"
            else print out
        }
    ' "$file"
}

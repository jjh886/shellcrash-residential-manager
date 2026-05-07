#!/bin/ash
# 规则小工具：统一处理手动分流里的域名后缀和关键词。
# 依赖调用方提前设置 RULES_FILE；目标分组由调用方传入。

split_values() {
    # 支持一行一个，也兼容用户用英文/中文逗号、分号连续粘贴。
    printf '%s\n' "$1" | awk '{
        gsub(/[,;]/, "\n")
        gsub(/，/, "\n")
        gsub(/；/, "\n")
        print
    }'
}

normalize_domains() {
    # 允许粘贴完整 URL，保存时只保留域名后缀。
    split_values "$1" |
        tr '\r' '\n' |
        sed 's/[[:space:]]//g; /^$/d; /^#/d; s#^http://##; s#^https://##; s#/.*$##; s/:.*$//; s/^\*\.//; s/^\.*//; s/\.$//' |
        sed '/^$/d' |
        awk '!seen[$0]++'
}

normalize_keywords() {
    # DOMAIN-KEYWORD 是“包含匹配”，所以只做轻量清洗，不强行改写用户输入。
    split_values "$1" |
        tr '\r' '\n' |
        sed 's/[[:space:]]//g; /^$/d; /^#/d; s#^http://##; s#^https://##; s#/.*$##; s/:.*$//; s/^\*\.//; s/^\.*//; s/\.$//' |
        sed '/^$/d' |
        awk 'length($0) <= 80 && !seen[$0]++'
}

extract_domains() {
    local group="$1"
    local target="$2"
    [ -f "$RULES_FILE" ] || return 0
    sed -n "/# shellcrash-manager:$group-begin/,/# shellcrash-manager:$group-end/p" "$RULES_FILE" |
        sed -n "s/^- 'DOMAIN-SUFFIX,\([^,']*\),$target'.*/\1/p"
}

extract_keywords() {
    local group="$1"
    local target="$2"
    [ -f "$RULES_FILE" ] || return 0
    sed -n "/# shellcrash-manager:$group-begin/,/# shellcrash-manager:$group-end/p" "$RULES_FILE" |
        sed -n "s/^- 'DOMAIN-KEYWORD,\([^,']*\),$target'.*/\1/p"
}

emit_domain_rules() {
    local domains="$1"
    local target="$2"
    printf '%s\n' "$domains" | while IFS= read -r domain; do
        [ -n "$domain" ] && echo "- 'DOMAIN-SUFFIX,$domain,$target'"
    done
}

emit_keyword_rules() {
    local keywords="$1"
    local target="$2"
    printf '%s\n' "$keywords" | while IFS= read -r keyword; do
        [ -n "$keyword" ] && echo "- 'DOMAIN-KEYWORD,$keyword,$target'"
    done
}

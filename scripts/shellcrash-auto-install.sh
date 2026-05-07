#!/bin/ash
# 作用：非交互安装或覆盖安装 ShellCrash，适合网页按钮和小米插件调用。
# 官方 install.sh 是交互式的；这里把选择目录、版本、别名改成环境变量。

SC_URL=${SC_URL:-https://testingcf.jsdelivr.net/gh/juewuy/ShellCrash@master}
SC_RELEASE=${SC_RELEASE:-master}
SC_ALIAS=${SC_ALIAS:-crash}
SC_DIR=${SC_DIR:-}
SC_START=${SC_START:-1}
MANAGER_DIR=${MANAGER_DIR:-$(cd "$(dirname "$0")/.." && pwd)}

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

pick_install_dir() {
    if [ -n "$SC_DIR" ]; then
        echo "$SC_DIR"
        return
    fi

    for dir in /data/other_vol /data /userdisk /etc; do
        [ -d "$dir" ] && [ -w "$dir" ] && {
            echo "$dir/ShellCrash"
            return
        }
    done

    echo "/data/other_vol/ShellCrash"
}

download() {
    local dst="$1"
    local src="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -kfsSL --connect-timeout 10 -o "$dst" "$src"
    else
        wget --no-check-certificate -q -O "$dst" "$src"
    fi
}

set_profile_alias() {
    local crashdir="$1"
    local profile=/etc/profile

    [ -w "$profile" ] || return 0
    sed -i "/alias $SC_ALIAS=.*ShellCrash\\/menu.sh/d; /CRASHDIR=.*ShellCrash/d" "$profile"
    {
        echo "export CRASHDIR=$crashdir"
        echo "alias $SC_ALIAS='$crashdir/menu.sh'"
    } >> "$profile"
}

install_shellcrash() {
    local crashdir="$1"
    local base_url version_file tar_file

    base_url=$(printf '%s' "$SC_URL" | sed "s/@master/@$SC_RELEASE/; s/@stable/@$SC_RELEASE/; s/@dev/@$SC_RELEASE/")
    version_file=/tmp/shellcrash-version.$$
    tar_file=/tmp/ShellCrash.tar.gz

    log "准备安装 ShellCrash：$base_url"
    download "$version_file" "$base_url/version" || log "版本文件下载失败，继续尝试下载安装包。"
    [ -s "$version_file" ] && version=$(cat "$version_file")
    rm -f "$version_file"

    download "$tar_file" "$base_url/ShellCrash.tar.gz" || {
        log "ShellCrash.tar.gz 下载失败。"
        exit 1
    }

    [ -x "$crashdir/start.sh" ] && "$crashdir/start.sh" stop >/dev/null 2>&1
    mkdir -p "$crashdir"
    tar -zxf "$tar_file" -C "$crashdir" 2>/dev/null || tar -zxf "$tar_file" --no-same-owner -C "$crashdir"

    [ -s "$crashdir/init.sh" ] || {
        log "解压后没有找到 init.sh，安装失败。"
        exit 1
    }

    export CRASHDIR="$crashdir"
    export my_alias="$SC_ALIAS"
    export url="$base_url"
    export version="$version"
    . "$crashdir/init.sh" >/dev/null
    set_profile_alias "$crashdir"

    [ -x "$MANAGER_DIR/scripts/setup-shellcrash-custom.sh" ] && \
        SHELLCRASH_HOME="$crashdir" "$MANAGER_DIR/scripts/setup-shellcrash-custom.sh"

    [ "$SC_START" = "1" ] && "$crashdir/start.sh" restart >/dev/null 2>&1
    log "ShellCrash 安装完成：$crashdir"
}

install_shellcrash "$(pick_install_dir)"

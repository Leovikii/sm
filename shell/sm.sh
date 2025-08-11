#!/bin/sh
set -u

DEFAULT_CONFIG_URL="https://example.com/config.json"
SCRIPT_REMOTE_URL="https://raw.githubusercontent.com/Leovikii/sm/main/shell/sm.sh"
SCRIPT_INSTALL_PATH="/usr/local/bin/sm.sh"
SINGBOX_CONFIG_DIR_OPENWRT="/etc/sing-box"
SINGBOX_CONFIG_DIR_DEBIAN="/etc/sing-box"
TMP_DIR="/tmp/sm_tmp"

_log() { printf '[INFO] %s\n' "$*"; }
_err() { printf '[ERROR] %s\n' "$*" >&2; }
_fatal() { _err "$*"; exit 1; }

prepare_tmp() {
    if [ ! -d "$TMP_DIR" ]; then
        mkdir -p "$TMP_DIR" 2>/dev/null || _fatal "创建临时目录 $TMP_DIR 失败"
    fi
}

detect_downloader() {
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
    else
        DOWNLOADER=""
    fi
}

download() {
    url="$1"; out="$2"
    detect_downloader
    if [ -z "$DOWNLOADER" ]; then
        _err "未检测到 curl 或 wget，无法下载 $url"
        return 1
    fi
    if [ "$DOWNLOADER" = "curl" ]; then
        curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$out"
        return $?
    else
        wget -q --tries=3 -O "$out" "$url"
        return $?
    fi
}

ensure_root() {
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            SUDO="sudo"
        else
            SUDO=""
        fi
    else
        SUDO=""
    fi
}

canonicalize() {
    target="$1"
    if [ -z "$target" ]; then
        printf '%s' ""
        return 0
    fi
    if command -v readlink >/dev/null 2>&1; then
        readlink -f "$target" 2>/dev/null || printf '%s' "$target"
    elif command -v realpath >/dev/null 2>&1; then
        realpath "$target" 2>/dev/null || printf '%s' "$target"
    else
        printf '%s' "$target"
    fi
}

get_script_path() {
    if [ "${SCRIPT_PATH_OVERRIDE-}" ]; then
        printf '%s' "$SCRIPT_PATH_OVERRIDE"
        return 0
    fi
    if command -v readlink >/dev/null 2>&1; then
        readlink -f "$0" 2>/dev/null || printf '%s' "$0"
    elif command -v realpath >/dev/null 2>&1; then
        realpath "$0" 2>/dev/null || printf '%s' "$0"
    else
        printf '%s' "$0"
    fi
}

OS_TYPE="unknown"

detect_os() {
    _log "检测操作系统..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release 2>/dev/null || true
        case "${ID:-}${ID_LIKE:-}" in
            *openwrt*|*OpenWrt*) OS_TYPE="openwrt" ;;
        esac
        case "${ID:-}" in
            debian|ubuntu|raspbian) OS_TYPE="debian" ;;
        esac
    fi
    if [ "$OS_TYPE" = "unknown" ]; then
        if command -v opkg >/dev/null 2>&1; then
            OS_TYPE="openwrt"
        elif command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
            OS_TYPE="debian"
        fi
    fi
    if [ "$OS_TYPE" = "unknown" ]; then
        printf '%s' "无法自动确定系统类型。请选择：\n1) OpenWrt\n2) Debian/Ubuntu\n3) 退出\n输入选项编号: "
        read -r opt
        case "$opt" in
            1) OS_TYPE="openwrt" ;;
            2) OS_TYPE="debian" ;;
            *) _fatal "已退出" ;;
        esac
    fi
    _log "检测到系统类型: $OS_TYPE"
}

install_deps_openwrt() {
    _log "OpenWrt：检查并安装依赖（opkg）"
    PKGS="ca-bundle curl jq"
    if ! opkg update >/dev/null 2>&1; then
        _log "opkg update 失败，继续检测已安装包" 
    fi
    for p in $PKGS; do
        if opkg list-installed "$p" >/dev/null 2>&1; then
            _log "$p 已安装"
        else
            _log "安装 $p"
            opkg install "$p" || _err "安装 $p 失败"
        fi
    done
}

install_deps_debian() {
    ensure_root
    _log "Debian：检查并安装依赖（apt）"
    PKGS="curl wget ca-certificates gnupg jq"
    if [ -n "$SUDO" ]; then
        RUNPREFIX="$SUDO"
    else
        RUNPREFIX=""
    fi
    $RUNPREFIX apt-get update || _err "apt-get update 失败"
    for p in $PKGS; do
        if dpkg -s "$p" >/dev/null 2>&1; then
            _log "$p 已安装"
        else
            _log "安装 $p"
            $RUNPREFIX apt-get install -y "$p" || _err "安装 $p 失败"
        fi
    done
}

install_deps() {
    prepare_tmp
    detect_downloader
    ensure_root
    case "$OS_TYPE" in
        openwrt) install_deps_openwrt ;;
        debian) install_deps_debian ;;
        *) _fatal "未知系统类型，无法安装依赖" ;;
    esac
}

is_singbox_installed() {
    if command -v sing-box >/dev/null 2>&1; then
        return 0
    fi
    if [ -x "/usr/bin/sing-box" ] || [ -x "/usr/sbin/sing-box" ] || [ -x "/bin/sing-box" ]; then
        return 0
    fi
    return 1
}

install_singbox_openwrt() {
    _log "使用官方安装脚本安装 sing-box(OpenWrt)"
    prepare_tmp
    if ! download "https://sing-box.app/install.sh" "$TMP_DIR/install_singbox.sh"; then
        _fatal "下载 sing-box 安装脚本失败"
    fi
    sh "$TMP_DIR/install_singbox.sh" || _err "运行官方安装脚本失败"
}

install_singbox_debian() {
    _log "通过 sagernet 仓库在 Debian 上安装 sing-box"
    ensure_root
    if [ -n "$SUDO" ]; then
        RUNPREFIX="$SUDO"
    else
        RUNPREFIX=""
    fi
    $RUNPREFIX mkdir -p /etc/apt/keyrings || _err "创建 /etc/apt/keyrings 失败"
    if ! download "https://sing-box.app/gpg.key" "/etc/apt/keyrings/sagernet.asc"; then
        _err "下载 GPG key 失败，尝试使用 curl 写入"
        $RUNPREFIX curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc || _err "写入 GPG key 失败"
    fi
    $RUNPREFIX chmod a+r /etc/apt/keyrings/sagernet.asc || _err "设置 key 权限失败"

    if [ -n "$RUNPREFIX" ]; then
        $RUNPREFIX tee /etc/apt/sources.list.d/sagernet.sources > /dev/null <<'EOF'
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
EOF
    else
        tee /etc/apt/sources.list.d/sagernet.sources > /dev/null <<'EOF'
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
EOF
    fi

    if ! $RUNPREFIX apt-get update; then
        _err "apt-get update 失败"
        return 1
    fi
    if ! $RUNPREFIX apt-get install -y sing-box; then
        _err "apt 安装 sing-box 失败"
        return 1
    fi
}

install_or_update_singbox() {
    if is_singbox_installed; then
        _log "检测到 sing-box 已安装"
        printf '%s' "检查更新并覆盖安装？(y/N): "
        read -r ans
        case "$ans" in
            [yY]*)
                if [ "$OS_TYPE" = "openwrt" ]; then
                    install_singbox_openwrt
                else
                    install_singbox_debian
                fi
                ;;
            *) _log "跳过更新" ;;
        esac
    else
        _log "未检测到 sing-box，开始安装..."
        if [ "$OS_TYPE" = "openwrt" ]; then
            install_singbox_openwrt
        else
            install_singbox_debian
        fi
    fi
}

get_config_from_script() {
    scriptpath=$(get_script_path)
    if [ -f "$scriptpath" ]; then
        val=$(grep -m1 '^DEFAULT_CONFIG_URL=' "$scriptpath" 2>/dev/null | sed -e 's/^DEFAULT_CONFIG_URL=//' -e 's/^"//' -e 's/"$//')
        printf '%s' "$val"
    else
        printf '%s' ""
    fi
}

save_config_to_script() {
    scriptpath=$(get_script_path)
    tmp="$TMP_DIR/sm.sh.tmp.$$"
    awk -v new="DEFAULT_CONFIG_URL=\"$1\"" 'BEGIN{repl=0}
        /^DEFAULT_CONFIG_URL=/ && repl==0 { print new; repl=1; next }
        { print }
        END{ if(repl==0) print new }' "$scriptpath" > "$tmp" || { _err "生成临时脚本失败"; return 1; }
    if [ -w "$scriptpath" ] || [ "$(id -u)" -eq 0 ]; then
        mv "$tmp" "$scriptpath" || { _err "替换脚本失败"; rm -f "$tmp"; return 1; }
    elif command -v sudo >/dev/null 2>&1; then
        sudo sh -c "cat '$tmp' > '$scriptpath'" || { _err "使用 sudo 写入脚本失败"; rm -f "$tmp"; return 1; }
        rm -f "$tmp"
    else
        _err "无权限写入脚本，请以 root 身份运行或安装 sudo。临时文件保留在 $tmp"
        return 1
    fi
    chmod +x "$scriptpath" 2>/dev/null || true
    return 0
}

download_and_replace_config() {
    url="$1"
    prepare_tmp
    out="$TMP_DIR/config.json"
    _log "从 $url 下载配置到 $out"
    if ! download "$url" "$out"; then _err "下载配置失败：$url"; return 1; fi
    if ! command -v jq >/dev/null 2>&1; then
        _err "未检测到 jq，无法验证 JSON 格式。"
        return 1
    fi
    if ! jq -e . "$out" >/dev/null 2>&1; then
        _err "下载的文件不是有效的 JSON（jq 验证失败）。"
        printf '%s' "是否保留该文件以便手动检查？(y/N): "
        read -r keep
        case "$keep" in
            [yY]*) _log "已保留下载文件：$out"; return 1 ;;
            *) rm -f "$out" 2>/dev/null || _err "删除临时文件失败：$out"; return 1 ;;
        esac
    fi
    if [ "$OS_TYPE" = "openwrt" ]; then
        confdir="$SINGBOX_CONFIG_DIR_OPENWRT"
    else
        confdir="$SINGBOX_CONFIG_DIR_DEBIAN"
    fi
    if [ ! -d "$confdir" ]; then
        mkdir -p "$confdir" || { _err "创建目录失败：$confdir"; return 1; }
    fi
    # 直接覆盖原有配置文件，不再备份
    if mv -f "$out" "$confdir/config.json" 2>/dev/null; then
        _log "配置已覆盖到 $confdir/config.json"
        return 0
    else
        if cp -f "$out" "$confdir/config.json" 2>/dev/null; then
            rm -f "$out" 2>/dev/null || true
            _log "配置已复制覆盖到 $confdir/config.json"
            return 0
        fi
        _err "移动/复制配置文件失败"
        return 1
    fi
} 

manage_singbox_menu() {
    while :; do
        _log "sing-box 管理 - 二级菜单"
        printf '1) 启动\n2) 停止\n3) 重启\n4) 强行停止\n5) 启用开机自启\n6) 禁用开机自启\n7) 查看日志（按页）\n8) 实时日志\n9) 卸载 sing-box\n0) 返回主菜单\n'
        printf '%s' "选择: "
        read -r opt
        case "$opt" in
            1) svc_action start ;;
            2) svc_action stop ;;
            3) svc_action restart ;;
            4) svc_action kill ;;
            5) svc_action enable ;;
            6) svc_action disable ;;
            7) svc_action journal ;;
            8) svc_action journalf ;;
            9) uninstall_singbox ;;
            0) break ;;
            *) _err "无效选项" ;;
        esac
    done
}

svc_action() {
    action="$1"
    if [ "$OS_TYPE" = "debian" ]; then
        ensure_root
        case "$action" in
            enable) $SUDO systemctl enable sing-box || _err "systemctl enable 失败" ;;
            disable) $SUDO systemctl disable sing-box || _err "systemctl disable 失败" ;;
            start) $SUDO systemctl start sing-box || _err "systemctl start 失败" ;;
            stop) $SUDO systemctl stop sing-box || _err "systemctl stop 失败" ;;
            kill) $SUDO systemctl kill sing-box || _err "systemctl kill 失败" ;;
            restart) $SUDO systemctl restart sing-box || _err "systemctl restart 失败" ;;
            journal) $SUDO journalctl -u sing-box --output cat -e || _err "journalctl 失败" ;;
            journalf) $SUDO journalctl -u sing-box --output cat -f || _err "journalctl -f 失败" ;;
            *) _err "未知操作 $action" ;;
        esac
    else
        if [ -x "/etc/init.d/sing-box" ]; then
            case "$action" in
                enable) /etc/init.d/sing-box enable || _err "enable 失败" ;;
                disable) /etc/init.d/sing-box disable || _err "disable 失败" ;;
                start) /etc/init.d/sing-box start || _err "start 失败" ;;
                stop) /etc/init.d/sing-box stop || _err "stop 失败" ;;
                restart) /etc/init.d/sing-box restart || _err "restart 失败" ;;
                kill)
                    if command -v pkill >/dev/null 2>&1; then
                        pkill -f sing-box || _err "pkill 失败或未找到进程"
                    elif command -v killall >/dev/null 2>&1; then
                        killall sing-box || _err "killall 失败或未找到进程"
                    else
                        PIDS="$(ps w 2>/dev/null | awk '/sing-box/ && !/awk/ {print $1}')"
                        if [ -n "$PIDS" ]; then
                            for pid in $PIDS; do
                                kill -9 "$pid" 2>/dev/null || _err "kill $pid 失败"
                            done
                        else
                            _err "未找到 sing-box 进程"
                        fi
                    fi
                    ;;
                journal|journalf)
                    if command -v logread >/dev/null 2>&1; then
                        if [ "$action" = "journalf" ]; then
                            logread -f || _err "logread -f 失败"
                        else
                            logread || _err "logread 失败"
                        fi
                    else
                        if [ -f /var/log/messages ]; then
                            tail -n 200 /var/log/messages || _err "读取 /var/log/messages 失败"
                        else
                            _err "未找到可读日志文件"
                        fi
                    fi
                    ;;
                *) _err "未知操作 $action" ;;
            esac
        else
            _err "/etc/init.d/sing-box 未找到，无法通过 init.d 管理，请手动管理二进制或检查安装。"
        fi
    fi
}

uninstall_singbox() {
    printf '%s' "确认要卸载 sing-box？(这会删除 sing-box 程序文件及配置，可选)(y/N): "
    read -r ans
    case "$ans" in
        [yY]*)
            if [ "$OS_TYPE" = "debian" ]; then
                ensure_root
                if [ -n "$SUDO" ]; then RUNPREFIX="$SUDO"; else RUNPREFIX=""; fi
                $RUNPREFIX apt-get remove --purge -y sing-box || _err "apt remove 失败"
            else
                if [ -x "/etc/init.d/sing-box" ]; then
                    /etc/init.d/sing-box stop || true
                    /etc/init.d/sing-box disable || true
                fi
                # 使用 opkg 卸载软件包（若可用），否则手动删除二进制
                if command -v opkg >/dev/null 2>&1; then
                    opkg remove sing-box || _err "opkg remove sing-box 失败"
                else
                    for p in /usr/bin/sing-box /usr/sbin/sing-box /bin/sing-box; do
                        if [ -f "$p" ]; then
                            rm -f "$p" || _err "删除 $p 失败"
                        fi
                    done
                fi
            fi
            _log "卸载操作完成"
            ;;
        *) _log "取消卸载" ;;
    esac
} 

update_script() {
    prepare_tmp
    out="$TMP_DIR/sm.sh"
    _log "从 $SCRIPT_REMOTE_URL 下载最新脚本到 $out"
    if ! download "$SCRIPT_REMOTE_URL" "$out"; then _err "下载脚本失败"; return 1; fi

    ensure_root
    if [ -n "$SUDO" ]; then RUNPREFIX="$SUDO"; else RUNPREFIX=""; fi

    if [ "$OS_TYPE" = "openwrt" ]; then
        target="/usr/sbin/sm.sh"
    else
        target="$SCRIPT_INSTALL_PATH"
    fi
    target_dir="$(dirname "$target")"
    if [ ! -d "$target_dir" ]; then
        if [ -n "$RUNPREFIX" ]; then
            $RUNPREFIX mkdir -p "$target_dir" 2>/dev/null || _err "创建 $target_dir 失败"
        else
            mkdir -p "$target_dir" 2>/dev/null || _err "创建 $target_dir 失败"
        fi
    fi

    if [ "$(id -u)" -eq 0 ]; then
        mv -f "$out" "$target" 2>/dev/null || { _err "移动脚本到 $target 失败"; rm -f "$out"; return 1; }
    elif [ -n "$RUNPREFIX" ]; then
        $RUNPREFIX sh -c "cat '$out' > '$target'" || { _err "使用 sudo 写入脚本失败"; rm -f "$out"; return 1; }
        rm -f "$out"
    else
        mv -f "$out" "./sm.sh" || { _err "写入当前目录失败"; rm -f "$out"; return 1; }
        target="$(pwd)/sm.sh"
    fi

    chmod +x "$target" 2>/dev/null || _err "chmod 失败"

    cur="$(get_script_path)"
    for p in "$cur" "/root/sm.sh" "/usr/bin/sm.sh" "$HOME/sm.sh"; do
        [ -e "$p" ] || continue
        if [ "$(canonicalize "$p")" != "$(canonicalize "$target")" ]; then
            if [ -n "$RUNPREFIX" ]; then
                $RUNPREFIX rm -f "$p" 2>/dev/null || _err "删除 $p 失败"
            else
                rm -f "$p" 2>/dev/null || _err "删除 $p 失败"
            fi
        fi
    done

    _log "脚本已更新并移动到 $target，其他副本已清理（若有权限）"
    return 0
} 


uninstall_script() {
    printf '%s' "确认卸载脚本并删除脚本生成的所有文件？(y/N): "
    read -r ans
    case "$ans" in
        [yY]*)
            files=""
            cur="$(get_script_path)"
            # 收集常见位置
            for f in "$SCRIPT_INSTALL_PATH" "$cur" "/root/sm.sh" "$HOME/sm.sh"; do
                [ -e "$f" ] || continue
                files="$files
$f"
            done
            if [ -d "$TMP_DIR" ]; then
                files="$files
$TMP_DIR"
            fi
            for d in "$SINGBOX_CONFIG_DIR_OPENWRT" "$SINGBOX_CONFIG_DIR_DEBIAN"; do
                if [ -d "$d" ]; then
                    for f in "$d"/config.json.bak.*; do
                        [ -e "$f" ] || continue
                        files="$files
$f"
                    done
                fi
            done
            files="$(printf '%s' "$files" | sed '/^$/d')"
            if [ -z "$files" ]; then
                _log "未检测到脚本生成的可删除文件或目录。"
            else
                printf '%s
' "将删除如下文件/目录：" "$files"
                printf '%s' "确认删除上列表中的所有文件/目录？(y/N): "
                read -r confirm
                case "$confirm" in
                    [yY]*)
                        ensure_root
                        if [ -n "$SUDO" ]; then RUNPREFIX="$SUDO"; else RUNPREFIX=""; fi
                        printf '%s
' "$files" | while IFS= read -r p; do
                            [ -z "$p" ] && continue
                            if [ -e "$p" ]; then
                                if [ -d "$p" ]; then
                                    $RUNPREFIX rm -rf "$p" || _err "删除 $p 失败"
                                else
                                    $RUNPREFIX rm -f "$p" || _err "删除 $p 失败"
                                fi
                            fi
                        done
                        _log "已尝试删除上列文件/目录（若出现错误，请查看日志或手动检查）。"
                        ;;
                    *) _log "取消删除文件" ;;
                esac
            fi
            printf '%s' "是否同时卸载 sing-box？(y/N): "
            read -r ans2
            case "$ans2" in
                [yY]*) uninstall_singbox ;;
                *) _log "保留 sing-box" ;;
            esac
            ;;
        *) _log "取消卸载脚本" ;;
    esac
}

script_management_menu() {
    while :; do
        _log "脚本管理 - 二级菜单"
        printf '1) 更新脚本
2) 卸载脚本（清理脚本生成的文件）
0) 返回主菜单
'
        printf '%s' "选择: "
        read -r opt
        case "$opt" in
            1) update_script ;;
            2) uninstall_script ;;
            0) break ;;
            *) _err "无效选项" ;;
        esac
    done
}


main_menu() {
    while :; do
        if [ "$OS_TYPE" = "openwrt" ]; then
            TITLE="Sing-box Manager for OpenWrt"
        else
            TITLE="Sing-box Manager for Debian"
        fi
        if command -v clear >/dev/null 2>&1; then
            clear
        fi
        cat <<HEADER
============================================================
  $TITLE
------------------------------------------------------------
  主机名: $(uname -n 2>/dev/null || echo unknown)    系统类型: $OS_TYPE
============================================================
HEADER
        cat <<MENU
  1) 安装或更新 sing-box
  2) 更新配置文件
  3) sing-box 管理
  4) 脚本管理
  0) 退出
MENU
        printf '%s' "请选择操作并回车: "
        read -r opt
        case "$opt" in
            1) install_or_update_singbox;;
            2) 
                CONFIG_URL="$(get_config_from_script)"
                config_update_menu;;
            3) manage_singbox_menu;;
            4) script_management_menu;;
            0) _log "退出"; break;;
            *) _err "无效选项，请输入 0-4 之间的数字";;
        esac
        printf '%s' "按回车返回菜单..."
        read -r _junk
    done
}

config_update_menu() {
    current="$(get_config_from_script)"
    if [ -n "$current" ]; then
        CONFIG_URL="$current"
    fi
    while :; do
        _log "配置文件更新 - 二级菜单"
        printf '当前默认地址: %s\n' "$CONFIG_URL"
        printf '1) 修改默认下载地址并保存到脚本本体\n2) 使用自定义地址下载并更新配置\n3) 使用默认地址更新配置\n4) 返回主菜单\n'
        printf '%s' "选择: "
        read -r opt
        case "$opt" in
            1)
                printf '%s' "输入新的默认下载地址: "
                read -r newurl
                if [ -n "$newurl" ]; then
                    if save_config_to_script "$newurl"; then
                        CONFIG_URL="$newurl"
                        _log "已更新并保存默认地址：$CONFIG_URL"
                    else
                        _err "保存默认地址到脚本失败，修改仅在当前会话生效。"
                    fi
                else
                    _err "地址为空，未修改"
                fi
                ;;
            2)
                printf '%s' "输入自定义下载地址: "
                read -r custom
                if [ -n "$custom" ]; then download_and_replace_config "$custom"; else _err "地址为空"; fi
                ;;
            3)
                download_and_replace_config "$CONFIG_URL"
                ;;
            4) break;;
            *) _err "无效选项";;
        esac
    done
}

install_self_if_needed() {
    cur="$(get_script_path)"
    # 根据系统类型选择安装目录（OpenWrt 使用 /usr/sbin）
    if [ "$OS_TYPE" = "openwrt" ]; then
        target="/usr/sbin/sm.sh"
    else
        target="$SCRIPT_INSTALL_PATH"
    fi
    if [ "$(canonicalize "$cur")" = "$(canonicalize "$target")" ]; then
        return 0
    fi

    ensure_root
    if [ -n "$SUDO" ]; then RUNPREFIX="$SUDO"; else RUNPREFIX=""; fi

    target_dir="$(dirname "$target")"
    if [ ! -d "$target_dir" ]; then
        if [ -n "$RUNPREFIX" ]; then
            $RUNPREFIX mkdir -p "$target_dir" 2>/dev/null || _err "无法创建目录 $target_dir"
        else
            mkdir -p "$target_dir" 2>/dev/null || _err "无法创建目录 $target_dir"
        fi
    fi

    if [ "$(id -u)" -eq 0 ]; then
        mv -f "$cur" "$target" 2>/dev/null || { _err "移动脚本到 $target 失败"; return 1; }
    elif [ -n "$RUNPREFIX" ]; then
        $RUNPREFIX sh -c "cat '$cur' > '$target' && rm -f '$cur'" || { _err "使用 sudo 移动脚本失败"; return 1; }
    else
        cp -f "$cur" "$target" 2>/dev/null || { _err "复制脚本到 $target 失败"; return 1; }
        rm -f "$cur" 2>/dev/null || true
    fi

    chmod +x "$target" 2>/dev/null || true

    for p in "/root/sm.sh" "/usr/bin/sm.sh" "$HOME/sm.sh" "$cur"; do
        [ -e "$p" ] || continue
        if [ "$(canonicalize "$p")" != "$(canonicalize "$target")" ]; then
            if [ -n "$RUNPREFIX" ]; then
                $RUNPREFIX rm -f "$p" 2>/dev/null || true
            else
                rm -f "$p" 2>/dev/null || true
            fi
        fi
    done

    _log "已将脚本移动到 $target 并清理其他副本"
    exec "$target" "$@"
    exit 0
} 

main() {
    detect_os
    install_self_if_needed "$@"
    install_deps
    main_menu
}

trap 'rm -rf "$TMP_DIR" >/dev/null 2>&1; _log "已退出并清理临时文件"; exit' INT TERM

main
 'rm -rf "$TMP_DIR" >/dev/null 2>&1; _log "已退出并清理临时文件"; exit' INT TERM

main
 'rm -rf "$TMP_DIR" >/dev/null 2>&1; _log "已退出并清理临时文件"; exit' INT TERM

main

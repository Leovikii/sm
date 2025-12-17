#!/bin/sh
set -u

# ==================== 配置常量 ====================
DEFAULT_CONFIG_URL="https://example.com/config.json"
SCRIPT_REMOTE_URL="https://raw.githubusercontent.com/Leovikii/sm/main/shell/sm.sh"
SCRIPT_INSTALL_PATH="/usr/local/bin/sm.sh"
SINGBOX_CONFIG_DIR_OPENWRT="/etc/sing-box"
SINGBOX_CONFIG_DIR_DEBIAN="/etc/sing-box"
TMP_DIR="/tmp/sm_tmp"
TCPX_URL="https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh"

# ==================== 工具函数 ====================
_log() { printf '\033[32m[INFO]\033[0m %s\n' "$*"; }
_warn() { printf '\033[33m[WARN]\033[0m %s\n' "$*"; }
_err() { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; }
_fatal() { _err "$*"; exit 1; }

prepare_tmp() {
    [ -d "$TMP_DIR" ] || mkdir -p "$TMP_DIR" 2>/dev/null || _fatal "创建临时目录 $TMP_DIR 失败"
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
    [ -z "$DOWNLOADER" ] && { _err "未检测到 curl 或 wget，无法下载"; return 1; }
    
    if [ "$DOWNLOADER" = "curl" ]; then
        curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$out"
    else
        wget -q --tries=3 -O "$out" "$url"
    fi
}

ensure_root() {
    if [ "$(id -u)" -ne 0 ]; then
        command -v sudo >/dev/null 2>&1 && SUDO="sudo" || SUDO=""
    else
        SUDO=""
    fi
}

get_script_path() {
    [ "${SCRIPT_PATH_OVERRIDE-}" ] && { printf '%s' "$SCRIPT_PATH_OVERRIDE"; return 0; }
    
    # 方法1: readlink (最准)
    if command -v readlink >/dev/null 2>&1; then
        readlink -f "$0" 2>/dev/null || printf '%s' "$0"
    # 方法2: realpath
    elif command -v realpath >/dev/null 2>&1; then
        realpath "$0" 2>/dev/null || printf '%s' "$0"
    # 方法3: 降级处理 (针对精简版 OpenWrt)
    else
        case "$0" in
            /*) printf '%s' "$0" ;;
            *) printf '%s/%s' "$(pwd)" "$0" ;;
        esac
    fi
}

canonicalize() {
    target="$1"
    [ -z "$target" ] && { printf '%s' ""; return 0; }
    if command -v readlink >/dev/null 2>&1; then
        readlink -f "$target" 2>/dev/null || printf '%s' "$target"
    elif command -v realpath >/dev/null 2>&1; then
        realpath "$target" 2>/dev/null || printf '%s' "$target"
    else
        printf '%s' "$target"
    fi
}

# ==================== 系统检测 ====================
OS_TYPE="unknown"
OS_VERSION=""

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release 2>/dev/null || true
        OS_VERSION="${PRETTY_NAME:-${NAME:-} ${VERSION:-}}"
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
            OS_VERSION="OpenWrt $(uname -r 2>/dev/null || echo "Unknown")"
        elif command -v apt-get >/dev/null 2>&1; then
            OS_TYPE="debian"
            OS_VERSION="Debian-based $(uname -r 2>/dev/null || echo "Unknown")"
        fi
    fi
    
    if [ "$OS_TYPE" = "unknown" ]; then
        printf '%s' "无法自动确定系统类型。请选择：\n1) OpenWrt\n2) Debian/Ubuntu\n3) 退出\n输入选项编号: "
        read -r opt
        case "$opt" in
            1) OS_TYPE="openwrt"; OS_VERSION="OpenWrt (Manual)" ;;
            2) OS_TYPE="debian"; OS_VERSION="Debian-based (Manual)" ;;
            *) _fatal "已退出" ;;
        esac
    fi
}

# ==================== 依赖安装 ====================
install_deps_openwrt() {
    _log "检查并安装依赖（OpenWrt）..."
    PKGS="curl jq"
    missing=""
    
    for p in $PKGS; do
        command -v "$p" >/dev/null 2>&1 || missing="$missing $p"
    done
    
    missing="$(printf '%s' "$missing" | sed 's/^ *//;s/ *$//')"
    [ -z "$missing" ] && { _log "所有依赖已满足"; return 0; }
    
    command -v opkg >/dev/null 2>&1 || { _err "opkg 未找到，请手动安装：$missing"; return 1; }
    
    _log "执行 opkg update..."
    opkg update >/dev/null 2>&1 || _warn "opkg update 失败（将继续尝试安装）"
    
    for p in $missing; do
        [ -z "$p" ] && continue
        _log "安装 $p..."
        opkg install "$p" >/dev/null 2>&1 && _log "$p 安装成功" || _warn "$p 安装失败"
    done
}

install_deps_debian() {
    ensure_root
    _log "检查并安装依赖（Debian）..."
    PKGS="curl wget ca-certificates gnupg jq"
    RUNPREFIX="${SUDO:-}"
    
    $RUNPREFIX apt-get update >/dev/null 2>&1 || _warn "apt-get update 失败"
    
    for p in $PKGS; do
        if dpkg -s "$p" >/dev/null 2>&1; then
            _log "$p 已安装"
        else
            _log "安装 $p..."
            $RUNPREFIX apt-get install -y "$p" >/dev/null 2>&1 || _warn "安装 $p 失败"
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

# ==================== Bash 安装 ====================
install_bash_if_needed() {
    command -v bash >/dev/null 2>&1 && return 0
    
    _warn "未检测到 bash，某些脚本需要 bash 环境"
    printf '%s' "是否现在安装 bash？(y/N): "
    read -r ans
    case "$ans" in
        [yY]*)
            ensure_root
            RUNPREFIX="${SUDO:-}"
            if [ "$OS_TYPE" = "debian" ]; then
                _log "安装 bash（Debian）..."
                $RUNPREFIX apt-get update >/dev/null 2>&1
                $RUNPREFIX apt-get install -y bash || { _err "安装 bash 失败"; return 1; }
            elif [ "$OS_TYPE" = "openwrt" ]; then
                _log "安装 bash（OpenWrt）..."
                opkg update >/dev/null 2>&1
                opkg install bash || { _err "安装 bash 失败"; return 1; }
            else
                _err "未知系统类型，无法自动安装 bash"
                return 1
            fi
            _log "bash 安装成功"
            return 0
            ;;
        *)
            _log "已取消安装 bash"
            return 1
            ;;
    esac
}

# ==================== Sing-box 管理 ====================
is_singbox_installed() {
    command -v sing-box >/dev/null 2>&1 && return 0
    [ -x "/usr/bin/sing-box" ] || [ -x "/usr/sbin/sing-box" ] || [ -x "/bin/sing-box" ]
}

get_singbox_version() {
    if is_singbox_installed; then
        version=$(sing-box version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        printf '%s' "$version"
    else
        printf '%s' "未安装"
    fi
}

get_singbox_status() {
    if ! is_singbox_installed; then
        printf '\033[90m%s\033[0m' "● 未安装"
        return
    fi
    
    if [ "$OS_TYPE" = "debian" ]; then
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl is-active sing-box >/dev/null 2>&1; then
                printf '\033[32m%s\033[0m' "● 运行中"
            else
                printf '\033[31m%s\033[0m' "● 已停止"
            fi
        else
            printf '\033[90m%s\033[0m' "● 状态未知"
        fi
    else
        # OpenWrt
        if [ -x "/etc/init.d/sing-box" ]; then
            if /etc/init.d/sing-box status 2>/dev/null | grep -q "running\|active"; then
                printf '\033[32m%s\033[0m' "● 运行中"
            elif ps w | grep -v grep | grep -q sing-box; then
                printf '\033[32m%s\033[0m' "● 运行中"
            else
                printf '\033[31m%s\033[0m' "● 已停止"
            fi
        elif ps w | grep -v grep | grep -q sing-box; then
            printf '\033[32m%s\033[0m' "● 运行中"
        else
            printf '\033[31m%s\033[0m' "● 已停止"
        fi
    fi
}

install_singbox_openwrt() {
    _log "使用官方安装脚本安装 sing-box（OpenWrt）..."
    prepare_tmp
    download "https://sing-box.app/install.sh" "$TMP_DIR/install_singbox.sh" || _fatal "下载安装脚本失败"
    sh "$TMP_DIR/install_singbox.sh" || _err "运行官方安装脚本失败"
}

install_singbox_debian() {
    _log "通过 sagernet 仓库安装 sing-box（Debian）..."
    ensure_root
    RUNPREFIX="${SUDO:-}"
    
    $RUNPREFIX mkdir -p /etc/apt/keyrings 2>/dev/null || _err "创建 /etc/apt/keyrings 失败"
    
    if ! download "https://sing-box.app/gpg.key" "/tmp/sagernet.asc"; then
        _log "使用 curl 直接写入 GPG key..."
        $RUNPREFIX curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc || _fatal "写入 GPG key 失败"
    else
        $RUNPREFIX mv /tmp/sagernet.asc /etc/apt/keyrings/sagernet.asc || _fatal "移动 GPG key 失败"
    fi
    
    $RUNPREFIX chmod a+r /etc/apt/keyrings/sagernet.asc || _err "设置 key 权限失败"
    
    $RUNPREFIX tee /etc/apt/sources.list.d/sagernet.sources > /dev/null <<'EOF'
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
EOF
    
    $RUNPREFIX apt-get update || { _err "apt-get update 失败"; return 1; }
    $RUNPREFIX apt-get install -y sing-box || { _err "apt 安装 sing-box 失败"; return 1; }
    
    # 自动启用开机自启
    _log "启用 sing-box 开机自启..."
    $RUNPREFIX systemctl enable sing-box 2>/dev/null && _log "已启用开机自启" || _warn "启用开机自启失败"
}

install_or_update_singbox() {
    # 在安装 sing-box 时才检查依赖
    _log "检查依赖..."
    install_deps
    
    if is_singbox_installed; then
        _log "检测到 sing-box 已安装"
        printf '%s' "检查更新并覆盖安装？(y/N): "
        read -r ans
        case "$ans" in
            [yY]*)
                [ "$OS_TYPE" = "openwrt" ] && install_singbox_openwrt || install_singbox_debian
                ;;
            *) _log "跳过更新" ;;
        esac
    else
        _log "未检测到 sing-box，开始安装..."
        [ "$OS_TYPE" = "openwrt" ] && install_singbox_openwrt || install_singbox_debian
    fi
}

uninstall_singbox() {
    printf '%s' "确认要卸载 sing-box？（这会删除 sing-box 程序文件及配置）(y/N): "
    read -r ans
    case "$ans" in
        [yY]*)
            if [ "$OS_TYPE" = "debian" ]; then
                ensure_root
                RUNPREFIX="${SUDO:-}"
                
                _log "停止并禁用 sing-box 服务..."
                $RUNPREFIX systemctl stop sing-box 2>/dev/null || true
                $RUNPREFIX systemctl disable sing-box 2>/dev/null || true
                
                _log "卸载 sing-box 软件包..."
                $RUNPREFIX apt-get remove --purge -y sing-box 2>&1 | grep -v "directory.*not empty so not removed" || true
                
                # 清理可能残留的 systemd 服务文件
                for f in /etc/systemd/system/sing-box.service /usr/lib/systemd/system/sing-box.service /lib/systemd/system/sing-box.service; do
                    if [ -f "$f" ]; then
                        _log "删除服务文件: $f"
                        $RUNPREFIX rm -f "$f" 2>/dev/null || true
                    fi
                done
                
                # 重新加载 systemd
                $RUNPREFIX systemctl daemon-reload 2>/dev/null || true
                
            else
                _log "停止 sing-box 服务..."
                [ -x "/etc/init.d/sing-box" ] && {
                    /etc/init.d/sing-box stop 2>/dev/null || true
                    /etc/init.d/sing-box disable 2>/dev/null || true
                }
                
                if command -v opkg >/dev/null 2>&1; then
                    _log "使用 opkg 卸载 sing-box..."
                    opkg remove sing-box 2>/dev/null || _warn "opkg remove 失败，尝试手动删除"
                fi
                
                # 手动清理二进制文件
                for p in /usr/bin/sing-box /usr/sbin/sing-box /bin/sing-box; do
                    if [ -f "$p" ]; then
                        _log "删除: $p"
                        rm -f "$p" 2>/dev/null || true
                    fi
                done
                
                # 清理 init.d 脚本
                [ -f "/etc/init.d/sing-box" ] && {
                    _log "删除 init.d 脚本"
                    rm -f "/etc/init.d/sing-box" 2>/dev/null || true
                }
            fi
            
            # 询问是否删除配置文件
            printf '%s' "是否同时删除 sing-box 配置目录？(y/N): "
            read -r del_conf
            case "$del_conf" in
                [yY]*)
                    for confdir in "$SINGBOX_CONFIG_DIR_OPENWRT" "$SINGBOX_CONFIG_DIR_DEBIAN" /etc/sing-box; do
                        if [ -d "$confdir" ]; then
                            _log "删除配置目录: $confdir"
                            rm -rf "$confdir" 2>/dev/null || _warn "删除 $confdir 失败"
                        fi
                    done
                    ;;
                *) _log "保留配置文件" ;;
            esac
            
            _log "sing-box 卸载完成"
            ;;
        *) _log "取消卸载" ;;
    esac
}

# ==================== 服务管理 ====================
svc_action() {
    action="$1"
    if [ "$OS_TYPE" = "debian" ]; then
        ensure_root
        RUNPREFIX="${SUDO:-}"
        case "$action" in
            enable) $RUNPREFIX systemctl enable sing-box || _err "systemctl enable 失败" ;;
            disable) $RUNPREFIX systemctl disable sing-box || _err "systemctl disable 失败" ;;
            start) $RUNPREFIX systemctl start sing-box || _err "systemctl start 失败" ;;
            stop) $RUNPREFIX systemctl stop sing-box || _err "systemctl stop 失败" ;;
            kill) $RUNPREFIX systemctl kill sing-box || _err "systemctl kill 失败" ;;
            restart) $RUNPREFIX systemctl restart sing-box || _err "systemctl restart 失败" ;;
            status) $RUNPREFIX systemctl status sing-box || true ;;
            journal) $RUNPREFIX journalctl -u sing-box --output cat -e || _err "journalctl 失败" ;;
            journalf) $RUNPREFIX journalctl -u sing-box --output cat -f || _err "journalctl -f 失败" ;;
            *) _err "未知操作 $action" ;;
        esac
    else
        if [ -x "/etc/init.d/sing-box" ]; then
            case "$action" in
                enable|disable|start|stop|restart)
                    /etc/init.d/sing-box "$action" || _err "$action 失败"
                    ;;
                status)
                    /etc/init.d/sing-box status 2>/dev/null || ps w | grep -v grep | grep sing-box || _log "未运行"
                    ;;
                kill)
                    if command -v pkill >/dev/null 2>&1; then
                        pkill -9 -f sing-box || _warn "未找到进程"
                    else
                        killall -9 sing-box 2>/dev/null || _warn "未找到进程"
                    fi
                    ;;
                journal|journalf)
                    if command -v logread >/dev/null 2>&1; then
                        [ "$action" = "journalf" ] && logread -f || logread
                    else
                        [ -f /var/log/messages ] && tail -n 200 /var/log/messages || _err "未找到日志文件"
                    fi
                    ;;
                *) _err "未知操作 $action" ;;
            esac
        else
            _err "/etc/init.d/sing-box 未找到，无法通过 init.d 管理"
        fi
    fi
}

manage_singbox_menu() {
    while :; do
        clear 2>/dev/null || printf '\033[2J\033[H'
        cat <<MENU
┌────────────────────────────────────────┐
│         Sing-box 服务管理              │
└────────────────────────────────────────┘
  1) 启动服务
  2) 停止服务
  3) 重启服务
  4) 查看状态
  5) 强制停止
  6) 启用开机自启
  7) 禁用开机自启
  8) 查看日志（按页）
  9) 实时日志
  u) 卸载 sing-box
  0) 返回主菜单
────────────────────────────────────────
MENU
        printf '%s' "选择: "
        read -r opt
        case "$opt" in
            1) svc_action start ;;
            2) svc_action stop ;;
            3) svc_action restart ;;
            4) svc_action status ;;
            5) svc_action kill ;;
            6) svc_action enable ;;
            7) svc_action disable ;;
            8) svc_action journal ;;
            9) svc_action journalf ;;
            u|U) uninstall_singbox ;;
            0) break ;;
            *) _err "无效选项" ;;
        esac
        [ "$opt" != "0" ] && { printf '%s' "按回车继续..."; read -r _; }
    done
}

# ==================== 配置管理 ====================
get_config_from_script() {
    scriptpath=$(get_script_path)
    [ -f "$scriptpath" ] || { printf '%s' ""; return 0; }
    val=$(grep -m1 '^DEFAULT_CONFIG_URL=' "$scriptpath" 2>/dev/null | sed -e 's/^DEFAULT_CONFIG_URL=//' -e 's/^"//' -e 's/"$//')
    printf '%s' "$val"
}

save_config_to_script() {
    # 修复：必须先确保临时目录存在
    prepare_tmp
    
    scriptpath=$(get_script_path)
    
    if [ ! -f "$scriptpath" ]; then
        _err "无法定位脚本文件路径: $scriptpath"
        return 1
    fi
    
    tmp="$TMP_DIR/sm.sh.tmp.$$"
    
    awk -v new="DEFAULT_CONFIG_URL=\"$1\"" 'BEGIN{repl=0}
        /^DEFAULT_CONFIG_URL=/ && repl==0 { print new; repl=1; next }
        { print }
        END{ if(repl==0) print new }' "$scriptpath" > "$tmp" || { _err "生成临时脚本失败"; return 1; }
    
    ensure_root
    RUNPREFIX="${SUDO:-}"
    
    # 修复：写入逻辑增强，处理权限并使用 cat/cp 避免 inode 丢失问题
    if [ -w "$scriptpath" ]; then
        cat "$tmp" > "$scriptpath" 2>/dev/null
    elif [ -n "$RUNPREFIX" ]; then
        $RUNPREFIX cp -f "$tmp" "$scriptpath"
        $RUNPREFIX chmod +x "$scriptpath"
    else
        _err "无权限写入脚本，请尝试 sudo 运行"
        rm -f "$tmp"
        return 1
    fi
    
    if [ $? -eq 0 ]; then
        rm -f "$tmp"
        _log "已更新并保存默认地址"
        return 0
    else
        _err "写入失败，临时文件保留在 $tmp"
        return 1
    fi
}

download_and_replace_config() {
    url="$1"
    prepare_tmp
    out="$TMP_DIR/config.json"
    
    _log "从 $url 下载配置..."
    download "$url" "$out" || { _err "下载配置失败：$url"; return 1; }
    
    command -v jq >/dev/null 2>&1 || { _err "未检测到 jq，无法验证 JSON 格式"; return 1; }
    
    if ! jq -e . "$out" >/dev/null 2>&1; then
        _err "下载的文件不是有效的 JSON"
        printf '%s' "是否保留该文件以便手动检查？(y/N): "
        read -r keep
        case "$keep" in
            [yY]*) _log "已保留下载文件：$out"; return 1 ;;
            *) rm -f "$out"; return 1 ;;
        esac
    fi
    
    [ "$OS_TYPE" = "openwrt" ] && confdir="$SINGBOX_CONFIG_DIR_OPENWRT" || confdir="$SINGBOX_CONFIG_DIR_DEBIAN"
    [ -d "$confdir" ] || mkdir -p "$confdir" || { _err "创建目录失败：$confdir"; return 1; }
    
    if mv -f "$out" "$confdir/config.json" 2>/dev/null || cp -f "$out" "$confdir/config.json" 2>/dev/null; then
        rm -f "$out" 2>/dev/null || true
        _log "配置已覆盖到 $confdir/config.json"
        return 0
    else
        _err "移动/复制配置文件失败"
        return 1
    fi
}

config_update_menu() {
    CONFIG_URL="$(get_config_from_script)"
    [ -z "$CONFIG_URL" ] && CONFIG_URL="$DEFAULT_CONFIG_URL"
    
    while :; do
        clear 2>/dev/null || printf '\033[2J\033[H'
        cat <<MENU
┌────────────────────────────────────────┐
│         配置文件管理                   │
└────────────────────────────────────────┘
  当前默认地址: $CONFIG_URL

  1) 修改默认下载地址
  2) 使用自定义地址下载配置
  3) 使用默认地址更新配置
  0) 返回主菜单
────────────────────────────────────────
MENU
        printf '%s' "选择: "
        read -r opt
        case "$opt" in
            1)
                printf '%s' "输入新的默认下载地址: "
                read -r newurl
                if [ -n "$newurl" ]; then
                    save_config_to_script "$newurl" && CONFIG_URL="$newurl"
                else
                    _err "地址为空，未修改"
                fi
                ;;
            2)
                printf '%s' "输入自定义下载地址: "
                read -r custom
                [ -n "$custom" ] && download_and_replace_config "$custom" || _err "地址为空"
                ;;
            3)
                download_and_replace_config "$CONFIG_URL"
                ;;
            0) break ;;
            *) _err "无效选项" ;;
        esac
        [ "$opt" != "0" ] && { printf '%s' "按回车继续..."; read -r _; }
    done
}

# ==================== UFW 防火墙脚本 ====================
download_and_run_ufw() {
    _log "下载 UFW 防火墙管理脚本..."
    prepare_tmp
    out="$TMP_DIR/ufw.sh"
    
    UFW_URL="https://raw.githubusercontent.com/Leovikii/sm/main/shell/ufw.sh"
    
    if ! download "$UFW_URL" "$out"; then
        _err "下载 UFW 脚本失败"
        return 1
    fi
    
    chmod +x "$out" || { _err "添加执行权限失败"; return 1; }
    
    # 检查并安装 bash（如果需要）
    if ! command -v bash >/dev/null 2>&1; then
        _warn "UFW 脚本需要 bash 环境"
        if ! install_bash_if_needed; then
            _err "无法运行 UFW 脚本：缺少 bash"
            return 1
        fi
    fi
    
    _log "UFW 脚本下载成功，开始运行..."
    bash "$out"
}

# ==================== TCP 优化脚本 ====================
download_tcpx() {
    _log "下载 TCP 优化脚本..."
    prepare_tmp
    out="$TMP_DIR/tcpx.sh"
    
    if ! download "$TCPX_URL" "$out"; then
        _err "下载 TCP 优化脚本失败"
        return 1
    fi
    
    chmod +x "$out" || { _err "添加执行权限失败"; return 1; }
    
    # 检查并安装 bash（如果需要）
    if ! command -v bash >/dev/null 2>&1; then
        if ! install_bash_if_needed; then
            _warn "继续使用 sh 运行，可能会失败..."
            sh "$out" 2>&1 || {
                _err "脚本执行失败"
                _log ""
                _log "原因：TCP 优化脚本使用了 bash 特性，而当前系统只有 sh"
                _log "解决方案："
                [ "$OS_TYPE" = "debian" ] && _log "  运行: apt-get install bash"
                [ "$OS_TYPE" = "openwrt" ] && _log "  运行: opkg install bash"
                return 1
            }
            return 0
        fi
    fi
    
    # 使用 bash 执行
    _log "使用 bash 运行 TCP 优化脚本..."
    bash "$out"
}

# ==================== 脚本管理 ====================
update_script() {
    prepare_tmp
    out="$TMP_DIR/sm.sh"
    
    _log "从 $SCRIPT_REMOTE_URL 下载最新脚本..."
    download "$SCRIPT_REMOTE_URL" "$out" || { _err "下载脚本失败"; return 1; }
    
    ensure_root
    RUNPREFIX="${SUDO:-}"
    
    [ "$OS_TYPE" = "openwrt" ] && target="/usr/sbin/sm.sh" || target="$SCRIPT_INSTALL_PATH"
    target_dir="$(dirname "$target")"
    [ -d "$target_dir" ] || $RUNPREFIX mkdir -p "$target_dir" 2>/dev/null
    
    if [ "$(id -u)" -eq 0 ]; then
        mv -f "$out" "$target" && chmod +x "$target"
    elif [ -n "$RUNPREFIX" ]; then
        $RUNPREFIX sh -c "cat '$out' > '$target' && chmod +x '$target'" && rm -f "$out"
    else
        mv -f "$out" "./sm.sh" && chmod +x "./sm.sh" && target="$(pwd)/sm.sh"
    fi
    
    _log "脚本已更新到 $target"
}

uninstall_script() {
    printf '%s' "确认卸载脚本并删除脚本生成的所有文件？(y/N): "
    read -r ans
    case "$ans" in
        [yY]*)
            files=""
            cur="$(get_script_path)"
            
            # 收集脚本文件
            for f in "$SCRIPT_INSTALL_PATH" "/usr/sbin/sm.sh" "$cur" "/root/sm.sh" "$HOME/sm.sh"; do
                [ -e "$f" ] && files="$files
$f"
            done
            
            # 收集临时目录
            [ -d "$TMP_DIR" ] && files="$files
$TMP_DIR"
            
            files="$(printf '%s' "$files" | sed '/^$/d' | sort -u)"
            
            if [ -z "$files" ]; then
                _log "未检测到可删除的脚本文件"
            else
                printf '%s\n' "将删除如下脚本文件/目录：" "$files"
                printf '%s' "确认删除上列脚本文件？(y/N): "
                read -r confirm
                case "$confirm" in
                    [yY]*)
                        ensure_root
                        RUNPREFIX="${SUDO:-}"
                        printf '%s\n' "$files" | while IFS= read -r p; do
                            [ -z "$p" ] || [ ! -e "$p" ] && continue
                            _log "删除: $p"
                            if [ -d "$p" ]; then
                                $RUNPREFIX rm -rf "$p" 2>/dev/null || _warn "删除 $p 失败"
                            else
                                $RUNPREFIX rm -f "$p" 2>/dev/null || _warn "删除 $p 失败"
                            fi
                        done
                        _log "脚本文件已删除"
                        ;;
                    *) _log "取消删除脚本文件" ;;
                esac
            fi
            
            # 单独询问是否卸载 sing-box
            printf '\n%s' "是否同时卸载 sing-box？(y/N): "
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
        clear 2>/dev/null || printf '\033[2J\033[H'
        cat <<MENU
┌────────────────────────────────────────┐
│         脚本管理                       │
└────────────────────────────────────────┘
  1) 更新脚本
  2) 卸载脚本（清理脚本生成的文件）
  0) 返回主菜单
────────────────────────────────────────
MENU
        printf '%s' "选择: "
        read -r opt
        case "$opt" in
            1) update_script ;;
            2) uninstall_script ;;
            0) break ;;
            *) _err "无效选项" ;;
        esac
        [ "$opt" != "0" ] && { printf '%s' "按回车继续..."; read -r _; }
    done
}

# ==================== 主菜单 ====================
main_menu() {
    while :; do
        clear 2>/dev/null || printf '\033[2J\033[H'
        
        # 获取系统信息
        hostname="$(uname -n 2>/dev/null || echo "unknown")"
        uptime_info="$(uptime 2>/dev/null | sed 's/.*up *//' | sed 's/,.*//' || echo "unknown")"
        
        # 获取 sing-box 信息
        singbox_version="$(get_singbox_version)"
        singbox_status="$(get_singbox_status)"
        
        cat <<HEADER
╔═══════════════════════════════════════╗
║      Sing-box Manager v2.0            ║
╠═══════════════════════════════════════╣
║ 主机名: ${hostname}
║ 系统: ${OS_VERSION}
║ 运行时间: ${uptime_info}
╠═══════════════════════════════════════╣
║ Sing-box 版本: ${singbox_version}
║ 运行状态: ${singbox_status}
╚═══════════════════════════════════════╝
HEADER
        
        cat <<MENU

  1) 下载 UFW 管理脚本（建议）
  2) 安装或更新 sing-box
  3) 更新配置文件
  4) sing-box 服务管理
  5) 下载 TCP 优化脚本
  6) 脚本管理
  0) 退出

────────────────────────────────────────
MENU
        printf '%s' "请选择操作: "
        read -r opt
        case "$opt" in
            1) 
                _log "提示：安装 UFW 防火墙可以有效保障服务器安全"
                printf '%s' "是否继续下载并运行 UFW 管理脚本？(y/N): "
                read -r ans
                case "$ans" in
                    [yY]*) download_and_run_ufw ;;
                    *) _log "已取消" ;;
                esac
                ;;
            2) install_or_update_singbox ;;
            3) config_update_menu ;;
            4) manage_singbox_menu ;;
            5) download_tcpx ;;
            6) script_management_menu ;;
            0) _log "退出"; break ;;
            *) _err "无效选项，请输入 0-6 之间的数字" ;;
        esac
        [ "$opt" != "0" ] && { printf '%s' "按回车返回菜单..."; read -r _; }
    done
}

# ==================== 脚本安装 ====================
install_self_if_needed() {
    cur="$(get_script_path)"
    [ "$OS_TYPE" = "openwrt" ] && target="/usr/sbin/sm.sh" || target="$SCRIPT_INSTALL_PATH"
    
    [ "$(canonicalize "$cur")" = "$(canonicalize "$target")" ] && return 0
    
    ensure_root
    RUNPREFIX="${SUDO:-}"
    target_dir="$(dirname "$target")"
    [ -d "$target_dir" ] || $RUNPREFIX mkdir -p "$target_dir" 2>/dev/null
    
    if [ "$(id -u)" -eq 0 ]; then
        mv -f "$cur" "$target" && chmod +x "$target"
    elif [ -n "$RUNPREFIX" ]; then
        $RUNPREFIX sh -c "cat '$cur' > '$target' && rm -f '$cur' && chmod +x '$target'"
    else
        cp -f "$cur" "$target" && rm -f "$cur" && chmod +x "$target"
    fi
    
    _log "已将脚本移动到 $target"
    exec "$target" "$@"
}

# ==================== 主函数 ====================
main() {
    detect_os
    install_self_if_needed "$@"
    main_menu
}

trap 'rm -rf "$TMP_DIR" 2>/dev/null; exit' INT TERM
main
#!/bin/bash
#
# sm.sh - Sing-box / 系统工具一体化管理脚本
# 自动生成 — 修改请编辑 shell/src/* 后运行 `bash shell/build.sh`
#

set -uo pipefail

# >>> src/config.sh
# ==============================================================================
# 全局常量、临时目录、信号陷阱
# ==============================================================================

SCRIPT_NAME="sm.sh"
SCRIPT_VERSION="3.0.2"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"
SCRIPT_UPDATE_URL="https://raw.githubusercontent.com/Leovikii/sm/main/shell/sm.sh"

DEFAULT_CONFIG_URL="https://example.com/config.json"
TCPX_URL="https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh"

STATIC_SITE_URL="https://html5up.net/massively/download"
CAMOUFLAGE_WEB_ROOT="/var/www/sm-camouflage"
OPENLIST_DIR="/opt/openlist"

# AnyTLS 证书同步目录：所有服务器统一使用 active.{crt,key}
SB_CERT_DIR="/etc/sing-box/certs"
CERT_SYNC_SCRIPT="/usr/local/bin/sm-cert-sync.sh"
CERT_SYNC_SERVICE="/etc/systemd/system/sm-cert-sync.service"
CERT_SYNC_TIMER="/etc/systemd/system/sm-cert-sync.timer"

# 用 $'...' 在赋值时就把 \033 解析成真 ESC 字节，
# 让 read -p / printf "%s" 等不解析转义的场景也能正常带色
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
PLAIN=$'\033[0m'

TMP_DIR="/tmp/sm_manager_tmp_$$"
DEPS_FLAG="/var/lib/sm/.deps_ok"
_DEPS_CHECKED=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT
trap 'echo -e "\n${YELLOW}[WARN]${PLAIN} 接收到退出指令，脚本终止。"; exit 130' INT TERM HUP

# >>> src/lib/log.sh
# ==============================================================================
# log:: 日志输出
# ==============================================================================

log::info() { echo -e "${GREEN}[INFO]${PLAIN} $1"; }
log::warn() { echo -e "${YELLOW}[WARN]${PLAIN} $1"; }
log::err()  { echo -e "${RED}[ERROR]${PLAIN} $1"; }
log::step() { echo -e "${BLUE}[*]${PLAIN} $1"; }

# >>> src/lib/ui.sh
# ==============================================================================
# ui:: 终端 UI 工具（菜单/输入/确认）
# ==============================================================================

ui::clear()   { clear; }
ui::divider() { echo -e "────────────────────────────────────────────────"; }

# ui::header TITLE [SUBTITLE]
ui::header() {
    local title="$1" subtitle="${2:-}"
    ui::clear
    echo -e "┌──────────────────────────────────────────────┐"
    printf "│              ${BLUE}%-32s${PLAIN}│\n" "$title"
    [[ -n "$subtitle" ]] && printf "│                ${GREEN}%-30s${PLAIN}│\n" "$subtitle"
    echo -e "└──────────────────────────────────────────────┘"
}

# ui::confirm PROMPT  -> 0 if yes, 1 otherwise
ui::confirm() {
    local prompt="$1" ans
    read -r -p "$prompt (y/N): " ans || exit 130
    [[ "${ans,,}" == "y" ]]
}

# ui::prompt PROMPT VARNAME [-e]
ui::prompt() {
    local prompt="$1" varname="$2" flag="${3:-}"
    if [[ "$flag" == "-e" ]]; then
        read -e -r -p "$prompt" "$varname" || exit 130
    else
        read -r -p "$prompt" "$varname" || exit 130
    fi
}

ui::pause() { read -n 1 -s -r -p "按任意键继续..." || exit 130; echo; }

# >>> src/lib/sys.sh
# ==============================================================================
# sys:: 系统探测与基本环境
# ==============================================================================

sys::has_cmd() { command -v "$1" &>/dev/null; }

sys::require_root() {
    [[ $EUID -ne 0 ]] && { log::err "请使用 root 用户运行此脚本 (sudo -i)"; exit 1; }
}

sys::require_debian() {
    if [[ ! -f /etc/os-release ]]; then
        log::err "无法检测系统版本，仅支持 Debian/Ubuntu 标准发行版。"
        exit 1
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "$ID" != "debian" && "$ID" != "ubuntu" && "${ID_LIKE:-}" != *"debian"* ]]; then
        log::warn "本脚本专为 Debian/Ubuntu 设计，检测到当前系统为: $ID"
        ui::confirm "是否强制继续?" || exit 1
    fi
}

sys::distro_id() {
    [[ -f /etc/os-release ]] && (. /etc/os-release && echo "${ID:-debian}") || echo "debian"
}

sys::distro_codename() {
    [[ -f /etc/os-release ]] && (. /etc/os-release && echo "${VERSION_CODENAME:-}")
}

sys::uptime() {
    sys::has_cmd uptime && uptime -p 2>/dev/null | sed 's/up //' || echo "N/A"
}

sys::reboot_if_needed() {
    [[ ! -f /var/run/reboot-required ]] && { log::info "升级完成，当前无需重启。"; return; }
    log::warn "系统提示需要重启以应用新内核 (常见于 root 提权漏洞修复)。"
    if ui::confirm "是否立即重启?"; then
        log::info "系统将在 3 秒后重启..."
        sleep 3
        reboot
    else
        log::info "请稍后手动执行 reboot 完成内核切换。"
    fi
}

# >>> src/lib/net.sh
# ==============================================================================
# net:: 网络下载（统一 UA / 超时 / 重试）
# ==============================================================================

# net::fetch URL  -> 输出到 stdout
net::fetch() {
    local url="$1"
    if sys::has_cmd curl; then
        curl -k -f -L --retry 2 --connect-timeout 5 -s -A "sing-box/1.0" "$url"
    else
        wget --no-check-certificate -q -O- -T 5 -t 2 --user-agent="sing-box/1.0" "$url"
    fi
}

# net::download URL DEST
net::download() {
    local url="$1" dest="$2"
    if sys::has_cmd curl; then
        curl -k -f -L --retry 3 --connect-timeout 10 -s -A "sing-box/1.0" -o "$dest" "$url"
    else
        wget --no-check-certificate -q -T 15 -t 3 --user-agent="sing-box/1.0" -O "$dest" "$url"
    fi
}

# >>> src/lib/pkg.sh
# ==============================================================================
# pkg:: APT 软件包管理封装
# ==============================================================================

pkg::update() {
    if [[ "${1:-}" == "quiet" ]]; then
        apt-get update -y >/dev/null 2>&1
    else
        apt-get update -y
    fi
}

pkg::install()       { DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; }
pkg::install_quiet() { DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >/dev/null 2>&1; }
pkg::purge()         { DEBIAN_FRONTEND=noninteractive apt-get purge -y "$@"; }
pkg::autoremove()    { DEBIAN_FRONTEND=noninteractive apt-get autoremove -y --purge "$@"; }
pkg::clean()         { apt-get clean; }

# pkg::full_upgrade [APT_OPTS...] - 内核及依赖全量升级
pkg::full_upgrade() {
    DEBIAN_FRONTEND=noninteractive apt-get "$@" -y full-upgrade
}

# pkg::ensure_deps - 安装通用依赖（带缓存标记）
pkg::ensure_deps() {
    [[ $_DEPS_CHECKED -eq 1 ]] && return 0
    if [[ -f "$DEPS_FLAG" ]]; then _DEPS_CHECKED=1; return 0; fi

    local deps="curl wget jq tar ca-certificates gnupg"
    local missing=""
    for dep in $deps; do
        sys::has_cmd "$dep" || missing="$missing $dep"
    done

    if [[ -n "$missing" ]]; then
        log::info "正在安装必要依赖:$missing"
        pkg::update quiet
        if ! pkg::install_quiet $missing; then
            log::err "依赖安装失败:$missing"
            return 1
        fi
    fi
    mkdir -p "$(dirname "$DEPS_FLAG")"
    touch "$DEPS_FLAG"
    _DEPS_CHECKED=1
}

# pkg::add_gpg_key URL DEST [--dearmor]
pkg::add_gpg_key() {
    local url="$1" dest="$2" mode="${3:-}"
    if [[ "$mode" == "--dearmor" ]]; then
        net::fetch "$url" | gpg --dearmor --yes -o "$dest" || return 1
    else
        net::fetch "$url" > "$dest" || return 1
        [[ -s "$dest" ]] || { rm -f "$dest"; return 1; }
    fi
    chmod a+r "$dest"
}

# pkg::write_repo CONTENT DEST_LIST
pkg::write_repo() {
    local content="$1" dest="$2"
    echo "$content" > "$dest"
}

# >>> src/lib/svc.sh
# ==============================================================================
# svc:: systemd 服务封装
# ==============================================================================

svc::is_active() { systemctl is-active --quiet "$1"; }
svc::start()     { systemctl start "$1"; }
svc::stop()      { systemctl stop "$1" 2>/dev/null; }
svc::restart()   { systemctl restart "$1"; }
svc::enable()    { systemctl enable "$1" >/dev/null 2>&1; }
svc::disable()   { systemctl disable "$1" 2>/dev/null; }
svc::logs()      { journalctl -u "$1" -f -o cat; }

# svc::ensure_running NAME [OK_MSG] [FAIL_MSG]
svc::ensure_running() {
    local name="$1"
    local ok_msg="${2:-$name 已启动}"
    local fail_msg="${3:-$name 启动失败，请检查 journalctl -u $name}"
    svc::enable "$name"
    svc::start "$name"
    if svc::is_active "$name"; then
        log::info "$ok_msg"
        return 0
    else
        log::warn "$fail_msg"
        return 1
    fi
}

# >>> src/self.sh
# ==============================================================================
# self:: 脚本自身的安装/更新/卸载/配置持久化
# ==============================================================================

self::install_shortcut() {
    [[ "$(realpath "$0")" == "$(realpath "$INSTALL_PATH" 2>/dev/null)" ]] && return 0
    log::info "首次运行，正在执行自安装..."
    cp -f "$0" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    log::info "快捷方式已安装: 输入 ${GREEN}${SCRIPT_NAME}${PLAIN} 即可随时启动"
    rm -f "$0"
    exec "$INSTALL_PATH" "$@"
}

# self::persist_var KEY VAL [PATH]
self::persist_var() {
    local key="$1" val="$2" path="${3:-$INSTALL_PATH}"
    sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$path"
}

self::read_var() {
    local key="$1"
    grep "^${key}=" "$INSTALL_PATH" 2>/dev/null | head -n 1 | cut -d'"' -f2
}

self::check_update() {
    log::info "正在检查脚本更新..."

    local remote_version
    remote_version=$(net::fetch "$SCRIPT_UPDATE_URL" | grep "^SCRIPT_VERSION=" | head -n 1 | cut -d'"' -f2)

    if [[ -z "$remote_version" ]]; then
        log::err "获取远程版本失败，请检查网络连接。"
        return 1
    fi
    if [[ "$SCRIPT_VERSION" == "$remote_version" ]]; then
        log::info "当前已是最新版本 (v${SCRIPT_VERSION})，无需更新。"
        return 0
    fi

    log::info "发现新版本: ${GREEN}v${remote_version}${PLAIN} (当前版本: v${SCRIPT_VERSION})"
    ui::confirm "是否更新管理脚本?" || { log::info "已取消更新。"; return 0; }

    mkdir -p "$TMP_DIR"
    local temp_script="$TMP_DIR/new_sm.sh"
    log::info "正在下载新版本..."
    if ! net::download "$SCRIPT_UPDATE_URL" "$temp_script"; then
        log::err "下载新版本文件失败。"
        return 1
    fi

    local old_url
    old_url=$(self::read_var "DEFAULT_CONFIG_URL")
    [[ -n "$old_url" ]] && self::persist_var "DEFAULT_CONFIG_URL" "$old_url" "$temp_script"

    chmod +x "$temp_script"
    mv -f "$temp_script" "$INSTALL_PATH"
    log::info "脚本更新成功！正在重新加载..."
    sleep 1
    exec "$INSTALL_PATH" "$@"
}

self::uninstall() {
    echo -e "\n${RED}⚠️  正在进行全面卸载向导${PLAIN}"
    log::info "脚本将逐项检查各组件是否已安装并询问是否一并卸载。"
    echo

    if sys::has_cmd sing-box; then
        if ui::confirm "检测到 ${BLUE}Sing-box${PLAIN}，是否卸载?"; then
            sb::uninstall
        else
            log::info "已保留 Sing-box"
        fi
        echo
    fi

    if caddy::is_installed; then
        if ui::confirm "检测到 ${BLUE}Caddy${PLAIN}，是否卸载?"; then
            caddy::uninstall
        else
            log::info "已保留 Caddy"
        fi
        echo
    fi

    if docker::is_installed; then
        if ui::confirm "检测到 ${BLUE}Docker${PLAIN}，是否卸载?"; then
            docker::uninstall
        else
            log::info "已保留 Docker"
        fi
        echo
    fi

    if ufw::is_installed; then
        if ui::confirm "检测到 ${BLUE}UFW${PLAIN}，是否卸载? (将丢失所有防火墙规则)"; then
            ufw::uninstall
        else
            log::info "已保留 UFW"
        fi
        echo
    fi

    if [[ -d "$CAMOUFLAGE_WEB_ROOT" || -f "$OPENLIST_DIR/docker-compose.yml" ]]; then
        if ui::confirm "检测到 ${BLUE}伪装站点${PLAIN}，是否卸载?"; then
            camouflage::uninstall
        else
            log::info "已保留伪装站点"
        fi
        echo
    fi

    echo -e "是否删除 ${BLUE}本管理脚本 ($SCRIPT_NAME)${PLAIN} 及缓存文件？"
    if ui::confirm "请输入"; then
        [[ -f "$INSTALL_PATH" ]] && rm -f "$INSTALL_PATH" && log::info "脚本文件已删除: $INSTALL_PATH"
        rm -f "$DEPS_FLAG"
        rm -rf /var/lib/sm
        echo -e "${GREEN}卸载完成。再见！${PLAIN}"
        exit 0
    else
        log::info "已保留管理脚本。"
    fi
}

# >>> src/modules/caddy.sh
# ==============================================================================
# caddy:: Caddy Web 服务器
# ==============================================================================

caddy::is_installed() { sys::has_cmd caddy; }

caddy::install() {
    log::info "准备安装 Caddy..."

    rm -f /etc/apt/sources.list.d/caddy-stable.list
    rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    rm -f /etc/apt/keyrings/caddy-stable-archive-keyring.gpg

    pkg::install_quiet debian-keyring debian-archive-keyring apt-transport-https

    mkdir -p /usr/share/keyrings
    if ! pkg::add_gpg_key \
            "https://dl.cloudsmith.io/public/caddy/stable/gpg.key" \
            "/usr/share/keyrings/caddy-stable-archive-keyring.gpg" \
            --dearmor; then
        log::err "Caddy GPG 密钥下载/导入失败。"
        return
    fi

    if ! net::fetch "https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt" \
            > /etc/apt/sources.list.d/caddy-stable.list; then
        log::err "Caddy 软件源列表下载失败。"
        rm -f /etc/apt/sources.list.d/caddy-stable.list
        return
    fi
    if [[ ! -s /etc/apt/sources.list.d/caddy-stable.list ]]; then
        log::err "Caddy 软件源列表为空，已中止。"
        rm -f /etc/apt/sources.list.d/caddy-stable.list
        return
    fi

    pkg::update || { log::err "apt-get update 失败。"; return; }
    if pkg::install caddy; then
        svc::ensure_running caddy "Caddy 安装成功并已启动 (配置: /etc/caddy/Caddyfile)"
    else
        log::err "Caddy 安装失败，请检查网络或源是否可用。"
    fi
}

caddy::uninstall() {
    if ! caddy::is_installed; then
        log::warn "Caddy 未安装"
        return
    fi
    log::warn "即将卸载 Caddy 及其软件源、密钥"
    ui::confirm "确认卸载?" || { log::info "取消卸载"; return; }

    log::step "正在停止服务..."
    svc::stop caddy
    svc::disable caddy

    log::step "正在卸载软件包..."
    pkg::purge caddy

    log::step "正在清理软件源与密钥..."
    rm -f /etc/apt/sources.list.d/caddy-stable.list
    rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    rm -f /etc/apt/keyrings/caddy-stable-archive-keyring.gpg

    if [[ -d /etc/caddy ]] && ui::confirm "是否同时删除配置目录 /etc/caddy?"; then
        rm -rf /etc/caddy
        log::info "/etc/caddy 已删除"
    fi

    pkg::autoremove >/dev/null 2>&1
    log::info "Caddy 已卸载"
}

# >>> src/modules/camouflage.sh
# ==============================================================================
# camouflage:: 伪装站点 + AnyTLS 证书统一同步
# 通过 systemd timer 每天扫描 Caddy 证书目录，同步到 /etc/sing-box/certs/
# 维护 active.{crt,key} 软链接，让所有服务器 AnyTLS 配置统一指向 active.*
# ==============================================================================

CADDY_MAIN_CONF="/etc/caddy/Caddyfile"
CADDY_SITES_DIR="/etc/caddy/sites.d"
ACTIVE_DOMAIN_FILE="${SB_CERT_DIR}/.active-domain"

# Caddy 进程以 caddy 用户运行；写入配置后必须确保 caddy 可读
# 否则 systemctl reload caddy 会报 "permission denied"
camouflage::_fix_caddy_perms() {
    local target="$1"
    chmod 0644 "$target" 2>/dev/null || true
    chown root:caddy "$target" 2>/dev/null || true
}

# active-domain 文件管理（决定 AnyTLS 用哪张证书）
camouflage::read_active_domain() {
    [[ -f "$ACTIVE_DOMAIN_FILE" ]] && cat "$ACTIVE_DOMAIN_FILE" 2>/dev/null || echo ""
}

camouflage::set_active_domain() {
    local domain="$1"
    mkdir -p "$SB_CERT_DIR"
    echo "$domain" > "$ACTIVE_DOMAIN_FILE"
    chmod 0644 "$ACTIVE_DOMAIN_FILE"
    log::info "AnyTLS 活动域名设为: $domain"

    # 立即把已存在的证书链接刷新一下
    if [[ -f "$SB_CERT_DIR/$domain.crt" ]]; then
        ln -sfn "$domain.crt" "$SB_CERT_DIR/active.crt"
        ln -sfn "$domain.key" "$SB_CERT_DIR/active.key"
        log::info "active.{crt,key} 已指向 $domain"
    else
        log::warn "$domain 的证书还未同步过，等下次 Caddy 续签后会自动指向"
    fi
}

# 部署伪装时调用：用户输入的域名就是 AnyTLS 要用的域名
#   - 首次部署：静默自动绑定为 active
#   - 重装同域名：什么都不做
#   - 冲突（已有 active 但本次域名不同）：询问是否切换
camouflage::bind_active_domain() {
    local domain="$1"
    local current
    current="$(camouflage::read_active_domain)"

    if [[ -z "$current" ]]; then
        camouflage::set_active_domain "$domain"
        return
    fi
    [[ "$current" == "$domain" ]] && return

    log::warn "当前 AnyTLS active 域名: $current"
    if ui::confirm "是否切换到本次部署的 $domain ?"; then
        camouflage::set_active_domain "$domain"
    else
        log::info "保持 active=$current ($domain 证书仍会被同步，但不动 active 软链接)"
    fi
}

camouflage::ensure_caddy() {
    caddy::is_installed && return 0
    log::info "伪装功能需要 Caddy，开始自动安装..."
    caddy::install
    caddy::is_installed || { log::err "Caddy 安装失败，无法继续。"; return 1; }
}

camouflage::ensure_docker() {
    docker::is_installed && return 0
    log::info "OpenList 伪装需要 Docker，开始自动安装..."
    docker::install
    docker::is_installed || { log::err "Docker 安装失败，无法继续。"; return 1; }
}

# 询问域名（必填，格式校验 + DNS 解析校验）
camouflage::_ask_domain() {
    local var="$1" prompt="${2:-请输入指向本机的域名: }" val=""
    while [[ -z "$val" ]]; do
        ui::prompt "$prompt" val
        if [[ ! "$val" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
            log::err "域名格式不正确，请重新输入"
            val=""
            continue
        fi
        if ! camouflage::_verify_domain_dns "$val"; then
            val=""
        fi
    done
    printf -v "$var" '%s' "$val"
}

# 拉本机公网 IP（IPv4 + IPv6 任一）
camouflage::_my_public_ips() {
    local v4 v6
    v4=$(curl -fsS4 --max-time 4 https://api.ipify.org 2>/dev/null || true)
    v6=$(curl -fsS6 --max-time 4 https://api64.ipify.org 2>/dev/null || true)
    [[ -n "$v4" ]] && echo "$v4"
    [[ -n "$v6" ]] && echo "$v6"
}

# 校验域名是否解析到本机公网 IP
# 返回 0 = 通过（匹配，或用户选择强制继续）；1 = 用户取消
camouflage::_verify_domain_dns() {
    local domain="$1"
    log::step "校验域名解析: $domain"

    local resolved my_ips matched=0
    # getent ahosts 一次返回 v4+v6 解析结果
    resolved=$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u)
    my_ips=$(camouflage::_my_public_ips)

    if [[ -z "$resolved" ]]; then
        log::warn "无法解析 $domain（DNS 故障或域名未生效）"
        ui::confirm "是否仍然继续? (用于内网测试 / DNS 未生效场景)"
        return $?
    fi
    if [[ -z "$my_ips" ]]; then
        log::warn "获取本机公网 IP 失败（网络异常或防火墙拦截 ipify）"
        log::info "解析到的 IP:"; echo "$resolved" | sed 's/^/    /'
        ui::confirm "无法验证，是否仍然继续?"
        return $?
    fi

    # 任一交集即视为匹配
    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        if echo "$resolved" | grep -qx "$ip"; then
            matched=1
            break
        fi
    done <<< "$my_ips"

    if [[ $matched -eq 1 ]]; then
        log::info "域名解析正确 ✓"
        return 0
    fi

    log::warn "域名 $domain 未解析到本机公网 IP"
    log::info "  本机公网 IP:"; echo "$my_ips"  | sed 's/^/    /'
    log::info "  域名解析到:";   echo "$resolved" | sed 's/^/    /'
    log::info "  CDN / 反代后端场景下解析必然不一致，可强制继续"
    ui::confirm "是否仍然继续?"
}

# 写出 cert-sync 脚本 + systemd timer。幂等。
# 不依赖 caddy events 模块（官方包不带 exec handler，那是第三方插件）。
# 改用 systemd timer 每天扫描 caddy 证书目录 → 同步到 SB_CERT_DIR
camouflage::install_cert_hook() {
    log::step "安装证书同步脚本与 systemd timer..."

    mkdir -p "$SB_CERT_DIR"
    chmod 0755 "$SB_CERT_DIR"

    cat > "$CERT_SYNC_SCRIPT" <<'SYNC_EOF'
#!/bin/bash
# sm-cert-sync.sh - 扫 caddy 证书目录，同步所有 .crt/.key 到 /etc/sing-box/certs
# 维护 active.{crt,key} 软链接（指向 .active-domain 文件里记录的域名）
set -uo pipefail

DEST="/etc/sing-box/certs"
ACTIVE_FILE="$DEST/.active-domain"
CADDY_DATA="${XDG_DATA_HOME:-/var/lib/caddy/.local/share}/caddy"
CERT_ROOT="$CADDY_DATA/certificates"

mkdir -p "$DEST"
[[ -d "$CERT_ROOT" ]] || { echo "[cert-sync] caddy 证书目录不存在: $CERT_ROOT" >&2; exit 0; }

# 遍历 CA 子目录下的所有域名子目录，复制 .crt/.key
# 用 cp -u（仅当 src 比 dest 新才复制）避免无谓 mtime 触动，
# 防止 sing-box 误以为证书变化而重载
shopt -s nullglob
synced=0
for ca_dir in "$CERT_ROOT"/*/; do
    for d in "$ca_dir"*/; do
        domain=$(basename "$d")
        crt="$d$domain.crt"
        key="$d$domain.key"
        [[ -s "$crt" && -s "$key" ]] || continue
        cp -u "$crt" "$DEST/$domain.crt"
        cp -u "$key" "$DEST/$domain.key"
        chmod 0644 "$DEST/$domain.crt"
        chmod 0640 "$DEST/$domain.key"
        synced=$((synced + 1))
    done
done

[[ $synced -eq 0 ]] && { echo "[cert-sync] 无证书可同步（caddy 还没拿到任何证书）" >&2; exit 0; }

# 维护 active 软链接：以 .active-domain 文件里记录的域名为准
# 若文件不存在，挑一个已同步的域名作为 active（首次部署兜底）
ACTIVE_DOMAIN=""
[[ -f "$ACTIVE_FILE" ]] && ACTIVE_DOMAIN="$(cat "$ACTIVE_FILE" 2>/dev/null || true)"
if [[ -z "$ACTIVE_DOMAIN" || ! -f "$DEST/$ACTIVE_DOMAIN.crt" ]]; then
    ACTIVE_DOMAIN=$(ls "$DEST"/*.crt 2>/dev/null | grep -v '/active.crt$' | head -n1 | xargs -r basename | sed 's/\.crt$//')
    [[ -n "$ACTIVE_DOMAIN" ]] && echo "$ACTIVE_DOMAIN" > "$ACTIVE_FILE"
fi
if [[ -n "$ACTIVE_DOMAIN" && -f "$DEST/$ACTIVE_DOMAIN.crt" ]]; then
    ln -sfn "$ACTIVE_DOMAIN.crt" "$DEST/active.crt"
    ln -sfn "$ACTIVE_DOMAIN.key" "$DEST/active.key"
fi
echo "[cert-sync] synced=$synced active=$ACTIVE_DOMAIN"
SYNC_EOF
    chmod +x "$CERT_SYNC_SCRIPT"

    # systemd service：单次 oneshot 跑同步脚本
    cat > "$CERT_SYNC_SERVICE" <<EOF
[Unit]
Description=sm cert sync (Caddy -> sing-box)

[Service]
Type=oneshot
ExecStart=${CERT_SYNC_SCRIPT}
EOF

    # systemd timer：开机后 2 分钟跑一次，之后每天跑一次
    # （Caddy 续签 60 天频率，旧证书还有 30 天，每天扫一次足够；
    # cp -u 跳过未变化的文件，无谓重载也已避免）
    cat > "$CERT_SYNC_TIMER" <<EOF
[Unit]
Description=sm cert sync timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=1d
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now sm-cert-sync.timer >/dev/null 2>&1
    log::info "证书同步 timer 已启用 (每日扫描一次)"

    # 自动 import sites.d
    mkdir -p "$CADDY_SITES_DIR"
    chown root:caddy "$CADDY_SITES_DIR" 2>/dev/null || true
    chmod 0755 "$CADDY_SITES_DIR" 2>/dev/null || true
    if [[ -f "$CADDY_MAIN_CONF" ]] && ! grep -q "import ${CADDY_SITES_DIR}/" "$CADDY_MAIN_CONF" 2>/dev/null; then
        echo "" >> "$CADDY_MAIN_CONF"
        echo "import ${CADDY_SITES_DIR}/*.caddy" >> "$CADDY_MAIN_CONF"
        camouflage::_fix_caddy_perms "$CADDY_MAIN_CONF"
    fi
}

# 立即跑一次同步（伪装部署完毕、Caddy 启动并拿到首张证书后调用）
camouflage::run_cert_sync_now() {
    [[ -x "$CERT_SYNC_SCRIPT" ]] || return 0
    "$CERT_SYNC_SCRIPT" 2>&1 | sed 's/^/  /' || true
}

# 等待 Caddy 申请到指定域名的证书（默认最多 60 秒），然后立即触发一次同步
# Caddy reload 后异步申请证书，通常 5-30 秒到位；超时仍未到位也不报错（依赖每日 timer 兜底）
camouflage::wait_and_sync_cert() {
    local domain="$1" timeout="${2:-60}"
    local cert_root="${XDG_DATA_HOME:-/var/lib/caddy/.local/share}/caddy/certificates"
    local i=0 found=""

    log::step "等待 Caddy 申请 ${domain} 证书 (最多 ${timeout} 秒)..."
    while (( i < timeout )); do
        found=$(find "$cert_root" -type f -name "${domain}.crt" 2>/dev/null | head -n1)
        if [[ -n "$found" && -s "$found" ]]; then
            log::info "Caddy 已拿到证书"
            camouflage::run_cert_sync_now
            return 0
        fi
        sleep 2
        i=$((i + 2))
    done
    log::warn "在 ${timeout} 秒内未检测到证书，将依赖每日 timer 自动同步"
    log::info "如已确认 Caddy 申请成功，可手动: systemctl start sm-cert-sync.service"
    return 1
}

# 抓取首次启动 (config.json 不存在时) 打印的初始管理员密码
# 已设置过密码的容器抓不到（容器看到 config 直接读取，不再打印）
camouflage::wait_openlist_password() {
    local container="${1:-openlist}"
    local timeout="${2:-30}"
    local pattern="initial password is:"
    local i=0 line=""

    while (( i < timeout )); do
        line=$(docker logs "$container" 2>&1 | grep -m1 "$pattern" || true)
        [[ -n "$line" ]] && break
        sleep 1
        i=$((i + 1))
    done

    if [[ -z "$line" ]]; then
        return 1
    fi
    # "... initial password is: PWD" -> PWD
    echo "${line##*initial password is: }"
}

# camouflage::_write_site DOMAIN BODY
camouflage::_write_site() {
    local domain="$1" body="$2"
    mkdir -p "$CADDY_SITES_DIR"
    cat > "$CADDY_SITES_DIR/${domain}.caddy" <<EOF
${domain} {
${body}
}
EOF
    camouflage::_fix_caddy_perms "$CADDY_SITES_DIR/${domain}.caddy"
}

camouflage::install_static() {
    camouflage::ensure_caddy || return 1

    local domain
    camouflage::_ask_domain domain "请输入指向本机的域名 (用于静态伪装): "

    log::step "下载静态伪装站点 (html5up Massively)..."
    mkdir -p "$CAMOUFLAGE_WEB_ROOT"
    local tmp_zip="$TMP_DIR/massively.zip"
    mkdir -p "$TMP_DIR"
    if ! net::download "$STATIC_SITE_URL" "$tmp_zip"; then
        log::err "静态站点下载失败"
        return 1
    fi
    if ! sys::has_cmd unzip; then
        pkg::install_quiet unzip || { log::err "unzip 安装失败"; return 1; }
    fi
    if ! unzip -oq "$tmp_zip" -d "$CAMOUFLAGE_WEB_ROOT"; then
        log::err "静态站点解压失败"
        return 1
    fi
    chown -R caddy:caddy "$CAMOUFLAGE_WEB_ROOT" 2>/dev/null || true
    log::info "静态站点已部署到 $CAMOUFLAGE_WEB_ROOT"

    camouflage::install_cert_hook

    camouflage::_write_site "$domain" "    root * ${CAMOUFLAGE_WEB_ROOT}
    encode gzip
    file_server
    log {
        output discard
    }"
    log::info "Caddy 站点配置已写入: $CADDY_SITES_DIR/${domain}.caddy"

    log::step "重载 Caddy..."
    if svc::is_active caddy; then
        systemctl reload caddy && log::info "Caddy 已重载"
    else
        svc::ensure_running caddy "Caddy 已启动"
    fi

    camouflage::bind_active_domain "$domain"

    echo
    log::info "✅ 静态伪装就绪: https://${domain}"
    log::info "   AnyTLS 活动域名: $(camouflage::read_active_domain)"
    camouflage::wait_and_sync_cert "$domain"
}

camouflage::install_openlist() {
    camouflage::ensure_caddy || return 1
    camouflage::ensure_docker || return 1

    local domain
    camouflage::_ask_domain domain "请输入指向本机的域名 (用于 OpenList): "

    log::step "准备 OpenList 部署目录..."
    mkdir -p "$OPENLIST_DIR/data"

    cat > "$OPENLIST_DIR/docker-compose.yml" <<EOF
services:
  openlist:
    image: openlistteam/openlist:latest
    container_name: openlist
    user: "0:0"
    volumes:
      - ${OPENLIST_DIR}/data:/opt/openlist/data
    ports:
      - 127.0.0.1:5244:5244
    environment:
      - UMASK=022
    labels:
      - com.centurylinklabs.watchtower.enable=true
    restart: unless-stopped

  watchtower:
    image: nickfedor/watchtower:latest
    container_name: openlist-watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_LABEL_ENABLE=true
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_SCHEDULE=0 0 4 1 * *
    restart: unless-stopped
EOF

    log::step "拉起 OpenList..."
    (cd "$OPENLIST_DIR" && docker compose up -d) || {
        log::err "docker compose 启动失败"; return 1; }

    camouflage::install_cert_hook

    camouflage::_write_site "$domain" "    encode gzip
    reverse_proxy 127.0.0.1:5244
    log {
        output discard
    }"
    log::info "Caddy 站点配置已写入: $CADDY_SITES_DIR/${domain}.caddy"

    log::step "重载 Caddy..."
    if svc::is_active caddy; then
        systemctl reload caddy && log::info "Caddy 已重载"
    else
        svc::ensure_running caddy "Caddy 已启动"
    fi

    camouflage::bind_active_domain "$domain"

    echo
    log::info "✅ OpenList 伪装就绪: https://${domain}"
    log::info "   OpenList 数据: ${OPENLIST_DIR}/data"
    log::info "   AnyTLS 活动域名: $(camouflage::read_active_domain)"
    camouflage::wait_and_sync_cert "$domain"

    # 抓取首次启动时打印的初始密码（已设置过密码的容器抓不到，正常）
    log::step "等待 OpenList 初始化输出默认密码 (最多 30 秒)..."
    local pwd
    if pwd=$(camouflage::wait_openlist_password openlist 30); then
        echo
        echo -e "  ${GREEN}━━━ OpenList 初始管理员凭证 ━━━${PLAIN}"
        echo -e "  地址  : ${BLUE}https://${domain}${PLAIN}"
        echo -e "  用户名: ${BLUE}admin${PLAIN}"
        echo -e "  密码  : ${YELLOW}${pwd}${PLAIN}"
        echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
        log::warn "请尽快登录 https://${domain} 修改默认密码"
    else
        log::warn "30 秒内未抓到默认密码"
        log::info "可能原因：容器初始化较慢，或 ${OPENLIST_DIR}/data 已存在数据（密码已修改过）"
        log::info "可手动查看完整日志: docker logs openlist | grep -i password"
    fi
}

camouflage::status_text() {
    local has_static=0 has_openlist=0
    [[ -d "$CAMOUFLAGE_WEB_ROOT" ]] && has_static=1
    [[ -f "$OPENLIST_DIR/docker-compose.yml" ]] && has_openlist=1
    if [[ $has_static -eq 0 && $has_openlist -eq 0 ]]; then
        echo -e "${YELLOW}未部署${PLAIN}"
    else
        local parts=()
        [[ $has_static   -eq 1 ]] && parts+=("静态")
        [[ $has_openlist -eq 1 ]] && parts+=("OpenList")
        local active
        active="$(camouflage::read_active_domain)"
        if [[ -n "$active" ]]; then
            echo -e "${GREEN}已部署: ${parts[*]}${PLAIN} | active: ${BLUE}${active}${PLAIN}"
        else
            echo -e "${GREEN}已部署: ${parts[*]}${PLAIN}"
        fi
    fi
}

# 列出已同步的所有证书域名
camouflage::list_synced_domains() {
    local f
    for f in "$SB_CERT_DIR"/*.crt; do
        [[ -e "$f" ]] || continue
        local name
        name="$(basename "$f" .crt)"
        [[ "$name" == "active" ]] && continue
        echo "$name"
    done
}

# 交互切换 active 域名
camouflage::switch_active() {
    log::info "AnyTLS 活动域名决定 ${SB_CERT_DIR}/active.{crt,key} 软链接指向哪个证书。"
    local current
    current="$(camouflage::read_active_domain)"
    [[ -n "$current" ]] && log::info "当前 active: ${current}" || log::warn "尚未设置 active 域名"

    local domains=()
    while IFS= read -r d; do
        [[ -n "$d" ]] && domains+=("$d")
    done < <(camouflage::list_synced_domains)

    if [[ ${#domains[@]} -eq 0 ]]; then
        log::err "尚未同步任何证书。请先访问伪装域名（让 Caddy 申请证书）。"
        return 1
    fi

    echo
    echo "已同步证书的域名："
    local i=1
    for d in "${domains[@]}"; do
        if [[ "$d" == "$current" ]]; then
            echo -e "  ${GREEN}${i}.${PLAIN} ${d}  ${GREEN}(当前 active)${PLAIN}"
        else
            echo -e "  ${GREEN}${i}.${PLAIN} ${d}"
        fi
        i=$((i + 1))
    done
    echo

    local choice
    ui::prompt "请选择新的 active 域名编号 (0 取消): " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" == "0" ]]; then
        log::info "已取消"
        return
    fi
    if (( choice < 1 || choice > ${#domains[@]} )); then
        log::err "无效编号"
        return 1
    fi
    camouflage::set_active_domain "${domains[$((choice - 1))]}"
}

camouflage::uninstall() {
    log::warn "即将清理伪装相关资源（站点文件、OpenList 容器、Caddy 站点配置、证书同步钩子）"
    ui::confirm "确认?" || { log::info "取消"; return; }

    # OpenList
    if [[ -f "$OPENLIST_DIR/docker-compose.yml" ]]; then
        log::step "停止 OpenList..."
        (cd "$OPENLIST_DIR" && docker compose down) 2>/dev/null || true
        if ui::confirm "是否删除 OpenList 数据目录 $OPENLIST_DIR ?"; then
            rm -rf "$OPENLIST_DIR"
            log::info "OpenList 目录已删除"
        fi
    fi

    # 静态站点
    [[ -d "$CAMOUFLAGE_WEB_ROOT" ]] && rm -rf "$CAMOUFLAGE_WEB_ROOT" && log::info "静态站点目录已删除"

    # Caddy sites
    if [[ -d "$CADDY_SITES_DIR" ]]; then
        rm -f "$CADDY_SITES_DIR"/*.caddy
        log::info "Caddy 站点配置已清理"
        svc::is_active caddy && systemctl reload caddy 2>/dev/null
    fi

    rm -f "$CERT_SYNC_SCRIPT"
    log::info "证书同步脚本已删除"

    systemctl disable --now sm-cert-sync.timer >/dev/null 2>&1 || true
    rm -f "$CERT_SYNC_TIMER" "$CERT_SYNC_SERVICE"
    systemctl daemon-reload
    log::info "证书同步 timer/service 已清理"

    rm -f "$ACTIVE_DOMAIN_FILE"
    log::warn "证书目录 $SB_CERT_DIR 已保留 (sing-box 仍在使用)。如需清理请手动 rm -rf"

    log::info "伪装功能已卸载"
}

# >>> src/modules/docker.sh
# ==============================================================================
# docker:: Docker CE + Compose
# ==============================================================================

docker::is_installed() { sys::has_cmd docker; }

docker::install() {
    log::info "准备安装 Docker CE + Compose 插件..."

    if sys::has_cmd docker; then
        log::warn "检测到已安装: $(docker --version 2>/dev/null)"
        ui::confirm "是否继续 (将走 apt 升级流程)?" || { log::info "已取消。"; return; }
    fi

    local distro_id distro_codename
    distro_id="$(sys::distro_id)"
    distro_codename="$(sys::distro_codename)"
    case "$distro_id" in
        ubuntu|debian) ;;
        *) distro_id="debian" ;;
    esac
    if [[ -z "$distro_codename" ]]; then
        log::err "无法读取系统代号 (VERSION_CODENAME)，安装中止。"
        return
    fi

    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg

    install -m 0755 -d /etc/apt/keyrings
    if ! pkg::add_gpg_key \
            "https://download.docker.com/linux/${distro_id}/gpg" \
            "/etc/apt/keyrings/docker.asc"; then
        log::err "Docker GPG 密钥下载失败。"
        return
    fi

    pkg::write_repo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${distro_id} ${distro_codename} stable" \
        /etc/apt/sources.list.d/docker.list

    pkg::update || { log::err "apt-get update 失败。"; return; }
    if pkg::install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        if svc::ensure_running docker "Docker 安装成功: $(docker --version 2>/dev/null)"; then
            log::info "Compose: $(docker compose version 2>/dev/null | head -n1)"
            log::info "如需非 root 用户使用 docker，请执行: usermod -aG docker <user> 后重新登录。"
        fi
    else
        log::err "Docker 安装失败，请检查网络或源是否可用。"
    fi
}

# /var/lib/docker 与 /var/lib/containerd 含镜像/卷/容器数据，单独二次确认
docker::uninstall() {
    if ! docker::is_installed; then
        log::warn "Docker 未安装"
        return
    fi
    log::warn "即将卸载 Docker CE / Compose / containerd 及其软件源、密钥"
    ui::confirm "确认卸载?" || { log::info "取消卸载"; return; }

    log::step "正在停止服务..."
    svc::stop docker
    svc::stop containerd
    svc::disable docker
    svc::disable containerd

    log::step "正在卸载软件包..."
    pkg::purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras

    log::step "正在清理软件源、密钥与配置..."
    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg
    rm -rf /etc/docker

    # 数据目录单独二次确认（默认保留）
    local need_confirm=0
    [[ -d /var/lib/docker || -d /var/lib/containerd ]] && need_confirm=1
    if [[ $need_confirm -eq 1 ]]; then
        echo
        log::warn "⚠️  /var/lib/docker 与 /var/lib/containerd 内含所有镜像、卷、容器数据"
        log::warn "    这些数据通常占用数 GB 至数十 GB，删除后无法恢复"
        if ui::confirm "是否一并清空 Docker 数据目录? (默认 N，强烈建议先备份重要卷)"; then
            rm -rf /var/lib/docker /var/lib/containerd
            log::info "Docker 数据目录已清空"
        else
            log::info "已保留 /var/lib/docker 与 /var/lib/containerd"
        fi
    fi

    pkg::autoremove >/dev/null 2>&1
    log::info "Docker 已卸载"
}

# >>> src/modules/sb.sh
# ==============================================================================
# sb:: Sing-box 业务模块
# ==============================================================================

sb::status() {
    if svc::is_active sing-box; then
        echo -e "${GREEN}运行中${PLAIN}"
    elif sys::has_cmd sing-box; then
        echo -e "${RED}已停止${PLAIN}"
    else
        echo -e "${YELLOW}未安装${PLAIN}"
    fi
}

sb::version() {
    if sys::has_cmd sing-box; then
        sing-box version 2>/dev/null | head -n 1 | awk '{print $3}'
    else
        echo "N/A"
    fi
}

sb::install() {
    log::info "准备安装/更新 Sing-box..."

    mkdir -p /etc/apt/keyrings
    pkg::add_gpg_key "https://sing-box.app/gpg.key" "/etc/apt/keyrings/sagernet.asc" || {
        log::err "Sing-box GPG 密钥下载失败。"; return 1; }

    pkg::write_repo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/sagernet.asc] https://deb.sagernet.org/ * *" \
        /etc/apt/sources.list.d/sagernet.list

    pkg::update quiet
    if pkg::install sing-box; then
        svc::ensure_running sing-box "Sing-box 安装成功并已启动！"
    else
        log::err "安装失败，请检查网络连接。"
    fi
}

sb::uninstall() {
    log::info "正在停止服务..."
    svc::stop sing-box
    svc::disable sing-box

    log::info "正在清理软件包..."
    pkg::purge sing-box

    log::info "正在清理配置文件..."
    rm -rf /etc/sing-box
    rm -f /etc/apt/sources.list.d/sagernet.list
    rm -f /etc/apt/keyrings/sagernet.asc

    log::info "Sing-box 及其配置已彻底移除。"
}

sb::apply_config() {
    local url="${1:-$DEFAULT_CONFIG_URL}"
    mkdir -p "$TMP_DIR"
    local tmp_conf="$TMP_DIR/config.json"

    log::info "正在下载配置: $url"
    if ! net::download "$url" "$tmp_conf"; then
        log::err "下载失败，请检查 URL 是否正确或网络是否畅通。"
        return 1
    fi
    if [[ ! -s "$tmp_conf" ]] || ! jq -e . "$tmp_conf" >/dev/null 2>&1; then
        log::err "下载的文件不是有效的 JSON 格式或内容为空，操作已取消。"
        return 1
    fi
    mkdir -p /etc/sing-box
    mv "$tmp_conf" /etc/sing-box/config.json
    log::info "配置文件验证通过并已应用。"
    if ui::confirm "是否重启 Sing-box 服务?"; then
        svc::restart sing-box && log::info "服务已重启。"
    fi
}

sb::set_default_url() {
    local new_url
    ui::prompt "请输入新的默认配置下载链接: " new_url -e
    if [[ -z "$new_url" ]]; then
        log::warn "链接为空，未修改。"
        return
    fi
    self::persist_var "DEFAULT_CONFIG_URL" "$new_url"
    DEFAULT_CONFIG_URL="$new_url"
    log::info "默认链接已更新。"
}

# >>> src/modules/system.sh
# ==============================================================================
# system:: 系统级操作（升级 / 内核）
# ==============================================================================

system::full_upgrade() {
    log::info "准备执行系统全量升级 (full-upgrade)..."
    log::warn "该操作会升级内核及所有依赖发生变化的软件包，建议升级后重启。"
    ui::confirm "确认继续?" || { log::info "已取消。"; return; }

    local apt_opts=(-o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef)

    log::step "[1/3] 更新软件源索引..."
    pkg::update || { log::err "apt-get update 失败，请检查软件源。"; return; }

    log::step "[2/3] 执行 full-upgrade (包含内核升级)..."
    if ! pkg::full_upgrade "${apt_opts[@]}"; then
        log::err "full-upgrade 执行失败。"
        return
    fi

    log::step "[3/3] 清理无用依赖..."
    pkg::autoremove "${apt_opts[@]}"
    pkg::clean

    sys::reboot_if_needed
}

# >>> src/modules/tcp.sh
# ==============================================================================
# tcp:: TCP 网络优化（运行外部脚本）
# ==============================================================================

tcp::run() {
    mkdir -p "$TMP_DIR"
    local tcp_local="$TMP_DIR/install_tcp.sh"

    log::info "正在下载 TCP 优化脚本..."
    if net::download "$TCPX_URL" "$tcp_local"; then
        chmod +x "$tcp_local"
        bash "$tcp_local"
    else
        log::err "TCP 脚本下载失败。"
    fi
}

# >>> src/modules/ufw.sh
# ==============================================================================
# ufw:: UFW 防火墙业务模块
# ==============================================================================

ufw::is_installed() { sys::has_cmd ufw; }

# 加 timeout 防止 ufw status numbered 在某些 nf_tables 状态下卡死
# 5 秒还没返回就放弃，避免脚本整个 hang 住
ufw::_status_numbered() {
    timeout 5 ufw status numbered 2>/dev/null
}

ufw::is_enabled() {
    sys::has_cmd ufw && LC_ALL=C timeout 5 ufw status verbose 2>/dev/null | head -n1 | grep -q "Status: active"
}

ufw::status_text() {
    if ! ufw::is_installed; then
        echo -e "${RED}未安装${PLAIN}"
    elif ufw::is_enabled; then
        echo -e "${GREEN}已启用${PLAIN}"
    else
        echo -e "${YELLOW}未启用${PLAIN}"
    fi
}

ufw::_require() {
    if ! ufw::is_installed; then
        log::err "UFW 未安装，请先安装 UFW"
        return 1
    fi
}

ufw::install() {
    if ufw::is_installed; then
        log::warn "UFW 已经安装，正在检查更新..."
        pkg::update quiet
        if apt list --upgradable 2>/dev/null | grep -q "^ufw/"; then
            log::info "发现 UFW 更新"
            if ui::confirm "是否更新 UFW?"; then
                pkg::install_quiet ufw && log::info "UFW 更新完成"
            else
                log::info "跳过更新"
            fi
        else
            log::info "UFW 已是最新版本"
        fi
        return
    fi

    log::info "正在安装 UFW..."
    pkg::update quiet
    if ! pkg::install_quiet ufw; then
        log::err "UFW 安装失败"
        return 1
    fi

    log::info "UFW 安装成功"
    log::warn "自动放行常用端口以防止服务中断 (IPv4/IPv6 双栈)"
    ufw::allow 22 tcp "SSH TCP"
    ufw::allow 22 udp "SSH UDP"
    ufw::allow 80 tcp "HTTP TCP"
    ufw::allow 80 udp "HTTP UDP"
    ufw::allow 443 tcp "HTTPS TCP"
    ufw::allow 443 udp "HTTPS UDP"

    log::step "正在启用 UFW..."
    if echo "y" | ufw enable >/dev/null 2>&1; then
        log::info "UFW 已自动启用"
    else
        log::err "UFW 启用失败"
    fi
}

ufw::enable() {
    ufw::_require || return
    if echo "y" | ufw enable >/dev/null 2>&1; then
        log::info "UFW 已启用"
    else
        log::err "UFW 启用失败"
    fi
}

ufw::disable() {
    ufw::_require || return
    if ufw disable >/dev/null 2>&1; then
        log::info "UFW 已禁用"
    else
        log::err "UFW 禁用失败"
    fi
}

ufw::reload() {
    ufw::_require || return
    if ufw reload >/dev/null 2>&1; then
        log::info "UFW 已重启"
    else
        log::err "UFW 重启失败"
    fi
}

ufw::uninstall() {
    if ! ufw::is_installed; then
        log::warn "UFW 未安装"
        return
    fi
    log::warn "即将卸载 UFW 及其所有配置"
    ui::confirm "确认卸载?" || { log::info "取消卸载"; return; }

    log::step "正在卸载 UFW..."
    ufw disable >/dev/null 2>&1
    pkg::purge ufw >/dev/null 2>&1
    pkg::autoremove >/dev/null 2>&1
    rm -rf /etc/ufw /lib/ufw /var/lib/ufw
    log::info "UFW 已完全卸载"
}

# ufw::allow PORT PROTO [COMMENT]
ufw::allow() {
    local port="$1" proto="$2" comment="${3:-Port ${1}/${2}}"
    if ufw allow "${port}/${proto}" comment "$comment" >/dev/null 2>&1; then
        log::info "已放行 ${port}/${proto} (IPv4/IPv6)"
    else
        log::err "添加规则失败: ${port}/${proto}"
        return 1
    fi
}

ufw::list_numbered() {
    ufw::_require || return
    ufw::_status_numbered
}

# 交互式添加：解析输入 + 询问是否同时放行另一协议
ufw::add_rule_interactive() {
    ufw::_require || return
    log::info "添加 UFW 规则 (示例: 2222/tcp 或 8080/udp)"
    log::info "规则会自动应用于 IPv4 和 IPv6 双栈"
    local input
    ui::prompt "请输入端口/协议 (如 2222/tcp): " input

    if [[ ! "$input" =~ ^([0-9]+)/(tcp|udp)$ ]]; then
        log::err "格式错误，请使用 端口/协议 格式"
        return 1
    fi
    local port="${BASH_REMATCH[1]}"
    local proto="${BASH_REMATCH[2]}"
    local other="udp"
    [[ "$proto" == "udp" ]] && other="tcp"

    ufw::allow "$port" "$proto"
    if ui::confirm "是否同时放行 ${port}/${other}?"; then
        ufw::allow "$port" "$other"
    fi
}

# 交互式删除：按编号选择，自动匹配同端口的所有规则（v4+v6）
ufw::delete_rule_interactive() {
    ufw::_require || return
    log::info "当前防火墙规则："
    ufw::_status_numbered

    if ! ufw::_status_numbered | grep -q "^\["; then
        log::warn "当前没有任何规则"
        return
    fi

    log::warn "UFW 会为每个端口自动创建 IPv4 和 IPv6 规则"
    log::warn "选择任意一条，脚本将智能删除该端口的所有相关规则"
    local rule_num
    ui::prompt "请输入要删除的规则编号 (0 取消): " rule_num
    if [[ ! "$rule_num" =~ ^[0-9]+$ ]] || [[ "$rule_num" == "0" ]]; then
        log::warn "取消删除"
        return
    fi

    local rules_raw rule_info
    rules_raw=$(ufw::_status_numbered)
    rule_info=$(echo "$rules_raw" | grep "^\[ *$rule_num\]" | sed 's/\x1b\[[0-9;]*m//g')
    if [[ -z "$rule_info" ]]; then
        log::err "无效的规则编号"
        return 1
    fi
    log::info "已选择规则: $rule_info"

    local target_def port proto other
    target_def=$(echo "$rule_info" | awk '{print $2}')
    port=$(echo "$target_def" | cut -d'/' -f1)
    proto=$(echo "$target_def" | cut -d'/' -f2)
    if [[ -z "$port" || -z "$proto" || "$port" == "$target_def" ]]; then
        log::err "无法解析规则信息，该规则可能不是标准的 端口/协议 格式"
        return 1
    fi
    other="udp"
    [[ "$proto" == "udp" ]] && other="tcp"

    local delete_other="n"
    if echo "$rules_raw" | grep -q "${port}/${other}"; then
        if ui::confirm "检测到 ${port}/${other} 规则，是否一并删除?"; then
            delete_other="y"
        fi
    fi

    local rules_to_delete=()
    log::step "正在查找所有相关规则..."
    while IFS= read -r line; do
        if echo "$line" | grep -q -w "${port}/${proto}"; then
            local num
            num=$(echo "$line" | sed 's/^\[ *\([0-9]\+\)\].*/\1/')
            [[ -n "$num" ]] && rules_to_delete+=("$num")
        fi
    done < <(echo "$rules_raw" | grep "^\[")

    if [[ "$delete_other" == "y" ]]; then
        while IFS= read -r line; do
            if echo "$line" | grep -q -w "${port}/${other}"; then
                local num
                num=$(echo "$line" | sed 's/^\[ *\([0-9]\+\)\].*/\1/')
                [[ -n "$num" ]] && rules_to_delete+=("$num")
            fi
        done < <(echo "$rules_raw" | grep "^\[")
    fi

    # 倒序去重，避免删除时编号偏移
    IFS=$'\n' read -r -d '' -a rules_to_delete < <(printf '%s\n' "${rules_to_delete[@]}" | sort -rn -u && printf '\0')

    if [[ ${#rules_to_delete[@]} -eq 0 ]]; then
        log::err "未找到匹配的规则"
        return 1
    fi

    log::warn "总共将删除 ${#rules_to_delete[@]} 条规则 (编号: ${rules_to_delete[*]})"
    ui::confirm "确认删除?" || { log::warn "取消删除"; return; }

    log::step "正在删除规则..."
    local num
    for num in "${rules_to_delete[@]}"; do
        if echo "y" | ufw delete "$num" >/dev/null 2>&1; then
            log::info "已删除规则 $num"
        else
            log::err "删除规则 $num 失败"
        fi
    done
    log::info "更新后的规则列表："
    ufw::_status_numbered
}

# >>> src/menu/camouflage.sh
# ==============================================================================
# menu::camouflage - 伪装站点子菜单
# ==============================================================================

menu::camouflage() {
    while true; do
        ui::header "安装伪装"
        echo -e " 当前状态: $(camouflage::status_text)"
        echo
        echo -e "  ${GREEN}1.${PLAIN} 安装静态伪装 (Caddy + html5up)"
        echo -e "  ${GREEN}2.${PLAIN} 安装 OpenList 伪装 (Docker + Caddy 反代)"
        echo -e "  ${GREEN}3.${PLAIN} 切换 AnyTLS 活动证书域名"
        echo -e "  ${GREEN}4.${PLAIN} 卸载伪装"
        echo -e "  ${GREEN}0.${PLAIN} 返回主菜单"
        echo
        echo -e " ${BLUE}提示${PLAIN}: AnyTLS 服务端配置统一指向 ${SB_CERT_DIR}/active.{crt,key}"
        echo -e "       Caddy 给任何域名续签证书都会自动同步到此目录"
        echo -e "       但只有 ${BLUE}活动域名${PLAIN} 决定 active.* 指向哪一张证书"
        echo -e "       (这意味着你以后可以放心给 Caddy 加任意反代/站点)"
        echo
        local opt
        ui::prompt " 请选择: " opt
        case "$opt" in
            1) camouflage::install_static ;;
            2) camouflage::install_openlist ;;
            3) camouflage::switch_active ;;
            4) camouflage::uninstall ;;
            0) return ;;
            *) log::err "无效选项" ;;
        esac
        [[ "$opt" != "0" ]] && ui::pause
    done
}

# >>> src/menu/common_software.sh
# ==============================================================================
# menu::common_software - 常用软件安装子菜单
# ==============================================================================

menu::common_software() {
    while true; do
        ui::header "常用软件安装 / 卸载"
        echo
        echo -e "  ${GREEN}1.${PLAIN} 安装 Caddy Web 服务器"
        echo -e "  ${GREEN}2.${PLAIN} 安装 Docker CE + Compose 插件"
        echo -e "  ${GREEN}3.${PLAIN} 一键安装 (Caddy + Docker)"
        ui::divider
        echo -e "  ${GREEN}4.${PLAIN} 卸载 Caddy"
        echo -e "  ${GREEN}5.${PLAIN} 卸载 Docker"
        echo -e "  ${GREEN}0.${PLAIN} 返回主菜单"
        echo
        local opt
        ui::prompt " 请选择: " opt
        case "$opt" in
            1) caddy::install ;;
            2) docker::install ;;
            3) caddy::install; docker::install ;;
            4) caddy::uninstall ;;
            5) docker::uninstall ;;
            0) return ;;
            *) log::err "无效选项" ;;
        esac
        [[ "$opt" != "0" ]] && ui::pause
    done
}

# >>> src/menu/sb_service.sh
# ==============================================================================
# menu::sb_service - Sing-box 服务管理子菜单
# ==============================================================================

menu::sb_service() {
    while true; do
        ui::header "Sing-box 服务管理"
        echo -e " 当前状态: $(sb::status)"
        echo
        echo -e "  ${GREEN}1.${PLAIN} 启动服务"
        echo -e "  ${GREEN}2.${PLAIN} 停止服务"
        echo -e "  ${GREEN}3.${PLAIN} 重启服务"
        echo -e "  ${GREEN}4.${PLAIN} 查看实时日志 (Ctrl+C 退出整个脚本)"
        echo -e "  ${GREEN}5.${PLAIN} 卸载 Sing-box"
        echo -e "  ${GREEN}0.${PLAIN} 返回主菜单"
        echo
        local opt
        ui::prompt " 请选择: " opt
        case "$opt" in
            1) svc::start sing-box && log::info "已启动" ;;
            2) svc::stop sing-box && log::info "已停止" ;;
            3) svc::restart sing-box && log::info "已重启" ;;
            4) svc::logs sing-box ;;
            5) ui::confirm "确定要彻底卸载 Sing-box 吗?" && sb::uninstall ;;
            0) return ;;
            *) log::err "无效选项" ;;
        esac
        [[ "$opt" != "4" && "$opt" != "0" ]] && ui::pause
    done
}

# >>> src/menu/ufw.sh
# ==============================================================================
# menu::ufw - UFW 顶层菜单及子菜单
# ==============================================================================

menu::ufw_manage() {
    while true; do
        ui::header "UFW 防火墙管理"
        echo -e " 当前状态: $(ufw::status_text)"
        echo
        echo -e "  ${GREEN}1.${PLAIN} 安装 UFW"
        echo -e "  ${GREEN}2.${PLAIN} 启用 UFW"
        echo -e "  ${GREEN}3.${PLAIN} 禁用 UFW"
        echo -e "  ${GREEN}4.${PLAIN} 重启 UFW"
        echo -e "  ${GREEN}5.${PLAIN} 卸载 UFW"
        echo -e "  ${GREEN}0.${PLAIN} 返回上级菜单"
        echo
        local opt
        ui::prompt " 请选择: " opt
        case "$opt" in
            1) ufw::install ;;
            2) ufw::enable ;;
            3) ufw::disable ;;
            4) ufw::reload ;;
            5) ufw::uninstall ;;
            0) return ;;
            *) log::err "无效选项" ;;
        esac
        [[ "$opt" != "0" ]] && ui::pause
    done
}

menu::ufw_rules() {
    while true; do
        ui::header "UFW 规则管理"
        echo -e " 当前状态: $(ufw::status_text)"
        echo
        echo -e "  ${GREEN}1.${PLAIN} 添加规则"
        echo -e "  ${GREEN}2.${PLAIN} 删除规则"
        echo -e "  ${GREEN}3.${PLAIN} 查看当前规则"
        echo -e "  ${GREEN}0.${PLAIN} 返回上级菜单"
        echo
        local opt
        ui::prompt " 请选择: " opt
        case "$opt" in
            1) ufw::add_rule_interactive ;;
            2) ufw::delete_rule_interactive ;;
            3) ufw::list_numbered ;;
            0) return ;;
            *) log::err "无效选项" ;;
        esac
        [[ "$opt" != "0" ]] && ui::pause
    done
}

menu::ufw() {
    while true; do
        ui::header "UFW 防火墙"
        echo -e " 当前状态: $(ufw::status_text)"
        echo
        echo -e "  ${GREEN}1.${PLAIN} UFW 服务管理 (安装/启停/卸载)"
        echo -e "  ${GREEN}2.${PLAIN} UFW 规则管理 (添加/删除/查看)"
        echo -e "  ${GREEN}0.${PLAIN} 返回主菜单"
        echo
        local opt
        ui::prompt " 请选择: " opt
        case "$opt" in
            1) menu::ufw_manage ;;
            2) menu::ufw_rules ;;
            0) return ;;
            *) log::err "无效选项"; ui::pause ;;
        esac
    done
}

# >>> src/menu/main.sh
# ==============================================================================
# menu::main - 主菜单
# ==============================================================================

menu::main() {
    while true; do
        # 状态采集集中在循环顶部，避免 echo 行内多次嵌套子 shell
        local up sb_ver sb_st ufw_st
        up="$(sys::uptime)"
        sb_ver="$(sb::version)"
        sb_st="$(sb::status)"
        ufw_st="$(ufw::status_text)"

        ui::clear
        echo -e "┌──────────────────────────────────────────────┐"
        echo -e "│              ${BLUE}Sing-box 管理脚本${PLAIN}               │"
        echo -e "│                ${GREEN}版本: v${SCRIPT_VERSION}${PLAIN}                 │"
        echo -e "└──────────────────────────────────────────────┘"
        echo -e " 系统运行时间: ${up}"
        echo -e " Sing-box版本: ${BLUE}${sb_ver}${PLAIN}"
        echo -e " 运行状态    : ${sb_st}"
        echo -e " UFW 状态    : ${ufw_st}"
        ui::divider
        echo -e "  ${GREEN}1.${PLAIN} 安装 / 更新 Sing-box"
        echo -e "  ${GREEN}2.${PLAIN} 管理 Sing-box 服务 (启动/停止/日志)"
        echo -e "  ${GREEN}3.${PLAIN} 更新配置文件"
        echo -e "  ${GREEN}4.${PLAIN} 修改默认配置下载链接"
        ui::divider
        echo -e "  ${GREEN}5.${PLAIN} 系统更新 (full-upgrade 修复内核漏洞)"
        echo -e "  ${GREEN}6.${PLAIN} 安装常用软件 (Caddy / Docker)"
        echo -e "  ${GREEN}7.${PLAIN} UFW 防火墙管理"
        echo -e "  ${GREEN}8.${PLAIN} 系统 TCP 网络优化"
        echo -e "  ${GREEN}9.${PLAIN} 安装伪装 (静态站 / OpenList)"
        ui::divider
        echo -e "  ${GREEN}10.${PLAIN} 检查并更新管理脚本"
        echo -e "  ${GREEN}11.${PLAIN} 卸载脚本 (可选卸载所有组件)"
        echo -e "  ${GREEN}0.${PLAIN} 退出"
        ui::divider
        echo -e " 快捷指令: 输入 ${GREEN}${SCRIPT_NAME}${PLAIN} 即可再次调出此菜单"
        echo
        local opt
        ui::prompt " 请输入选项 [0-11]: " opt
        case "$opt" in
            1)  sb::install ;;
            2)  menu::sb_service ;;
            3)  sb::apply_config "$DEFAULT_CONFIG_URL" ;;
            4)  sb::set_default_url ;;
            5)  system::full_upgrade ;;
            6)  menu::common_software ;;
            7)  menu::ufw ;;
            8)  tcp::run ;;
            9)  menu::camouflage ;;
            10) self::check_update "$@" ;;
            11) self::uninstall ;;
            0)  exit 0 ;;
            *)  log::err "无效选项，请重新输入" ;;
        esac
        [[ "$opt" != "10" ]] && ui::pause
    done
}

# >>> src/entry.sh
# ==============================================================================
# 入口
# ==============================================================================

main() {
    sys::require_root
    sys::require_debian
    pkg::ensure_deps || { log::err "依赖准备失败，无法继续。"; exit 1; }
    self::install_shortcut "$@"
    menu::main "$@"
}

main "$@"

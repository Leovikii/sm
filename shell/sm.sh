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
SCRIPT_VERSION="3.2.3"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"
SCRIPT_UPDATE_URL="https://raw.githubusercontent.com/Leovikii/sm/main/shell/sm.sh"

CONFIG_URL_FILE="/var/lib/sm/default_url"
CONFIG_DATE_FILE="/var/lib/sm/config_last_update"
TCPX_URL="https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh"

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

# 缩进 1 空格让上下文呼吸，色调统一蓝色
ui::divider() { echo -e "${BLUE} ──────────────────────────────────────────────${PLAIN}"; }

# 不画封闭 box —— 含 CJK 字符时 printf "%-Ns" 永远对不齐右侧 │，
# 且 │ ─ 这些方框字在不同终端下宽度歧义（East Asian Ambiguous Width）
ui::header() {
    local title="$1" subtitle="${2:-}"
    ui::clear
    echo
    echo -e "${BLUE} ──────────────────────────────────────────────${PLAIN}"
    if [[ -n "$subtitle" ]]; then
        echo -e "  ${BLUE}❯${PLAIN} ${BLUE}${title}${PLAIN}  ${GREEN}${subtitle}${PLAIN}"
    else
        echo -e "  ${BLUE}❯${PLAIN} ${BLUE}${title}${PLAIN}"
    fi
    echo -e "${BLUE} ──────────────────────────────────────────────${PLAIN}"
}

ui::confirm() {
    local prompt="$1" ans
    read -r -p "$prompt (y/N): " ans || exit 130
    [[ "${ans,,}" == "y" ]]
}

ui::prompt() {
    local prompt="$1" varname="$2" flag="${3:-}"
    if [[ "$flag" == "-e" ]]; then
        read -e -r -p "$prompt" "${varname?}" || exit 130
    else
        read -r -p "$prompt" "${varname?}" || exit 130
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

net::fetch() {
    local url="$1"
    if sys::has_cmd curl; then
        curl -k -f -L --retry 2 --connect-timeout 5 -s -A "sing-box/1.0" "$url"
    else
        wget --no-check-certificate -q -O- -T 5 -t 2 --user-agent="sing-box/1.0" "$url"
    fi
}

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

pkg::full_upgrade() {
    DEBIAN_FRONTEND=noninteractive apt-get "$@" -y full-upgrade
}

# 静默模式失败时回退到 verbose 模式重跑，让用户看到真实 apt 错误
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
        if ! pkg::update quiet; then
            log::warn "apt-get update 静默失败，重试 verbose 模式以暴露错误..."
            pkg::update || { log::err "apt-get update 失败，请检查软件源/DNS/网络"; return 1; }
        fi
        if ! pkg::install_quiet $missing; then
            log::warn "依赖安装静默失败，重试 verbose 模式以暴露错误..."
            if ! pkg::install $missing; then
                log::err "依赖安装失败:$missing"
                log::info "常见原因: 软件源失效 / DNS 故障 / 签名过期 / 网络受限"
                return 1
            fi
        fi
    fi
    mkdir -p "$(dirname "$DEPS_FLAG")"
    touch "$DEPS_FLAG"
    _DEPS_CHECKED=1
}

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
svc::logs()      {
    trap - INT
    journalctl -u "$1" -f -o cat
    trap 'echo -e "\n${YELLOW}[WARN]${PLAIN} 接收到退出指令，脚本终止。"; exit 130' INT TERM HUP
}

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

    if ufw::is_installed; then
        if ui::confirm "检测到 ${BLUE}UFW${PLAIN}，是否卸载? (将丢失所有防火墙规则)"; then
            ufw::uninstall
        else
            log::info "已保留 UFW"
        fi
        echo
    fi

    if nftbl::is_installed; then
        if ui::confirm "检测到 ${BLUE}nftables 黑名单${PLAIN}，是否卸载?"; then
            nftbl::uninstall
        else
            log::info "已保留 nftables 黑名单"
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

# >>> src/modules/nftbl.sh
# ==============================================================================
# nftbl:: nftables 黑名单 (trick77/nftables-blacklist)
# 部署官方 update-blacklist.sh + 每月自动更新 timer
# 卸载时只清理脚本自动生成的资源，绝不动用户编辑过的配置
# ==============================================================================

NFTBL_SCRIPT_PATH="/usr/local/sbin/update-blacklist.sh"
NFTBL_CONF_DIR="/etc/nftables-blacklist"
NFTBL_CONF_FILE="${NFTBL_CONF_DIR}/nftables-blacklist.conf"
NFTBL_TIMER="/etc/systemd/system/sm-nftbl-update.timer"
NFTBL_SERVICE="/etc/systemd/system/sm-nftbl-update.service"
NFTBL_TIMER_NAME="sm-nftbl-update.timer"
NFTBL_SERVICE_NAME="sm-nftbl-update.service"
NFTBL_SCRIPT_URL="https://raw.githubusercontent.com/trick77/nftables-blacklist/master/update-blacklist.sh"
NFTBL_CONF_URL="https://raw.githubusercontent.com/trick77/nftables-blacklist/master/nftables-blacklist.conf"

nftbl::is_installed() { [[ -x "$NFTBL_SCRIPT_PATH" ]]; }

nftbl::table_exists() {
    sys::has_cmd nft && nft list table inet blacklist >/dev/null 2>&1
}

nftbl::status_text() {
    if ! nftbl::is_installed; then
        echo -e "${RED}未安装${PLAIN}"
    elif nftbl::table_exists; then
        echo -e "${GREEN}已部署${PLAIN}"
    else
        echo -e "${YELLOW}已安装(规则未加载)${PLAIN}"
    fi
}

nftbl::_require() {
    if ! nftbl::is_installed; then
        log::err "nftables 黑名单未安装，请先执行安装"
        return 1
    fi
}

nftbl::install() {
    if nftbl::is_installed; then
        log::warn "已检测到 ${NFTBL_SCRIPT_PATH}"
        ui::confirm "是否覆盖重装?" || { log::info "已取消"; return; }
    fi

    log::step "[1/6] 安装依赖 (curl / iprange / nftables)..."
    pkg::update quiet
    if ! pkg::install_quiet curl iprange nftables; then
        log::warn "依赖静默安装失败，重试 verbose 模式..."
        pkg::install curl iprange nftables || { log::err "依赖安装失败"; return 1; }
    fi

    log::step "[2/6] 下载 update-blacklist.sh..."
    if ! net::download "$NFTBL_SCRIPT_URL" "$NFTBL_SCRIPT_PATH"; then
        log::err "更新脚本下载失败"
        rm -f "$NFTBL_SCRIPT_PATH"
        return 1
    fi
    chmod +x "$NFTBL_SCRIPT_PATH"

    log::step "[3/6] 准备配置文件..."
    mkdir -p "$NFTBL_CONF_DIR"
    if [[ -f "$NFTBL_CONF_FILE" ]]; then
        log::info "已存在 ${NFTBL_CONF_FILE}，保留用户配置不覆盖"
    else
        if ! net::download "$NFTBL_CONF_URL" "$NFTBL_CONF_FILE"; then
            log::err "默认配置下载失败"
            return 1
        fi
        log::info "默认配置已下载到 ${NFTBL_CONF_FILE}"
    fi

    log::step "[4/6] 立即跑一次 update-blacklist.sh..."
    if ! "$NFTBL_SCRIPT_PATH" "$NFTBL_CONF_FILE"; then
        log::warn "首次执行返回非 0，可能源 IP 列表当前不可达，可稍后通过菜单重试"
    fi

    log::step "[5/6] 写入 systemd service / timer..."
    cat > "$NFTBL_SERVICE" <<EOF
[Unit]
Description=sm nftables blacklist update (trick77)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${NFTBL_SCRIPT_PATH} ${NFTBL_CONF_FILE}
EOF

    cat > "$NFTBL_TIMER" <<EOF
[Unit]
Description=sm nftables blacklist monthly update timer

[Timer]
OnCalendar=monthly
RandomizedDelaySec=1h
Persistent=true
Unit=${NFTBL_SERVICE_NAME}

[Install]
WantedBy=timers.target
EOF

    log::step "[6/6] 启用每月自动更新 timer..."
    systemctl daemon-reload
    if systemctl enable --now "$NFTBL_TIMER_NAME" >/dev/null 2>&1; then
        log::info "${NFTBL_TIMER_NAME} 已启用 (每月自动更新)"
    else
        log::err "timer 启用失败，请手动检查 systemctl status ${NFTBL_TIMER_NAME}"
    fi

    echo
    log::info "✅ nftables 黑名单部署完成"
    log::info "  脚本    : ${NFTBL_SCRIPT_PATH}"
    log::info "  配置    : ${NFTBL_CONF_FILE}"
    log::info "  自动更新: 每月一次 (${NFTBL_TIMER_NAME})"
    if nftbl::table_exists; then
        local v4 v6
        v4=$(nft list set inet blacklist blacklist4 2>/dev/null | grep -c '^\s*[0-9]')
        v6=$(nft list set inet blacklist blacklist6 2>/dev/null | grep -c '^\s*[a-fA-F0-9]')
        log::info "  当前规则: IPv4≈${v4} 行 / IPv6≈${v6} 行"
    fi
    log::info "  下次触发: $(systemctl list-timers ${NFTBL_TIMER_NAME} 2>/dev/null | awk 'NR==2 {print $1, $2}')"
}

nftbl::update_now() {
    nftbl::_require || return
    log::step "运行 update-blacklist.sh..."
    if "$NFTBL_SCRIPT_PATH" "$NFTBL_CONF_FILE"; then
        log::info "黑名单更新完成"
    else
        log::err "更新失败 (退出码 $?)"
        return 1
    fi
}

nftbl::edit_config() {
    nftbl::_require || return
    if [[ ! -f "$NFTBL_CONF_FILE" ]]; then
        log::err "配置文件不存在: $NFTBL_CONF_FILE"
        return 1
    fi
    local editor="${EDITOR:-}"
    if [[ -z "$editor" ]]; then
        if sys::has_cmd nano; then editor=nano
        elif sys::has_cmd vim; then editor=vim
        elif sys::has_cmd vi;  then editor="vi"
        else
            log::err "未找到可用编辑器 (nano/vim/vi)，请手动编辑 ${NFTBL_CONF_FILE}"
            return 1
        fi
    fi
    "$editor" "$NFTBL_CONF_FILE"
    if ui::confirm "是否立即重新应用配置?"; then
        nftbl::update_now
    fi
}

nftbl::show_status() {
    if ! sys::has_cmd nft; then
        log::err "nft 命令不可用，请先安装 nftables"
        return 1
    fi
    if ! nftbl::table_exists; then
        log::warn "inet blacklist 表不存在 (尚未运行过 update-blacklist.sh 或已被清理)"
        return 1
    fi

    log::info "── 表 inet blacklist ──"
    nft list table inet blacklist 2>/dev/null | head -n 40
    echo
    log::info "── IPv4 set (前 20 行) ──"
    nft list set inet blacklist blacklist4 2>/dev/null | sed -n '1,20p'
    echo
    log::info "── IPv6 set (前 20 行) ──"
    nft list set inet blacklist blacklist6 2>/dev/null | sed -n '1,20p'
    echo
    log::info "── input chain 计数器 ──"
    nft list chain inet blacklist input 2>/dev/null
    echo
    log::info "── timer 下次触发 ──"
    systemctl list-timers "$NFTBL_TIMER_NAME" 2>/dev/null | head -n 3
}

nftbl::uninstall() {
    if ! nftbl::is_installed && [[ ! -f "$NFTBL_TIMER" && ! -f "$NFTBL_SERVICE" ]]; then
        log::warn "nftables 黑名单未安装"
        return
    fi
    log::warn "即将卸载 nftables 黑名单 (仅清理本脚本自动生成的资源)"
    ui::confirm "确认卸载?" || { log::info "取消"; return; }

    systemctl disable --now "$NFTBL_TIMER_NAME" >/dev/null 2>&1 || true
    rm -f "$NFTBL_TIMER" "$NFTBL_SERVICE"
    systemctl daemon-reload

    if sys::has_cmd nft && nftbl::table_exists; then
        nft delete table inet blacklist 2>/dev/null && log::info "nft 表已删除"
    fi

    rm -f "$NFTBL_SCRIPT_PATH"

    if [[ -d "$NFTBL_CONF_DIR" ]]; then
        echo
        log::warn "配置目录 ${NFTBL_CONF_DIR} 可能包含您手工编辑过的内容"
        if ui::confirm "是否一并删除? (默认 N)"; then
            rm -rf "$NFTBL_CONF_DIR"
            log::info "${NFTBL_CONF_DIR} 已删除"
        else
            log::info "已保留 ${NFTBL_CONF_DIR}"
        fi
    fi

    log::info "nftables 黑名单已卸载"
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
    log::warn "即将卸载 Sing-box 及其软件源、密钥"
    ui::confirm "确认卸载?" || { log::info "取消卸载"; return; }

    svc::stop sing-box
    svc::disable sing-box
    pkg::purge sing-box

    rm -f /etc/apt/sources.list.d/sagernet.list
    rm -f /etc/apt/keyrings/sagernet.asc

    # /etc/sing-box 内有用户拉下来或手写的 config.json 以及历史证书目录，
    # 默认保留并询问是否清理
    if [[ -d /etc/sing-box ]] && ui::confirm "是否同时删除配置目录 /etc/sing-box?"; then
        rm -rf /etc/sing-box
        log::info "/etc/sing-box 已删除"
    fi

    log::info "Sing-box 已卸载"
}

sb::require_installed() {
    if ! sys::has_cmd sing-box; then
        log::warn "未检测到 Sing-box 内核，配置与服务管理需要依赖它。"
        if ui::confirm "是否立即安装 Sing-box?"; then
            sb::install || return 1
        else
            return 1
        fi
    fi
    return 0
}

sb::get_default_url() {
    [[ -n "$CONFIG_URL_FILE" && -f "$CONFIG_URL_FILE" ]] && cat "$CONFIG_URL_FILE"
}

sb::set_default_url() {
    mkdir -p "$(dirname "$CONFIG_URL_FILE")"
    echo "$1" > "$CONFIG_URL_FILE"
}

sb::get_last_update_date() {
    [[ -n "$CONFIG_DATE_FILE" && -f "$CONFIG_DATE_FILE" ]] && cat "$CONFIG_DATE_FILE"
}

sb::set_last_update_date() {
    mkdir -p "$(dirname "$CONFIG_DATE_FILE")"
    date "+%Y-%m-%d %H:%M:%S" > "$CONFIG_DATE_FILE"
}

sb::update_config_interactive() {
    local default_url
    default_url=$(sb::get_default_url)
    local last_date
    last_date=$(sb::get_last_update_date)

    if [[ -n "$last_date" ]]; then
        echo -e "上次配置更新日期: ${YELLOW}${last_date}${PLAIN}"
    fi

    local new_url
    if [[ -z "$default_url" ]]; then
        ui::prompt "请输入配置下载链接: " new_url -e
        if [[ -z "$new_url" ]]; then
            log::err "链接不能为空，操作取消。"
            return 1
        fi
    else
        echo -e "当前默认配置链接: ${BLUE}${default_url}${PLAIN}"
        ui::prompt "请输入配置下载链接 (直接回车保持默认): " new_url -e
        [[ -z "$new_url" ]] && new_url="$default_url"
    fi

    if [[ ! "$new_url" =~ ^https?://.+ ]]; then
        log::err "输入链接不合法，必须以 http:// 或 https:// 开头。"
        return 1
    fi

    if [[ "$new_url" != "$default_url" ]]; then
        sb::set_default_url "$new_url"
    fi

    local url="$new_url"
    mkdir -p "$TMP_DIR"
    local tmp_conf="$TMP_DIR/config.json"

    log::info "正在下载配置: $url"
    if ! net::download "$url" "$tmp_conf"; then
        log::err "下载失败，请检查 URL 是否正确或网络是否畅通。"
        return 1
    fi

    if [[ ! -s "$tmp_conf" ]]; then
        log::err "下载的文件为空或不存在，下载失败。"
        return 1
    fi
    
    log::step "使用 Sing-box 内核进行配置语法语义校验..."
    if ! sing-box check -c "$tmp_conf"; then
        log::err "Sing-box 配置校验失败！请检查 JSON 内容是否合法。操作已取消。"
        return 1
    fi
    
    mkdir -p /etc/sing-box
    local target_conf="/etc/sing-box/config.json"
    
    if [[ -f "$target_conf" ]]; then
        local old_md5 new_md5
        old_md5=$(md5sum "$target_conf" | awk '{print $1}')
        new_md5=$(md5sum "$tmp_conf" | awk '{print $1}')
        if [[ "$old_md5" == "$new_md5" ]]; then
            log::info "配置文件校验通过，但内容未发生变化。"
            sb::set_last_update_date
            return 0
        fi
    fi

    mv "$tmp_conf" "$target_conf"
    sb::set_last_update_date
    log::info "配置文件校验通过并已应用！更新成功。"
    if ui::confirm "是否重启 Sing-box 服务?"; then
        svc::restart sing-box && log::info "服务已重启。"
    fi
}

# >>> src/modules/system.sh
# ==============================================================================
# system:: 系统级操作（升级 / 内核）
# ==============================================================================

system::full_upgrade() {
    log::info "准备执行系统全量升级 (full-upgrade)..."
    
    log::step "[1/4] 更新软件源索引..."
    pkg::update || { log::err "apt-get update 失败，请检查软件源。"; return; }

    log::step "[2/4] 获取可更新的软件包列表..."
    local up_list
    up_list=$(apt list --upgradable 2>/dev/null | grep -v 'Listing...')
    if [[ -z "$up_list" ]]; then
        log::info "当前系统已是最新，没有需要升级的软件包。"
        return
    fi
    echo
    echo -e "${BLUE}=== 以下软件包将被升级 ===${PLAIN}"
    echo "$up_list" | head -n 20
    local up_count
    up_count=$(echo "$up_list" | wc -l)
    if [[ "$up_count" -gt 20 ]]; then
        echo -e "${YELLOW}... 等共计 ${up_count} 个软件包更新。${PLAIN}"
    fi
    echo
    
    log::warn "全量升级可能包含内核更新及依赖变化，建议升级后重启。"
    ui::confirm "确认继续升级上述软件包?" || { log::info "已取消。"; return; }

    local apt_opts=(-o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef)

    log::step "[3/4] 执行 full-upgrade (包含内核升级)..."
    if ! pkg::full_upgrade "${apt_opts[@]}"; then
        log::err "full-upgrade 执行失败。"
        return
    fi

    log::step "[4/4] 清理无用依赖..."
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

# 加 timeout 防止某些 nf_tables 状态下 ufw status numbered 卡死
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

    ufw disable >/dev/null 2>&1
    pkg::purge ufw >/dev/null 2>&1
    rm -rf /etc/ufw /lib/ufw /var/lib/ufw
    log::info "UFW 已完全卸载"
}

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

ufw::add_rule_interactive() {
    ufw::_require || return
    log::info "添加 UFW 规则 (示例: 2222/tcp 或 8080/udp)"
    log::info "规则会自动应用于 IPv4 和 IPv6 双栈"
    local input
    ui::prompt "请输入端口/协议 (如 2222/tcp): " input

    if [[ ! "$input" =~ ^([0-9]+)/(tcp|udp)$ ]]; then
        log::err "格式错误，请使用 端口/协议 格式（输入: $input）"
        return 1
    fi
    local port="${BASH_REMATCH[1]}"
    local proto="${BASH_REMATCH[2]}"
    if (( port < 1 || port > 65535 )); then
        log::err "端口必须在 1-65535 范围内（输入: $port）"
        return 1
    fi
    local other="udp"
    [[ "$proto" == "udp" ]] && other="tcp"

    ufw::allow "$port" "$proto"
    if ui::confirm "是否同时放行 ${port}/${other}?"; then
        ufw::allow "$port" "$other"
    fi
}

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

    local rules_to_delete=("$rule_num")
    local delete_other="n"

    # 提取类似 22/tcp 的结构，不匹配则说明是复杂规则（如应用配置 Nginx Full 或带 IP 的规则）
    local target_def
    target_def=$(echo "$rule_info" | sed -E 's/^\[[[:space:]]*[0-9]+\][[:space:]]+([0-9]+\/(tcp|udp)).*/\1/' 2>/dev/null)
    
    if [[ "$target_def" =~ ^([0-9]+)/(tcp|udp)$ ]]; then
        local port="${BASH_REMATCH[1]}"
        local proto="${BASH_REMATCH[2]}"
        local other="udp"
        [[ "$proto" == "udp" ]] && other="tcp"

        if echo "$rules_raw" | grep -q "${port}/${other}"; then
            if ui::confirm "检测到对应的 ${port}/${other} 规则，是否一并删除?"; then
                delete_other="y"
            fi
        fi
        
        # 如果是标准端口规则，我们通过遍历寻找所有相关编号以解决 IPv4/IPv6 双胞胎问题
        rules_to_delete=()
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
    else
        log::info "此为非标准端口规则 (或应用名规则)，将仅删除您选择的单条规则。"
    fi

    # 倒序去重，避免删除时编号偏移
    IFS=$'\n' read -r -d '' -a rules_to_delete < <(printf '%s\n' "${rules_to_delete[@]}" | sort -rn -u && printf '\0')

    if [[ ${#rules_to_delete[@]} -eq 0 ]]; then
        log::err "未找到匹配的规则"
        return 1
    fi

    log::warn "总共将删除 ${#rules_to_delete[@]} 条规则 (编号: ${rules_to_delete[*]})"
    ui::confirm "确认删除?" || { log::warn "取消删除"; return; }

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

# >>> src/menu/nftbl.sh
# ==============================================================================
# menu::nftbl - nftables 黑名单 (trick77/nftables-blacklist) 管理子菜单
# ==============================================================================

menu::nftbl() {
    while true; do
        ui::header "nftables 黑名单 (trick77)"
        echo -e " 当前状态: $(nftbl::status_text)"
        echo
        echo -e "  ${GREEN}1.${PLAIN} 安装并启用 (含每月自动更新)"
        echo -e "  ${GREEN}2.${PLAIN} 立即更新黑名单"
        echo -e "  ${GREEN}3.${PLAIN} 编辑配置文件 (黑名单源列表)"
        echo -e "  ${GREEN}4.${PLAIN} 查看状态 (nft 表 / IPv4·IPv6 set / 计数器)"
        echo -e "  ${GREEN}5.${PLAIN} 卸载"
        echo -e "  ${GREEN}0.${PLAIN} 返回主菜单"
        echo
        echo -e " ${BLUE}提示${PLAIN}: 自动生成资源:"
        echo -e "       ${NFTBL_SCRIPT_PATH}"
        echo -e "       ${NFTBL_TIMER}"
        echo -e "       ${NFTBL_SERVICE}"
        echo -e "       配置文件 ${NFTBL_CONF_FILE} 视为用户文件，卸载时仅询问"
        echo
        local opt
        ui::prompt " 请选择: " opt
        case "$opt" in
            1) nftbl::install ;;
            2) nftbl::update_now ;;
            3) nftbl::edit_config ;;
            4) nftbl::show_status ;;
            5) nftbl::uninstall ;;
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
        local up sb_ver sb_st ufw_st
        up="$(sys::uptime)"
        sb_ver="$(sb::version)"
        sb_st="$(sb::status)"
        ufw_st="$(ufw::status_text)"

        ui::clear
        echo
        echo -e "${BLUE} ──────────────────────────────────────────────${PLAIN}"
        echo -e "  ${BLUE}❯${PLAIN} ${BLUE}Sing-box 管理脚本${PLAIN}  ${GREEN}v${SCRIPT_VERSION}${PLAIN}"
        echo -e "${BLUE} ──────────────────────────────────────────────${PLAIN}"
        echo -e "  ${BLUE}·${PLAIN} 系统运行时间  ${up}"
        echo -e "  ${BLUE}·${PLAIN} Sing-box 版本 ${BLUE}${sb_ver}${PLAIN}"
        echo -e "  ${BLUE}·${PLAIN} 运行状态      ${sb_st}"
        echo -e "  ${BLUE}·${PLAIN} UFW 状态      ${ufw_st}"
        ui::divider
        echo -e "  ${GREEN}1.${PLAIN} 安装 / 更新 Sing-box"
        echo -e "  ${GREEN}2.${PLAIN} 管理 Sing-box 服务 (启动/停止/日志)"
        echo -e "  ${GREEN}3.${PLAIN} 更新 Sing-box 配置文件"
        ui::divider
        echo -e "  ${GREEN}4.${PLAIN} 系统更新 (full-upgrade 修复内核漏洞)"
        echo -e "  ${GREEN}5.${PLAIN} UFW 防火墙管理"
        echo -e "  ${GREEN}6.${PLAIN} 系统 TCP 网络优化"
        echo -e "  ${GREEN}7.${PLAIN} nftables 黑名单 (trick77/nftables-blacklist)"
        ui::divider
        echo -e "  ${GREEN}8.${PLAIN} 检查并更新管理脚本"
        echo -e "  ${GREEN}9.${PLAIN} 卸载脚本 (可选卸载所有组件)"
        echo -e "  ${GREEN}0.${PLAIN}  退出"
        ui::divider
        echo -e "  ${BLUE}快捷指令${PLAIN}: 输入 ${GREEN}${SCRIPT_NAME}${PLAIN} 即可再次调出此菜单"
        echo
        local opt
        ui::prompt " 请输入选项 [0-9]: " opt
        case "$opt" in
            1)  sb::install; ui::pause ;;
            2)  if sb::require_installed; then menu::sb_service; else ui::pause; fi ;;
            3)  sb::require_installed && sb::update_config_interactive; ui::pause ;;
            4)  system::full_upgrade; ui::pause ;;
            5)  menu::ufw ;;
            6)  tcp::run; ui::pause ;;
            7)  menu::nftbl ;;
            8)  self::check_update "$@" ;;
            9)  self::uninstall; ui::pause ;;
            0)  exit 0 ;;
            *)  log::err "无效选项，请重新输入"; ui::pause ;;
        esac
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

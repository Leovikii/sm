#!/bin/bash

SCRIPT_NAME="sm.sh"
SCRIPT_VERSION="2.1.2"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"
SCRIPT_UPDATE_URL="https://raw.githubusercontent.com/Leovikii/sm/main/shell/sm.sh"

DEFAULT_CONFIG_URL="https://example.com/config.json"
TCPX_URL="https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh"
UFW_URL="https://raw.githubusercontent.com/Leovikii/sm/main/shell/ufw.sh"

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
PLAIN='\033[0m'

TMP_DIR="/tmp/sm_manager_tmp_$$"
DEPS_FLAG="/var/lib/sm/.deps_ok"
_DEPS_CHECKED=0

cleanup() { rm -rf "$TMP_DIR"; }

trap cleanup EXIT
trap 'echo -e "\n${YELLOW}[WARN]${PLAIN} 接收到退出指令，脚本终止。"; exit 130' INT TERM HUP

log_info() { echo -e "${GREEN}[INFO]${PLAIN} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${PLAIN} $1"; }
log_err() { echo -e "${RED}[ERROR]${PLAIN} $1"; }

check_root() {
    [[ $EUID -ne 0 ]] && { log_err "请使用 root 用户运行此脚本 (sudo -i)"; exit 1; }
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" != "debian" && "$ID" != "ubuntu" && "$ID_LIKE" != *"debian"* ]]; then
             log_warn "本脚本专为 Debian/Ubuntu 设计，检测到当前系统为: $ID"
             read -r -p "是否强制继续? (y/N): " force || exit 130
             [[ "${force,,}" != "y" ]] && exit 1
        fi
    else
        log_err "无法检测系统版本，仅支持 Debian/Ubuntu 标准发行版。"
        exit 1
    fi
}

install_dependencies() {
    [[ $_DEPS_CHECKED -eq 1 ]] && return
    if [[ -f "$DEPS_FLAG" ]]; then
        _DEPS_CHECKED=1
        return
    fi
    local deps="curl wget jq tar ca-certificates gnupg"
    local missing=""
    for dep in $deps; do
        if ! command -v "$dep" &>/dev/null; then missing="$missing $dep"; fi
    done
    if [[ -n "$missing" ]]; then
        log_info "正在安装必要依赖: $missing"
        apt-get update -y >/dev/null 2>&1
        if ! apt-get install -y $missing >/dev/null 2>&1; then
            log_err "依赖安装失败: $missing"
            return 1
        fi
    fi
    mkdir -p "$(dirname "$DEPS_FLAG")"
    touch "$DEPS_FLAG"
    _DEPS_CHECKED=1
}

fetch_text() {
    local url="$1"
    if command -v curl &>/dev/null; then
        curl -k -f -L --retry 2 --connect-timeout 5 -s -A "sing-box/1.0" "$url"
    else
        wget --no-check-certificate -q -O- -T 5 -t 2 --user-agent="sing-box/1.0" "$url"
    fi
}

download_file() {
    local url="$1"
    local dest="$2"
    if command -v curl &>/dev/null; then
        curl -k -f -L --retry 3 --connect-timeout 10 -s -A "sing-box/1.0" -o "$dest" "$url"
    else
        wget --no-check-certificate -q -T 15 -t 3 --user-agent="sing-box/1.0" -O "$dest" "$url"
    fi
}

self_install_and_cleanup() {
    if [[ "$(realpath "$0")" != "$(realpath "$INSTALL_PATH")" ]]; then
        log_info "首次运行，正在执行自安装..."
        cp -f "$0" "$INSTALL_PATH"
        chmod +x "$INSTALL_PATH"
        log_info "快捷方式已安装: 输入 ${GREEN}${SCRIPT_NAME}${PLAIN} 即可随时启动"
        rm -f "$0"
        exec "$INSTALL_PATH" "$@"
    fi
}

get_sb_status() {
    if systemctl is-active --quiet sing-box; then
        echo -e "${GREEN}运行中${PLAIN}"
    elif command -v sing-box &>/dev/null; then
        echo -e "${RED}已停止${PLAIN}"
    else
        echo -e "${YELLOW}未安装${PLAIN}"
    fi
}

get_sb_version() {
    if command -v sing-box &>/dev/null; then
        sing-box version 2>/dev/null | head -n 1 | awk '{print $3}'
    else
        echo "N/A"
    fi
}

install_singbox() {
    install_dependencies
    log_info "准备安装/更新 Sing-box..."
    
    mkdir -p /etc/apt/keyrings
    fetch_text "https://sing-box.app/gpg.key" > /etc/apt/keyrings/sagernet.asc
    chmod a+r /etc/apt/keyrings/sagernet.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/sagernet.asc] https://deb.sagernet.org/ * *" | \
        tee /etc/apt/sources.list.d/sagernet.list > /dev/null

    apt-get update >/dev/null 2>&1
    if apt-get install -y sing-box; then
        systemctl enable sing-box >/dev/null 2>&1
        systemctl start sing-box
        log_info "Sing-box 安装成功并已启动！"
    else
        log_err "安装失败，请检查网络连接。"
    fi
}

do_uninstall_singbox() {
    log_info "正在停止服务..."
    systemctl stop sing-box 2>/dev/null
    systemctl disable sing-box 2>/dev/null
    
    log_info "正在清理软件包..."
    apt-get purge -y sing-box
    
    log_info "正在清理配置文件..."
    rm -rf /etc/sing-box
    rm -f /etc/apt/sources.list.d/sagernet.list
    rm -f /etc/apt/keyrings/sagernet.asc
    
    log_info "Sing-box 及其配置已彻底移除。"
}

update_config() {
    install_dependencies
    local url="${1:-$DEFAULT_CONFIG_URL}"
    mkdir -p "$TMP_DIR"
    local tmp_conf="$TMP_DIR/config.json"
    
    log_info "正在下载配置: $url"
    if download_file "$url" "$tmp_conf"; then
        if [[ -s "$tmp_conf" ]] && jq -e . "$tmp_conf" >/dev/null 2>&1; then
            mkdir -p /etc/sing-box
            mv "$tmp_conf" /etc/sing-box/config.json
            log_info "配置文件验证通过并已应用。"
            read -r -p "是否重启 Sing-box 服务? (y/N): " restart_opt || exit 130
            [[ "${restart_opt,,}" == "y" ]] && systemctl restart sing-box && log_info "服务已重启。"
        else
            log_err "下载的文件不是有效的 JSON 格式或内容为空，操作已取消。"
        fi
    else
        log_err "下载失败，请检查 URL 是否正确或网络是否畅通。"
    fi
}

set_default_config_url() {
    read -e -r -p "请输入新的默认配置下载链接: " new_url || exit 130
    if [[ -n "$new_url" ]]; then
        sed -i "s|^DEFAULT_CONFIG_URL=.*|DEFAULT_CONFIG_URL=\"$new_url\"|" "$INSTALL_PATH"
        DEFAULT_CONFIG_URL="$new_url"
        log_info "默认链接已更新。"
    else
        log_warn "链接为空，未修改。"
    fi
}

run_ufw_script() {
    install_dependencies
    mkdir -p "$TMP_DIR"
    local ufw_local="$TMP_DIR/install_ufw.sh"
    
    log_info "正在下载 UFW 防火墙脚本..."
    if download_file "$UFW_URL" "$ufw_local"; then
        chmod +x "$ufw_local"
        log_info "下载成功，正在启动安装程序..."
        bash "$ufw_local"
    else
        log_err "UFW 脚本下载失败，请检查网络。"
    fi
}

run_tcp_script() {
    install_dependencies
    mkdir -p "$TMP_DIR"
    local tcp_local="$TMP_DIR/install_tcp.sh"

    log_info "正在下载 TCP 优化脚本..."
    if download_file "$TCPX_URL" "$tcp_local"; then
        chmod +x "$tcp_local"
        bash "$tcp_local"
    else
        log_err "TCP 脚本下载失败。"
    fi
}

system_full_upgrade() {
    log_info "准备执行系统全量升级 (full-upgrade)..."
    log_warn "该操作会升级内核及所有依赖发生变化的软件包，建议升级后重启。"
    read -r -p "确认继续? (y/N): " confirm || exit 130
    [[ "${confirm,,}" != "y" ]] && { log_info "已取消。"; return; }

    export DEBIAN_FRONTEND=noninteractive
    local apt_opts='-o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef'

    log_info "[1/3] 更新软件源索引..."
    if ! apt-get update -y; then
        log_err "apt-get update 失败，请检查软件源。"
        return
    fi

    log_info "[2/3] 执行 full-upgrade (包含内核升级)..."
    if ! apt-get $apt_opts -y full-upgrade; then
        log_err "full-upgrade 执行失败。"
        return
    fi

    log_info "[3/3] 清理无用依赖..."
    apt-get $apt_opts -y autoremove --purge
    apt-get clean

    if [[ -f /var/run/reboot-required ]]; then
        log_warn "系统提示需要重启以应用新内核 (常见于 root 提权漏洞修复)。"
        read -r -p "是否立即重启? (y/N): " reboot_opt || exit 130
        if [[ "${reboot_opt,,}" == "y" ]]; then
            log_info "系统将在 3 秒后重启..."
            sleep 3
            reboot
        else
            log_info "请稍后手动执行 reboot 完成内核切换。"
        fi
    else
        log_info "升级完成，当前无需重启。"
    fi
}

install_caddy() {
    install_dependencies
    log_info "准备安装 Caddy..."

    rm -f /etc/apt/sources.list.d/caddy-stable.list
    rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    rm -f /etc/apt/keyrings/caddy-stable-archive-keyring.gpg

    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https >/dev/null 2>&1

    mkdir -p /usr/share/keyrings
    if ! fetch_text "https://dl.cloudsmith.io/public/caddy/stable/gpg.key" \
            | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg; then
        log_err "Caddy GPG 密钥下载/导入失败。"
        return
    fi
    chmod a+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg

    if ! fetch_text "https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt" \
            > /etc/apt/sources.list.d/caddy-stable.list; then
        log_err "Caddy 软件源列表下载失败。"
        rm -f /etc/apt/sources.list.d/caddy-stable.list
        return
    fi
    if [[ ! -s /etc/apt/sources.list.d/caddy-stable.list ]]; then
        log_err "Caddy 软件源列表为空，已中止。"
        rm -f /etc/apt/sources.list.d/caddy-stable.list
        return
    fi

    if ! apt-get update; then
        log_err "apt-get update 失败，请检查上方错误。"
        return
    fi
    if apt-get install -y caddy; then
        systemctl enable caddy >/dev/null 2>&1
        systemctl start caddy
        if systemctl is-active --quiet caddy; then
            log_info "Caddy 安装成功并已启动 (配置: /etc/caddy/Caddyfile)"
        else
            log_warn "Caddy 已安装但启动失败，请检查 journalctl -u caddy"
        fi
    else
        log_err "Caddy 安装失败，请检查网络或源是否可用。"
    fi
}

install_docker() {
    install_dependencies
    log_info "准备安装 Docker CE + Compose 插件..."

    if command -v docker &>/dev/null; then
        log_warn "检测到已安装: $(docker --version 2>/dev/null)"
        read -r -p "是否继续 (将走 apt 升级流程)? (y/N): " confirm || exit 130
        [[ "${confirm,,}" != "y" ]] && { log_info "已取消。"; return; }
    fi

    local distro_id="" distro_codename=""
    if [[ -f /etc/os-release ]]; then
        distro_id=$(. /etc/os-release && echo "$ID")
        distro_codename=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
    fi
    case "$distro_id" in
        ubuntu|debian) ;;
        *) distro_id="debian" ;;
    esac
    if [[ -z "$distro_codename" ]]; then
        log_err "无法读取系统代号 (VERSION_CODENAME)，安装中止。"
        return
    fi

    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg

    install -m 0755 -d /etc/apt/keyrings
    if ! fetch_text "https://download.docker.com/linux/${distro_id}/gpg" \
            > /etc/apt/keyrings/docker.asc; then
        log_err "Docker GPG 密钥下载失败。"
        rm -f /etc/apt/keyrings/docker.asc
        return
    fi
    if [[ ! -s /etc/apt/keyrings/docker.asc ]]; then
        log_err "Docker GPG 密钥文件为空，已中止。"
        rm -f /etc/apt/keyrings/docker.asc
        return
    fi
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${distro_id} ${distro_codename} stable" \
        > /etc/apt/sources.list.d/docker.list

    if ! apt-get update; then
        log_err "apt-get update 失败，请检查上方错误。"
        return
    fi
    if apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        systemctl enable docker >/dev/null 2>&1
        systemctl start docker
        if systemctl is-active --quiet docker; then
            log_info "Docker 安装成功: $(docker --version 2>/dev/null)"
            log_info "Compose: $(docker compose version 2>/dev/null | head -n1)"
            log_info "如需非 root 用户使用 docker，请执行: usermod -aG docker <user> 后重新登录。"
        else
            log_warn "Docker 已安装但未启动，请检查 journalctl -u docker"
        fi
    else
        log_err "Docker 安装失败，请检查网络或源是否可用。"
    fi
}

common_software_menu() {
    while true; do
        clear
        echo -e "┌──────────────────────────────────────────────┐"
        echo -e "│              ${BLUE}常用软件安装${PLAIN}                    │"
        echo -e "└──────────────────────────────────────────────┘"
        echo
        echo -e "  ${GREEN}1.${PLAIN} 安装 Caddy Web 服务器"
        echo -e "  ${GREEN}2.${PLAIN} 安装 Docker CE + Compose 插件"
        echo -e "  ${GREEN}3.${PLAIN} 一键安装 (Caddy + Docker)"
        echo -e "  ${GREEN}0.${PLAIN} 返回主菜单"
        echo
        read -r -p " 请选择: " sub_opt || exit 130
        case "$sub_opt" in
            *$'\x03'*|*^C*) exit 130 ;;
            1) install_caddy ;;
            2) install_docker ;;
            3) install_caddy; install_docker ;;
            0) break ;;
            *) log_err "无效选项" ;;
        esac
        [[ "$sub_opt" != "0" ]] && { read -n 1 -s -r -p "按任意键继续..." || exit 130; }
    done
}

manage_service_menu() {
    while true; do
        clear
        echo -e "┌──────────────────────────────────────────────┐"
        echo -e "│            ${BLUE}Sing-box 服务管理${PLAIN}                 │"
        echo -e "└──────────────────────────────────────────────┘"
        echo -e " 当前状态: $(get_sb_status)"
        echo
        echo -e "  ${GREEN}1.${PLAIN} 启动服务"
        echo -e "  ${GREEN}2.${PLAIN} 停止服务"
        echo -e "  ${GREEN}3.${PLAIN} 重启服务"
        echo -e "  ${GREEN}4.${PLAIN} 查看实时日志 (Ctrl+C 退出整个脚本)"
        echo -e "  ${GREEN}5.${PLAIN} 卸载 Sing-box"
        echo -e "  ${GREEN}0.${PLAIN} 返回主菜单"
        echo
        read -r -p " 请选择: " sub_opt || exit 130
        case "$sub_opt" in
            *$'\x03'*|*^C*) exit 130 ;;
            1) systemctl start sing-box && log_info "已启动";;
            2) systemctl stop sing-box && log_info "已停止";;
            3) systemctl restart sing-box && log_info "已重启";;
            4) journalctl -u sing-box -f -o cat;;
            5) 
                read -r -p "确定要彻底卸载 Sing-box 吗? (y/N): " un_opt || exit 130
                [[ "${un_opt,,}" == "y" ]] && do_uninstall_singbox
                ;;
            0) break;;
            *) log_err "无效选项";;
        esac
        [[ "$sub_opt" != "4" && "$sub_opt" != "0" ]] && { read -n 1 -s -r -p "按任意键继续..." || exit 130; }
    done
}

update_script() {
    install_dependencies
    log_info "正在检查脚本更新..."
    
    local remote_version
    remote_version=$(fetch_text "$SCRIPT_UPDATE_URL" | grep "^SCRIPT_VERSION=" | head -n 1 | cut -d'"' -f2)

    if [[ -z "$remote_version" ]]; then
        log_err "获取远程版本失败，请检查网络连接。"
    elif [[ "$SCRIPT_VERSION" == "$remote_version" ]]; then
        log_info "当前已是最新版本 (v${SCRIPT_VERSION})，无需更新。"
    else
        log_info "发现新版本: ${GREEN}v${remote_version}${PLAIN} (当前版本: v${SCRIPT_VERSION})"
        read -r -p "是否更新管理脚本? (y/N): " confirm_update || exit 130
        if [[ "${confirm_update,,}" == "y" ]]; then
            mkdir -p "$TMP_DIR"
            local temp_script="$TMP_DIR/new_sm.sh"
            log_info "正在下载新版本..."
            if download_file "$SCRIPT_UPDATE_URL" "$temp_script"; then
                local old_url
                old_url=$(grep "^DEFAULT_CONFIG_URL=" "$INSTALL_PATH" | head -n 1 | cut -d'"' -f2)
                if [[ -n "$old_url" ]]; then
                    sed -i "s|^DEFAULT_CONFIG_URL=.*|DEFAULT_CONFIG_URL=\"$old_url\"|" "$temp_script"
                fi
                chmod +x "$temp_script"
                mv -f "$temp_script" "$INSTALL_PATH"
                log_info "脚本更新成功！正在重新加载..."
                sleep 1
                exec "$INSTALL_PATH" "$@"
            else
                log_err "下载新版本文件失败。"
            fi
        else
            log_info "已取消更新。"
        fi
    fi
}

uninstall_script() {
    echo -e "\n${RED}⚠️  正在进行卸载程序...${PLAIN}"
    
    echo -e "是否同时卸载 ${BLUE}Sing-box${PLAIN} 软件及其所有配置文件？"
    read -r -p "请输入 (y/N): " uninstall_sb || exit 130
    if [[ "${uninstall_sb,,}" == "y" ]]; then
        do_uninstall_singbox
    else
        log_info "已保留 Sing-box 软件及配置。"
    fi

    echo -e "\n是否删除 ${BLUE}本管理脚本 ($SCRIPT_NAME)${PLAIN} 及清理缓存文件？"
    read -r -p "请输入 (y/N): " uninstall_self || exit 130
    if [[ "${uninstall_self,,}" == "y" ]]; then
        if [[ -f "$INSTALL_PATH" ]]; then
            rm -f "$INSTALL_PATH"
            log_info "脚本文件已删除: $INSTALL_PATH"
        fi
        rm -rf /var/lib/sm
        echo -e "${GREEN}卸载完成。再见！${PLAIN}"
        exit 0
    else
        log_info "取消卸载脚本。"
    fi
}

show_menu() {
    clear
    local version=$(get_sb_version)
    local status=$(get_sb_status)
    local uptime_str="N/A"
    if command -v uptime &>/dev/null; then
        uptime_str=$(uptime -p 2>/dev/null | sed 's/up //')
    fi
    
    echo -e "┌──────────────────────────────────────────────┐"
    echo -e "│              ${BLUE}Sing-box 管理脚本${PLAIN}               │"
    echo -e "│                ${GREEN}版本: v${SCRIPT_VERSION}${PLAIN}                 │"
    echo -e "└──────────────────────────────────────────────┘"
    echo -e " 系统运行时间: ${uptime_str}"
    echo -e " Sing-box版本: ${BLUE}${version}${PLAIN}"
    echo -e " 运行状态    : ${status}"
    echo -e "────────────────────────────────────────────────"
    echo -e "  ${GREEN}1.${PLAIN} 安装 / 更新 Sing-box"
    echo -e "  ${GREEN}2.${PLAIN} 管理 Sing-box 服务 (启动/停止/日志)"
    echo -e "  ${GREEN}3.${PLAIN} 更新配置文件"
    echo -e "  ${GREEN}4.${PLAIN} 修改默认配置下载链接"
    echo -e "────────────────────────────────────────────────"
    echo -e "  ${GREEN}5.${PLAIN} 系统更新 (full-upgrade 修复内核漏洞)"
    echo -e "  ${GREEN}6.${PLAIN} 安装常用软件 (Caddy / Docker)"
    echo -e "  ${GREEN}7.${PLAIN} 安装 UFW 防火墙 (安全推荐)"
    echo -e "  ${GREEN}8.${PLAIN} 系统 TCP 网络优化"
    echo -e "────────────────────────────────────────────────"
    echo -e "  ${GREEN}9.${PLAIN} 检查并更新管理脚本"
    echo -e "  ${GREEN}10.${PLAIN} 卸载脚本 (可选卸载 Sing-box)"
    echo -e "  ${GREEN}0.${PLAIN} 退出"
    echo -e "────────────────────────────────────────────────"
    echo -e " 快捷指令: 输入 ${GREEN}${SCRIPT_NAME}${PLAIN} 即可再次调出此菜单"
    echo
}

main() {
    check_root
    check_os
    self_install_and_cleanup "$@"

    while true; do
        show_menu
        read -r -p " 请输入选项 [0-10]: " opt || exit 130
        case "$opt" in
            *$'\x03'*|*^C*) exit 130 ;;
            1) install_singbox ;;
            2) manage_service_menu ;;
            3) update_config "$DEFAULT_CONFIG_URL" ;;
            4) set_default_config_url ;;
            5) system_full_upgrade ;;
            6) common_software_menu ;;
            7) run_ufw_script ;;
            8) run_tcp_script ;;
            9) update_script ;;
            10) uninstall_script ;;
            0) exit 0 ;;
            *) log_err "无效选项，请重新输入" ;;
        esac
        [[ "$opt" != "9" ]] && { read -n 1 -s -r -p "按任意键返回菜单..." || exit 130; }
    done
}

main "$@"
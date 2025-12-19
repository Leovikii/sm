#!/bin/bash

# ==================== 全局配置 ====================
# 脚本安装名称 (安装后使用 sm.sh 命令启动)
SCRIPT_NAME="sm.sh"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"

# 外部资源链接
DEFAULT_CONFIG_URL="https://example.com/config.json"
TCPX_URL="https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh"
UFW_URL="https://raw.githubusercontent.com/Leovikii/sm/main/shell/ufw.sh"

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
PLAIN='\033[0m'

# 临时目录 (固定目录名，确保只删除这个目录)
TMP_DIR="/tmp/sm_manager_tmp"

# ==================== 基础工具函数 ====================
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
             read -p "是否强制继续? (y/N): " force
             [[ "$force" != "y" ]] && exit 1
        fi
    else
        log_err "无法检测系统版本，仅支持 Debian/Ubuntu 标准发行版。"
        exit 1
    fi
}

install_dependencies() {
    if ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
        log_info "正在安装必要依赖 (curl, jq, wget, tar)..."
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl wget jq tar ca-certificates gnupg >/dev/null 2>&1
    fi
}

# ==================== 自安装与清理逻辑 ====================
self_install_and_cleanup() {
    # 如果当前脚本路径不是安装路径
    if [[ "$(realpath "$0")" != "$(realpath "$INSTALL_PATH")" ]]; then
        log_info "首次运行，正在执行自安装..."
        
        # 复制自身到系统路径
        cp -f "$0" "$INSTALL_PATH"
        chmod +x "$INSTALL_PATH"
        
        log_info "快捷方式已安装: 输入 ${GREEN}${SCRIPT_NAME}${PLAIN} 即可随时启动"
        
        # 清理原始文件 (防止重复)
        rm -f "$0"
        
        # 重新执行安装后的脚本
        exec "$INSTALL_PATH" "$@"
    fi
}

# ==================== Sing-box 核心逻辑 ====================
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
    log_info "准备安装/更新 Sing-box (使用官方稳定源)..."
    
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
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

# 独立的 Sing-box 卸载函数 (供内部调用)
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

# ==================== 配置管理 ====================
update_config() {
    local url="${1:-$DEFAULT_CONFIG_URL}"
    mkdir -p "$TMP_DIR"
    
    log_info "正在下载配置: $url"
    if curl -L --retry 3 -s -o "$TMP_DIR/config.json" "$url"; then
        # 验证 JSON 格式
        if jq -e . "$TMP_DIR/config.json" >/dev/null 2>&1; then
            mkdir -p /etc/sing-box
            mv "$TMP_DIR/config.json" /etc/sing-box/config.json
            log_info "配置文件验证通过并已应用。"
            read -p "是否重启 Sing-box 服务? (y/N): " restart_opt
            [[ "$restart_opt" == "y" || "$restart_opt" == "Y" ]] && systemctl restart sing-box && log_info "服务已重启。"
        else
            log_err "下载的文件不是有效的 JSON 格式，操作已取消。"
        fi
    else
        log_err "下载失败，请检查 URL 是否正确。"
    fi
    rm -rf "$TMP_DIR"
}

set_default_config_url() {
    read -p "请输入新的默认配置下载链接: " new_url
    if [[ -n "$new_url" ]]; then
        # 修改脚本自身的变量
        sed -i "s|^DEFAULT_CONFIG_URL=.*|DEFAULT_CONFIG_URL=\"$new_url\"|" "$INSTALL_PATH"
        # 更新当前运行时的变量
        DEFAULT_CONFIG_URL="$new_url"
        log_info "默认链接已更新。"
    else
        log_warn "链接为空，未修改。"
    fi
}

# ==================== 扩展功能 ====================
run_ufw_script() {
    mkdir -p "$TMP_DIR"
    local ufw_local="$TMP_DIR/install_ufw.sh"
    
    log_info "正在下载 UFW 防火墙脚本..."
    if curl -L --retry 3 -s -o "$ufw_local" "$UFW_URL"; then
        chmod +x "$ufw_local"
        log_info "下载成功，正在启动安装程序..."
        bash "$ufw_local"
    else
        log_err "UFW 脚本下载失败，请检查网络。"
    fi
}

run_tcp_script() {
    command -v bash &>/dev/null || apt-get install -y bash
    mkdir -p "$TMP_DIR"
    local tcp_local="$TMP_DIR/install_tcp.sh"
    
    log_info "正在下载 TCP 优化脚本..."
    if curl -L --retry 3 -s -o "$tcp_local" "$TCPX_URL"; then
        chmod +x "$tcp_local"
        bash "$tcp_local"
    else
        log_err "TCP 脚本下载失败。"
    fi
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
        echo -e "  ${GREEN}4.${PLAIN} 查看实时日志 (Ctrl+C 退出)"
        echo -e "  ${GREEN}5.${PLAIN} 卸载 Sing-box"
        echo -e "  ${GREEN}0.${PLAIN} 返回主菜单"
        echo
        read -p " 请选择: " sub_opt
        case "$sub_opt" in
            1) systemctl start sing-box && log_info "已启动";;
            2) systemctl stop sing-box && log_info "已停止";;
            3) systemctl restart sing-box && log_info "已重启";;
            4) journalctl -u sing-box -f -o cat;;
            5) 
                read -p "确定要彻底卸载 Sing-box 吗? (y/N): " un_opt
                [[ "$un_opt" == "y" ]] && do_uninstall_singbox
                ;;
            0) break;;
            *) log_err "无效选项";;
        esac
        [[ "$sub_opt" != "4" && "$sub_opt" != "0" ]] && read -n 1 -s -r -p "按任意键继续..."
    done
}

# ==================== 安全卸载逻辑 (重点更新) ====================
uninstall_script() {
    echo -e "\n${RED}⚠️  正在进行卸载程序...${PLAIN}"
    
    # 1. 询问是否卸载 Sing-box
    echo -e "是否同时卸载 ${BLUE}Sing-box${PLAIN} 软件及其所有配置文件？"
    read -p "请输入 (y/N): " uninstall_sb
    if [[ "$uninstall_sb" == "y" || "$uninstall_sb" == "Y" ]]; then
        do_uninstall_singbox
    else
        log_info "已保留 Sing-box 软件及配置。"
    fi

    # 2. 询问是否删除脚本自身
    echo -e "\n是否删除 ${BLUE}本管理脚本 ($SCRIPT_NAME)${PLAIN} 及清理缓存文件？"
    read -p "请输入 (y/N): " uninstall_self
    if [[ "$uninstall_self" == "y" || "$uninstall_self" == "Y" ]]; then
        # 安全检查：确保变量不为空且路径正确
        if [[ -n "$INSTALL_PATH" && "$INSTALL_PATH" == "/usr/local/bin/sm.sh" ]]; then
            rm -f "$INSTALL_PATH"
            log_info "脚本文件已删除: $INSTALL_PATH"
        fi
        
        if [[ -n "$TMP_DIR" && "$TMP_DIR" == "/tmp/sm_manager_tmp" ]]; then
            rm -rf "$TMP_DIR"
            log_info "临时缓存已清理: $TMP_DIR"
        fi
        
        echo -e "${GREEN}卸载完成。再见！${PLAIN}"
        exit 0
    else
        log_info "取消卸载脚本。"
    fi
}

# ==================== 主菜单 ====================
show_menu() {
    clear
    local version=$(get_sb_version)
    local status=$(get_sb_status)
    local uptime=$(uptime -p | sed 's/up //')
    
    echo -e "┌──────────────────────────────────────────────┐"
    echo -e "│             ${BLUE}Sing-box 管理脚本${PLAIN}                │"
    echo -e "│             ${YELLOW}Debian/Ubuntu 专用${PLAIN}               │"
    echo -e "└──────────────────────────────────────────────┘"
    echo -e " 系统运行时间: ${uptime}"
    echo -e " Sing-box版本: ${BLUE}${version}${PLAIN}"
    echo -e " 运行状态    : ${status}"
    echo -e "────────────────────────────────────────────────"
    echo -e "  ${GREEN}1.${PLAIN} 安装 / 更新 Sing-box"
    echo -e "  ${GREEN}2.${PLAIN} 管理 Sing-box 服务 (启动/停止/日志)"
    echo -e "  ${GREEN}3.${PLAIN} 更新配置文件 (使用默认链接)"
    echo -e "  ${GREEN}4.${PLAIN} 更新配置文件 (输入自定义链接)"
    echo -e "  ${GREEN}5.${PLAIN} 修改默认配置下载链接"
    echo -e "────────────────────────────────────────────────"
    echo -e "  ${GREEN}6.${PLAIN} 安装 UFW 防火墙 (安全推荐)"
    echo -e "  ${GREEN}7.${PLAIN} 系统 TCP 网络优化"
    echo -e "  ${GREEN}8.${PLAIN} 卸载脚本 (可选卸载 Sing-box)"
    echo -e "  ${GREEN}0.${PLAIN} 退出"
    echo -e "────────────────────────────────────────────────"
    echo -e " 快捷指令: 输入 ${GREEN}${SCRIPT_NAME}${PLAIN} 即可再次调出此菜单"
    echo
}

main() {
    check_root
    check_os
    install_dependencies
    self_install_and_cleanup "$@"
    
    while true; do
        show_menu
        read -p " 请输入选项 [0-8]: " opt
        case "$opt" in
            1) install_singbox ;;
            2) manage_service_menu ;;
            3) update_config "$DEFAULT_CONFIG_URL" ;;
            4) 
                read -p "请输入配置链接: " custom_url
                [[ -n "$custom_url" ]] && update_config "$custom_url"
                ;;
            5) set_default_config_url ;;
            6) run_ufw_script ;;
            7) run_tcp_script ;;
            8) uninstall_script ;;
            0) exit 0 ;;
            *) log_err "无效选项，请重新输入" ;;
        esac
        read -n 1 -s -r -p "按任意键返回菜单..."
    done
}

# 捕获退出信号，清理临时文件
trap 'rm -rf "$TMP_DIR"; exit' INT TERM

main "$@"
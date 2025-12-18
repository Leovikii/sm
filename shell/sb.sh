#!/bin/bash

# ==================== 用户配置 ====================
DEFAULT_CONF_URL=""

# ==================== 全局变量 ====================
SCRIPT_NAME="sb.sh"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"
# 脚本更新地址
SCRIPT_URL="https://raw.githubusercontent.com/Leovikii/sm/main/shell/sb.sh"

BIN_PATH="/usr/local/bin/sing-box"
CONF_DIR="/etc/sing-box"
CONF_FILE="$CONF_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/sing-box.service"

REPO="SagerNet/sing-box"
TMP_DIR="/tmp/sb_tmp_$$"

# 镜像池
MIRRORS=(
    "https://ghproxy.net/"
    "https://mirror.ghproxy.com/"
    "https://fastgh.yzu.edu.cn/"
    "https://github.moeyy.xyz/"
    "" 
)

# 颜色
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[36m'
PLAIN='\033[0m'

# ==================== 基础工具 ====================

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT SIGINT SIGTERM

_log() { echo -e "${GREEN}[INFO]${PLAIN} $*"; }
_warn() { echo -e "${YELLOW}[WARN]${PLAIN} $*"; }
_err() { echo -e "${RED}[ERROR]${PLAIN} $*"; }
_fatal() { _err "$*"; exit 1; }

check_root() { [[ $EUID -ne 0 ]] && _fatal "请使用 sudo 或 root 运行"; }

install_self() {
    local current_path=$(readlink -f "$0")
    if [[ "$current_path" == "$INSTALL_PATH" ]]; then return; fi
    cp -f "$current_path" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    rm -f "$current_path"
    _log "脚本安装完成，正在重启..."
    sleep 1
    exec "$INSTALL_PATH" "$@"
}

check_deps() {
    local deps="curl wget tar jq file"
    local missing=""
    for dep in $deps; do
        if ! command -v "$dep" &>/dev/null; then missing="$missing $dep"; fi
    done
    if [[ -n "$missing" ]]; then
        _warn "缺少依赖:$missing，自动安装..."
        if command -v apt-get &>/dev/null; then
            apt-get update -q && apt-get install -y $missing
        elif command -v yum &>/dev/null; then
            yum install -y $missing
        else
            _fatal "请手动安装: $missing"
        fi
    fi
}

get_sys_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64) echo "amd64" ;;
        aarch64|armv8) echo "arm64" ;;
        armv7*) echo "armv7" ;;
        s390x) echo "s390x" ;;
        *) echo "unknown" ;;
    esac
}

# ==================== 核心功能模块 ====================

# 鲁棒下载函数
download_file_robust() {
    local raw_url="$1"
    local save_path="$2"
    local success=false

    for mirror in "${MIRRORS[@]}"; do
        local final_url="${mirror}${raw_url}"
        local mirror_name="${mirror:-[官方直连]}"
        
        _log "尝试下载通道: ${BLUE}${mirror_name}${PLAIN}"
        
        if command -v curl &>/dev/null; then
            curl -k -L -f --retry 2 --connect-timeout 10 --max-time 120 -o "$save_path" "$final_url"
        else
            wget --no-check-certificate -T 15 -t 2 -O "$save_path" "$final_url"
        fi

        if [[ -s "$save_path" ]]; then
            # 文件校验
            if [[ "$save_path" == *".tar.gz" ]]; then
                if file -b "$save_path" | grep -q "gzip compressed data"; then
                    success=true; break
                else
                    _warn "非 gzip 格式，尝试下一个..."
                fi
            elif [[ "$save_path" == *".json" ]]; then
                 if grep -q "{" "$save_path"; then success=true; break; fi
                 _warn "非 JSON 格式，尝试下一个..."
            elif [[ "$save_path" == *".sh" ]]; then
                 if grep -qE "^#!" "$save_path" || grep -q "bash" "$save_path"; then 
                    success=true; break
                 fi
                 _warn "非脚本文件，尝试下一个..."
            else
                success=true; break
            fi
        fi
        rm -f "$save_path"
    done

    if [[ "$success" == "true" ]]; then return 0; else return 1; fi
}

get_latest_tag() {
    local mirror="https://mirror.ghproxy.com/"
    local url="${mirror}https://github.com/${REPO}/releases/latest"
    local final_url=$(curl -k -Ls -o /dev/null -w %{url_effective} --connect-timeout 5 "$url")
    local tag=$(echo "$final_url" | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$")
    if [[ -n "$tag" ]]; then echo "$tag"; return 0; fi
    return 1
}

# 获取本地已安装版本
get_installed_ver() {
    if [[ -f "$BIN_PATH" ]]; then
        $BIN_PATH version 2>/dev/null | head -n 1 | awk '{print $3}'
    else
        echo ""
    fi
}

# 安装逻辑主函数
download_and_install() {
    check_deps
    
    # === [新增功能 1] 检测本地文件 ===
    if [[ -f "./sing-box" ]]; then
        echo -e "${YELLOW}检测到当前目录下存在 sing-box 二进制文件。${PLAIN}"
        read -p "是否直接安装此本地文件? [Y/n] " install_local
        if [[ "$install_local" != "n" && "$install_local" != "N" ]]; then
            chmod +x "./sing-box"
            # 简单验证文件是否可执行
            if ./sing-box version >/dev/null 2>&1; then
                _log "本地文件校验通过，正在安装..."
                systemctl stop sing-box 2>/dev/null
                cp -f "./sing-box" "$BIN_PATH"
                chmod +x "$BIN_PATH"
                
                local v=$($BIN_PATH version 2>/dev/null | head -n 1 | awk '{print $3}')
                _log "安装完成！当前版本: ${GREEN}${v}${PLAIN}"
                setup_service
                return
            else
                _err "本地 sing-box 文件无法运行，将转为在线下载模式。"
            fi
        fi
    fi

    # === [新增功能 2] 检测已安装版本并提示升级 ===
    local current_ver=$(get_installed_ver)
    
    _log "正在查找最新版本信息..."
    local tag_version=$(get_latest_tag)
    
    # 兜底
    if [[ -z "$tag_version" ]]; then
        _warn "自动检测版本失败，默认目标版本: v1.12.13"
        tag_version="v1.12.13"
    fi

    if [[ -n "$current_ver" ]]; then
        echo -e "------------------------------------"
        echo -e "当前已安装版本: ${RED}${current_ver}${PLAIN}"
        echo -e "检测到最新版本: ${GREEN}${tag_version}${PLAIN}"
        echo -e "------------------------------------"
        read -p "是否进行更新/重装? [Y/n] " update_confirm
        if [[ "$update_confirm" == "n" || "$update_confirm" == "N" ]]; then
            _log "已取消更新。"
            return
        fi
    fi

    # === 开始下载流程 ===
    mkdir -p "$TMP_DIR"
    local arch=$(get_sys_arch)
    [[ "$arch" == "unknown" ]] && _fatal "不支持的架构: $(uname -m)"

    local ver_num="${tag_version#v}" 
    local filename="sing-box-${ver_num}-linux-${arch}.tar.gz"
    local raw_url="https://github.com/${REPO}/releases/download/${tag_version}/${filename}"
    local tmp_file="$TMP_DIR/$filename"

    _log "目标版本: ${GREEN}${tag_version}${PLAIN} (${arch})"

    if download_file_robust "$raw_url" "$tmp_file"; then
        _log "下载成功，校验通过！"
    else
        _fatal "下载失败，请检查网络。"
    fi

    _log "正在安装..."
    tar -zxf "$tmp_file" -C "$TMP_DIR" || _fatal "解压失败"
    local bin_src=$(find "$TMP_DIR" -name "sing-box" -type f | head -n 1)
    [[ -z "$bin_src" ]] && _fatal "未找到二进制文件"

    systemctl stop sing-box 2>/dev/null
    cp -f "$bin_src" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -rf "$TMP_DIR"/*

    local installed_ver=$(get_installed_ver)
    _log "安装完成！当前版本: ${GREEN}$installed_ver${PLAIN}"
    setup_service
}

setup_service() {
    if [[ ! -f "$SERVICE_FILE" ]]; then
        _log "配置 Systemd 服务..."
        cat > $SERVICE_FILE <<EOF
[Unit]
Description=sing-box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=$BIN_PATH run -c $CONF_FILE
Restart=on-failure
RestartSec=10
LimitNPROC=512
LimitNOFILE=infinity
CacheDirectory=sing-box
LogsDirectory=sing-box
RuntimeDirectory=sing-box

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable sing-box >/dev/null 2>&1
    fi
    mkdir -p "$CONF_DIR"
}

update_config() {
    check_deps
    mkdir -p "$TMP_DIR"
    local url=""

    echo -e "当前配置文件: ${BLUE}$CONF_FILE${PLAIN}"
    if [[ -n "$DEFAULT_CONF_URL" ]]; then
        echo -e "默认地址: ${BLUE}$DEFAULT_CONF_URL${PLAIN}"
        read -p "使用默认地址? [Y/n] " choice
        [[ "$choice" != "n" && "$choice" != "N" ]] && url="$DEFAULT_CONF_URL"
    fi

    if [[ -z "$url" ]]; then read -p "请输入配置 URL: " url; fi
    [[ -z "$url" ]] && return

    local target_url="$url"
    if [[ "$url" == *"github.com"* ]]; then
        for m in "${MIRRORS[@]}"; do [[ -n "$m" ]] && target_url="${target_url#$m}"; done
    fi

    local tmp_conf="$TMP_DIR/config.json"
    if ! download_file_robust "$target_url" "$tmp_conf"; then
        curl -k -L -o "$tmp_conf" "$url" || { _err "下载失败"; return; }
    fi

    if command -v jq &>/dev/null; then
        if ! jq -e . "$tmp_conf" >/dev/null 2>&1; then
            _err "JSON 格式无效，取消更新"; return
        fi
    fi

    mv "$tmp_conf" "$CONF_FILE"
    rm -f "$tmp_conf"
    _log "配置已更新"

    if [[ "$url" != "$DEFAULT_CONF_URL" ]]; then
        read -p "保存为默认地址? [Y/n] " save
        if [[ "$save" != "n" ]]; then
             sed -i "s#^DEFAULT_CONF_URL=.*#DEFAULT_CONF_URL=\"$url\"#" "$INSTALL_PATH"
             DEFAULT_CONF_URL="$url"
        fi
    fi
    systemctl restart sing-box
    _log "服务已重启"
}

# ==================== 菜单管理 ====================

update_script() {
    _log "正在检查脚本更新..."
    mkdir -p "$TMP_DIR"
    local tmp_script="$TMP_DIR/new_sb.sh"
    
    if download_file_robust "$SCRIPT_URL" "$tmp_script"; then
        if ! grep -q "#!/bin/bash" "$tmp_script"; then
            _err "文件校验失败，取消更新。"; return
        fi
        local old_url=$(grep "^DEFAULT_CONF_URL=" "$INSTALL_PATH" | cut -d'"' -f2)
        [[ -n "$old_url" ]] && sed -i "s#^DEFAULT_CONF_URL=.*#DEFAULT_CONF_URL=\"$old_url\"#" "$tmp_script"
        
        mv "$tmp_script" "$INSTALL_PATH"
        chmod +x "$INSTALL_PATH"
        _log "更新成功，正在重启..."
        sleep 1
        exec "$INSTALL_PATH" "script_manager"
    else
        _err "更新失败，连接超时。"
    fi
}

uninstall_script() {
    echo -e "${RED}警告：此操作将卸载脚本。${PLAIN}"
    read -p "是否同时卸载 Sing-box 服务 (删除程序/配置/服务)? [y/N] " del_sb
    if [[ "$del_sb" =~ ^[yY] ]]; then
        systemctl stop sing-box 2>/dev/null
        systemctl disable sing-box 2>/dev/null
        rm -f "$SERVICE_FILE" "$BIN_PATH"
        rm -rf "$CONF_DIR"
        systemctl daemon-reload
        _log "Sing-box 已卸载。"
    fi
    rm -f "$INSTALL_PATH"
    _log "脚本已卸载。"
    exit 0
}

script_manager_menu() {
    while true; do
        clear
        echo -e "${BLUE}┌──────── Script Management ─────────┐${PLAIN}"
        echo -e "${BLUE}│${PLAIN}          ${GREEN}脚本维护与管理${PLAIN}            ${BLUE}│${PLAIN}"
        echo -e "${BLUE}└────────────────────────────────────┘${PLAIN}"
        echo -e "
 ${GREEN}1.${PLAIN} 更新脚本 (Update Script)
 ${GREEN}2.${PLAIN} 卸载脚本 (Uninstall)
 ------------------------
 ${GREEN}0.${PLAIN} 返回主菜单
"
        read -p " 请选择: " choice
        case "$choice" in
            1) update_script; break ;; 
            2) uninstall_script ;;
            0) break ;;
            *) ;;
        esac
        read -p " 按回车继续..."
    done
}

service_manager_menu() {
    while true; do
        clear
        echo -e "${BLUE}┌──────── Service Management ────────┐${PLAIN}"
        echo -e "${BLUE}│${PLAIN}        ${GREEN}Sing-box 服务管理${PLAIN}           ${BLUE}│${PLAIN}"
        echo -e "${BLUE}└────────────────────────────────────┘${PLAIN}"
        
        if systemctl is-active --quiet sing-box; then echo -e " 状态: ${GREEN}运行中${PLAIN}"; else echo -e " 状态: ${RED}未运行${PLAIN}"; fi
        
        echo -e "
 ${GREEN}1.${PLAIN} 启动服务
 ${GREEN}2.${PLAIN} 停止服务
 ${GREEN}3.${PLAIN} 重启服务
 ------------------------
 ${GREEN}4.${PLAIN} 启用开机自启
 ${GREEN}5.${PLAIN} 禁用开机自启
 ------------------------
 ${GREEN}6.${PLAIN} 查看最后日志
 ${GREEN}7.${PLAIN} 实时滚动日志
 ------------------------
 ${GREEN}0.${PLAIN} 返回主菜单
"
        read -p " 请选择: " choice
        case "$choice" in
            1) systemctl start sing-box && _log "已启动" ;;
            2) systemctl stop sing-box && _log "已停止" ;;
            3) systemctl restart sing-box && _log "已重启" ;;
            4) systemctl enable sing-box && _log "已启用开机自启" ;;
            5) systemctl disable sing-box && _log "已禁用开机自启" ;;
            6) journalctl -u sing-box -n 20 --no-pager ;;
            7) echo -e "${YELLOW}按 Ctrl+C 退出...${PLAIN}"; sleep 1; journalctl -u sing-box -f --output cat ;;
            0) break ;;
            *) ;;
        esac
        [[ "$choice" != "7" && "$choice" != "0" ]] && read -p " 按回车继续..."
    done
}

show_menu() {
    check_deps
    local arch=$(uname -m)
    local ver=$(get_installed_ver)
    [[ -z "$ver" ]] && ver="未安装"
    [[ -f "$BIN_PATH" ]] && status_text="${GREEN}运行中${PLAIN}" || status_text="${RED}未运行${PLAIN}"
    if ! systemctl is-active --quiet sing-box; then status_text="${RED}未运行${PLAIN}"; fi

    while true; do
        clear
        echo -e "
${BLUE}┌──────────────────────────────────────────────┐${PLAIN}
${BLUE}│${PLAIN}           ${GREEN}Sing-box 管理面板 v8.0${PLAIN}             ${BLUE}│${PLAIN}
${BLUE}├──────────────────────────────────────────────┤${PLAIN}
${BLUE}│${PLAIN} 架构: ${arch}
${BLUE}│${PLAIN} 版本: ${GREEN}${ver}${PLAIN}
${BLUE}│${PLAIN} 状态: ${status_text}
${BLUE}└──────────────────────────────────────────────┘${PLAIN}"

        echo -e "
 ${GREEN}1.${PLAIN} 安装/升级 Sing-box
 ${GREEN}2.${PLAIN} 更新配置文件
 ----------------------------------
 ${GREEN}3.${PLAIN} [服务管理] (启停/自启/日志) >
 ${GREEN}4.${PLAIN} [脚本管理] (更新/卸载脚本) >
 ----------------------------------
 ${GREEN}0.${PLAIN} 退出
"
        read -p " 请选择: " choice
        case "$choice" in
            1) download_and_install && break ;;
            2) update_config ;;
            3) service_manager_menu ;;
            4) script_manager_menu ;;
            0) exit 0 ;;
            *) ;;
        esac
        echo ""; read -p " 按回车返回..." 
    done
    show_menu
}

main() {
    check_root
    install_self "$@"
    if [[ -n "$1" ]]; then
        case "$1" in
            script_manager) script_manager_menu ;;
            install) download_and_install ;;
            start) systemctl start sing-box ;;
            stop) systemctl stop sing-box ;;
            restart) systemctl restart sing-box ;;
            log) journalctl -u sing-box -f ;;
            *) show_menu ;;
        esac
    else
        show_menu
    fi
}

main "$@"
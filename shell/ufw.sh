#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_NAME="ufw.sh"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"
GITHUB_URL="https://raw.githubusercontent.com/Leovikii/sm/main/shell/ufw.sh"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 请使用root权限运行此脚本${NC}"
        exit 1
    fi
}

first_run_install() {
    local current_script="$(readlink -f "$0")"
    
    if [ "$current_script" != "$INSTALL_PATH" ]; then
        echo -e "${BLUE}检测到首次运行，正在安装快捷方式...${NC}"
        cp -f "$current_script" "$INSTALL_PATH"
        chmod +x "$INSTALL_PATH"
        
        if [ "$current_script" != "$INSTALL_PATH" ]; then
            rm -f "$current_script"
        fi
        
        echo -e "${GREEN}✓ 安装完成！${NC}"
        echo -e "${GREEN}现在可以在任何位置使用 '${SCRIPT_NAME}' 命令启动脚本${NC}"
        echo ""
        sleep 2
        exec "$INSTALL_PATH" "$@"
    fi
}

print_header() {
    clear
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}    Debian UFW 管理脚本${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
}

check_ufw_installed() {
    command -v ufw &> /dev/null
}

install_ufw() {
    print_header
    
    if check_ufw_installed; then
        echo -e "${YELLOW}UFW已经安装，正在检查更新...${NC}"
        apt-get update -y >/dev/null 2>&1
        
        if apt list --upgradable 2>/dev/null | grep -q "ufw"; then
            echo -e "${YELLOW}发现UFW更新${NC}"
            read -r -p "是否更新UFW? (y/N): " update_choice
            if [[ "$update_choice" == "y" || "$update_choice" == "Y" ]]; then
                apt-get upgrade -y ufw >/dev/null 2>&1
                echo -e "${GREEN}✓ UFW更新完成${NC}"
            else
                echo -e "${YELLOW}跳过更新${NC}"
            fi
        else
            echo -e "${GREEN}✓ UFW已是最新版本${NC}"
        fi
    else
        echo -e "${BLUE}正在安装UFW...${NC}"
        apt-get update -y >/dev/null 2>&1
        
        if apt-get install -y ufw >/dev/null 2>&1; then
            echo -e "${GREEN}✓ UFW安装成功${NC}\n"
            echo -e "${YELLOW}⚠ 自动放行常用端口以防止服务中断（IPv4/IPv6双栈）${NC}"
            
            ufw allow 22/tcp comment 'SSH TCP' >/dev/null
            ufw allow 22/udp comment 'SSH UDP' >/dev/null
            echo -e "${GREEN}✓ 已放行 22/tcp 和 22/udp (SSH)${NC}"
            
            ufw allow 80/tcp comment 'HTTP TCP' >/dev/null
            ufw allow 80/udp comment 'HTTP UDP' >/dev/null
            echo -e "${GREEN}✓ 已放行 80/tcp 和 80/udp (HTTP)${NC}"
            
            ufw allow 443/tcp comment 'HTTPS TCP' >/dev/null
            ufw allow 443/udp comment 'HTTPS UDP' >/dev/null
            echo -e "${GREEN}✓ 已放行 443/tcp 和 443/udp (HTTPS)${NC}"
            
            echo -e "${BLUE}注: UFW默认为每个规则创建IPv4和IPv6双栈规则${NC}\n"
            echo -e "${BLUE}正在启用UFW...${NC}"
            
            if echo "y" | ufw enable >/dev/null 2>&1; then
                echo -e "${GREEN}✓ UFW已自动启用${NC}"
            else
                echo -e "${RED}✗ UFW启用失败${NC}"
            fi
        else
            echo -e "${RED}✗ UFW安装失败${NC}"
        fi
    fi
    echo ""
    read -n 1 -s -r -p "按任意键继续..."
}

enable_ufw() {
    print_header
    if ! check_ufw_installed; then
        echo -e "${RED}✗ UFW未安装，请先安装UFW${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    echo -e "${BLUE}正在启用UFW...${NC}"
    if echo "y" | ufw enable >/dev/null 2>&1; then
        echo -e "${GREEN}✓ UFW已启用${NC}"
    else
        echo -e "${RED}✗ UFW启用失败${NC}"
    fi
    echo ""
    read -n 1 -s -r -p "按任意键继续..."
}

disable_ufw() {
    print_header
    if ! check_ufw_installed; then
        echo -e "${RED}✗ UFW未安装${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    echo -e "${BLUE}正在禁用UFW...${NC}"
    if ufw disable >/dev/null 2>&1; then
        echo -e "${GREEN}✓ UFW已禁用${NC}"
    else
        echo -e "${RED}✗ UFW禁用失败${NC}"
    fi
    echo ""
    read -n 1 -s -r -p "按任意键继续..."
}

restart_ufw() {
    print_header
    if ! check_ufw_installed; then
        echo -e "${RED}✗ UFW未安装${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    echo -e "${BLUE}正在重启UFW...${NC}"
    if ufw reload >/dev/null 2>&1; then
        echo -e "${GREEN}✓ UFW已重启${NC}"
    else
        echo -e "${RED}✗ UFW重启失败${NC}"
    fi
    echo ""
    read -n 1 -s -r -p "按任意键继续..."
}

uninstall_ufw() {
    print_header
    if ! check_ufw_installed; then
        echo -e "${YELLOW}UFW未安装${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    echo -e "${RED}警告: 即将卸载UFW及其所有配置${NC}"
    read -r -p "确认卸载? (y/N): " confirm
    
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo -e "${BLUE}正在卸载UFW...${NC}"
        ufw disable >/dev/null 2>&1
        apt-get remove --purge -y ufw >/dev/null 2>&1
        apt-get autoremove -y >/dev/null 2>&1
        rm -rf /etc/ufw /lib/ufw /var/lib/ufw
        echo -e "${GREEN}✓ UFW已完全卸载${NC}"
    else
        echo -e "${YELLOW}取消卸载${NC}"
    fi
    echo ""
    read -n 1 -s -r -p "按任意键继续..."
}

ufw_management_menu() {
    while true; do
        print_header
        echo -e "${GREEN}UFW管理${NC}\n"
        echo "1) 安装UFW"
        echo "2) 启用UFW"
        echo "3) 禁用UFW"
        echo "4) 重启UFW"
        echo "5) 卸载UFW"
        echo "0) 返回主菜单"
        echo ""
        read -r -p "请选择操作 [0-5]: " choice
        
        case $choice in
            1) install_ufw ;;
            2) enable_ufw ;;
            3) disable_ufw ;;
            4) restart_ufw ;;
            5) uninstall_ufw ;;
            0) return ;;
            *) echo -e "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

add_rule() {
    print_header
    if ! check_ufw_installed; then
        echo -e "${RED}✗ UFW未安装，请先安装UFW${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    echo -e "${GREEN}添加UFW规则${NC}\n"
    echo -e "${YELLOW}示例: 2222/tcp 或 8080/udp${NC}"
    echo -e "${BLUE}注: 规则会自动应用于IPv4和IPv6双栈${NC}\n"
    read -r -p "请输入端口/协议 (如 2222/tcp): " input
    
    if [[ ! "$input" =~ ^([0-9]+)/(tcp|udp)$ ]]; then
        echo -e "${RED}✗ 格式错误，请使用 端口/协议 格式${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    port="${BASH_REMATCH[1]}"
    protocol="${BASH_REMATCH[2]}"
    
    echo -e "\n${BLUE}准备添加规则: ${port}/${protocol} (IPv4/IPv6双栈)${NC}"
    
    local other_protocol="udp"
    if [ "$protocol" == "udp" ]; then
        other_protocol="tcp"
    fi
    
    read -r -p "是否同时放行 ${port}/${other_protocol}? (y/N): " add_both
    
    if ufw allow "${port}/${protocol}" comment "Port ${port}/${protocol}" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 已添加规则: ${port}/${protocol} (包含IPv4和IPv6)${NC}"
    else
        echo -e "${RED}✗ 添加规则失败${NC}"
    fi
    
    if [[ "$add_both" == "y" || "$add_both" == "Y" ]]; then
        if ufw allow "${port}/${other_protocol}" comment "Port ${port}/${other_protocol}" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ 已添加规则: ${port}/${other_protocol} (包含IPv4和IPv6)${NC}"
        else
            echo -e "${RED}✗ 添加规则失败${NC}"
        fi
    fi
    echo ""
    read -n 1 -s -r -p "按任意键继续..."
}

delete_rule() {
    print_header
    if ! check_ufw_installed; then
        echo -e "${RED}✗ UFW未安装${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    echo -e "${GREEN}删除UFW规则${NC}\n"
    echo -e "${BLUE}当前防火墙规则：${NC}"
    ufw status numbered
    
    if ! ufw status numbered | grep -q "^\["; then
        echo -e "${YELLOW}当前没有任何规则${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    echo -e "\n${YELLOW}提示: UFW会为每个端口自动创建IPv4和IPv6规则${NC}"
    echo -e "${YELLOW}      选择任意一条，脚本将智能删除该端口的所有相关规则${NC}\n"
    read -r -p "请输入要删除的规则编号 (0取消): " rule_num
    
    if [[ ! "$rule_num" =~ ^[0-9]+$ ]] || [ "$rule_num" == "0" ]; then
        echo -e "${YELLOW}取消删除${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    local rules_raw=$(ufw status numbered 2>/dev/null)
    local rule_info=$(echo "$rules_raw" | grep "^\[ *$rule_num\]" | sed 's/\x1b\[[0-9;]*m//g')
    
    if [ -z "$rule_info" ]; then
        echo -e "${RED}✗ 无效的规则编号${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    echo -e "\n${BLUE}已选择规则: $rule_info${NC}"
    
    local target_def=$(echo "$rule_info" | awk '{print $2}')
    local port=$(echo "$target_def" | cut -d'/' -f1)
    local protocol=$(echo "$target_def" | cut -d'/' -f2)
    
    if [[ -z "$port" || -z "$protocol" || "$port" == "$target_def" ]]; then
        echo -e "${RED}✗ 无法解析规则信息，该规则可能不是标准的 端口/协议 格式${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    local other_protocol="udp"
    if [ "$protocol" == "udp" ]; then
        other_protocol="tcp"
    fi
    
    local delete_other_protocol="n"
    if echo "$rules_raw" | grep -q "${port}/${other_protocol}"; then
        echo ""
        read -r -p "检测到 ${port}/${other_protocol} 规则，是否一并删除? (y/N): " delete_other_protocol
    fi
    
    local rules_to_delete=()
    echo -e "\n${BLUE}正在查找所有相关规则...${NC}"
    
    while IFS= read -r line; do
        if echo "$line" | grep -q -w "${port}/${protocol}"; then
            local num=$(echo "$line" | sed 's/^\[ *\([0-9]\+\)\].*/\1/')
            if [ -n "$num" ]; then
                rules_to_delete+=($num)
                echo "  - 规则 $num: $(echo "$line" | sed 's/^\[[^]]*\] *//' | sed 's/\x1b\[[0-9;]*m//g')"
            fi
        fi
    done < <(echo "$rules_raw" | grep "^\[")
    
    if [[ "$delete_other_protocol" == "y" || "$delete_other_protocol" == "Y" ]]; then
        while IFS= read -r line; do
            if echo "$line" | grep -q -w "${port}/${other_protocol}"; then
                local num=$(echo "$line" | sed 's/^\[ *\([0-9]\+\)\].*/\1/')
                if [ -n "$num" ]; then
                    rules_to_delete+=($num)
                    echo "  - 规则 $num: $(echo "$line" | sed 's/^\[[^]]*\] *//' | sed 's/\x1b\[[0-9;]*m//g')"
                fi
            fi
        done < <(echo "$rules_raw" | grep "^\[")
    fi
    
    rules_to_delete=($(printf '%s\n' "${rules_to_delete[@]}" | sort -rn -u))
    
    if [ ${#rules_to_delete[@]} -eq 0 ]; then
        echo -e "${RED}✗ 未找到匹配的规则${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    echo -e "\n${YELLOW}总共将删除 ${#rules_to_delete[@]} 条规则 (编号: ${rules_to_delete[*]})${NC}"
    read -r -p "确认删除? (y/N): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}取消删除${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    echo -e "\n${BLUE}正在删除规则...${NC}"
    for num in "${rules_to_delete[@]}"; do
        if echo "y" | ufw delete $num > /dev/null 2>&1; then
            echo -e "${GREEN}  ✓ 已删除规则 $num${NC}"
        else
            echo -e "${RED}  ✗ 删除规则 $num 失败${NC}"
        fi
    done
    
    echo -e "\n${GREEN}✓ 删除完成${NC}"
    echo -e "\n${BLUE}更新后的规则列表：${NC}"
    ufw status numbered
    echo ""
    read -n 1 -s -r -p "按任意键继续..."
}

rule_management_menu() {
    while true; do
        print_header
        echo -e "${GREEN}UFW规则管理${NC}\n"
        echo "1) 添加规则"
        echo "2) 删除规则"
        echo "0) 返回主菜单"
        echo ""
        read -r -p "请选择操作 [0-2]: " choice
        
        case $choice in
            1) add_rule ;;
            2) delete_rule ;;
            0) return ;;
            *) echo -e "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

update_script() {
    print_header
    echo -e "${BLUE}正在从GitHub下载最新版本...${NC}\n"
    
    local temp_file="/tmp/ufw_update_$$.sh"
    local dl_success=false

    if command -v curl &>/dev/null; then
        if curl -k -f -L --retry 3 --connect-timeout 10 -s -o "$temp_file" "$GITHUB_URL"; then
            dl_success=true
        fi
    else
        if wget --no-check-certificate -q -T 15 -t 3 -O "$temp_file" "$GITHUB_URL"; then
            dl_success=true
        fi
    fi
    
    if [[ "$dl_success" == true && -s "$temp_file" ]]; then
        chmod +x "$temp_file"
        mv -f "$temp_file" "$INSTALL_PATH"
        echo -e "${GREEN}✓ 脚本更新成功${NC}"
        echo -e "${YELLOW}重新启动脚本以应用更新...${NC}"
        sleep 2
        exec "$INSTALL_PATH" "$@"
    else
        echo -e "${RED}✗ 下载失败，请检查网络连接${NC}"
        rm -f "$temp_file"
    fi
    echo ""
    read -n 1 -s -r -p "按任意键继续..."
}

uninstall_script() {
    print_header
    echo -e "${RED}警告: 即将卸载UFW管理脚本${NC}"
    read -r -p "确认卸载脚本? (y/N): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}取消卸载${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    if check_ufw_installed; then
        echo ""
        read -r -p "是否同时卸载UFW? (y/N): " uninstall_ufw_choice
        
        if [[ "$uninstall_ufw_choice" == "y" || "$uninstall_ufw_choice" == "Y" ]]; then
            echo -e "${BLUE}正在卸载UFW...${NC}"
            ufw disable >/dev/null 2>&1
            apt-get remove --purge -y ufw >/dev/null 2>&1
            apt-get autoremove -y >/dev/null 2>&1
            rm -rf /etc/ufw /lib/ufw /var/lib/ufw
            echo -e "${GREEN}✓ UFW已卸载${NC}"
        fi
    fi
    
    echo -e "${BLUE}正在删除脚本文件...${NC}"
    rm -f "$INSTALL_PATH"
    echo -e "${GREEN}✓ 脚本已完全卸载${NC}\n"
    exit 0
}

script_management_menu() {
    while true; do
        print_header
        echo -e "${GREEN}脚本管理${NC}\n"
        echo "1) 更新脚本"
        echo "2) 卸载脚本"
        echo "0) 返回主菜单"
        echo ""
        read -r -p "请选择操作 [0-2]: " choice
        
        case $choice in
            1) update_script ;;
            2) uninstall_script ;;
            0) return ;;
            *) echo -e "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

main_menu() {
    while true; do
        print_header
        
        if check_ufw_installed; then
            if ufw status | grep -qwE "active|激活|运行中"; then
                echo -e "UFW状态: ${GREEN}已启用${NC}"
            else
                echo -e "UFW状态: ${YELLOW}未启用${NC}"
            fi
        else
            echo -e "UFW状态: ${RED}未安装${NC}"
        fi
        
        echo ""
        echo "1) 管理UFW"
        echo "2) UFW规则管理"
        echo "3) 脚本管理"
        echo "0) 退出"
        echo ""
        read -r -p "请选择操作 [0-3]: " choice
        
        case $choice in
            1) ufw_management_menu ;;
            2) rule_management_menu ;;
            3) script_management_menu ;;
            0) 
                echo -e "${GREEN}感谢使用！${NC}"
                exit 0
                ;;
            *) 
                echo -e "${RED}无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

main() {
    check_root
    first_run_install "$@"
    main_menu
}

main "$@"
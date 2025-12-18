#!/bin/bash

# UFW管理脚本
# 版本: 1.0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本路径
SCRIPT_NAME="ufw.sh"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"
GITHUB_URL="https://raw.githubusercontent.com/Leovikii/sm/main/shell/ufw.sh"

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 请使用root权限运行此脚本${NC}"
        exit 1
    fi
}

# 首次运行安装
first_run_install() {
    local current_script="$(readlink -f "$0")"
    
    # 如果脚本不在安装路径，则进行安装
    if [ "$current_script" != "$INSTALL_PATH" ]; then
        echo -e "${BLUE}检测到首次运行，正在安装快捷方式...${NC}"
        
        # 复制脚本到系统路径
        cp "$current_script" "$INSTALL_PATH"
        chmod +x "$INSTALL_PATH"
        
        # 删除原始脚本
        if [ "$current_script" != "$INSTALL_PATH" ]; then
            rm -f "$current_script"
        fi
        
        echo -e "${GREEN}✓ 安装完成！${NC}"
        echo -e "${GREEN}现在可以在任何位置使用 '${SCRIPT_NAME}' 命令启动脚本${NC}"
        echo ""
        sleep 2
        
        # 重新执行已安装的脚本
        exec "$INSTALL_PATH" "$@"
    fi
}

# 打印标题
print_header() {
    clear
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}    Debian UFW 管理脚本${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
}

# 检查UFW是否已安装
check_ufw_installed() {
    if command -v ufw &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# 安装UFW
install_ufw() {
    print_header
    
    if check_ufw_installed; then
        echo -e "${YELLOW}UFW已经安装，正在检查更新...${NC}"
        apt update
        
        if apt list --upgradable 2>/dev/null | grep -q "ufw"; then
            echo -e "${YELLOW}发现UFW更新${NC}"
            read -p "是否更新UFW? (y/n): " update_choice
            if [[ $update_choice == "y" || $update_choice == "Y" ]]; then
                apt upgrade -y ufw
                echo -e "${GREEN}✓ UFW更新完成${NC}"
            else
                echo -e "${YELLOW}跳过更新${NC}"
            fi
        else
            echo -e "${GREEN}✓ UFW已是最新版本${NC}"
        fi
    else
        echo -e "${BLUE}正在安装UFW...${NC}"
        apt update
        apt install -y ufw
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ UFW安装成功${NC}"
            echo ""
            echo -e "${YELLOW}⚠ 自动放行常用端口以防止服务中断（IPv4/IPv6双栈）${NC}"
            
            # 放行SSH端口 (22)
            ufw allow 22/tcp comment 'SSH TCP'
            ufw allow 22/udp comment 'SSH UDP'
            echo -e "${GREEN}✓ 已放行 22/tcp 和 22/udp (SSH)${NC}"
            
            # 放行HTTP端口 (80)
            ufw allow 80/tcp comment 'HTTP TCP'
            ufw allow 80/udp comment 'HTTP UDP'
            echo -e "${GREEN}✓ 已放行 80/tcp 和 80/udp (HTTP)${NC}"
            
            # 放行HTTPS端口 (443)
            ufw allow 443/tcp comment 'HTTPS TCP'
            ufw allow 443/udp comment 'HTTPS UDP'
            echo -e "${GREEN}✓ 已放行 443/tcp 和 443/udp (HTTPS)${NC}"
            
            echo -e "${BLUE}注: UFW默认为每个规则创建IPv4和IPv6双栈规则${NC}"
            
            echo ""
            echo -e "${BLUE}正在启用UFW...${NC}"
            echo "y" | ufw enable
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ UFW已自动启用${NC}"
            else
                echo -e "${RED}✗ UFW启用失败${NC}"
            fi
        else
            echo -e "${RED}✗ UFW安装失败${NC}"
        fi
    fi
    
    echo ""
    read -p "按Enter键继续..."
}

# 启用UFW
enable_ufw() {
    print_header
    
    if ! check_ufw_installed; then
        echo -e "${RED}✗ UFW未安装，请先安装UFW${NC}"
        read -p "按Enter键继续..."
        return
    fi
    
    echo -e "${BLUE}正在启用UFW...${NC}"
    echo "y" | ufw enable
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ UFW已启用${NC}"
    else
        echo -e "${RED}✗ UFW启用失败${NC}"
    fi
    
    echo ""
    read -p "按Enter键继续..."
}

# 禁用UFW
disable_ufw() {
    print_header
    
    if ! check_ufw_installed; then
        echo -e "${RED}✗ UFW未安装${NC}"
        read -p "按Enter键继续..."
        return
    fi
    
    echo -e "${BLUE}正在禁用UFW...${NC}"
    ufw disable
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ UFW已禁用${NC}"
    else
        echo -e "${RED}✗ UFW禁用失败${NC}"
    fi
    
    echo ""
    read -p "按Enter键继续..."
}

# 重启UFW
restart_ufw() {
    print_header
    
    if ! check_ufw_installed; then
        echo -e "${RED}✗ UFW未安装${NC}"
        read -p "按Enter键继续..."
        return
    fi
    
    echo -e "${BLUE}正在重启UFW...${NC}"
    ufw reload
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ UFW已重启${NC}"
    else
        echo -e "${RED}✗ UFW重启失败${NC}"
    fi
    
    echo ""
    read -p "按Enter键继续..."
}

# 卸载UFW
uninstall_ufw() {
    print_header
    
    if ! check_ufw_installed; then
        echo -e "${YELLOW}UFW未安装${NC}"
        read -p "按Enter键继续..."
        return
    fi
    
    echo -e "${RED}警告: 即将卸载UFW及其所有配置${NC}"
    read -p "确认卸载? (y/n): " confirm
    
    if [[ $confirm == "y" || $confirm == "Y" ]]; then
        echo -e "${BLUE}正在卸载UFW...${NC}"
        
        # 停止并禁用UFW
        ufw disable
        
        # 卸载UFW
        apt remove --purge -y ufw
        apt autoremove -y
        
        # 清理UFW配置文件
        rm -rf /etc/ufw
        rm -rf /lib/ufw
        rm -rf /var/lib/ufw
        
        echo -e "${GREEN}✓ UFW已完全卸载${NC}"
    else
        echo -e "${YELLOW}取消卸载${NC}"
    fi
    
    echo ""
    read -p "按Enter键继续..."
}

# UFW管理菜单
ufw_management_menu() {
    while true; do
        print_header
        echo -e "${GREEN}UFW管理${NC}"
        echo ""
        echo "1) 安装UFW"
        echo "2) 启用UFW"
        echo "3) 禁用UFW"
        echo "4) 重启UFW"
        echo "5) 卸载UFW"
        echo "0) 返回主菜单"
        echo ""
        read -p "请选择操作 [0-5]: " choice
        
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

# 添加规则
add_rule() {
    print_header
    
    if ! check_ufw_installed; then
        echo -e "${RED}✗ UFW未安装，请先安装UFW${NC}"
        read -p "按Enter键继续..."
        return
    fi
    
    echo -e "${GREEN}添加UFW规则${NC}"
    echo ""
    echo -e "${YELLOW}示例: 2222/tcp 或 8080/udp${NC}"
    echo -e "${BLUE}注: 规则会自动应用于IPv4和IPv6双栈${NC}"
    echo ""
    read -p "请输入端口/协议 (如 2222/tcp): " input
    
    if [[ ! $input =~ ^([0-9]+)/(tcp|udp)$ ]]; then
        echo -e "${RED}✗ 格式错误，请使用 端口/协议 格式${NC}"
        read -p "按Enter键继续..."
        return
    fi
    
    port="${BASH_REMATCH[1]}"
    protocol="${BASH_REMATCH[2]}"
    
    echo ""
    echo -e "${BLUE}准备添加规则: ${port}/${protocol} (IPv4/IPv6双栈)${NC}"
    
    # 询问是否同时添加另一个协议
    if [ "$protocol" == "tcp" ]; then
        other_protocol="udp"
    else
        other_protocol="tcp"
    fi
    
    read -p "是否同时放行 ${port}/${other_protocol}? (y/n): " add_both
    
    # 添加规则（UFW会自动创建IPv4和IPv6规则）
    ufw allow ${port}/${protocol} comment "Port ${port}/${protocol}"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 已添加规则: ${port}/${protocol} (包含IPv4和IPv6)${NC}"
    else
        echo -e "${RED}✗ 添加规则失败${NC}"
    fi
    
    if [[ $add_both == "y" || $add_both == "Y" ]]; then
        ufw allow ${port}/${other_protocol} comment "Port ${port}/${other_protocol}"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 已添加规则: ${port}/${other_protocol} (包含IPv4和IPv6)${NC}"
        else
            echo -e "${RED}✗ 添加规则失败${NC}"
        fi
    fi
    
    echo ""
    read -p "按Enter键继续..."
}

# 删除规则
delete_rule() {
    print_header
    
    if ! check_ufw_installed; then
        echo -e "${RED}✗ UFW未安装${NC}"
        read -p "按Enter键继续..."
        return
    fi
    
    echo -e "${GREEN}删除UFW规则${NC}"
    echo ""
    
    # 显示完整的规则列表（不过滤，显示UFW原始输出）
    echo -e "${BLUE}当前防火墙规则：${NC}"
    ufw status numbered
    
    if ! ufw status numbered | grep -q "^\["; then
        echo -e "${YELLOW}当前没有任何规则${NC}"
        read -p "按Enter键继续..."
        return
    fi
    
    echo ""
    echo -e "${YELLOW}提示: UFW会为每个端口自动创建IPv4和IPv6规则${NC}"
    echo -e "${YELLOW}      选择任意一条，脚本将智能删除该端口的所有相关规则${NC}"
    echo ""
    read -p "请输入要删除的规则编号 (0取消): " rule_num
    
    if [[ ! $rule_num =~ ^[0-9]+$ ]] || [ "$rule_num" == "0" ]; then
        echo -e "${YELLOW}取消删除${NC}"
        read -p "按Enter键继续..."
        return
    fi
    
    # 获取原始规则列表用于解析
    rules_raw=$(ufw status numbered 2>/dev/null)
    
    # 提取选中规则的详细信息
    rule_info=$(echo "$rules_raw" | grep "^\[ *$rule_num\]" | sed 's/\x1b\[[0-9;]*m//g')
    
    if [ -z "$rule_info" ]; then
        echo -e "${RED}✗ 无效的规则编号${NC}"
        read -p "按Enter键继续..."
        return
    fi
    
    echo ""
    echo -e "${BLUE}已选择规则: $rule_info${NC}"
    
    # 提取端口号和协议（处理IPv4和IPv6两种格式）
    # IPv4格式: [ 1] 22/tcp                     ALLOW IN    Anywhere
    # IPv6格式: [ 2] 22/tcp (v6)                ALLOW IN    Anywhere (v6)
    port=$(echo "$rule_info" | grep -oP '\d+(?=/(tcp|udp))' | head -1)
    protocol=$(echo "$rule_info" | grep -oP '(?<=/)(tcp|udp)(?=\s|\(v6\))' | head -1)
    
    if [[ -z "$port" || -z "$protocol" ]]; then
        echo -e "${RED}✗ 无法解析规则信息${NC}"
        read -p "按Enter键继续..."
        return
    fi
    
    # 询问是否删除同端口的其他协议规则
    delete_other_protocol="n"
    if [ "$protocol" == "tcp" ]; then
        other_protocol="udp"
    else
        other_protocol="tcp"
    fi
    
    # 检查是否存在同端口的其他协议规则
    if echo "$rules_raw" | grep -q "${port}/${other_protocol}"; then
        echo ""
        read -p "检测到 ${port}/${other_protocol} 规则，是否一并删除? (y/n): " delete_other_protocol
    fi
    
    # 收集要删除的所有规则编号
    rules_to_delete=()
    
    echo ""
    echo -e "${BLUE}正在查找所有相关规则...${NC}"
    
    # 查找所有同端口同协议的规则（包括IPv4和IPv6）
    while IFS= read -r line; do
        if echo "$line" | grep -q "${port}/${protocol}"; then
            num=$(echo "$line" | grep -oP '^\[\s*\K[0-9]+')
            if [ -n "$num" ]; then
                rules_to_delete+=($num)
                echo "  - 规则 $num: $(echo "$line" | sed 's/^\[[^]]*\] *//' | sed 's/\x1b\[[0-9;]*m//g')"
            fi
        fi
    done < <(echo "$rules_raw" | grep "^\[")
    
    # 如果选择删除另一个协议
    if [[ $delete_other_protocol == "y" || $delete_other_protocol == "Y" ]]; then
        while IFS= read -r line; do
            if echo "$line" | grep -q "${port}/${other_protocol}"; then
                num=$(echo "$line" | grep -oP '^\[\s*\K[0-9]+')
                if [ -n "$num" ]; then
                    rules_to_delete+=($num)
                    echo "  - 规则 $num: $(echo "$line" | sed 's/^\[[^]]*\] *//' | sed 's/\x1b\[[0-9;]*m//g')"
                fi
            fi
        done < <(echo "$rules_raw" | grep "^\[")
    fi
    
    # 去重并从大到小排序（避免删除时编号变化）
    rules_to_delete=($(printf '%s\n' "${rules_to_delete[@]}" | sort -rn -u))
    
    if [ ${#rules_to_delete[@]} -eq 0 ]; then
        echo -e "${RED}✗ 未找到匹配的规则${NC}"
        read -p "按Enter键继续..."
        return
    fi
    
    echo ""
    echo -e "${YELLOW}总共将删除 ${#rules_to_delete[@]} 条规则 (编号: ${rules_to_delete[*]})${NC}"
    read -p "确认删除? (y/n): " confirm
    
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        echo -e "${YELLOW}取消删除${NC}"
        read -p "按Enter键继续..."
        return
    fi
    
    # 从大到小删除规则
    echo ""
    echo -e "${BLUE}正在删除规则...${NC}"
    for num in "${rules_to_delete[@]}"; do
        echo "y" | ufw delete $num > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}  ✓ 已删除规则 $num${NC}"
        else
            echo -e "${RED}  ✗ 删除规则 $num 失败${NC}"
        fi
    done
    
    echo ""
    echo -e "${GREEN}✓ 删除完成${NC}"
    
    # 显示删除后的规则列表
    echo ""
    echo -e "${BLUE}更新后的规则列表：${NC}"
    ufw status numbered
    
    echo ""
    read -p "按Enter键继续..."
}

# 规则管理菜单
rule_management_menu() {
    while true; do
        print_header
        echo -e "${GREEN}UFW规则管理${NC}"
        echo ""
        echo "1) 添加规则"
        echo "2) 删除规则"
        echo "0) 返回主菜单"
        echo ""
        read -p "请选择操作 [0-2]: " choice
        
        case $choice in
            1) add_rule ;;
            2) delete_rule ;;
            0) return ;;
            *) echo -e "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

# 更新脚本
update_script() {
    print_header
    echo -e "${BLUE}正在从GitHub下载最新版本...${NC}"
    echo ""
    
    # 下载到临时文件
    temp_file="/tmp/ufw_update_$$.sh"
    
    if wget -O "$temp_file" "$GITHUB_URL" 2>&1 | grep -q "200 OK\|saved"; then
        chmod +x "$temp_file"
        
        # 替换当前脚本
        mv -f "$temp_file" "$INSTALL_PATH"
        
        echo -e "${GREEN}✓ 脚本更新成功${NC}"
        echo -e "${YELLOW}重新启动脚本以应用更新...${NC}"
        sleep 2
        
        # 重新执行脚本
        exec "$INSTALL_PATH" "$@"
    else
        echo -e "${RED}✗ 下载失败，请检查网络连接${NC}"
        rm -f "$temp_file"
    fi
    
    echo ""
    read -p "按Enter键继续..."
}

# 卸载脚本
uninstall_script() {
    print_header
    echo -e "${RED}警告: 即将卸载UFW管理脚本${NC}"
    read -p "确认卸载脚本? (y/n): " confirm
    
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        echo -e "${YELLOW}取消卸载${NC}"
        read -p "按Enter键继续..."
        return
    fi
    
    # 询问是否卸载UFW
    if check_ufw_installed; then
        echo ""
        read -p "是否同时卸载UFW? (y/n): " uninstall_ufw_choice
        
        if [[ $uninstall_ufw_choice == "y" || $uninstall_ufw_choice == "Y" ]]; then
            echo -e "${BLUE}正在卸载UFW...${NC}"
            ufw disable
            apt remove --purge -y ufw
            apt autoremove -y
            rm -rf /etc/ufw
            rm -rf /lib/ufw
            rm -rf /var/lib/ufw
            echo -e "${GREEN}✓ UFW已卸载${NC}"
        fi
    fi
    
    # 删除脚本
    echo -e "${BLUE}正在删除脚本文件...${NC}"
    rm -f "$INSTALL_PATH"
    
    echo -e "${GREEN}✓ 脚本已完全卸载${NC}"
    echo ""
    exit 0
}

# 脚本管理菜单
script_management_menu() {
    while true; do
        print_header
        echo -e "${GREEN}脚本管理${NC}"
        echo ""
        echo "1) 更新脚本"
        echo "2) 卸载脚本"
        echo "0) 返回主菜单"
        echo ""
        read -p "请选择操作 [0-2]: " choice
        
        case $choice in
            1) update_script ;;
            2) uninstall_script ;;
            0) return ;;
            *) echo -e "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

# 主菜单
main_menu() {
    while true; do
        print_header
        
        # 显示UFW状态
        if check_ufw_installed; then
            status=$(ufw status | grep -oP '(?<=Status: )\w+')
            if [ "$status" == "active" ]; then
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
        read -p "请选择操作 [0-3]: " choice
        
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

# 主程序
main() {
    check_root
    first_run_install "$@"
    main_menu
}

# 运行主程序
main "$@"
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

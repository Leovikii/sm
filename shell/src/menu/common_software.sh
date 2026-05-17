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

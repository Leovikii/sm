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

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

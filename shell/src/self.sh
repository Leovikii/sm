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

    # 替换横杠为波浪号以利用 GNU sort -V 对预发布版本(alpha/beta/rc)的排序特性
    # 原理：3.2.4~beta.1 会被 sort -V 认为老于 3.2.4
    local local_fmt="${SCRIPT_VERSION//-/~}"
    local remote_fmt="${remote_version//-/~}"
    local highest
    highest=$(printf "%s\n%s\n" "$local_fmt" "$remote_fmt" | sort -V | tail -n 1)

    if [[ "$highest" != "$remote_fmt" ]]; then
        log::info "当前本地版本 (v${SCRIPT_VERSION}) 高于或等于远端版本 (v${remote_version})，无需更新。"
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

# ==============================================================================
# sb:: Sing-box 业务模块
# ==============================================================================

sb::status() {
    if svc::is_active sing-box; then
        echo -e "${GREEN}运行中${PLAIN}"
    elif sys::has_cmd sing-box; then
        echo -e "${RED}已停止${PLAIN}"
    else
        echo -e "${YELLOW}未安装${PLAIN}"
    fi
}

sb::version() {
    if sys::has_cmd sing-box; then
        sing-box version 2>/dev/null | head -n 1 | awk '{print $3}'
    else
        echo "N/A"
    fi
}

sb::install() {
    log::info "准备安装/更新 Sing-box..."

    mkdir -p /etc/apt/keyrings
    pkg::add_gpg_key "https://sing-box.app/gpg.key" "/etc/apt/keyrings/sagernet.asc" || {
        log::err "Sing-box GPG 密钥下载失败。"; return 1; }

    pkg::write_repo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/sagernet.asc] https://deb.sagernet.org/ * *" \
        /etc/apt/sources.list.d/sagernet.list

    pkg::update quiet
    if pkg::install sing-box; then
        svc::ensure_running sing-box "Sing-box 安装成功并已启动！"
    else
        log::err "安装失败，请检查网络连接。"
    fi
}

sb::uninstall() {
    log::warn "即将卸载 Sing-box 及其软件源、密钥"
    ui::confirm "确认卸载?" || { log::info "取消卸载"; return; }

    svc::stop sing-box
    svc::disable sing-box
    pkg::purge sing-box

    rm -f /etc/apt/sources.list.d/sagernet.list
    rm -f /etc/apt/keyrings/sagernet.asc

    # /etc/sing-box 内有用户拉下来或手写的 config.json 以及历史证书目录，
    # 默认保留并询问是否清理
    if [[ -d /etc/sing-box ]] && ui::confirm "是否同时删除配置目录 /etc/sing-box?"; then
        rm -rf /etc/sing-box
        log::info "/etc/sing-box 已删除"
    fi

    log::info "Sing-box 已卸载"
}

sb::require_installed() {
    if ! sys::has_cmd sing-box; then
        log::warn "未检测到 Sing-box 内核，配置与服务管理需要依赖它。"
        if ui::confirm "是否立即安装 Sing-box?"; then
            sb::install || return 1
        else
            return 1
        fi
    fi
    return 0
}

sb::update_config_interactive() {
    local new_url
    ui::prompt "请输入配置下载链接 (直接回车保持默认): " new_url -e
    if [[ -n "$new_url" ]]; then
        self::persist_var "DEFAULT_CONFIG_URL" "$new_url"
        DEFAULT_CONFIG_URL="$new_url"
    elif [[ -z "$DEFAULT_CONFIG_URL" || "$DEFAULT_CONFIG_URL" == "https://example.com/config.json" ]]; then
        log::err "未设置有效的默认下载链接，请重新输入 URL。"
        return 1
    fi

    local url="$DEFAULT_CONFIG_URL"
    mkdir -p "$TMP_DIR"
    local tmp_conf="$TMP_DIR/config.json"

    log::info "正在下载配置: $url"
    if ! net::download "$url" "$tmp_conf"; then
        log::err "下载失败，请检查 URL 是否正确或网络是否畅通。"
        return 1
    fi
    
    log::step "使用 Sing-box 内核进行配置语法语义校验..."
    if ! sing-box check -c "$tmp_conf"; then
        log::err "Sing-box 配置校验失败！请检查 JSON 内容是否合法。操作已取消。"
        return 1
    fi
    
    mkdir -p /etc/sing-box
    mv "$tmp_conf" /etc/sing-box/config.json
    log::info "配置文件校验通过并已应用！"
    if ui::confirm "是否重启 Sing-box 服务?"; then
        svc::restart sing-box && log::info "服务已重启。"
    fi
}

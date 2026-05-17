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
    log::info "正在停止服务..."
    svc::stop sing-box
    svc::disable sing-box

    log::info "正在清理软件包..."
    pkg::purge sing-box

    log::info "正在清理配置文件..."
    rm -rf /etc/sing-box
    rm -f /etc/apt/sources.list.d/sagernet.list
    rm -f /etc/apt/keyrings/sagernet.asc

    log::info "Sing-box 及其配置已彻底移除。"
}

sb::apply_config() {
    local url="${1:-$DEFAULT_CONFIG_URL}"
    mkdir -p "$TMP_DIR"
    local tmp_conf="$TMP_DIR/config.json"

    log::info "正在下载配置: $url"
    if ! net::download "$url" "$tmp_conf"; then
        log::err "下载失败，请检查 URL 是否正确或网络是否畅通。"
        return 1
    fi
    if [[ ! -s "$tmp_conf" ]] || ! jq -e . "$tmp_conf" >/dev/null 2>&1; then
        log::err "下载的文件不是有效的 JSON 格式或内容为空，操作已取消。"
        return 1
    fi
    mkdir -p /etc/sing-box
    mv "$tmp_conf" /etc/sing-box/config.json
    log::info "配置文件验证通过并已应用。"
    if ui::confirm "是否重启 Sing-box 服务?"; then
        svc::restart sing-box && log::info "服务已重启。"
    fi
}

sb::set_default_url() {
    local new_url
    ui::prompt "请输入新的默认配置下载链接: " new_url -e
    if [[ -z "$new_url" ]]; then
        log::warn "链接为空，未修改。"
        return
    fi
    self::persist_var "DEFAULT_CONFIG_URL" "$new_url"
    DEFAULT_CONFIG_URL="$new_url"
    log::info "默认链接已更新。"
}

# ==============================================================================
# caddy:: Caddy Web 服务器
# ==============================================================================

caddy::is_installed() { sys::has_cmd caddy; }

caddy::install() {
    log::info "准备安装 Caddy..."

    rm -f /etc/apt/sources.list.d/caddy-stable.list
    rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    rm -f /etc/apt/keyrings/caddy-stable-archive-keyring.gpg

    pkg::install_quiet debian-keyring debian-archive-keyring apt-transport-https

    mkdir -p /usr/share/keyrings
    if ! pkg::add_gpg_key \
            "https://dl.cloudsmith.io/public/caddy/stable/gpg.key" \
            "/usr/share/keyrings/caddy-stable-archive-keyring.gpg" \
            --dearmor; then
        log::err "Caddy GPG 密钥下载/导入失败。"
        return
    fi

    if ! net::fetch "https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt" \
            > /etc/apt/sources.list.d/caddy-stable.list; then
        log::err "Caddy 软件源列表下载失败。"
        rm -f /etc/apt/sources.list.d/caddy-stable.list
        return
    fi
    if [[ ! -s /etc/apt/sources.list.d/caddy-stable.list ]]; then
        log::err "Caddy 软件源列表为空，已中止。"
        rm -f /etc/apt/sources.list.d/caddy-stable.list
        return
    fi

    pkg::update || { log::err "apt-get update 失败。"; return; }
    if pkg::install caddy; then
        svc::ensure_running caddy "Caddy 安装成功并已启动 (配置: /etc/caddy/Caddyfile)"
    else
        log::err "Caddy 安装失败，请检查网络或源是否可用。"
    fi
}

caddy::uninstall() {
    if ! caddy::is_installed; then
        log::warn "Caddy 未安装"
        return
    fi
    log::warn "即将卸载 Caddy 及其软件源、密钥"
    ui::confirm "确认卸载?" || { log::info "取消卸载"; return; }

    svc::stop caddy
    svc::disable caddy
    pkg::purge caddy

    rm -f /etc/apt/sources.list.d/caddy-stable.list
    rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    rm -f /etc/apt/keyrings/caddy-stable-archive-keyring.gpg

    if [[ -d /etc/caddy ]] && ui::confirm "是否同时删除配置目录 /etc/caddy?"; then
        rm -rf /etc/caddy
        log::info "/etc/caddy 已删除"
    fi

    pkg::autoremove >/dev/null 2>&1
    log::info "Caddy 已卸载"
}

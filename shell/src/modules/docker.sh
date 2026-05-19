# ==============================================================================
# docker:: Docker CE + Compose
# ==============================================================================

docker::is_installed() { sys::has_cmd docker; }

docker::install() {
    log::info "准备安装 Docker CE + Compose 插件..."

    if sys::has_cmd docker; then
        log::warn "检测到已安装: $(docker --version 2>/dev/null)"
        ui::confirm "是否继续 (将走 apt 升级流程)?" || { log::info "已取消。"; return; }
    fi

    local distro_id distro_codename
    distro_id="$(sys::distro_id)"
    distro_codename="$(sys::distro_codename)"
    case "$distro_id" in
        ubuntu|debian) ;;
        *) distro_id="debian" ;;
    esac
    if [[ -z "$distro_codename" ]]; then
        log::err "无法读取系统代号 (VERSION_CODENAME)，安装中止。"
        return
    fi

    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg

    install -m 0755 -d /etc/apt/keyrings
    if ! pkg::add_gpg_key \
            "https://download.docker.com/linux/${distro_id}/gpg" \
            "/etc/apt/keyrings/docker.asc"; then
        log::err "Docker GPG 密钥下载失败。"
        return
    fi

    pkg::write_repo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${distro_id} ${distro_codename} stable" \
        /etc/apt/sources.list.d/docker.list

    pkg::update || { log::err "apt-get update 失败。"; return; }
    if pkg::install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        if svc::ensure_running docker "Docker 安装成功: $(docker --version 2>/dev/null)"; then
            log::info "Compose: $(docker compose version 2>/dev/null | head -n1)"
            log::info "如需非 root 用户使用 docker，请执行: usermod -aG docker <user> 后重新登录。"
        fi
    else
        log::err "Docker 安装失败，请检查网络或源是否可用。"
    fi
}

docker::uninstall() {
    if ! docker::is_installed; then
        log::warn "Docker 未安装"
        return
    fi
    log::warn "即将卸载 Docker CE / Compose / containerd 及其软件源、密钥"
    ui::confirm "确认卸载?" || { log::info "取消卸载"; return; }

    svc::stop docker
    svc::stop containerd
    svc::disable docker
    svc::disable containerd

    pkg::purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras

    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg

    # /etc/docker 含用户的 daemon.json，默认保留并询问
    if [[ -d /etc/docker ]] && ui::confirm "是否同时删除配置目录 /etc/docker (含 daemon.json)?"; then
        rm -rf /etc/docker
        log::info "/etc/docker 已删除"
    fi

    # /var/lib/docker 与 /var/lib/containerd 含镜像/卷/容器数据，可能数十 GB，单独二次确认
    if [[ -d /var/lib/docker || -d /var/lib/containerd ]]; then
        echo
        log::warn "/var/lib/docker 与 /var/lib/containerd 内含所有镜像、卷、容器数据"
        log::warn "这些数据通常占用数 GB 至数十 GB，删除后无法恢复"
        if ui::confirm "是否一并清空 Docker 数据目录? (默认 N，强烈建议先备份重要卷)"; then
            rm -rf /var/lib/docker /var/lib/containerd
            log::info "Docker 数据目录已清空"
        else
            log::info "已保留 /var/lib/docker 与 /var/lib/containerd"
        fi
    fi

    pkg::autoremove >/dev/null 2>&1
    log::info "Docker 已卸载"
}

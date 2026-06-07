# ==============================================================================
# nftbl:: nftables 黑名单 (trick77/nftables-blacklist)
# 部署官方 update-blacklist.sh + 每月自动更新 timer
# 卸载时只清理脚本自动生成的资源，绝不动用户编辑过的配置
# ==============================================================================

NFTBL_SCRIPT_PATH="/usr/local/sbin/update-blacklist.sh"
NFTBL_CONF_DIR="/etc/nftables-blacklist"
NFTBL_CONF_FILE="${NFTBL_CONF_DIR}/nftables-blacklist.conf"
NFTBL_TIMER="/etc/systemd/system/sm-nftbl-update.timer"
NFTBL_SERVICE="/etc/systemd/system/sm-nftbl-update.service"
NFTBL_TIMER_NAME="sm-nftbl-update.timer"
NFTBL_SERVICE_NAME="sm-nftbl-update.service"
NFTBL_SCRIPT_URL="https://raw.githubusercontent.com/trick77/nftables-blacklist/master/update-blacklist.sh"
NFTBL_CONF_URL="https://raw.githubusercontent.com/trick77/nftables-blacklist/master/nftables-blacklist.conf"

nftbl::is_installed() { [[ -x "$NFTBL_SCRIPT_PATH" ]]; }

nftbl::table_exists() {
    sys::has_cmd nft && nft list table inet blacklist >/dev/null 2>&1
}

nftbl::status_text() {
    if ! nftbl::is_installed; then
        echo -e "${RED}未安装${PLAIN}"
    elif nftbl::table_exists; then
        echo -e "${GREEN}已部署${PLAIN}"
    else
        echo -e "${YELLOW}已安装(规则未加载)${PLAIN}"
    fi
}

nftbl::_require() {
    if ! nftbl::is_installed; then
        log::err "nftables 黑名单未安装，请先执行安装"
        return 1
    fi
}

nftbl::install() {
    if nftbl::is_installed; then
        log::warn "已检测到 ${NFTBL_SCRIPT_PATH}"
        ui::confirm "是否覆盖重装?" || { log::info "已取消"; return; }
    fi

    log::step "[1/6] 安装依赖 (curl / iprange / nftables)..."
    pkg::update quiet
    if ! pkg::install_quiet curl iprange nftables; then
        log::warn "依赖静默安装失败，重试 verbose 模式..."
        pkg::install curl iprange nftables || { log::err "依赖安装失败"; return 1; }
    fi

    log::step "[2/6] 下载 update-blacklist.sh..."
    if ! net::download "$NFTBL_SCRIPT_URL" "$NFTBL_SCRIPT_PATH"; then
        log::err "更新脚本下载失败"
        rm -f "$NFTBL_SCRIPT_PATH"
        return 1
    fi
    chmod +x "$NFTBL_SCRIPT_PATH"

    log::step "[3/6] 准备配置文件..."
    mkdir -p "$NFTBL_CONF_DIR"
    if [[ -f "$NFTBL_CONF_FILE" ]]; then
        log::info "已存在 ${NFTBL_CONF_FILE}，保留用户配置不覆盖"
    else
        if ! net::download "$NFTBL_CONF_URL" "$NFTBL_CONF_FILE"; then
            log::err "默认配置下载失败"
            return 1
        fi
        log::info "默认配置已下载到 ${NFTBL_CONF_FILE}"
    fi

    log::step "[4/6] 立即跑一次 update-blacklist.sh..."
    if ! "$NFTBL_SCRIPT_PATH" "$NFTBL_CONF_FILE"; then
        log::warn "首次执行返回非 0，可能源 IP 列表当前不可达，可稍后通过菜单重试"
    fi

    log::step "[5/6] 写入 systemd service / timer..."
    cat > "$NFTBL_SERVICE" <<EOF
[Unit]
Description=sm nftables blacklist update (trick77)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${NFTBL_SCRIPT_PATH} ${NFTBL_CONF_FILE}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    cat > "$NFTBL_TIMER" <<EOF
[Unit]
Description=sm nftables blacklist monthly update timer

[Timer]
OnCalendar=monthly
RandomizedDelaySec=1h
Persistent=true
Unit=${NFTBL_SERVICE_NAME}

[Install]
WantedBy=timers.target
EOF

    log::step "[6/6] 启用开机自启与每月更新定时器..."
    systemctl daemon-reload
    if systemctl enable --now "$NFTBL_SERVICE_NAME" >/dev/null 2>&1 && \
       systemctl enable --now "$NFTBL_TIMER_NAME" >/dev/null 2>&1; then
        log::info "系统服务及 Timer 已启用 (开机自启加载 + 每月更新)"
    else
        log::err "服务启用失败，请手动检查 systemctl status ${NFTBL_SERVICE_NAME}"
    fi

    echo
    log::info "✅ nftables 黑名单部署完成"
    log::info "  脚本    : ${NFTBL_SCRIPT_PATH}"
    log::info "  配置    : ${NFTBL_CONF_FILE}"
    log::info "  自动更新: 每月一次 (${NFTBL_TIMER_NAME})"
    if nftbl::table_exists; then
        local v4 v6
        v4=$(nft list set inet blacklist blacklist4 2>/dev/null | grep -c '^\s*[0-9]')
        v6=$(nft list set inet blacklist blacklist6 2>/dev/null | grep -c '^\s*[a-fA-F0-9]')
        log::info "  当前规则: IPv4≈${v4} 行 / IPv6≈${v6} 行"
    fi
    log::info "  下次触发: $(systemctl list-timers ${NFTBL_TIMER_NAME} 2>/dev/null | awk 'NR==2 {print $1, $2}')"
}

nftbl::update_now() {
    nftbl::_require || return
    log::step "运行 update-blacklist.sh..."
    if "$NFTBL_SCRIPT_PATH" "$NFTBL_CONF_FILE"; then
        log::info "黑名单更新完成"
    else
        log::err "更新失败 (退出码 $?)"
        return 1
    fi
}

nftbl::edit_config() {
    nftbl::_require || return
    if [[ ! -f "$NFTBL_CONF_FILE" ]]; then
        log::err "配置文件不存在: $NFTBL_CONF_FILE"
        return 1
    fi
    local editor="${EDITOR:-}"
    if [[ -z "$editor" ]]; then
        if sys::has_cmd nano; then editor=nano
        elif sys::has_cmd vim; then editor=vim
        elif sys::has_cmd vi;  then editor="vi"
        else
            log::err "未找到可用编辑器 (nano/vim/vi)，请手动编辑 ${NFTBL_CONF_FILE}"
            return 1
        fi
    fi
    "$editor" "$NFTBL_CONF_FILE"
    if ui::confirm "是否立即重新应用配置?"; then
        nftbl::update_now
    fi
}

nftbl::show_status() {
    if ! sys::has_cmd nft; then
        log::err "nft 命令不可用，请先安装 nftables"
        return 1
    fi
    if ! nftbl::table_exists; then
        log::warn "inet blacklist 表不存在 (尚未运行过 update-blacklist.sh 或已被清理)"
        return 1
    fi

    log::info "── 表 inet blacklist ──"
    nft list table inet blacklist 2>/dev/null | head -n 40
    echo
    log::info "── IPv4 set (前 20 行) ──"
    nft list set inet blacklist blacklist4 2>/dev/null | sed -n '1,20p'
    echo
    log::info "── IPv6 set (前 20 行) ──"
    nft list set inet blacklist blacklist6 2>/dev/null | sed -n '1,20p'
    echo
    log::info "── input chain 计数器 ──"
    nft list chain inet blacklist input 2>/dev/null
    echo
    log::info "── timer 下次触发 ──"
    systemctl list-timers "$NFTBL_TIMER_NAME" 2>/dev/null | head -n 3
}

nftbl::uninstall() {
    if ! nftbl::is_installed && [[ ! -f "$NFTBL_TIMER" && ! -f "$NFTBL_SERVICE" ]]; then
        log::warn "nftables 黑名单未安装"
        return
    fi
    log::warn "即将卸载 nftables 黑名单 (仅清理本脚本自动生成的资源)"
    ui::confirm "确认卸载?" || { log::info "取消"; return; }

    systemctl disable --now "$NFTBL_TIMER_NAME" >/dev/null 2>&1 || true
    systemctl disable --now "$NFTBL_SERVICE_NAME" >/dev/null 2>&1 || true
    rm -f "$NFTBL_TIMER" "$NFTBL_SERVICE"
    systemctl daemon-reload

    if sys::has_cmd nft && nftbl::table_exists; then
        nft delete table inet blacklist 2>/dev/null && log::info "nft 表已删除"
    fi

    rm -f "$NFTBL_SCRIPT_PATH"

    if [[ -d "$NFTBL_CONF_DIR" ]]; then
        echo
        log::warn "配置目录 ${NFTBL_CONF_DIR} 可能包含您手工编辑过的内容"
        if ui::confirm "是否一并删除? (默认 N)"; then
            rm -rf "$NFTBL_CONF_DIR"
            log::info "${NFTBL_CONF_DIR} 已删除"
        else
            log::info "已保留 ${NFTBL_CONF_DIR}"
        fi
    fi

    log::info "nftables 黑名单已卸载"
}

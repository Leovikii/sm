# ==============================================================================
# ufw:: UFW 防火墙业务模块
# ==============================================================================

ufw::is_installed() { sys::has_cmd ufw; }

# 加 timeout 防止某些 nf_tables 状态下 ufw status numbered 卡死
ufw::_status_numbered() {
    timeout 5 ufw status numbered 2>/dev/null
}

ufw::is_enabled() {
    sys::has_cmd ufw && LC_ALL=C timeout 5 ufw status verbose 2>/dev/null | head -n1 | grep -q "Status: active"
}

ufw::status_text() {
    if ! ufw::is_installed; then
        echo -e "${RED}未安装${PLAIN}"
    elif ufw::is_enabled; then
        echo -e "${GREEN}已启用${PLAIN}"
    else
        echo -e "${YELLOW}未启用${PLAIN}"
    fi
}

ufw::_require() {
    if ! ufw::is_installed; then
        log::err "UFW 未安装，请先安装 UFW"
        return 1
    fi
}

ufw::install() {
    if ufw::is_installed; then
        log::warn "UFW 已经安装，正在检查更新..."
        pkg::update quiet
        if apt list --upgradable 2>/dev/null | grep -q "^ufw/"; then
            log::info "发现 UFW 更新"
            if ui::confirm "是否更新 UFW?"; then
                pkg::install_quiet ufw && log::info "UFW 更新完成"
            else
                log::info "跳过更新"
            fi
        else
            log::info "UFW 已是最新版本"
        fi
        return
    fi

    log::info "正在安装 UFW..."
    pkg::update quiet
    if ! pkg::install_quiet ufw; then
        log::err "UFW 安装失败"
        return 1
    fi

    log::info "UFW 安装成功"
    log::warn "自动放行常用端口以防止服务中断 (IPv4/IPv6 双栈)"
    ufw::allow 22 tcp "SSH TCP"
    ufw::allow 22 udp "SSH UDP"
    ufw::allow 80 tcp "HTTP TCP"
    ufw::allow 80 udp "HTTP UDP"
    ufw::allow 443 tcp "HTTPS TCP"
    ufw::allow 443 udp "HTTPS UDP"

    log::step "正在启用 UFW..."
    if echo "y" | ufw enable >/dev/null 2>&1; then
        log::info "UFW 已自动启用"
    else
        log::err "UFW 启用失败"
    fi
}

ufw::enable() {
    ufw::_require || return
    if echo "y" | ufw enable >/dev/null 2>&1; then
        log::info "UFW 已启用"
    else
        log::err "UFW 启用失败"
    fi
}

ufw::disable() {
    ufw::_require || return
    if ufw disable >/dev/null 2>&1; then
        log::info "UFW 已禁用"
    else
        log::err "UFW 禁用失败"
    fi
}

ufw::reload() {
    ufw::_require || return
    if ufw reload >/dev/null 2>&1; then
        log::info "UFW 已重启"
    else
        log::err "UFW 重启失败"
    fi
}

ufw::uninstall() {
    if ! ufw::is_installed; then
        log::warn "UFW 未安装"
        return
    fi
    log::warn "即将卸载 UFW 及其所有配置"
    ui::confirm "确认卸载?" || { log::info "取消卸载"; return; }

    ufw disable >/dev/null 2>&1
    pkg::purge ufw >/dev/null 2>&1
    pkg::autoremove >/dev/null 2>&1
    rm -rf /etc/ufw /lib/ufw /var/lib/ufw
    log::info "UFW 已完全卸载"
}

ufw::allow() {
    local port="$1" proto="$2" comment="${3:-Port ${1}/${2}}"
    if ufw allow "${port}/${proto}" comment "$comment" >/dev/null 2>&1; then
        log::info "已放行 ${port}/${proto} (IPv4/IPv6)"
    else
        log::err "添加规则失败: ${port}/${proto}"
        return 1
    fi
}

ufw::list_numbered() {
    ufw::_require || return
    ufw::_status_numbered
}

ufw::add_rule_interactive() {
    ufw::_require || return
    log::info "添加 UFW 规则 (示例: 2222/tcp 或 8080/udp)"
    log::info "规则会自动应用于 IPv4 和 IPv6 双栈"
    local input
    ui::prompt "请输入端口/协议 (如 2222/tcp): " input

    if [[ ! "$input" =~ ^([0-9]+)/(tcp|udp)$ ]]; then
        log::err "格式错误，请使用 端口/协议 格式（输入: $input）"
        return 1
    fi
    local port="${BASH_REMATCH[1]}"
    local proto="${BASH_REMATCH[2]}"
    if (( port < 1 || port > 65535 )); then
        log::err "端口必须在 1-65535 范围内（输入: $port）"
        return 1
    fi
    local other="udp"
    [[ "$proto" == "udp" ]] && other="tcp"

    ufw::allow "$port" "$proto"
    if ui::confirm "是否同时放行 ${port}/${other}?"; then
        ufw::allow "$port" "$other"
    fi
}

ufw::delete_rule_interactive() {
    ufw::_require || return
    log::info "当前防火墙规则："
    ufw::_status_numbered

    if ! ufw::_status_numbered | grep -q "^\["; then
        log::warn "当前没有任何规则"
        return
    fi

    log::warn "UFW 会为每个端口自动创建 IPv4 和 IPv6 规则"
    log::warn "选择任意一条，脚本将智能删除该端口的所有相关规则"
    local rule_num
    ui::prompt "请输入要删除的规则编号 (0 取消): " rule_num
    if [[ ! "$rule_num" =~ ^[0-9]+$ ]] || [[ "$rule_num" == "0" ]]; then
        log::warn "取消删除"
        return
    fi

    local rules_raw rule_info
    rules_raw=$(ufw::_status_numbered)
    rule_info=$(echo "$rules_raw" | grep "^\[ *$rule_num\]" | sed 's/\x1b\[[0-9;]*m//g')
    if [[ -z "$rule_info" ]]; then
        log::err "无效的规则编号"
        return 1
    fi
    log::info "已选择规则: $rule_info"

    local target_def port proto other
    # 跳过 "[ N]" 头部再取下一个 token；awk '{print $2}' 在编号 1-9
    # ("[ 1]" 内含空格) 时会把 "1]" 当成 $2，造成解析失败
    target_def=$(echo "$rule_info" | sed -E 's/^\[[[:space:]]*[0-9]+\][[:space:]]+([^[:space:]]+).*/\1/')
    port=$(echo "$target_def" | cut -d'/' -f1)
    proto=$(echo "$target_def" | cut -d'/' -f2)
    if [[ -z "$port" || -z "$proto" || "$port" == "$target_def" ]]; then
        log::err "无法解析规则信息，该规则可能不是标准的 端口/协议 格式"
        return 1
    fi
    other="udp"
    [[ "$proto" == "udp" ]] && other="tcp"

    local delete_other="n"
    if echo "$rules_raw" | grep -q "${port}/${other}"; then
        if ui::confirm "检测到 ${port}/${other} 规则，是否一并删除?"; then
            delete_other="y"
        fi
    fi

    local rules_to_delete=()
    while IFS= read -r line; do
        if echo "$line" | grep -q -w "${port}/${proto}"; then
            local num
            num=$(echo "$line" | sed 's/^\[ *\([0-9]\+\)\].*/\1/')
            [[ -n "$num" ]] && rules_to_delete+=("$num")
        fi
    done < <(echo "$rules_raw" | grep "^\[")

    if [[ "$delete_other" == "y" ]]; then
        while IFS= read -r line; do
            if echo "$line" | grep -q -w "${port}/${other}"; then
                local num
                num=$(echo "$line" | sed 's/^\[ *\([0-9]\+\)\].*/\1/')
                [[ -n "$num" ]] && rules_to_delete+=("$num")
            fi
        done < <(echo "$rules_raw" | grep "^\[")
    fi

    # 倒序去重，避免删除时编号偏移
    IFS=$'\n' read -r -d '' -a rules_to_delete < <(printf '%s\n' "${rules_to_delete[@]}" | sort -rn -u && printf '\0')

    if [[ ${#rules_to_delete[@]} -eq 0 ]]; then
        log::err "未找到匹配的规则"
        return 1
    fi

    log::warn "总共将删除 ${#rules_to_delete[@]} 条规则 (编号: ${rules_to_delete[*]})"
    ui::confirm "确认删除?" || { log::warn "取消删除"; return; }

    local num
    for num in "${rules_to_delete[@]}"; do
        if echo "y" | ufw delete "$num" >/dev/null 2>&1; then
            log::info "已删除规则 $num"
        else
            log::err "删除规则 $num 失败"
        fi
    done
    log::info "更新后的规则列表："
    ufw::_status_numbered
}

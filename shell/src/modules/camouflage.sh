# ==============================================================================
# camouflage:: 伪装站点 + AnyTLS 证书统一同步
#
# 设计目标：
#   - 静态伪装：用 Caddy 直发一个低资源 html5up Massively 模板
#   - OpenList 伪装：docker compose 起 OpenList，Caddy 反代 5244
#   - 证书统一：通过 Caddy events on cert_obtained 钩子，把申请到的证书
#               同步到 /etc/sing-box/certs/<domain>.{crt,key}，并维护
#               active.{crt,key} 软链接，让所有服务器的 anytls 配置统一
#               指向 active.* 即可，证书自动续签后自动同步
# ==============================================================================

CADDY_MAIN_CONF="/etc/caddy/Caddyfile"
CADDY_SITES_DIR="/etc/caddy/sites.d"
ACTIVE_DOMAIN_FILE="${SB_CERT_DIR}/.active-domain"

# Caddy 进程以 caddy 用户运行；写入配置后必须确保 caddy 可读
# 否则 systemctl reload caddy 会报 "permission denied"
camouflage::_fix_caddy_perms() {
    local target="$1"
    chmod 0644 "$target" 2>/dev/null || true
    chown root:caddy "$target" 2>/dev/null || true
}

# active-domain 文件管理（决定 AnyTLS 用哪张证书）
camouflage::read_active_domain() {
    [[ -f "$ACTIVE_DOMAIN_FILE" ]] && cat "$ACTIVE_DOMAIN_FILE" 2>/dev/null || echo ""
}

camouflage::set_active_domain() {
    local domain="$1"
    mkdir -p "$SB_CERT_DIR"
    echo "$domain" > "$ACTIVE_DOMAIN_FILE"
    chmod 0644 "$ACTIVE_DOMAIN_FILE"
    log::info "AnyTLS 活动域名设为: $domain"

    # 立即把已存在的证书链接刷新一下
    if [[ -f "$SB_CERT_DIR/$domain.crt" ]]; then
        ln -sfn "$domain.crt" "$SB_CERT_DIR/active.crt"
        ln -sfn "$domain.key" "$SB_CERT_DIR/active.key"
        log::info "active.{crt,key} 已指向 $domain"
    else
        log::warn "$domain 的证书还未同步过，等下次 Caddy 续签后会自动指向"
    fi
}

# 部署伪装时调用：用户输入的域名就是 AnyTLS 要用的域名
#   - 首次部署：静默自动绑定为 active
#   - 重装同域名：什么都不做
#   - 冲突（已有 active 但本次域名不同）：询问是否切换
camouflage::bind_active_domain() {
    local domain="$1"
    local current
    current="$(camouflage::read_active_domain)"

    if [[ -z "$current" ]]; then
        camouflage::set_active_domain "$domain"
        return
    fi
    [[ "$current" == "$domain" ]] && return

    log::warn "当前 AnyTLS active 域名: $current"
    if ui::confirm "是否切换到本次部署的 $domain ?"; then
        camouflage::set_active_domain "$domain"
    else
        log::info "保持 active=$current ($domain 证书仍会被同步，但不动 active 软链接)"
    fi
}

camouflage::ensure_caddy() {
    caddy::is_installed && return 0
    log::info "伪装功能需要 Caddy，开始自动安装..."
    caddy::install
    caddy::is_installed || { log::err "Caddy 安装失败，无法继续。"; return 1; }
}

camouflage::ensure_docker() {
    docker::is_installed && return 0
    log::info "OpenList 伪装需要 Docker，开始自动安装..."
    docker::install
    docker::is_installed || { log::err "Docker 安装失败，无法继续。"; return 1; }
}

# 询问域名（必填，格式校验 + DNS 解析校验）
camouflage::_ask_domain() {
    local var="$1" prompt="${2:-请输入指向本机的域名: }" val=""
    while [[ -z "$val" ]]; do
        ui::prompt "$prompt" val
        if [[ ! "$val" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
            log::err "域名格式不正确，请重新输入"
            val=""
            continue
        fi
        if ! camouflage::_verify_domain_dns "$val"; then
            val=""
        fi
    done
    printf -v "$var" '%s' "$val"
}

# 拉本机公网 IP（IPv4 + IPv6 任一）
camouflage::_my_public_ips() {
    local v4 v6
    v4=$(curl -fsS4 --max-time 4 https://api.ipify.org 2>/dev/null || true)
    v6=$(curl -fsS6 --max-time 4 https://api64.ipify.org 2>/dev/null || true)
    [[ -n "$v4" ]] && echo "$v4"
    [[ -n "$v6" ]] && echo "$v6"
}

# 校验域名是否解析到本机公网 IP
# 返回 0 = 通过（匹配，或用户选择强制继续）；1 = 用户取消
camouflage::_verify_domain_dns() {
    local domain="$1"
    log::step "校验域名解析: $domain"

    local resolved my_ips matched=0
    # getent ahosts 一次返回 v4+v6 解析结果
    resolved=$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u)
    my_ips=$(camouflage::_my_public_ips)

    if [[ -z "$resolved" ]]; then
        log::warn "无法解析 $domain（DNS 故障或域名未生效）"
        ui::confirm "是否仍然继续? (用于内网测试 / DNS 未生效场景)"
        return $?
    fi
    if [[ -z "$my_ips" ]]; then
        log::warn "获取本机公网 IP 失败（网络异常或防火墙拦截 ipify）"
        log::info "解析到的 IP:"; echo "$resolved" | sed 's/^/    /'
        ui::confirm "无法验证，是否仍然继续?"
        return $?
    fi

    # 任一交集即视为匹配
    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        if echo "$resolved" | grep -qx "$ip"; then
            matched=1
            break
        fi
    done <<< "$my_ips"

    if [[ $matched -eq 1 ]]; then
        log::info "域名解析正确 ✓"
        return 0
    fi

    log::warn "域名 $domain 未解析到本机公网 IP"
    log::info "  本机公网 IP:"; echo "$my_ips"  | sed 's/^/    /'
    log::info "  域名解析到:";   echo "$resolved" | sed 's/^/    /'
    log::info "  CDN / 反代后端场景下解析必然不一致，可强制继续"
    ui::confirm "是否仍然继续?"
}

# ----------------------------------------------------------------------
# 证书同步钩子安装
# ----------------------------------------------------------------------
# 写出 cert-sync 脚本与 Caddyfile events 块。
# 幂等：重复调用只更新内容，不重复注入。
camouflage::install_cert_hook() {
    log::step "安装 Caddy → sing-box 证书同步钩子..."

    # 1. 同步脚本
    mkdir -p "$SB_CERT_DIR"
    chmod 0755 "$SB_CERT_DIR"

    cat > "$CERT_SYNC_SCRIPT" <<'SYNC_EOF'
#!/bin/bash
# sm-cert-sync.sh - Caddy 申请/续签证书后由 events 钩子自动调用
#
# 行为：
#   - 总是把证书复制到 /etc/sing-box/certs/<domain>.{crt,key}
#     (无害，多个域名可共存)
#   - 只有当本次域名 == /etc/sing-box/certs/.active-domain 里记录的域名时，
#     才更新 active.{crt,key} 软链接
#   - .active-domain 不存在时（首次部署）当前域名自动成为 active
#
# 这样，将来你手动新增任何反代/Caddy 站点都不会影响 AnyTLS 用的证书。
set -euo pipefail
DOMAIN="${1:-}"
[[ -z "$DOMAIN" ]] && { echo "usage: $0 DOMAIN" >&2; exit 1; }

DEST="/etc/sing-box/certs"
ACTIVE_FILE="$DEST/.active-domain"
mkdir -p "$DEST"

# Caddy 证书目录：CA 子目录可能不同（letsencrypt / zerossl）
CADDY_DATA="${XDG_DATA_HOME:-/var/lib/caddy/.local/share}/caddy"
SRC=$(find "$CADDY_DATA/certificates" -type d -name "$DOMAIN" 2>/dev/null | head -n1)
[[ -z "$SRC" ]] && { echo "[cert-sync] 未找到 $DOMAIN 的 Caddy 证书目录" >&2; exit 1; }

cp -f "$SRC/$DOMAIN.crt" "$DEST/$DOMAIN.crt"
cp -f "$SRC/$DOMAIN.key" "$DEST/$DOMAIN.key"
chmod 0644 "$DEST/$DOMAIN.crt"
chmod 0640 "$DEST/$DOMAIN.key"

# 首次部署：自动认领 active
if [[ ! -f "$ACTIVE_FILE" ]]; then
    echo "$DOMAIN" > "$ACTIVE_FILE"
    chmod 0644 "$ACTIVE_FILE"
fi

ACTIVE_DOMAIN="$(cat "$ACTIVE_FILE" 2>/dev/null || true)"

if [[ "$DOMAIN" == "$ACTIVE_DOMAIN" ]]; then
    ln -sfn "$DOMAIN.crt" "$DEST/active.crt"
    ln -sfn "$DOMAIN.key" "$DEST/active.key"
    echo "[cert-sync] $DOMAIN (active) -> $DEST/active.{crt,key}"
else
    echo "[cert-sync] $DOMAIN copied (active=$ACTIVE_DOMAIN, link unchanged)"
fi

# sing-box v1.8+ 检测到证书文件变化会自动热重载，无需 systemctl reload
SYNC_EOF
    chmod +x "$CERT_SYNC_SCRIPT"
    log::info "证书同步脚本: $CERT_SYNC_SCRIPT"

    # 2. Caddyfile events 块（幂等注入）
    if [[ ! -f "$CADDY_MAIN_CONF" ]] || ! grep -q "cert_obtained.*sm-cert-sync" "$CADDY_MAIN_CONF" 2>/dev/null; then
        camouflage::_inject_caddy_events
    fi

    # 3. 自动 import sites.d
    mkdir -p "$CADDY_SITES_DIR"
    chown root:caddy "$CADDY_SITES_DIR" 2>/dev/null || true
    chmod 0755 "$CADDY_SITES_DIR" 2>/dev/null || true
    if ! grep -q "import ${CADDY_SITES_DIR}/" "$CADDY_MAIN_CONF" 2>/dev/null; then
        echo "" >> "$CADDY_MAIN_CONF"
        echo "import ${CADDY_SITES_DIR}/*.caddy" >> "$CADDY_MAIN_CONF"
    fi
    camouflage::_fix_caddy_perms "$CADDY_MAIN_CONF"
}

# 在 Caddyfile 顶部全局选项中注入 events 钩子
camouflage::_inject_caddy_events() {
    local block
    block="$(cat <<EOF
{
    email admin@example.com
    events {
        on cert_obtained exec ${CERT_SYNC_SCRIPT} {event.data.identifier}
    }
}
EOF
)"
    if [[ -f "$CADDY_MAIN_CONF" ]] && grep -q "^{" "$CADDY_MAIN_CONF"; then
        # 已有全局块：用 sed 在第一个 { 之后插入 events 行（仅当未注入时）
        if ! grep -q "cert_obtained" "$CADDY_MAIN_CONF"; then
            sed -i "/^{/a\\    events {\\n        on cert_obtained exec ${CERT_SYNC_SCRIPT} {event.data.identifier}\\n    }" "$CADDY_MAIN_CONF"
            log::info "已在现有 Caddyfile 全局块中注入 events 钩子"
        fi
    else
        # 无全局块或文件不存在：写入全新内容（保留原内容追加在后）
        local tmp
        tmp=$(mktemp)
        echo "$block" > "$tmp"
        [[ -f "$CADDY_MAIN_CONF" ]] && cat "$CADDY_MAIN_CONF" >> "$tmp"
        mv "$tmp" "$CADDY_MAIN_CONF"
        log::info "已写入新 Caddyfile 全局块（含 events 钩子）"
    fi
    # mktemp 默认 0600 + mv 保留权限，会让 caddy 用户读不到 → reload 失败
    camouflage::_fix_caddy_perms "$CADDY_MAIN_CONF"
}

# ----------------------------------------------------------------------
# OpenList 默认密码抓取
# ----------------------------------------------------------------------
# 首次启动 (config.json 不存在) 时 OpenList 会打印类似：
#   Successfully created the admin user and the initial password is: 0SL9xLxz
# 该日志在容器内部初始化完成时才出现，速度受机器性能影响。
# 我们最多轮询 30 秒，每秒查一次 docker logs。
camouflage::wait_openlist_password() {
    local container="${1:-openlist}"
    local timeout="${2:-30}"
    local pattern="initial password is:"
    local i=0 line=""

    while (( i < timeout )); do
        line=$(docker logs "$container" 2>&1 | grep -m1 "$pattern" || true)
        [[ -n "$line" ]] && break
        sleep 1
        i=$((i + 1))
    done

    if [[ -z "$line" ]]; then
        return 1
    fi
    # "... initial password is: PWD" -> PWD
    echo "${line##*initial password is: }"
}

# ----------------------------------------------------------------------
# 站点配置（每个域名一个文件，便于增删）
# ----------------------------------------------------------------------
# camouflage::_write_site DOMAIN BODY
camouflage::_write_site() {
    local domain="$1" body="$2"
    mkdir -p "$CADDY_SITES_DIR"
    cat > "$CADDY_SITES_DIR/${domain}.caddy" <<EOF
${domain} {
${body}
}
EOF
    camouflage::_fix_caddy_perms "$CADDY_SITES_DIR/${domain}.caddy"
}

# ----------------------------------------------------------------------
# 静态伪装
# ----------------------------------------------------------------------
camouflage::install_static() {
    camouflage::ensure_caddy || return 1

    local domain
    camouflage::_ask_domain domain "请输入指向本机的域名 (用于静态伪装): "

    log::step "下载静态伪装站点 (html5up Massively)..."
    mkdir -p "$CAMOUFLAGE_WEB_ROOT"
    local tmp_zip="$TMP_DIR/massively.zip"
    mkdir -p "$TMP_DIR"
    if ! net::download "$STATIC_SITE_URL" "$tmp_zip"; then
        log::err "静态站点下载失败"
        return 1
    fi
    if ! sys::has_cmd unzip; then
        pkg::install_quiet unzip || { log::err "unzip 安装失败"; return 1; }
    fi
    if ! unzip -oq "$tmp_zip" -d "$CAMOUFLAGE_WEB_ROOT"; then
        log::err "静态站点解压失败"
        return 1
    fi
    chown -R caddy:caddy "$CAMOUFLAGE_WEB_ROOT" 2>/dev/null || true
    log::info "静态站点已部署到 $CAMOUFLAGE_WEB_ROOT"

    camouflage::install_cert_hook

    camouflage::_write_site "$domain" "    root * ${CAMOUFLAGE_WEB_ROOT}
    encode gzip
    file_server
    log {
        output discard
    }"
    log::info "Caddy 站点配置已写入: $CADDY_SITES_DIR/${domain}.caddy"

    log::step "重载 Caddy..."
    if svc::is_active caddy; then
        systemctl reload caddy && log::info "Caddy 已重载"
    else
        svc::ensure_running caddy "Caddy 已启动"
    fi

    camouflage::bind_active_domain "$domain"

    echo
    log::info "✅ 静态伪装就绪: https://${domain}"
    log::info "   首次访问由 Caddy 自动申请证书，证书将自动同步到 ${SB_CERT_DIR}/"
    log::info "   AnyTLS 活动域名: $(camouflage::read_active_domain)"
}

# ----------------------------------------------------------------------
# OpenList 伪装
# ----------------------------------------------------------------------
camouflage::install_openlist() {
    camouflage::ensure_caddy || return 1
    camouflage::ensure_docker || return 1

    local domain
    camouflage::_ask_domain domain "请输入指向本机的域名 (用于 OpenList): "

    log::step "准备 OpenList 部署目录..."
    mkdir -p "$OPENLIST_DIR/data"

    cat > "$OPENLIST_DIR/docker-compose.yml" <<EOF
services:
  openlist:
    image: openlistteam/openlist:latest
    container_name: openlist
    user: "0:0"
    volumes:
      - ${OPENLIST_DIR}/data:/opt/openlist/data
    ports:
      - 127.0.0.1:5244:5244
    environment:
      - UMASK=022
    labels:
      - com.centurylinklabs.watchtower.enable=true
    restart: unless-stopped

  watchtower:
    image: nickfedor/watchtower:latest
    container_name: openlist-watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_LABEL_ENABLE=true
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_SCHEDULE=0 0 4 1 * *
    restart: unless-stopped
EOF

    log::step "拉起 OpenList..."
    (cd "$OPENLIST_DIR" && docker compose up -d) || {
        log::err "docker compose 启动失败"; return 1; }

    camouflage::install_cert_hook

    camouflage::_write_site "$domain" "    encode gzip
    reverse_proxy 127.0.0.1:5244
    log {
        output discard
    }"
    log::info "Caddy 站点配置已写入: $CADDY_SITES_DIR/${domain}.caddy"

    log::step "重载 Caddy..."
    if svc::is_active caddy; then
        systemctl reload caddy && log::info "Caddy 已重载"
    else
        svc::ensure_running caddy "Caddy 已启动"
    fi

    camouflage::bind_active_domain "$domain"

    echo
    log::info "✅ OpenList 伪装就绪: https://${domain}"
    log::info "   OpenList 数据: ${OPENLIST_DIR}/data"
    log::info "   AnyTLS 活动域名: $(camouflage::read_active_domain)"

    # 抓取首次启动时打印的初始密码（已设置过密码的容器抓不到，正常）
    log::step "等待 OpenList 初始化输出默认密码 (最多 30 秒)..."
    local pwd
    if pwd=$(camouflage::wait_openlist_password openlist 30); then
        echo
        echo -e "  ${GREEN}━━━ OpenList 初始管理员凭证 ━━━${PLAIN}"
        echo -e "  地址  : ${BLUE}https://${domain}${PLAIN}"
        echo -e "  用户名: ${BLUE}admin${PLAIN}"
        echo -e "  密码  : ${YELLOW}${pwd}${PLAIN}"
        echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
        log::warn "请尽快登录 https://${domain} 修改默认密码"
    else
        log::warn "30 秒内未抓到默认密码"
        log::info "可能原因：容器初始化较慢，或 ${OPENLIST_DIR}/data 已存在数据（密码已修改过）"
        log::info "可手动查看完整日志: docker logs openlist | grep -i password"
    fi
}

# ----------------------------------------------------------------------
# 状态查询 / 卸载
# ----------------------------------------------------------------------
camouflage::status_text() {
    local has_static=0 has_openlist=0
    [[ -d "$CAMOUFLAGE_WEB_ROOT" ]] && has_static=1
    [[ -f "$OPENLIST_DIR/docker-compose.yml" ]] && has_openlist=1
    if [[ $has_static -eq 0 && $has_openlist -eq 0 ]]; then
        echo -e "${YELLOW}未部署${PLAIN}"
    else
        local parts=()
        [[ $has_static   -eq 1 ]] && parts+=("静态")
        [[ $has_openlist -eq 1 ]] && parts+=("OpenList")
        local active
        active="$(camouflage::read_active_domain)"
        if [[ -n "$active" ]]; then
            echo -e "${GREEN}已部署: ${parts[*]}${PLAIN} | active: ${BLUE}${active}${PLAIN}"
        else
            echo -e "${GREEN}已部署: ${parts[*]}${PLAIN}"
        fi
    fi
}

# 列出已同步的所有证书域名
camouflage::list_synced_domains() {
    local f
    for f in "$SB_CERT_DIR"/*.crt; do
        [[ -e "$f" ]] || continue
        local name
        name="$(basename "$f" .crt)"
        [[ "$name" == "active" ]] && continue
        echo "$name"
    done
}

# 交互切换 active 域名
camouflage::switch_active() {
    log::info "AnyTLS 活动域名决定 ${SB_CERT_DIR}/active.{crt,key} 软链接指向哪个证书。"
    local current
    current="$(camouflage::read_active_domain)"
    [[ -n "$current" ]] && log::info "当前 active: ${current}" || log::warn "尚未设置 active 域名"

    local domains=()
    while IFS= read -r d; do
        [[ -n "$d" ]] && domains+=("$d")
    done < <(camouflage::list_synced_domains)

    if [[ ${#domains[@]} -eq 0 ]]; then
        log::err "尚未同步任何证书。请先访问伪装域名（让 Caddy 申请证书）。"
        return 1
    fi

    echo
    echo "已同步证书的域名："
    local i=1
    for d in "${domains[@]}"; do
        if [[ "$d" == "$current" ]]; then
            echo -e "  ${GREEN}${i}.${PLAIN} ${d}  ${GREEN}(当前 active)${PLAIN}"
        else
            echo -e "  ${GREEN}${i}.${PLAIN} ${d}"
        fi
        i=$((i + 1))
    done
    echo

    local choice
    ui::prompt "请选择新的 active 域名编号 (0 取消): " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" == "0" ]]; then
        log::info "已取消"
        return
    fi
    if (( choice < 1 || choice > ${#domains[@]} )); then
        log::err "无效编号"
        return 1
    fi
    camouflage::set_active_domain "${domains[$((choice - 1))]}"
}

camouflage::uninstall() {
    log::warn "即将清理伪装相关资源（站点文件、OpenList 容器、Caddy 站点配置、证书同步钩子）"
    ui::confirm "确认?" || { log::info "取消"; return; }

    # OpenList
    if [[ -f "$OPENLIST_DIR/docker-compose.yml" ]]; then
        log::step "停止 OpenList..."
        (cd "$OPENLIST_DIR" && docker compose down) 2>/dev/null || true
        if ui::confirm "是否删除 OpenList 数据目录 $OPENLIST_DIR ?"; then
            rm -rf "$OPENLIST_DIR"
            log::info "OpenList 目录已删除"
        fi
    fi

    # 静态站点
    [[ -d "$CAMOUFLAGE_WEB_ROOT" ]] && rm -rf "$CAMOUFLAGE_WEB_ROOT" && log::info "静态站点目录已删除"

    # Caddy sites
    if [[ -d "$CADDY_SITES_DIR" ]]; then
        rm -f "$CADDY_SITES_DIR"/*.caddy
        log::info "Caddy 站点配置已清理"
        svc::is_active caddy && systemctl reload caddy 2>/dev/null
    fi

    rm -f "$CERT_SYNC_SCRIPT"
    log::info "证书同步脚本已删除"
    rm -f "$ACTIVE_DOMAIN_FILE"
    log::warn "证书目录 $SB_CERT_DIR 已保留 (sing-box 仍在使用)。如需清理请手动 rm -rf"

    log::info "伪装功能已卸载"
}

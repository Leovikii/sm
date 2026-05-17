# ==============================================================================
# pkg:: APT 软件包管理封装
# ==============================================================================

pkg::update() {
    if [[ "${1:-}" == "quiet" ]]; then
        apt-get update -y >/dev/null 2>&1
    else
        apt-get update -y
    fi
}

pkg::install()       { DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; }
pkg::install_quiet() { DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >/dev/null 2>&1; }
pkg::purge()         { DEBIAN_FRONTEND=noninteractive apt-get purge -y "$@"; }
pkg::autoremove()    { DEBIAN_FRONTEND=noninteractive apt-get autoremove -y --purge "$@"; }
pkg::clean()         { apt-get clean; }

# pkg::full_upgrade [APT_OPTS...] - 内核及依赖全量升级
pkg::full_upgrade() {
    DEBIAN_FRONTEND=noninteractive apt-get "$@" -y full-upgrade
}

# pkg::ensure_deps - 安装通用依赖（带缓存标记）
pkg::ensure_deps() {
    [[ $_DEPS_CHECKED -eq 1 ]] && return 0
    if [[ -f "$DEPS_FLAG" ]]; then _DEPS_CHECKED=1; return 0; fi

    local deps="curl wget jq tar ca-certificates gnupg"
    local missing=""
    for dep in $deps; do
        sys::has_cmd "$dep" || missing="$missing $dep"
    done

    if [[ -n "$missing" ]]; then
        log::info "正在安装必要依赖:$missing"
        pkg::update quiet
        if ! pkg::install_quiet $missing; then
            log::err "依赖安装失败:$missing"
            return 1
        fi
    fi
    mkdir -p "$(dirname "$DEPS_FLAG")"
    touch "$DEPS_FLAG"
    _DEPS_CHECKED=1
}

# pkg::add_gpg_key URL DEST [--dearmor]
pkg::add_gpg_key() {
    local url="$1" dest="$2" mode="${3:-}"
    if [[ "$mode" == "--dearmor" ]]; then
        net::fetch "$url" | gpg --dearmor --yes -o "$dest" || return 1
    else
        net::fetch "$url" > "$dest" || return 1
        [[ -s "$dest" ]] || { rm -f "$dest"; return 1; }
    fi
    chmod a+r "$dest"
}

# pkg::write_repo CONTENT DEST_LIST
pkg::write_repo() {
    local content="$1" dest="$2"
    echo "$content" > "$dest"
}

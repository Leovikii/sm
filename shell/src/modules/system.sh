# ==============================================================================
# system:: 系统级操作（升级 / 内核）
# ==============================================================================

system::full_upgrade() {
    log::info "准备执行系统全量升级 (full-upgrade)..."
    log::warn "该操作会升级内核及所有依赖发生变化的软件包，建议升级后重启。"
    ui::confirm "确认继续?" || { log::info "已取消。"; return; }

    local apt_opts=(-o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef)

    log::step "[1/3] 更新软件源索引..."
    pkg::update || { log::err "apt-get update 失败，请检查软件源。"; return; }

    log::step "[2/3] 执行 full-upgrade (包含内核升级)..."
    if ! pkg::full_upgrade "${apt_opts[@]}"; then
        log::err "full-upgrade 执行失败。"
        return
    fi

    log::step "[3/3] 清理无用依赖..."
    pkg::autoremove "${apt_opts[@]}"
    pkg::clean

    sys::reboot_if_needed
}

# ==============================================================================
# ui:: 终端 UI 工具（菜单/输入/确认）
# ==============================================================================

ui::clear()   { clear; }
ui::divider() { echo -e "────────────────────────────────────────────────"; }

# ui::header TITLE [SUBTITLE]
ui::header() {
    local title="$1" subtitle="${2:-}"
    ui::clear
    echo -e "┌──────────────────────────────────────────────┐"
    printf "│              ${BLUE}%-32s${PLAIN}│\n" "$title"
    [[ -n "$subtitle" ]] && printf "│                ${GREEN}%-30s${PLAIN}│\n" "$subtitle"
    echo -e "└──────────────────────────────────────────────┘"
}

# ui::confirm PROMPT  -> 0 if yes, 1 otherwise
ui::confirm() {
    local prompt="$1" ans
    read -r -p "$prompt (y/N): " ans || exit 130
    [[ "${ans,,}" == "y" ]]
}

# ui::prompt PROMPT VARNAME [-e]
ui::prompt() {
    local prompt="$1" varname="$2" flag="${3:-}"
    if [[ "$flag" == "-e" ]]; then
        read -e -r -p "$prompt" "$varname" || exit 130
    else
        read -r -p "$prompt" "$varname" || exit 130
    fi
}

ui::pause() { read -n 1 -s -r -p "按任意键继续..." || exit 130; echo; }

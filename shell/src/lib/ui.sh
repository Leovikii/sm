# ==============================================================================
# ui:: 终端 UI 工具（菜单/输入/确认）
# ==============================================================================

ui::clear()   { clear; }

# 缩进 1 空格让上下文呼吸，色调统一蓝色
ui::divider() { echo -e "${BLUE} ──────────────────────────────────────────────${PLAIN}"; }

# 不画封闭 box —— 含 CJK 字符时 printf "%-Ns" 永远对不齐右侧 │，
# 且 │ ─ 这些方框字在不同终端下宽度歧义（East Asian Ambiguous Width）
ui::header() {
    local title="$1" subtitle="${2:-}"
    ui::clear
    echo
    echo -e "${BLUE} ──────────────────────────────────────────────${PLAIN}"
    if [[ -n "$subtitle" ]]; then
        echo -e "  ${BLUE}❯${PLAIN} ${BLUE}${title}${PLAIN}  ${GREEN}${subtitle}${PLAIN}"
    else
        echo -e "  ${BLUE}❯${PLAIN} ${BLUE}${title}${PLAIN}"
    fi
    echo -e "${BLUE} ──────────────────────────────────────────────${PLAIN}"
}

ui::confirm() {
    local prompt="$1" ans
    read -r -p "$prompt (y/N): " ans || exit 130
    [[ "${ans,,}" == "y" ]]
}

ui::prompt() {
    local prompt="$1" varname="$2" flag="${3:-}"
    if [[ "$flag" == "-e" ]]; then
        read -e -r -p "$prompt" "$varname" || exit 130
    else
        read -r -p "$prompt" "$varname" || exit 130
    fi
}

ui::pause() { read -n 1 -s -r -p "按任意键继续..." || exit 130; echo; }

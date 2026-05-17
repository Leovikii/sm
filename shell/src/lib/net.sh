# ==============================================================================
# net:: 网络下载（统一 UA / 超时 / 重试）
# ==============================================================================

# net::fetch URL  -> 输出到 stdout
net::fetch() {
    local url="$1"
    if sys::has_cmd curl; then
        curl -k -f -L --retry 2 --connect-timeout 5 -s -A "sing-box/1.0" "$url"
    else
        wget --no-check-certificate -q -O- -T 5 -t 2 --user-agent="sing-box/1.0" "$url"
    fi
}

# net::download URL DEST
net::download() {
    local url="$1" dest="$2"
    if sys::has_cmd curl; then
        curl -k -f -L --retry 3 --connect-timeout 10 -s -A "sing-box/1.0" -o "$dest" "$url"
    else
        wget --no-check-certificate -q -T 15 -t 3 --user-agent="sing-box/1.0" -O "$dest" "$url"
    fi
}

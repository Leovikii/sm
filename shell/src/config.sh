# ==============================================================================
# L0  常量与配置
# ==============================================================================

SCRIPT_NAME="sm.sh"
SCRIPT_VERSION="3.0.1"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"
SCRIPT_UPDATE_URL="https://raw.githubusercontent.com/Leovikii/sm/main/shell/sm.sh"

DEFAULT_CONFIG_URL="https://example.com/config.json"
TCPX_URL="https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh"

# 伪装功能资源
STATIC_SITE_URL="https://html5up.net/massively/download"
CAMOUFLAGE_WEB_ROOT="/var/www/sm-camouflage"
OPENLIST_DIR="/opt/openlist"

# AnyTLS 证书同步：所有服务器统一使用 active.{crt,key}，证书续签自动同步
SB_CERT_DIR="/etc/sing-box/certs"
CERT_SYNC_SCRIPT="/usr/local/bin/sm-cert-sync.sh"

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
PLAIN='\033[0m'

TMP_DIR="/tmp/sm_manager_tmp_$$"
DEPS_FLAG="/var/lib/sm/.deps_ok"
_DEPS_CHECKED=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT
trap 'echo -e "\n${YELLOW}[WARN]${PLAIN} 接收到退出指令，脚本终止。"; exit 130' INT TERM HUP

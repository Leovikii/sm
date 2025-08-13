#!/bin/bash

# 创建服务文件
SERVICE_FILE="/etc/systemd/system/sing-box.service"
cat > $SERVICE_FILE <<EOF
[Unit]
Description=sing-box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/etc/sing-box/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=10
LimitNPROC=512
LimitNOFILE=infinity
CacheDirectory=sing-box
LogsDirectory=sing-box
RuntimeDirectory=sing-box

[Install]
WantedBy=multi-user.target
EOF

# 重新加载systemd配置
systemctl daemon-reload

# 启用开机自启
systemctl enable sing-box

echo "服务已创建并启用开机启动"
echo "请确保配置文件位于: /etc/sing-box/config.json"
echo "管理命令:"
echo "启动服务: systemctl start sing-box"
echo "查看状态: systemctl status sing-box"
echo "查看日志: journalctl -u sing-box -f"

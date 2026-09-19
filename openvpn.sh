#!/bin/bash

export LANG=en_US.UTF-8

# 定义颜色变量
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 恢复默认颜色

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    printf "${RED}❌ 请使用 root 权限运行此脚本！(例如: sudo bash openvpn.sh)\n${NC}"
    exit 1
fi

# 检查是否已经安装过
check_installed() {
    if [ -d "/etc/openvpn/server" ] || [ -f "/etc/systemd/system/openvpn-server@server.service" ]; then
        return 0 # 已安装
    else
        return 1 # 未安装
    fi
}

# 静默卸载（用于清理）
do_uninstall_quiet() {
    if systemctl is-active --quiet openvpn-server@server; then
        systemctl stop openvpn-server@server >/dev/null 2>&1
    fi
    if systemctl is-enabled --quiet openvpn-server@server; then
        systemctl disable openvpn-server@server >/dev/null 2>&1
    fi
    rm -rf /etc/openvpn
    rm -f /etc/systemd/system/openvpn-server*
    rm -f ~/client*.ovpn
    rm -f openvpn-install.sh
    systemctl daemon-reload >/dev/null 2>&1
}

# 1. 安装 OpenVPN 服务端与客户端管理
do_install() {
    if [ ! -f "openvpn-install.sh" ]; then
        wget -O openvpn-install.sh https://git.io/vpn >/dev/null 2>&1
        chmod +x openvpn-install.sh
    fi

    if check_installed; then
        echo ""
        echo "=================================================="
        printf "${GREEN}✅ 检测到 OpenVPN 服务端已安装！${NC}\n"
        printf "${GREEN}即将为您打开原版客户端与服务端管理菜单...${NC}\n"
        echo "=================================================="
        echo ""
        read -p "请按回车键继续进入管理菜单..."
    else
        echo "=== 正在下载并运行原版 OpenVPN 安装程序 ==="
    fi

    # 直接调用原版脚本（未安装时走安装流程，已安装时会自动进入原版管理菜单）
    bash openvpn-install.sh
}

# 2. 卸载 OpenVPN 服务端
do_uninstall() {
    if ! check_installed; then
        printf "${RED}❌ 系统中未检测到 OpenVPN 服务端，无需卸载。\n${NC}"
        return
    fi

    echo "=== 正在全面清理并卸载 OpenVPN 服务端 ==="
    do_uninstall_quiet
    echo "=================================================="
    printf "${GREEN}✅ OpenVPN 服务端已完全卸载干净！\n${NC}"
    echo "=================================================="
}

# 3. 检查运行状态与各项配置
check_status() {
    echo "=== 正在检查 OpenVPN 运行状态与配置 ==="
    if ! check_installed; then
        printf "${RED}未安装 OpenVPN 服务。\n${NC}"
        return
    fi

    systemctl status openvpn-server@server --no-pager
    
    echo ""
    echo "--- 配置检测结果 ---"
    FINAL_PORT=$(grep "^port " /etc/openvpn/server/server.conf | awk '{print $2}')
    FINAL_PROTO=$(grep "^proto " /etc/openvpn/server/server.conf | awk '{print $2}')
    printf "${GREEN}[OK] 当前服务端口: $FINAL_PORT${NC}\n"
    printf "${GREEN}[OK] 当前传输协议: $FINAL_PROTO${NC}\n"
}

# 交互主菜单
while true; do
    echo ""
    echo "========================================="
    echo "     OpenVPN 服务端一键管理脚本          "
    echo "========================================="
    echo " 1. 安装 OpenVPN 服务端与客户端管理"
    echo " 2. 卸载 OpenVPN 服务端"
    echo " 3. 查看 OpenVPN 运行状态与配置"
    echo " 0. 退出脚本"
    echo "========================================="
    read -p "请选择操作 [0-3]: " CHOICE

    case "$CHOICE" in
        1)
            do_install
            ;;
        2)
            do_uninstall
            ;;
        3)
            check_status
            ;;
        0)
            echo "已安全退出脚本。"
            break
            ;;
        *)
            printf "${RED}❌ 无效的选项，请输入 0 到 3 之间的数字。\n${NC}"
            ;;
    esac
done

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

# 1. 安装 OpenVPN 服务端（完全使用原版交互）
do_install() {
    if check_installed; then
        echo ""
        echo "=================================================="
        printf "${RED}检测到系统中已经安装了 OpenVPN 服务端！\n${NC}"
        printf "${RED}如需重新安装，请先选择选项 3 卸载后再试。\n${NC}"
        echo "=================================================="
        return
    fi

    echo "=== 正在下载原版 OpenVPN 安装脚本 ==="
    wget -O openvpn-install.sh https://git.io/vpn
    chmod +x openvpn-install.sh

    # 直接调用原版脚本，保留所有原生菜单和交互
    bash openvpn-install.sh

    # 安装完成后，自动补全多设备同证书在线(duplicate-cn)以及默认客户端固定IP
    echo "=== 正在为默认客户端配置固定 IP 及多设备共存策略 ==="
    
    # 寻找默认生成的客户端名称（通常是第一个生成的 .ovpn 文件名）
    FIRST_OVPN=$(ls ~/*.ovpn 2>/dev/null | head -n 1)
    if [ -n "$FIRST_OVPN" ]; then
        CLIENT_NAME=$(basename "$FIRST_OVPN" .ovpn)
    else
        CLIENT_NAME="client"
    fi

    mkdir -p /etc/openvpn/ccd
    cat << CCD > /etc/openvpn/ccd/${CLIENT_NAME}
ifconfig-push 10.8.0.2 255.255.255.0
CCD

    # 写入服务端配置
    if ! grep -q "client-config-dir" /etc/openvpn/server/server.conf; then
        echo 'client-config-dir /etc/openvpn/ccd' >> /etc/openvpn/server/server.conf
    fi
    if ! grep -q "duplicate-cn" /etc/openvpn/server/server.conf; then
        echo 'duplicate-cn' >> /etc/openvpn/server/server.conf
    fi

    systemctl restart openvpn-server@server

    echo ""
    echo "=================================================="
    printf "${GREEN}OpenVPN 安装完毕，多设备同时在线功能已激活！\n${NC}"
    echo "=================================================="
}

# 2. 新增客户端配置文件（完全使用原版交互）
do_add_client() {
    if ! check_installed; then
        printf "${RED}❌ 系统中未检测到 OpenVPN 服务端，请先安装！\n${NC}"
        return
    fi

    if [ ! -f "openvpn-install.sh" ]; then
        wget -O openvpn-install.sh https://git.io/vpn
        chmod +x openvpn-install.sh
    fi

    # 直接调用原版脚本的增删管理菜单
    bash openvpn-install.sh

    # 确保新增客户端后服务端依然保持多用户在线与配置路径开启
    if ! grep -q "client-config-dir" /etc/openvpn/server/server.conf; then
        echo 'client-config-dir /etc/openvpn/ccd' >> /etc/openvpn/server/server.conf
    fi
    if ! grep -q "duplicate-cn" /etc/openvpn/server/server.conf; then
        echo 'duplicate-cn' >> /etc/openvpn/server/server.conf
    fi
    systemctl restart openvpn-server@server >/dev/null 2>&1
}

# 3. 卸载 OpenVPN 服务端
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

# 4. 检查运行状态与各项配置
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
    
    if grep -q "duplicate-cn" /etc/openvpn/server/server.conf; then
        printf "${GREEN}[OK] 多设备同证书并发在线 (duplicate-cn) 已开启${NC}\n"
    fi
    if grep -q "client-config-dir" /etc/openvpn/server/server.conf; then
        printf "${GREEN}[OK] 客户端固定IP策略 (CCD) 已挂载${NC}\n"
    fi
}

# 交互主菜单
while true; do
    echo ""
    echo "========================================="
    echo "     OpenVPN 服务端一键管理脚本          "
    echo "========================================="
    echo " 1. 安装 OpenVPN 服务端 (原版交互)"
    echo " 2. 新增客户端配置文件 (原版交互/多设备)"
    echo " 3. 卸载 OpenVPN 服务端"
    echo " 4. 查看 OpenVPN 运行状态与配置"
    echo " 0. 退出脚本"
    echo "========================================="
    read -p "请选择操作 [0-4]: " CHOICE

    case "$CHOICE" in
        1)
            do_install
            ;;
        2)
            do_add_client
            ;;
        3)
            do_uninstall
            ;;
        4)
            check_status
            ;;
        0)
            echo "已安全退出脚本。"
            break
            ;;
        *)
            printf "${RED}❌ 无效的选项，请输入 0 到 4 之间的数字。\n${NC}"
            ;;
    esac
done

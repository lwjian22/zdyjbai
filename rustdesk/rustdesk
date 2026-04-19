#!/bin/sh

# RustDesk 交互式管理脚本 (Alpine Linux 专用版 - 无sudo版)
# 适配：OpenRC, apk, 纯 root 运行

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 全局变量
UNAME=$(whoami)
GNAME=$(id -gn ${UNAME})
ADMINTOKEN=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c16)
ARCH=$(uname -m)

# 显示菜单
show_menu() {
    clear
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}      RustDesk 服务器管理脚本 (Alpine)${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
    echo -e "${GREEN}1. 安装 RustDesk 服务器${NC}"
    echo -e "${YELLOW}2. 修改监听端口${NC}"
    echo -e "${RED}3. 卸载 RustDesk 服务器${NC}"
    echo -e "${BLUE}4. 查看服务状态${NC}"
    echo -e "${NC}5. 退出${NC}"
    echo ""
}

# 安装前置依赖 (直接 apk，不加 sudo)
install_prerequisites() {
    echo -e "${BLUE}正在安装前置依赖 (apk)...${NC}"
    apk update
    apk add curl wget unzip tar bind-tools
    if [ $? -ne 0 ]; then
        echo -e "${RED}依赖安装失败，请检查网络或镜像源${NC}"
        exit 1
    fi
}

# 获取连接方式
get_connection_method() {
    echo ""
    echo -e "${BLUE}选择连接方式:${NC}"
    echo "1) 自动获取公网IP"
    echo "2) 手动输入域名/IP"
    read -ep "请选择 [1-2]: " choice

    case $choice in
        1)
            WANIP=$(dig @resolver4.opendns.com myip.opendns.com +short 2>/dev/null)
            if [ -z "$WANIP" ]; then
                echo -e "${RED}无法自动获取IP，请尝试手动输入${NC}"
                exit 1
            fi
            echo -e "${GREEN}检测到的公网IP: $WANIP${NC}"
            ;;
        2)
            read -ep "请输入域名或IP地址: " WANIP
            if [ -z "$WANIP" ]; then
                echo -e "${RED}输入不能为空${NC}"
                exit 1
            fi
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            exit 1
            ;;
    esac
}

# 创建目录 (去掉 sudo，直接 mkdir/chown)
create_directories() {
    # 确保 /opt 存在
    mkdir -p /opt
    
    if [ ! -d "/opt/rustdesk" ]; then
        echo -e "${BLUE}创建 /opt/rustdesk 目录${NC}"
        mkdir -p /opt/rustdesk/
    fi
    # 修改归属权
    chown "${UNAME}:${GNAME}" -R /opt/rustdesk
    cd /opt/rustdesk/ || exit 1

    # 日志目录
    if [ ! -d "/var/log/rustdesk" ]; then
        mkdir -p /var/log/rustdesk/
    fi
    chown "${UNAME}:${GNAME}" -R /var/log/rustdesk/
}

# 检查二进制兼容性
check_binary_compat() {
    echo -e "${BLUE}检查二进制文件兼容性...${NC}"
    if ! /opt/rustdesk/hbbs --help > /dev/null 2>&1; then
        echo -e "${RED}❌ 错误：二进制文件无法在 Alpine (musl libc) 上运行。${NC}"
        echo -e "${YELLOW}解决方案：运行: apk add gcompat${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ 兼容性检查通过${NC}"
}

# 下载并安装 RustDesk
install_rustdesk() {
    echo -e "${BLUE}正在下载 RustDesk 服务器...${NC}"

    RDLATEST=$(curl -s https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest | grep "tag_name" | awk -F'"' '{print $4}')

    if [ "${ARCH}" = "x86_64" ]; then
        wget "https://github.com/rustdesk/rustdesk-server/releases/download/${RDLATEST}/rustdesk-server-linux-amd64.zip"
        unzip rustdesk-server-linux-amd64.zip
        mv amd64/* /opt/rustdesk/
    elif [ "${ARCH}" = "armv7l" ]; then
        wget "https://github.com/rustdesk/rustdesk-server/releases/download/${RDLATEST}/rustdesk-server-linux-armv7.zip"
        unzip rustdesk-server-linux-armv7.zip
        mv armv7/* /opt/rustdesk/
    elif [ "${ARCH}" = "aarch64" ]; then
        wget "https://github.com/rustdesk/rustdesk-server/releases/download/${RDLATEST}/rustdesk-server-linux-arm64v8.zip"
        unzip rustdesk-server-linux-arm64v8.zip
        mv arm64v8/* /opt/rustdesk/
    else
        echo -e "${RED}不支持的架构: ${ARCH}${NC}"
        exit 1
    fi

    chmod +x /opt/rustdesk/hbbs
    chmod +x /opt/rustdesk/hbbr

    check_binary_compat

    rm -f *.zip
    rm -rf amd64 armv7 arm64v8 2>/dev/null
}

# 配置 OpenRC 服务 (去掉 sudo，直接写入)
configure_openrc_services() {
    echo -e "${BLUE}配置 OpenRC 服务...${NC}"

    # Signal 服务
    cat << EOF > /etc/init.d/rustdesksignal
#!/sbin/openrc-run

description="Rustdesk Signal Server (hbbs)"
command="/opt/rustdesk/hbbs"
command_background=true
command_user="${UNAME}:${GNAME}"
pidfile="/run/rustdesksignal.pid"
start_stop_daemon_args="-d /opt/rustdesk/"
output_log="/var/log/rustdesk/signalserver.log"
error_log="/var/log/rustdesk/signalserver.error"

depend() {
    need net
    after firewall
}
EOF

    # Relay 服务
    cat << EOF > /etc/init.d/rustdeskrelay
#!/sbin/openrc-run

description="Rustdesk Relay Server (hbbr)"
command="/opt/rustdesk/hbbr"
command_background=true
command_user="${UNAME}:${GNAME}"
pidfile="/run/rustdeskrelay.pid"
start_stop_daemon_args="-d /opt/rustdesk/"
output_log="/var/log/rustdesk/relayserver.log"
error_log="/var/log/rustdesk/relayserver.error"

depend() {
    need net
    after firewall
}
EOF

    chmod +x /etc/init.d/rustdesksignal /etc/init.d/rustdeskrelay
    rc-update add rustdesksignal default
    rc-update add rustdeskrelay default

    echo -e "${BLUE}启动服务...${NC}"
    rc-service rustdesksignal start
    rc-service rustdeskrelay start

    sleep 5
    if rc-service rustdeskrelay status | grep -q "started"; then
        echo -e "${GREEN}✅ 服务启动成功${NC}"
    else
        echo -e "${RED}❌ 服务可能启动失败，检查日志 /var/log/rustdesk/${NC}"
    fi
}

# 获取配置信息
get_config_info() {
    PUBNAME=$(find /opt/rustdesk -name "*.pub" 2>/dev/null | head -n 1)
    if [ -z "$PUBNAME" ]; then
        echo -e "${RED}错误：未找到公钥文件，服务可能未正常启动${NC}"
        return
    fi
    KEY=$(cat "${PUBNAME}")

    STRING="{\"host\":\"${WANIP}\",\"relay\":\"${WANIP}\",\"key\":\"${KEY}\"}"
    STRING64=$(echo -n "$STRING" | base64 -w 0 | tr -d '=')
    STRING64REV=$(echo -n "$STRING64" | rev)

    echo ""
    echo -e "${GREEN}安装完成！${NC}"
    echo -e "${YELLOW}服务器地址: ${WANIP}${NC}"
    echo -e "${YELLOW}公钥: ${KEY}${NC}"
    echo ""
    echo -e "${BLUE}客户端配置信息 (Base64):${NC}"
    echo "${STRING64REV}"
    echo ""
}

# 安装主流程
install_main() {
    install_prerequisites
    get_connection_method
    create_directories
    install_rustdesk
    configure_openrc_services
    get_config_info

    echo -e "${GREEN}按任意键返回主菜单...${NC}"
    read -n 1
}

# 修改端口
modify_port() {
    if [ ! -f "/etc/init.d/rustdesksignal" ]; then
        echo -e "${RED}错误: RustDesk 未安装${NC}"
        read -n 1
        return
    fi

    echo -e "${BLUE}当前端口配置:${NC}"
    echo "Signal Server 端口: 21116"
    echo "Relay Server 端口: 21117"
    echo ""

    read -ep "请输入新的 Signal Server 端口 (默认:21116): " new_signal_port
    new_signal_port=${new_signal_port:-21116}

    read -ep "请输入新的 Relay Server 端口 (默认:21117): " new_relay_port
    new_relay_port=${new_relay_port:-21117}

    # 🔧 二次修改兼容：先删旧 command_args，再插新行
    # 处理 hbbs (Signal)
    sed -i '/^command_args="/d; /^command="\/opt\/rustdesk\/hbbs"$/a command_args="-k _ -p '"${new_signal_port}"'"' /etc/init.d/rustdesksignal
    
    # 处理 hbbr (Relay)
    sed -i '/^command_args="/d; /^command="\/opt\/rustdesk\/hbbr"$/a command_args="-k _ -p '"${new_relay_port}"'"' /etc/init.d/rustdeskrelay
    
    echo -e "${BLUE}重启服务以应用更改...${NC}"
    rc-service rustdesksignal stop
    rc-service rustdeskrelay stop
    
    rc-service rustdesksignal restart
    rc-service rustdeskrelay restart

    echo -e "${GREEN}端口修改完成！${NC}"
    echo -e "${YELLOW}新的 Signal Server 端口: ${new_signal_port}${NC}"
    echo -e "${YELLOW}新的 Relay Server 端口: ${new_relay_port}${NC}"
    echo -e "${GREEN}按任意键返回主菜单...${NC}"
    read -n 1
}

# 卸载
uninstall_rustdesk() {
    if [ ! -f "/etc/init.d/rustdesksignal" ]; then
        echo -e "${RED}未安装${NC}"
        read -n 1
        return
    fi

    echo -e "${RED}⚠️  即将完全卸载${NC}"
    read -ep "确认？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return
    fi

    rc-service rustdesksignal stop
    rc-service rustdeskrelay stop
    rc-update del rustdesksignal
    rc-update del rustdeskrelay
    rm -f /etc/init.d/rustdesksignal /etc/init.d/rustdeskrelay
    rm -rf /opt/rustdesk/ /var/log/rustdesk/

    echo -e "${GREEN}卸载完成${NC}"
    read -n 1
}

# 查看状态
check_status() {
    echo -e "${BLUE}服务状态:${NC}"
    rc-service rustdesksignal status
    echo ""
    rc-service rustdeskrelay status
    echo ""
    read -n 1
}

# 主循环
main() {
    while true; do
        show_menu
        read -ep "选择 [1-5]:" choice
        case $choice in
            1) install_main ;;
            2) modify_port ;;
            3) uninstall_rustdesk ;;
            4) check_status ;;
            5) exit 0 ;;
            *) echo -e "${RED}无效输入${NC}"; sleep 1 ;;
        esac
    done
}

main

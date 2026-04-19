#!/bin/bash

# RustDesk 交互式管理脚本
# 功能：安装、卸载、修改端口

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

# 识别操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        UPSTREAM_ID=${ID_LIKE,,}

        # 回退到 ID_LIKE 如果 ID 不是 'ubuntu' 或 'debian'
        if [ "${UPSTREAM_ID}" != "debian" ] && [ "${UPSTREAM_ID}" != "ubuntu" ]; then
            UPSTREAM_ID="$(echo ${ID_LIKE,,} | sed s/\"//g | cut -d' ' -f1)"
        fi
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        OS=Debian
        VER=$(cat /etc/debian_version)
    elif [ -f /etc/redhat-release ]; then
        OS=RedHat
        VER=$(cat /etc/redhat-release)
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
}

# 显示菜单
show_menu() {
    clear
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}      RustDesk 服务器管理脚本${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
    echo -e "${GREEN}1. 安装 RustDesk 服务器${NC}"
    echo -e "${YELLOW}2. 修改监听端口${NC}"
    echo -e "${RED}3. 卸载 RustDesk 服务器${NC}"
    echo -e "${BLUE}4. 查看服务状态${NC}"
    echo -e "${NC}5. 退出${NC}"
    echo ""
}

# 安装前置依赖
install_prerequisites() {
    echo -e "${BLUE}正在安装前置依赖...${NC}"

    # 通用依赖
    PREREQ="curl wget unzip tar"
    PREREQDEB="dnsutils"
    PREREQRPM="bind-utils"
    PREREQARCH="bind"

    if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ] || [ "${UPSTREAM_ID}" = "ubuntu" ] || [ "${UPSTREAM_ID}" = "debian" ]; then
        sudo apt-get update
        sudo apt-get install -y ${PREREQ} ${PREREQDEB}
    elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ] || [ "${UPSTREAM_ID}" = "rhel" ]; then
        sudo yum update -y
        sudo yum install -y ${PREREQ} ${PREREQRPM}
    elif [ "${ID}" = "arch" ] || [ "${UPSTREAM_ID}" = "arch" ]; then
        sudo pacman -Syu
        sudo pacman -S ${PREREQ} ${PREREQARCH}
    else
        echo -e "${RED}不支持的操作系统${NC}"
        echo -n "是否继续安装？依赖可能无法满足... [y/N]: "
        read continue_no_dependencies
        if [[ ! "$continue_no_dependencies" =~ ^[Yy]$ ]]; then
            exit 1
        fi
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
            WANIP=$(dig @resolver4.opendns.com myip.opendns.com +short)
            echo -e "${GREEN}检测到的公网IP: $WANIP${NC}"
            ;;
        2)
            read -ep "请输入域名或IP地址: " WANIP
            # 验证域名/IP格式
            if ! [[ $WANIP =~ ^[a-zA-Z0-9]+([a-zA-Z0-9.-]*[a-zA-Z0-9]+)?$ ]] && ! [[ $WANIP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                echo -e "${RED}无效的域名或IP地址${NC}"
                exit 1
            fi
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            exit 1
            ;;
    esac
}

# 创建目录
create_directories() {
    # 创建 RustDesk 目录
    if [ ! -d "/opt/rustdesk" ]; then
        echo -e "${BLUE}创建 /opt/rustdesk 目录${NC}"
        sudo mkdir -p /opt/rustdesk/
    fi
    sudo chown "${UNAME}" -R /opt/rustdesk
    cd /opt/rustdesk/ || exit 1

    # 创建日志目录
    if [ ! -d "/var/log/rustdesk" ]; then
        echo -e "${BLUE}创建 /var/log/rustdesk 日志目录${NC}"
        sudo mkdir -p /var/log/rustdesk/
    fi
    sudo chown "${UNAME}" -R /var/log/rustdesk/
}

# 下载并安装 RustDesk
install_rustdesk() {
    echo -e "${BLUE}正在下载 RustDesk 服务器...${NC}"

    RDLATEST=$(curl https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest -s | grep "tag_name" | awk -F'"' '{print $4}')

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

    # 清理下载文件
    cleanup_install_files
}

# 清理安装文件
cleanup_install_files() {
    if [ "${ARCH}" = "x86_64" ]; then
        rm rustdesk-server-linux-amd64.zip
        rm -rf amd64
    elif [ "${ARCH}" = "armv7l" ]; then
        rm rustdesk-server-linux-armv7.zip
        rm -rf armv7
    elif [ "${ARCH}" = "aarch64" ]; then
        rm rustdesk-server-linux-arm64v8.zip
        rm -rf arm64v8
    fi
}

# 配置 Systemd 服务
configure_systemd_services() {
    echo -e "${BLUE}配置 Systemd 服务...${NC}"

    # Signal Server 服务
    rustdesksignal="$(cat << EOF
[Unit]
Description=Rustdesk Signal Server
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/opt/rustdesk/hbbs
WorkingDirectory=/opt/rustdesk/
User=${UNAME}
Group=${GNAME}
Restart=always
StandardOutput=append:/var/log/rustdesk/signalserver.log
StandardError=append:/var/log/rustdesk/signalserver.error
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
)"
    echo "${rustdesksignal}" | sudo tee /etc/systemd/system/rustdesksignal.service > /dev/null

    # Relay Server 服务
    rustdeskrelay="$(cat << EOF
[Unit]
Description=Rustdesk Relay Server
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/opt/rustdesk/hbbr
WorkingDirectory=/opt/rustdesk/
User=${UNAME}
Group=${GNAME}
Restart=always
StandardOutput=append:/var/log/rustdesk/relayserver.log
StandardError=append:/var/log/rustdesk/relayserver.error
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
)"
    echo "${rustdeskrelay}" | sudo tee /etc/systemd/system/rustdeskrelay.service > /dev/null

    # 重载并启动服务
    sudo systemctl daemon-reload
    sudo systemctl enable rustdesksignal.service
    sudo systemctl enable rustdeskrelay.service
    sudo systemctl start rustdesksignal.service
    sudo systemctl start rustdeskrelay.service

    # 等待服务启动
    echo -e "${BLUE}等待服务启动...${NC}"
    while ! [[ $CHECK_RUSTDESK_READY ]]; do
        CHECK_RUSTDESK_READY=$(sudo systemctl status rustdeskrelay.service | grep "Active: active (running)")
        echo -ne "Rustdesk Relay 服务尚未就绪...
"
        sleep 3
    done
}

# 获取配置信息
get_config_info() {
    PUBNAME=$(find /opt/rustdesk -name "*.pub")
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

# 安装主函数
install_main() {
    detect_os
    install_prerequisites
    get_connection_method
    create_directories
    install_rustdesk
    configure_systemd_services
    get_config_info

    echo -e "${GREEN}按任意键返回主菜单...${NC}"
    read -n 1
}

# 修改监听端口
modify_port() {
    if [ ! -f "/etc/systemd/system/rustdesksignal.service" ]; then
        echo -e "${RED}错误: RustDesk 未安装${NC}"
        echo -e "${GREEN}按任意键返回主菜单...${NC}"
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

    # 备份原始配置文件
    sudo cp /etc/systemd/system/rustdesksignal.service /etc/systemd/system/rustdesksignal.service.backup
    sudo cp /etc/systemd/system/rustdeskrelay.service /etc/systemd/system/rustdeskrelay.service.backup

    # 更新 Signal Server 配置 - 使用 .*来匹配行尾的所有内容（包括之前添加的端口参数）
    sudo sed -i "s|ExecStart=/opt/rustdesk/hbbs.*|ExecStart=/opt/rustdesk/hbbs -k _ -p ${new_signal_port}|g" /etc/systemd/system/rustdesksignal.service
    #sed -i: 直接修改文件内容（-i表示原地修改）。
    #s|...|...|g: 替换命令，将 ExecStart=/opt/rustdesk/hbbs.*替换为 ExecStart=/opt/rustdesk/hbbs -k _ -p ${new_signal_port}
    
    # 更新 Relay Server 配置 - 使用 .*来匹配行尾的所有内容（包括之前添加的端口参数）
    sudo sed -i "s|ExecStart=/opt/rustdesk/hbbr.*|ExecStart=/opt/rustdesk/hbbr -k _ -p ${new_relay_port}|g" /etc/systemd/system/rustdeskrelay.service

    # 重启服务
    echo -e "${BLUE}重启服务以应用更改...${NC}"
    sudo systemctl daemon-reload
    sudo systemctl restart rustdesksignal.service
    sudo systemctl restart rustdeskrelay.service

    echo -e "${GREEN}端口修改完成！${NC}"
    echo -e "${YELLOW}新的 Signal Server 端口: ${new_signal_port}${NC}"
    echo -e "${YELLOW}新的 Relay Server 端口: ${new_relay_port}${NC}"
    echo ""
    echo -e "${BLUE}注意: 客户端需要使用新的端口配置连接服务器${NC}"

    echo -e "${GREEN}按任意键返回主菜单...${NC}"
    read -n 1
}

# 卸载 RustDesk
uninstall_rustdesk() {
    if [ ! -f "/etc/systemd/system/rustdesksignal.service" ]; then
        echo -e "${RED}错误: RustDesk 未安装${NC}"
        echo -e "${GREEN}按任意键返回主菜单...${NC}"
        read -n 1
        return
    fi

    echo -e "${RED}警告: 此操作将完全卸载 RustDesk 服务器${NC}"
    echo -n "确认卸载? [y/N]: "
    read confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}取消卸载${NC}"
        echo -e "${GREEN}按任意键返回主菜单...${NC}"
        read -n 1
        return
    fi

    echo -e "${BLUE}停止服务...${NC}"
    sudo systemctl stop rustdesksignal.service
    sudo systemctl stop rustdeskrelay.service

    echo -e "${BLUE}禁用服务...${NC}"
    sudo systemctl disable rustdesksignal.service
    sudo systemctl disable rustdeskrelay.service

    echo -e "${BLUE}删除服务文件...${NC}"
    sudo rm -f /etc/systemd/system/rustdesksignal.service
    sudo rm -f /etc/systemd/system/rustdeskrelay.service

    echo -e "${BLUE}删除程序文件...${NC}"
    sudo rm -rf /opt/rustdesk/

    echo -e "${BLUE}删除日志文件...${NC}"
    sudo rm -rf /var/log/rustdesk/

    echo -e "${BLUE}重载 Systemd...${NC}"
    sudo systemctl daemon-reload

    echo -e "${GREEN}RustDesk 服务器已成功卸载！${NC}"

    # 检查是否安装了 HTTP 服务器
    if [ -f "/etc/systemd/system/gohttpserver.service" ]; then
        echo ""
        echo -n "是否同时卸载 HTTP 服务器? [y/N]: "
        read uninstall_http
        if [[ "$uninstall_http" =~ ^[Yy]$ ]]; then
            sudo systemctl stop gohttpserver.service
            sudo systemctl disable gohttpserver.service
            sudo rm -f /etc/systemd/system/gohttpserver.service
            sudo rm -rf /opt/gohttp/
            sudo rm -rf /var/log/gohttp/
            sudo systemctl daemon-reload
            echo -e "${GREEN}HTTP 服务器已成功卸载！${NC}"
        fi
    fi

    echo -e "${GREEN}按任意键返回主菜单...${NC}"
    read -n 1
}

# 查看服务状态
check_status() {
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}           RustDesk 服务状态${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""

    echo -e "${YELLOW}Signal Server 状态:${NC}"
    sudo systemctl status rustdesksignal.service --no-pager -l

    echo ""
    echo -e "${YELLOW}Relay Server 状态:${NC}"
    sudo systemctl status rustdeskrelay.service --no-pager -l

    if [ -f "/etc/systemd/system/gohttpserver.service" ]; then
        echo ""
        echo -e "${YELLOW}HTTP Server 状态:${NC}"
        sudo systemctl status gohttpserver.service --no-pager -l
    fi

    echo ""
    echo -e "${GREEN}按任意键返回主菜单...${NC}"
    read -n 1
}

# 主循环
main() {
    while true; do
        show_menu
        read -ep "请选择操作 [1-5]:" choice

        case $choice in
            1)
                install_main
                ;;
            2)
                modify_port
                ;;
            3)
                uninstall_rustdesk
                ;;
            4)
                check_status
                ;;
            5)
                echo -e "${BLUE}感谢使用 RustDesk 管理脚本！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${NC}"
                sleep 2
                ;;
        esac
    done
}

# 启动主程序
main

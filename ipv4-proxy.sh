#!/bin/bash
# IPv4 代理工具 - 统一入口脚本
# 让 IPv6-only VPS 通过 WireGuard 隧道代理其他 VPS 的 IPv4 访问能力

set -e

# 如果脚本是通过curl下载执行，则保存为原始文件名
if [[ "${BASH_SOURCE[0]}" == "bash" ]] && [[ -t 0 ]]; then
    # 获取原始文件名
    SCRIPT_URL="https://raw.githubusercontent.com/88899/gitmen-vps/main/ipv4-proxy.sh"
    SCRIPT_NAME="ipv4-proxy.sh"
    
    # 确定保存目录（优先使用当前目录，如果不可写则使用/root）
    if [ -w "." ]; then
        SCRIPT_DIR="$(pwd)"
    else
        SCRIPT_DIR="/root"
        mkdir -p "$SCRIPT_DIR" 2>/dev/null || true
    fi
    
    SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"
    
    # 下载并保存为原始文件名
    if curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_PATH" 2>/dev/null; then
        chmod +x "$SCRIPT_PATH"
        echo -e "\033[1;32m脚本已保存为: $SCRIPT_PATH\033[0m"
        echo -e "\033[1;33m正在执行脚本...\033[0m"
        sleep 1
        exec "$SCRIPT_PATH" "$@"
    else
        echo -e "\033[1;31m下载失败，请检查网络连接\033[0m"
        exit 1
    fi
fi

# 参数解析
if [ $# -gt 0 ]; then
    case $1 in
        --install-server)
            check_root
            install_server
            exit $?
            ;;
        --install-client)
            if [ $# -lt 3 ]; then
                echo "Usage: $0 --install-client <server_ipv6> <server_pubkey>"
                exit 1
            fi
            check_root
            install_client_auto "$2" "$3"
            exit $?
            ;;
        --add-client)
            if [ $# -lt 2 ]; then
                echo "Usage: $0 --add-client <client_pubkey> [client_ip]"
                exit 1
            fi
            check_root
            add_client_auto "$2" "${3:-10.66.66.2}"
            exit $?
            ;;
        --check-env)
            check_root
            check_environment
            exit $?
            ;;
        --show-server)
            check_root
            show_server_info
            exit $?
            ;;
        --show-client)
            check_root
            show_client_info
            exit $?
            ;;
        --manage-domains)
            check_root
            manage_domains
            exit $?
            ;;
        --show-status)
            check_root
            show_status
            exit $?
            ;;
        --start)
            check_root
            start_service
            exit $?
            ;;
        --stop)
            check_root
            stop_service
            exit $?
            ;;
        --uninstall)
            check_root
            uninstall
            exit $?
            ;;
        --update)
            check_root
            update_script
            exit $?
            ;;
        --help)
            echo "IPv4 代理工具 - 命令行模式"
            echo "Usage: $0 [option] [args...]"
            echo ""
            echo "安装选项:"
            echo "  --install-server                 在有 IPv4 的 VPS 上安装服务器端"
            echo "  --install-client <ipv6> <pubkey> 在 IPv6-only VPS 上安装客户端"
            echo "  --add-client <pubkey> [ip]       将客户端添加到服务器"
            echo ""
            echo "管理选项:"
            echo "  --check-env                      检测系统环境"
            echo "  --show-server                    查看服务器配置"
            echo "  --show-client                    查看客户端配置"
            echo "  --manage-domains                 管理分流域名"
            echo "  --show-status                    查看运行状态"
            echo "  --start                          启动服务"
            echo "  --stop                           停止服务"
            echo "  --uninstall                      卸载"
            echo "  --update                         更新脚本"
            echo ""
            echo "其他:"
            echo "  --help                           显示此帮助信息"
            echo "  (无参数)                         进入交互式菜单"
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
fi

# 检测终端是否支持颜色
if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    # 支持颜色
    re='\033[0m'
    red='\033[1;91m'
    green='\033[1;32m'
    yellow='\033[1;33m'
    blue='\033[1;34m'
    purple='\033[1;35m'
    skyblue='\033[1;96m'
    white='\033[1;97m'
else
    # 不支持颜色，禁用
    re=''
    red=''
    green=''
    yellow=''
    blue=''
    purple=''
    skyblue=''
    white=''
fi

# 配置
WG_IF="wg0"
WG_NET="10.66.66.0/24"
WG_SERVER_IP="10.66.66.1/24"
WG_CLIENT_IP="10.66.66.2/24"
WG_PORT=51820
WG_DIR="/etc/wireguard"
FW_MARK=0x66
RT_TABLE=100
RT_NAME="wg-ipv4"
NFT_TABLE="wg_route"
NFT_SET="wg_sites"

# 默认分流域名
DEFAULT_DOMAINS=(
    "tiktok.com"
    "youtube.com"
    "googlevideo.com"
    "google.com"
    "openai.com"
    "chatgpt.com"
    "anthropic.com"
    "claude.ai"
)

# 日志函数
log_info() {
    echo -e "${green}[✓]${re} $1"
}

log_warn() {
    echo -e "${yellow}[!]${re} $1"
}

log_error() {
    echo -e "${red}[✗]${re} $1"
}

log_step() {
    echo -e "${skyblue}[→]${re} $1"
}

# 等待用户返回
break_end() {
    echo ""
    echo -e "${yellow}按任意键返回主菜单...${re}"
    read -n 1 -s -r -p "" </dev/tty
    echo ""
}

# 打印三列菜单（表格样式）
print_three_columns() {
    # 使用更精确的方法处理对齐
    local col1="$1"
    local col2="$2"
    local col3="$3"
    
    # 移除颜色标记计算实际文本长度
    local len1=$(echo -e "$col1" | sed 's/\x1b\[[0-9;]*m//g' | wc -m)
    local len2=$(echo -e "$col2" | sed 's/\x1b\[[0-9;]*m//g' | wc -m)
    local len3=$(echo -e "$col3" | sed 's/\x1b\[[0-9;]*m//g' | wc -m)
    
    # 计算需要的填充空格数
    local pad1=$((40 - len1))
    local pad2=$((40 - len2))
    
    # 如果第三列为空，则只显示两列
    if [ -z "$col3" ]; then
        printf "  %s%*s%s\n" "$col1" $pad1 "" "$col2"
    else
        local pad3=$((40 - len3))
        printf "  %s%*s%s%*s%s\n" "$col1" $pad1 "" "$col2" $pad2 "" "$col3"
    fi
}

# 打印两列菜单（表格样式）
print_two_columns() {
    # 使用更精确的方法处理对齐
    local col1="$1"
    local col2="$2"
    
    # 移除颜色标记计算实际文本长度
    local len1=$(echo -e "$col1" | sed 's/\x1b\[[0-9;]*m//g' | wc -m)
    
    # 计算需要的填充空格数
    local pad1=$((60 - len1))
    
    # 显示两列
    printf "  %s%*s%s\n" "$col1" $pad1 "" "$col2"
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
        OS_VERSION=$(cat /etc/alpine-release)
    else
        log_error "无法检测操作系统"
        exit 1
    fi

    case $OS in
        debian|ubuntu)
            PKG_MANAGER="apt"
            ;;
        alpine)
            PKG_MANAGER="apk"
            ;;
        *)
            log_error "不支持的操作系统: $OS"
            echo "目前支持: Debian, Ubuntu, Alpine Linux"
            exit 1
            ;;
    esac
}

# 安装软件包
install_packages() {
    local packages="$1"

    case $PKG_MANAGER in
        apt)
            log_step "更新软件包列表..."
            apt update -qq
            log_step "安装软件包..."
            DEBIAN_FRONTEND=noninteractive apt install -y $packages >/dev/null 2>&1
            ;;
        apk)
            log_step "更新软件包列表..."
            apk update >/dev/null 2>&1
            log_step "安装软件包..."
            apk add $packages >/dev/null 2>&1
            ;;
    esac
}

# 检测默认网络接口
detect_interface() {
    ip route | awk '/default/ {print $5; exit}'
}

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${white}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
    echo -e "${skyblue}  ██╗██████╗ ██╗   ██╗██╗  ██╗    ██████╗ ██████╗  ██████╗ ██╗  ██╗██╗   ██╗${re}"
    echo -e "${skyblue}  ██║██╔══██╗██║   ██║██║  ██║    ██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝╚██╗ ██╔╝${re}"
    echo -e "${skyblue}  ██║██████╔╝██║   ██║███████║    ██████╔╝██████╔╝██║   ██║ ╚███╔╝  ╚████╔╝ ${re}"
    echo -e "${skyblue}  ██║██╔═══╝ ╚██╗ ██╔╝╚════██║    ██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗   ╚██╔╝  ${re}"
    echo -e "${skyblue}  ██║██║      ╚████╔╝      ██║    ██║     ██║  ██║╚██████╔╝██╔╝ ██╗   ██║   ${re}"
    echo -e "${skyblue}  ╚═╝╚═╝       ╚═══╝       ╚═╝    ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ${re}"
    echo ""
    echo -e "                    ${yellow}IPv4 代理工具 v1.0.0${re}"
    echo -e "        ${white}让 IPv6-only VPS 通过 WireGuard 代理 IPv4 网络${re}"
    echo -e "${white}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
    echo ""
    
    # 使用两列布局，确保对齐
    echo -e "${purple}【安装部署】${re}"
    echo -e "${green} 1.${re} 安装服务器端 ${skyblue}(有IPv4的VPS)${re}          ${green} 2.${re} 安装客户端 ${skyblue}(IPv6-only VPS)${re}"
    echo -e "${green} 3.${re} 添加客户端到服务器${re}"
    echo ""
    
    echo -e "${purple}【检测查看】${re}"
    echo -e "${green} 4.${re} 检测系统环境${re}                           ${green} 5.${re} 查看服务器配置${re}"
    echo -e "${green} 6.${re} 查看客户端配置${re}"
    echo ""
    
    echo -e "${purple}【管理维护】${re}"
    echo -e "${green} 7.${re} 管理分流域名${re}                           ${green} 8.${re} 查看运行状态${re}"
    echo -e "${green} 9.${re} 启动服务${re}                             ${green}10.${re} 停止服务${re}"
    echo -e "${red}11.${re} 卸载${re}"
    echo ""
    
    echo -e "${white}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
    echo -e "${green} 0.${re} 退出脚本${re}                             ${skyblue}99.${re} 更新脚本${re}"
    echo -e "${white}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
    echo -n -e "${red}请输入你的选择 [0-11/99]: ${re}"
}

# 安装服务器端
install_server() {
    clear
    echo -e "${blue}════════════════════════════════════════${re}"
    echo -e "${blue}  安装服务器端（IPv4 出口机）${re}"
    echo -e "${blue}════════════════════════════════════════${re}"
    echo

    log_step "检测系统..."
    detect_os
    log_info "操作系统: $OS $OS_VERSION"

    install_packages "wireguard-tools nftables iproute2"

    log_step "启用 IPv4 转发..."
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wg-ipv4.conf
    sysctl -p /etc/sysctl.d/99-wg-ipv4.conf >/dev/null 2>&1

    log_step "检测网络接口..."
    DEF_IF=$(detect_interface)
    if [ -z "$DEF_IF" ]; then
        log_error "无法检测到默认网络接口"
        return 1
    fi
    log_info "默认接口: $DEF_IF"

    mkdir -p "$WG_DIR"
    cd "$WG_DIR"

    if [ ! -f server.key ]; then
        log_step "生成 WireGuard 密钥..."
        wg genkey | tee server.key | wg pubkey > server.pub
        chmod 600 server.key
    else
        log_warn "密钥已存在，跳过生成"
    fi

    SERVER_KEY=$(cat server.key)

    log_step "创建 WireGuard 配置..."
    cat > wg0.conf <<EOF
[Interface]
Address = $WG_SERVER_IP
ListenPort = $WG_PORT
PrivateKey = $SERVER_KEY

# 客户端配置将通过菜单选项 3 添加
EOF
    chmod 600 wg0.conf

    log_step "配置 nftables NAT..."
    cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
flush ruleset
table inet wg_nat {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    oifname "$DEF_IF" ip saddr $WG_NET masquerade
  }
}
EOF
    chmod 755 /etc/nftables.conf

    # 启动 nftables
    case $OS in
        debian|ubuntu)
            systemctl enable nftables --now >/dev/null 2>&1
            ;;
        alpine)
            rc-update add nftables default >/dev/null 2>&1
            rc-service nftables start >/dev/null 2>&1
            ;;
    esac

    log_step "启动 WireGuard..."
    case $OS in
        debian|ubuntu)
            systemctl enable wg-quick@$WG_IF --now >/dev/null 2>&1
            ;;
        alpine)
            # Alpine 需要创建 OpenRC 服务
            ln -sf /etc/init.d/wg-quick /etc/init.d/wg-quick.$WG_IF 2>/dev/null || true
            rc-update add wg-quick.$WG_IF default >/dev/null 2>&1
            rc-service wg-quick.$WG_IF start >/dev/null 2>&1
            ;;
    esac

    echo
    echo -e "${green}════════════════════════════════════════${re}"
    echo -e "${green}  服务器端安装完成！${re}"
    echo -e "${green}════════════════════════════════════════${re}"
    echo
    echo "服务器公钥（请复制保存）："
    echo -e "${yellow}$(cat server.pub)${re}"
    echo
    echo "下一步："
    echo "1. 在客户端 VPS 上运行此脚本，选择菜单 2"
    echo "2. 获取客户端公钥后，回到本机选择菜单 3 添加客户端"
    echo
    break_end
}

# 安装客户端
install_client() {
    clear
    echo -e "${blue}════════════════════════════════════════${re}"
    echo -e "${blue}  安装客户端（IPv6-only VPS）${re}"
    echo -e "${blue}════════════════════════════════════════${re}"
    echo

    read -p "请输入服务器的 IPv6 地址: " SERVER_IPV6 </dev/tty
    if [ -z "$SERVER_IPV6" ]; then
        log_error "服务器 IPv6 地址不能为空"
        break_end
        return 1
    fi

    SERVER_IPV6="${SERVER_IPV6#[}"
    SERVER_IPV6="${SERVER_IPV6%]}"

    read -p "请输入服务器公钥: " SERVER_PUBKEY </dev/tty
    if [ -z "$SERVER_PUBKEY" ]; then
        log_error "服务器公钥不能为空"
        break_end
        return 1
    fi

    echo
    log_step "检测系统..."
    detect_os
    log_info "操作系统: $OS $OS_VERSION"

    install_packages "wireguard-tools nftables dnsmasq iproute2"

    mkdir -p "$WG_DIR"
    cd "$WG_DIR"

    if [ ! -f client.key ]; then
        log_step "生成 WireGuard 密钥..."
        wg genkey | tee client.key | wg pubkey > client.pub
        chmod 600 client.key
    else
        log_warn "密钥已存在，跳过生成"
    fi

    CLIENT_KEY=$(cat client.key)

    log_step "创建 WireGuard 配置..."
    cat > wg0.conf <<EOF
[Interface]
PrivateKey = $CLIENT_KEY
Address = $WG_CLIENT_IP

[Peer]
PublicKey = $SERVER_PUBKEY
Endpoint = [${SERVER_IPV6}]:${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    chmod 600 wg0.conf

    log_step "配置策略路由..."
    if ! grep -q "$RT_NAME" /etc/iproute2/rt_tables; then
        echo "$RT_TABLE $RT_NAME" >> /etc/iproute2/rt_tables
    fi

    log_step "配置 nftables..."
    cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
flush ruleset
table inet $NFT_TABLE {
  set $NFT_SET {
    type ipv4_addr
    flags interval
  }
  chain output {
    type route hook output priority mangle;
    ip daddr @$NFT_SET meta mark set $FW_MARK
  }
}
EOF
    chmod 755 /etc/nftables.conf

    # 启动 nftables
    case $OS in
        debian|ubuntu)
            systemctl enable nftables --now >/dev/null 2>&1
            ;;
        alpine)
            rc-update add nftables default >/dev/null 2>&1
            rc-service nftables start >/dev/null 2>&1
            ;;
    esac

    log_step "配置 dnsmasq..."
    mkdir -p /etc/dnsmasq.d
    cat > /etc/dnsmasq.d/wg-ipv4.conf <<EOF
# IPv4 分流域名配置
EOF

    for domain in "${DEFAULT_DOMAINS[@]}"; do
        echo "nftset=/${domain}/inet#${NFT_TABLE}#${NFT_SET}" >> /etc/dnsmasq.d/wg-ipv4.conf
    done

    # 创建域名列表
    cat > "$WG_DIR/domains.txt" <<EOF
# IPv4 分流域名列表（每行一个）
EOF
    for domain in "${DEFAULT_DOMAINS[@]}"; do
        echo "$domain" >> "$WG_DIR/domains.txt"
    done

    log_step "配置 DNS..."
    case $OS in
        debian|ubuntu)
            # 处理 systemd-resolved 冲突
            if [ -f /etc/systemd/resolved.conf ]; then
                sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
                systemctl restart systemd-resolved >/dev/null 2>&1
                ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf 2>/dev/null || true
            fi
            systemctl enable dnsmasq --now >/dev/null 2>&1
            ;;
        alpine)
            # Alpine 使用 OpenRC
            rc-update add dnsmasq default >/dev/null 2>&1
            rc-service dnsmasq start >/dev/null 2>&1
            ;;
    esac

    log_step "启动 WireGuard..."
    case $OS in
        debian|ubuntu)
            systemctl enable wg-quick@$WG_IF --now >/dev/null 2>&1
            ;;
        alpine)
            ln -sf /etc/init.d/wg-quick /etc/init.d/wg-quick.$WG_IF 2>/dev/null || true
            rc-update add wg-quick.$WG_IF default >/dev/null 2>&1
            rc-service wg-quick.$WG_IF start >/dev/null 2>&1
            ;;
    esac
    sleep 2

    log_step "设置策略路由..."
    ip route replace default dev $WG_IF table $RT_NAME 2>/dev/null || true
    ip rule add fwmark $FW_MARK table $RT_NAME 2>/dev/null || true

    echo
    echo -e "${green}════════════════════════════════════════${re}"
    echo -e "${green}  客户端安装完成！${re}"
    echo -e "${green}════════════════════════════════════════${re}"
    echo
    echo "客户端公钥（请复制保存）："
    echo -e "${yellow}$(cat client.pub)${re}"
    echo
    echo "下一步："
    echo "在服务器上运行此脚本，选择菜单 3，输入上面的公钥"
    echo
    break_end
}

# 自动安装客户端（命令行模式）
install_client_auto() {
    SERVER_IPV6=$1
    SERVER_PUBKEY=$2

    SERVER_IPV6="${SERVER_IPV6#[}"
    SERVER_IPV6="${SERVER_IPV6%]}"

    echo -e "${blue}════════════════════════════════════════${re}"
    echo -e "${blue}  自动安装客户端（IPv6-only VPS）${re}"
    echo -e "${blue}════════════════════════════════════════${re}"
    echo

    log_step "检测系统..."
    detect_os
    log_info "操作系统: $OS $OS_VERSION"

    install_packages "wireguard-tools nftables dnsmasq iproute2"

    mkdir -p "$WG_DIR"
    cd "$WG_DIR"

    if [ ! -f client.key ]; then
        log_step "生成 WireGuard 密钥..."
        wg genkey | tee client.key | wg pubkey > client.pub
        chmod 600 client.key
    else
        log_warn "密钥已存在，跳过生成"
    fi

    CLIENT_KEY=$(cat client.key)

    log_step "创建 WireGuard 配置..."
    cat > wg0.conf <<EOF
[Interface]
PrivateKey = $CLIENT_KEY
Address = $WG_CLIENT_IP

[Peer]
PublicKey = $SERVER_PUBKEY
Endpoint = [${SERVER_IPV6}]:${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    chmod 600 wg0.conf

    log_step "配置策略路由..."
    if ! grep -q "$RT_NAME" /etc/iproute2/rt_tables; then
        echo "$RT_TABLE $RT_NAME" >> /etc/iproute2/rt_tables
    fi

    log_step "配置 nftables..."
    cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
flush ruleset
table inet $NFT_TABLE {
  set $NFT_SET {
    type ipv4_addr
    flags interval
  }
  chain output {
    type route hook output priority mangle;
    ip daddr @$NFT_SET meta mark set $FW_MARK
  }
}
EOF
    chmod 755 /etc/nftables.conf

    # 启动 nftables
    case $OS in
        debian|ubuntu)
            systemctl enable nftables --now >/dev/null 2>&1
            ;;
        alpine)
            rc-update add nftables default >/dev/null 2>&1
            rc-service nftables start >/dev/null 2>&1
            ;;
    esac

    log_step "配置 dnsmasq..."
    mkdir -p /etc/dnsmasq.d
    cat > /etc/dnsmasq.d/wg-ipv4.conf <<EOF
# IPv4 分流域名配置
EOF

    for domain in "${DEFAULT_DOMAINS[@]}"; do
        echo "nftset=/${domain}/inet#${NFT_TABLE}#${NFT_SET}" >> /etc/dnsmasq.d/wg-ipv4.conf
    done

    # 创建域名列表
    cat > "$WG_DIR/domains.txt" <<EOF
# IPv4 分流域名列表（每行一个）
EOF
    for domain in "${DEFAULT_DOMAINS[@]}"; do
        echo "$domain" >> "$WG_DIR/domains.txt"
    done

    log_step "配置 DNS..."
    case $OS in
        debian|ubuntu)
            # 处理 systemd-resolved 冲突
            if [ -f /etc/systemd/resolved.conf ]; then
                sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
                systemctl restart systemd-resolved >/dev/null 2>&1
                ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf 2>/dev/null || true
            fi
            systemctl enable dnsmasq --now >/dev/null 2>&1
            ;;
        alpine)
            # Alpine 使用 OpenRC
            rc-update add dnsmasq default >/dev/null 2>&1
            rc-service dnsmasq start >/dev/null 2>&1
            ;;
    esac

    log_step "启动 WireGuard..."
    case $OS in
        debian|ubuntu)
            systemctl enable wg-quick@$WG_IF --now >/dev/null 2>&1
            ;;
        alpine)
            ln -sf /etc/init.d/wg-quick /etc/init.d/wg-quick.$WG_IF 2>/dev/null || true
            rc-update add wg-quick.$WG_IF default >/dev/null 2>&1
            rc-service wg-quick.$WG_IF start >/dev/null 2>&1
            ;;
    esac
    sleep 2

    log_step "设置策略路由..."
    ip route replace default dev $WG_IF table $RT_NAME 2>/dev/null || true
    ip rule add fwmark $FW_MARK table $RT_NAME 2>/dev/null || true

    echo
    echo -e "${green}════════════════════════════════════════${re}"
    echo -e "${green}  客户端安装完成！${re}"
    echo -e "${green}════════════════════════════════════════${re}"
    echo
    echo "客户端公钥（请复制保存）："
    echo -e "${yellow}$(cat client.pub)${re}"
    echo
    echo "下一步："
    echo "在服务器上运行此脚本，选择菜单 3，输入上面的公钥"
    echo
}

# 添加客户端到服务器
add_client() {
    clear
    echo -e "${blue}════════════════════════════════════════${re}"
    echo -e "${blue}  添加客户端到服务器${re}"
    echo -e "${blue}════════════════════════════════════════${re}"
    echo

    if [ ! -f "$WG_DIR/wg0.conf" ]; then
        log_error "未找到服务器配置，请先安装服务器端（菜单 1）"
        break_end
        return 1
    fi

    read -p "请输入客户端公钥: " CLIENT_PUBKEY </dev/tty
    if [ -z "$CLIENT_PUBKEY" ]; then
        log_error "客户端公钥不能为空"
        break_end
        return 1
    fi

    read -p "请输入客户端 IP [默认: 10.66.66.2]: " CLIENT_IP </dev/tty
    CLIENT_IP=${CLIENT_IP:-10.66.66.2}

    echo
    log_step "添加客户端配置..."

    if grep -q "$CLIENT_PUBKEY" "$WG_DIR/wg0.conf"; then
        log_warn "客户端已存在，更新配置..."
        # 删除包含该公钥的 Peer 块
        sed -i "/\[Peer\]/,/AllowedIPs.*$/{ /PublicKey = ${CLIENT_PUBKEY}/,/AllowedIPs.*$/d; }" "$WG_DIR/wg0.conf" 2>/dev/null || true
    fi

    cat >> "$WG_DIR/wg0.conf" <<EOF

[Peer]
PublicKey = $CLIENT_PUBKEY
AllowedIPs = ${CLIENT_IP}/32
EOF

    log_step "重新加载配置..."
    # 检查 WireGuard 是否运行
    if wg show wg0 >/dev/null 2>&1; then
        wg syncconf wg0 <(wg-quick strip wg0) 2>/dev/null || {
            case $OS in
                debian|ubuntu)
                    systemctl restart wg-quick@wg0 2>/dev/null
                    ;;
                alpine)
                    rc-service wg-quick.$WG_IF restart 2>/dev/null
                    ;;
            esac
        }
    else
        log_warn "WireGuard 未运行，请先启动服务（菜单 6）"
    fi

    echo
    log_info "客户端添加成功！"
    echo
    echo "当前连接的客户端："
    wg show wg0 peers 2>/dev/null || echo "  暂无连接"
    echo
    break_end
}

# 自动添加客户端到服务器（命令行模式）
add_client_auto() {
    CLIENT_PUBKEY=$1
    CLIENT_IP=$2

    echo -e "${blue}════════════════════════════════════════${re}"
    echo -e "${blue}  自动添加客户端到服务器${re}"
    echo -e "${blue}════════════════════════════════════════${re}"
    echo

    if [ ! -f "$WG_DIR/wg0.conf" ]; then
        log_error "未找到服务器配置，请先安装服务器端"
        return 1
    fi

    echo
    log_step "添加客户端配置..."

    if grep -q "$CLIENT_PUBKEY" "$WG_DIR/wg0.conf"; then
        log_warn "客户端已存在，更新配置..."
        # 删除包含该公钥的 Peer 块
        sed -i "/\[Peer\]/,/AllowedIPs.*$/{ /PublicKey = ${CLIENT_PUBKEY}/,/AllowedIPs.*$/d; }" "$WG_DIR/wg0.conf" 2>/dev/null || true
    fi

    cat >> "$WG_DIR/wg0.conf" <<EOF

[Peer]
PublicKey = $CLIENT_PUBKEY
AllowedIPs = ${CLIENT_IP}/32
EOF

    log_step "重新加载配置..."
    # 检查 WireGuard 是否运行
    if wg show wg0 >/dev/null 2>&1; then
        wg syncconf wg0 <(wg-quick strip wg0) 2>/dev/null || {
            case $OS in
                debian|ubuntu)
                    systemctl restart wg-quick@wg0 2>/dev/null
                    ;;
                alpine)
                    rc-service wg-quick.$WG_IF restart 2>/dev/null
                    ;;
            esac
        }
    else
        log_warn "WireGuard 未运行，请先启动服务"
    fi

    echo
    log_info "客户端添加成功！"
    echo
    echo "当前连接的客户端："
    wg show wg0 peers 2>/dev/null || echo "  暂无连接"
    echo
}

# 管理域名菜单
manage_domains() {
    while true; do
        clear
        echo -e "${blue}════════════════════════════════════════${re}"
        echo -e "${blue}  管理分流域名${re}"
        echo -e "${blue}════════════════════════════════════════${re}"
        echo
        echo "  1) 查看域名列表"
        echo "  2) 添加域名"
        echo "  3) 删除域名"
        echo "  0) 返回主菜单"
        echo
        echo -n "请选择 [0-3]: "
        read choice

        case $choice in
            1) list_domains ;;
            2) add_domain ;;
            3) remove_domain ;;
            0) return ;;
            *) log_error "无效选择"; sleep 1 ;;
        esac
    done
}

# 查看域名列表
list_domains() {
    clear
    echo -e "${blue}════════════════════════════════════════${re}"
    echo -e "${blue}  当前分流域名列表${re}"
    echo -e "${blue}════════════════════════════════════════${re}"
    echo

    if [ ! -f "$WG_DIR/domains.txt" ]; then
        log_error "域名列表文件不存在"
        break_end
        return 1
    fi

    grep -v "^#" "$WG_DIR/domains.txt" | grep -v "^$" | nl
    echo
    echo "总计: $(grep -v "^#" "$WG_DIR/domains.txt" | grep -v "^$" | wc -l) 个域名"
    echo
    break_end
}

# 添加域名
add_domain() {
    clear
    echo -e "${blue}════════════════════════════════════════${re}"
    echo -e "${blue}  添加分流域名${re}"
    echo -e "${blue}════════════════════════════════════════${re}"
    echo

    if [ ! -f /etc/dnsmasq.d/wg-ipv4.conf ]; then
        log_error "dnsmasq 配置不存在，请先安装客户端（菜单 2）"
        break_end
        return 1
    fi

    read -p "请输入要添加的域名（多个用空格分隔）: " domains </dev/tty
    if [ -z "$domains" ]; then
        log_error "域名不能为空"
        break_end
        return 1
    fi

    echo
    for domain in $domains; do
        if grep -q "nftset=/${domain}/" /etc/dnsmasq.d/wg-ipv4.conf; then
            log_warn "域名 $domain 已存在，跳过"
            continue
        fi

        log_info "添加域名: $domain"
        echo "nftset=/${domain}/inet#${NFT_TABLE}#${NFT_SET}" >> /etc/dnsmasq.d/wg-ipv4.conf
        echo "$domain" >> "$WG_DIR/domains.txt"
    done

    detect_os >/dev/null 2>&1
    log_step "重启 dnsmasq..."
    case $OS in
        debian|ubuntu)
            systemctl restart dnsmasq
            ;;
        alpine)
            rc-service dnsmasq restart
            ;;
    esac

    echo
    log_info "域名添加完成！"
    break_end
}

# 删除域名
remove_domain() {
    clear
    echo -e "${blue}════════════════════════════════════════${re}"
    echo -e "${blue}  删除分流域名${re}"
    echo -e "${blue}════════════════════════════════════════${re}"
    echo

    if [ ! -f /etc/dnsmasq.d/wg-ipv4.conf ]; then
        log_error "dnsmasq 配置不存在"
        break_end
        return 1
    fi

    read -p "请输入要删除的域名（多个用空格分隔）: " domains </dev/tty
    if [ -z "$domains" ]; then
        log_error "域名不能为空"
        break_end
        return 1
    fi

    echo
    for domain in $domains; do
        # 转义特殊字符
        escaped_domain=$(echo "$domain" | sed 's/\./\\./g')
        log_info "删除域名: $domain"
        sed -i "/nftset=\/${escaped_domain}\//d" /etc/dnsmasq.d/wg-ipv4.conf
        sed -i "/^${escaped_domain}$/d" "$WG_DIR/domains.txt" 2>/dev/null || true
    done

    log_step "重启 dnsmasq..."
    case $OS in
        debian|ubuntu)
            systemctl restart dnsmasq
            ;;
        alpine)
            rc-service dnsmasq restart
            ;;
    esac

    echo
    log_info "域名删除完成！"
    break_end
}

# 检测系统环境
check_environment() {
    clear
    echo -e "${blue}════════════════════════════════════════${re}"
    echo -e "${blue}  系统环境检测${re}"
    echo -e "${blue}════════════════════════════════════════${re}"
    echo

    # 检测操作系统
    echo "【操作系统】"
    detect_os 2>/dev/null || true
    if [ -n "$OS" ]; then
        log_info "系统: $OS $OS_VERSION"
        log_info "包管理器: $PKG_MANAGER"
    else
        log_error "无法检测操作系统"
    fi
    echo

    # 检测网络接口
    echo "【网络接口】"
    DEF_IF=$(detect_interface)
    if [ -n "$DEF_IF" ]; then
        log_info "默认接口: $DEF_IF"

        # 显示接口 IP 地址
        if command -v ip >/dev/null 2>&1; then
            echo "  IPv4 地址:"
            ip -4 addr show "$DEF_IF" 2>/dev/null | grep inet | awk '{print "    " $2}' || echo "    无"
            echo "  IPv6 地址:"
            ip -6 addr show "$DEF_IF" 2>/dev/null | grep inet6 | grep -v "fe80" | awk '{print "    " $2}' || echo "    无"
        fi
    else
        log_warn "无法检测默认网络接口"
    fi
    echo

    # 检测已安装的软件
    echo "【软件包检测】"
    packages=("wireguard" "wireguard-tools" "nftables" "dnsmasq" "iproute2" "curl")
    for pkg in "${packages[@]}"; do
        if command -v wg >/dev/null 2>&1 && [ "$pkg" = "wireguard" ]; then
            log_info "$pkg: 已安装 ($(wg --version 2>&1 | head -1))"
        elif command -v nft >/dev/null 2>&1 && [ "$pkg" = "nftables" ]; then
            log_info "$pkg: 已安装 ($(nft --version 2>&1))"
        elif command -v dnsmasq >/dev/null 2>&1 && [ "$pkg" = "dnsmasq" ]; then
            log_info "$pkg: 已安装 ($(dnsmasq --version 2>&1 | head -1))"
        elif command -v ip >/dev/null 2>&1 && [ "$pkg" = "iproute2" ]; then
            log_info "$pkg: 已安装"
        elif command -v curl >/dev/null 2>&1 && [ "$pkg" = "curl" ]; then
            log_info "$pkg: 已安装"
        elif [ "$pkg" = "wireguard-tools" ]; then
            continue
        else
            log_warn "$pkg: 未安装"
        fi
    done
    echo

    # 检测现有配置
    echo "【现有配置】"
    if [ -f "$WG_DIR/wg0.conf" ]; then
        log_info "WireGuard 配置: 已存在"
        if grep -q "\[Peer\]" "$WG_DIR/wg0.conf" 2>/dev/null; then
            peer_count=$(grep -c "\[Peer\]" "$WG_DIR/wg0.conf")
            echo "  对等节点数: $peer_count"
        fi
    else
        log_warn "WireGuard 配置: 不存在"
    fi

    if [ -f /etc/nftables.conf ]; then
        log_info "nftables 配置: 已存在"
    else
        log_warn "nftables 配置: 不存在"
    fi

    if [ -f /etc/dnsmasq.d/wg-ipv4.conf ]; then
        log_info "dnsmasq 配置: 已存在"
        domain_count=$(grep -c "^nftset=" /etc/dnsmasq.d/wg-ipv4.conf 2>/dev/null || echo 0)
        echo "  分流域名数: $domain_count"
    else
        log_warn "dnsmasq 配置: 不存在"
    fi
    echo

    # 检测防火墙端口
    echo "【防火墙/端口】"
    if command -v ss >/dev/null 2>&1; then
        if ss -ulnp 2>/dev/null | grep -q ":$WG_PORT"; then
            log_info "UDP $WG_PORT: 正在监听"
        else
            log_warn "UDP $WG_PORT: 未监听"
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -ulnp 2>/dev/null | grep -q ":$WG_PORT"; then
            log_info "UDP $WG_PORT: 正在监听"
        else
            log_warn "UDP $WG_PORT: 未监听"
        fi
    else
        log_warn "无法检测端口状态（ss/netstat 未安装）"
    fi
    echo

    # 检测 IPv4 转发
    echo "【系统配置】"
    if [ -f /proc/sys/net/ipv4/ip_forward ]; then
        forward_status=$(cat /proc/sys/net/ipv4/ip_forward)
        if [ "$forward_status" = "1" ]; then
            log_info "IPv4 转发: 已启用"
        else
            log_warn "IPv4 转发: 未启用"
        fi
    fi

    if grep -q "$RT_NAME" /etc/iproute2/rt_tables 2>/dev/null; then
        log_info "策略路由表: 已配置"
    else
        log_warn "策略路由表: 未配置"
    fi
    echo

    break_end
}

# 查看服务器配置信息
show_server_info() {
    clear
    echo -e "${blue}════════════════════════════════════════${re}"
    echo -e "${blue}  服务器配置信息${re}"
    echo -e "${blue}════════════════════════════════════════${re}"
    echo

    if [ ! -f "$WG_DIR/wg0.conf" ]; then
        log_error "未找到服务器配置"
        echo
        echo "请先安装服务器端（菜单 1）"
        echo
        break_end
        return 1
    fi

    # 显示服务器公钥
    echo "【服务器信息】"
    if [ -f "$WG_DIR/server.pub" ]; then
        echo "服务器公钥:"
        echo -e "${yellow}$(cat $WG_DIR/server.pub)${re}"
    else
        log_warn "服务器公钥文件不存在"
    fi
    echo

    # 显示监听配置
    echo "【监听配置】"
    if grep -q "ListenPort" "$WG_DIR/wg0.conf"; then
        port=$(grep "ListenPort" "$WG_DIR/wg0.conf" | awk '{print $3}')
        log_info "监听端口: UDP $port"
    fi

    if grep -q "Address" "$WG_DIR/wg0.conf"; then
        addr=$(grep "Address" "$WG_DIR/wg0.conf" | head -1 | awk '{print $3}')
        log_info "隧道地址: $addr"
    fi
    echo

    # 显示客户端列表
    echo "【已添加的客户端】"
    if grep -q "\[Peer\]" "$WG_DIR/wg0.conf"; then
        peer_count=$(grep -c "\[Peer\]" "$WG_DIR/wg0.conf")
        echo "客户端数量: $peer_count"
        echo

        # 提取每个客户端的信息
        awk '/\[Peer\]/{flag=1; count++; print "客户端 " count ":"}
             flag && /PublicKey/{print "  公钥: " $3}
             flag && /AllowedIPs/{print "  IP: " $3; flag=0}' "$WG_DIR/wg0.conf"
    else
        echo "暂无客户端"
    fi
    echo

    # 显示 NAT 配置
    echo "【NAT 配置】"
    if [ -f /etc/nftables.conf ]; then
        if grep -q "masquerade" /etc/nftables.conf; then
            log_info "NAT 已配置"
            echo "  源网段: $WG_NET"
            out_if=$(grep "oifname" /etc/nftables.conf | awk -F'"' '{print $2}' | head -1)
            if [ -n "$out_if" ]; then
                echo "  出口接口: $out_if"
            fi
        else
            log_warn "NAT 未配置"
        fi
    else
        log_warn "nftables 配置文件不存在"
    fi
    echo

    # 显示连接状态
    echo "【连接状态】"
    if wg show wg0 >/dev/null 2>&1; then
        log_info "WireGuard 运行中"
        echo
        wg show wg0 2>/dev/null | grep -A 5 "peer:"
    else
        log_warn "WireGuard 未运行"
    fi
    echo

    # 显示给客户端的配置信息
    echo "【客户端需要的信息】"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "请将以下信息提供给客户端："
    echo

    # 获取服务器 IPv6 地址
    echo "1. 服务器 IPv6 地址:"
    DEF_IF=$(detect_interface)
    if [ -n "$DEF_IF" ]; then
        ipv6_addr=$(ip -6 addr show "$DEF_IF" 2>/dev/null | grep "inet6" | grep -v "fe80" | head -1 | awk '{print $2}' | cut -d'/' -f1)
        if [ -n "$ipv6_addr" ]; then
            echo -e "   ${yellow}$ipv6_addr${re}"
        else
            echo "   无法获取（请手动查看）"
        fi
    fi
    echo

    echo "2. 服务器公钥:"
    if [ -f "$WG_DIR/server.pub" ]; then
        echo -e "   ${yellow}$(cat $WG_DIR/server.pub)${re}"
    fi
    echo

    echo "3. 监听端口:"
    if grep -q "ListenPort" "$WG_DIR/wg0.conf"; then
        port=$(grep "ListenPort" "$WG_DIR/wg0.conf" | awk '{print $3}')
        echo -e "   ${yellow}$port${re}"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    break_end
}

# 查看客户端配置信息
show_client_info() {
    clear
    echo -e "${blue}════════════════════════════════════════${re}"
    echo -e "${blue}  客户端配置信息${re}"
    echo -e "${blue}════════════════════════════════════════${re}"
    echo

    if [ ! -f "$WG_DIR/wg0.conf" ]; then
        log_error "未找到客户端配置"
        echo
        echo "请先安装客户端（菜单 2）"
        echo
        break_end
        return 1
    fi

    # 显示客户端公钥
    echo "【客户端信息】"
    if [ -f "$WG_DIR/client.pub" ]; then
        echo "客户端公钥（需添加到服务器）:"
        echo -e "${yellow}$(cat $WG_DIR/client.pub)${re}"
    else
        log_warn "客户端公钥文件不存在"
    fi
    echo

    # 显示隧道配置
    echo "【隧道配置】"
    if grep -q "Address" "$WG_DIR/wg0.conf"; then
        addr=$(grep "Address" "$WG_DIR/wg0.conf" | awk '{print $3}')
        log_info "隧道地址: $addr"
    fi

    if grep -q "Endpoint" "$WG_DIR/wg0.conf"; then
        endpoint=$(grep "Endpoint" "$WG_DIR/wg0.conf" | awk '{print $3}')
        log_info "服务器端点: $endpoint"
    fi
    echo

    # 显示分流域名
    echo "【分流域名配置】"
    if [ -f "$WG_DIR/domains.txt" ]; then
        domain_count=$(grep -v "^#" "$WG_DIR/domains.txt" | grep -v "^$" | wc -l)
        log_info "分流域名数量: $domain_count"
        echo
        echo "当前分流的域名:"
        grep -v "^#" "$WG_DIR/domains.txt" | grep -v "^$" | head -10 | sed 's/^/  - /'
        if [ $domain_count -gt 10 ]; then
            echo "  ... 还有 $((domain_count - 10)) 个域名"
        fi
    else
        log_warn "域名列表文件不存在"
    fi
    echo

    # 显示策略路由
    echo "【策略路由】"
    if ip rule show 2>/dev/null | grep -q "fwmark $FW_MARK"; then
        log_info "策略路由规则: 已配置"
        ip rule show | grep "$FW_MARK"
    else
        log_warn "策略路由规则: 未配置"
    fi

    if ip route show table $RT_NAME 2>/dev/null | grep -q "default"; then
        log_info "路由表 $RT_NAME: 已配置"
        ip route show table $RT_NAME | head -3
    else
        log_warn "路由表 $RT_NAME: 未配置"
    fi
    echo

    # 显示 nftables 规则
    echo "【流量标记规则】"
    if nft list set inet $NFT_TABLE $NFT_SET 2>/dev/null | grep -q "type ipv4_addr"; then
        log_info "nftables IP 集合: 已配置"
        ip_count=$(nft list set inet $NFT_TABLE $NFT_SET 2>/dev/null | grep -o "elements = {" | wc -l)
        if [ "$ip_count" -gt 0 ]; then
            echo "  当前 IP 数量: $(nft list set inet $NFT_TABLE $NFT_SET 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+' | wc -l)"
        else
            echo "  IP 集合为空（正常，需要 DNS 查询后填充）"
        fi
    else
        log_warn "nftables IP 集合: 未配置"
    fi
    echo

    # 显示 DNS 配置
    echo "【DNS 配置】"
    if [ -f /etc/dnsmasq.d/wg-ipv4.conf ]; then
        log_info "dnsmasq 配置: 已存在"
        if pgrep -x dnsmasq >/dev/null 2>&1; then
            log_info "dnsmasq 服务: 运行中"
        else
            log_warn "dnsmasq 服务: 未运行"
        fi
    else
        log_warn "dnsmasq 配置: 不存在"
    fi
    echo

    # 显示连接状态
    echo "【连接状态】"
    if wg show wg0 >/dev/null 2>&1; then
        log_info "WireGuard: 运行中"
        echo
        if wg show wg0 | grep -q "latest handshake"; then
            log_info "与服务器握手成功"
            wg show wg0 | grep "latest handshake"
            wg show wg0 | grep "transfer"
        else
            log_warn "未与服务器建立连接"
        fi
    else
        log_warn "WireGuard: 未运行"
    fi
    echo

    # 测试连通性
    echo "【连通性测试】"
    if command -v curl >/dev/null 2>&1; then
        echo -n "测试 IPv4 出口... "
        ipv4=$(timeout 5 curl -4 -s ip.sb 2>/dev/null)
        if [ -n "$ipv4" ]; then
            echo -e "${green}成功${re}"
            echo "  IPv4 地址: $ipv4"
        else
            echo -e "${red}失败${re}"
        fi

        echo -n "测试 IPv6 出口... "
        ipv6=$(timeout 5 curl -6 -s ip.sb 2>/dev/null)
        if [ -n "$ipv6" ]; then
            echo -e "${green}成功${re}"
            echo "  IPv6 地址: $ipv6"
        else
            echo -e "${yellow}无 IPv6${re}"
        fi
    else
        log_warn "curl 未安装，跳过测试"
    fi
    echo

    break_end
}

# 查看状态
show_status() {
    clear
    echo -e "${blue}════════════════════════════════════════${re}"
    echo -e "${blue}  系统状态${re}"
    echo -e "${blue}════════════════════════════════════════${re}"
    echo

    echo "【WireGuard 状态】"
    if wg show wg0 >/dev/null 2>&1; then
        log_info "WireGuard 运行中"
        wg show wg0 2>/dev/null || echo "  无法获取详细信息"
    else
        log_error "WireGuard 未运行"
    fi
    echo

    echo "【nftables 状态】"
    if nft list ruleset >/dev/null 2>&1; then
        log_info "nftables 运行中"
        if nft list set inet wg_route wg_sites 2>/dev/null | grep -q "elements"; then
            echo "  IP 集合："
            nft list set inet wg_route wg_sites 2>/dev/null | grep -A 5 "elements"
        else
            echo "  IP 集合为空（正常，需要 DNS 查询后才会填充）"
        fi
    else
        log_error "nftables 未运行"
    fi
    echo

    if [ -f /etc/dnsmasq.d/wg-ipv4.conf ]; then
        echo "【dnsmasq 状态】"
        if pgrep -x dnsmasq >/dev/null 2>&1; then
            log_info "dnsmasq 运行中"
            domain_count=$(grep -c "^nftset=" /etc/dnsmasq.d/wg-ipv4.conf 2>/dev/null || echo 0)
            echo "  分流域名数量: $domain_count"
        else
            log_error "dnsmasq 未运行"
        fi
        echo
    fi

    echo "【连通性测试】"
    if command -v curl >/dev/null 2>&1; then
        echo -n "IPv4 出口: "
        timeout 5 curl -4 -s ip.sb 2>/dev/null || echo "无法连接"
        echo -n "IPv6 出口: "
        timeout 5 curl -6 -s ip.sb 2>/dev/null || echo "无法连接"
    else
        echo "curl 未安装，跳过测试"
    fi

    echo
    break_end
}

# 启动服务
start_service() {
    clear
    echo -e "${blue}════════════════════════════════════════${re}"
    echo -e "${blue}  启动服务${re}"
    echo -e "${blue}════════════════════════════════════════${re}"
    echo

    detect_os >/dev/null 2>&1

    log_step "启动 nftables..."
    case $OS in
        debian|ubuntu)
            systemctl start nftables 2>/dev/null && log_info "nftables 已启动" || log_warn "nftables 启动失败"
            ;;
        alpine)
            rc-service nftables start 2>/dev/null && log_info "nftables 已启动" || log_warn "nftables 启动失败"
            ;;
    esac

    log_step "启动 WireGuard..."
    case $OS in
        debian|ubuntu)
            systemctl start wg-quick@$WG_IF 2>/dev/null && log_info "WireGuard 已启动" || log_warn "WireGuard 启动失败"
            ;;
        alpine)
            rc-service wg-quick.$WG_IF start 2>/dev/null && log_info "WireGuard 已启动" || log_warn "WireGuard 启动失败"
            ;;
    esac

    if [ -f /etc/dnsmasq.d/wg-ipv4.conf ]; then
        log_step "启动 dnsmasq..."
        case $OS in
            debian|ubuntu)
                systemctl start dnsmasq 2>/dev/null && log_info "dnsmasq 已启动" || log_warn "dnsmasq 启动失败"
                ;;
            alpine)
                rc-service dnsmasq start 2>/dev/null && log_info "dnsmasq 已启动" || log_warn "dnsmasq 启动失败"
                ;;
        esac
    fi

    sleep 2
    if [ -f "$WG_DIR/wg0.conf" ] && grep -q "Peer" "$WG_DIR/wg0.conf" 2>/dev/null; then
        log_step "设置策略路由..."
        ip route replace default dev $WG_IF table $RT_NAME 2>/dev/null || true
        ip rule add fwmark $FW_MARK table $RT_NAME 2>/dev/null || true
    fi

    echo
    log_info "服务启动完成！"
    break_end
}

# 停止服务
stop_service() {
    clear
    echo -e "${blue}════════════════════════════════════════${re}"
    echo -e "${blue}  停止服务${re}"
    echo -e "${blue}════════════════════════════════════════${re}"
    echo

    detect_os >/dev/null 2>&1

    log_step "停止 dnsmasq..."
    case $OS in
        debian|ubuntu)
            systemctl stop dnsmasq 2>/dev/null && log_info "dnsmasq 已停止" || log_warn "dnsmasq 未运行"
            ;;
        alpine)
            rc-service dnsmasq stop 2>/dev/null && log_info "dnsmasq 已停止" || log_warn "dnsmasq 未运行"
            ;;
    esac

    log_step "停止 WireGuard..."
    case $OS in
        debian|ubuntu)
            systemctl stop wg-quick@$WG_IF 2>/dev/null && log_info "WireGuard 已停止" || log_warn "WireGuard 未运行"
            ;;
        alpine)
            rc-service wg-quick.$WG_IF stop 2>/dev/null && log_info "WireGuard 已停止" || log_warn "WireGuard 未运行"
            ;;
    esac

    log_step "清理策略路由..."
    ip rule del fwmark $FW_MARK table $RT_NAME 2>/dev/null || true
    log_info "策略路由已清理"

    echo
    log_info "服务停止完成！"
    break_end
}

# 卸载
uninstall() {
    clear
    echo -e "${red}════════════════════════════════════════${re}"
    echo -e "${red}  卸载 IPv4 代理工具${re}"
    echo -e "${red}════════════════════════════════════════${re}"
    echo
    log_warn "此操作将完全卸载所有配置"
    echo
    read -p "确认继续？(yes/no): " confirm </dev/tty

    if [ "$confirm" != "yes" ]; then
        log_info "取消卸载"
        break_end
        return
    fi

    echo
    detect_os >/dev/null 2>&1

    log_step "停止服务..."
    case $OS in
        debian|ubuntu)
            systemctl stop wg-quick@$WG_IF 2>/dev/null || true
            systemctl stop dnsmasq 2>/dev/null || true
            systemctl disable wg-quick@$WG_IF 2>/dev/null || true
            ;;
        alpine)
            rc-service wg-quick.$WG_IF stop 2>/dev/null || true
            rc-service dnsmasq stop 2>/dev/null || true
            rc-update del wg-quick.$WG_IF default 2>/dev/null || true
            rc-update del dnsmasq default 2>/dev/null || true
            rm -f /etc/init.d/wg-quick.$WG_IF 2>/dev/null || true
            ;;
    esac

    log_step "删除配置文件..."
    rm -f /etc/dnsmasq.d/wg-ipv4.conf
    rm -f /etc/sysctl.d/99-wg-ipv4.conf

    read -p "是否删除 WireGuard 配置和密钥？(yes/no): " del_wg </dev/tty
    if [ "$del_wg" = "yes" ]; then
        rm -rf "$WG_DIR"
        log_info "WireGuard 配置已删除"
    fi

    read -p "是否删除 nftables 配置？(yes/no): " del_nft </dev/tty
    if [ "$del_nft" = "yes" ]; then
        rm -f /etc/nftables.conf
        nft flush ruleset 2>/dev/null || true
        log_info "nftables 配置已删除"
    fi

    log_step "清理路由表..."
    sed -i "/$RT_NAME/d" /etc/iproute2/rt_tables 2>/dev/null || true

    sysctl --system >/dev/null 2>&1

    echo
    log_info "卸载完成！"
    break_end
    exit 0
}

# 更新脚本
update_script() {
    clear
    echo -e "${white}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
    echo -e "${purple}  更新脚本${re}"
    echo -e "${white}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
    echo

    SCRIPT_URL="https://raw.githubusercontent.com/88899/gitmen-vps/main/ipv4-proxy.sh"
    TEMP_SCRIPT="/tmp/ipv4-proxy_latest.sh"

    log_step "正在检查更新..."

    # 下载最新版本
    if curl -fsSL "$SCRIPT_URL" -o "$TEMP_SCRIPT" 2>/dev/null; then
        log_info "下载成功"

        # 获取当前脚本路径
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
        CURRENT_SCRIPT="$SCRIPT_DIR/$SCRIPT_NAME"
        
        # 如果当前文件名不是原始文件名，则使用原始文件名
        if [ "$SCRIPT_NAME" != "ipv4-proxy.sh" ]; then
            CURRENT_SCRIPT="$SCRIPT_DIR/ipv4-proxy.sh"
            SCRIPT_NAME="ipv4-proxy.sh"
        fi

        # 比较文件
        if diff -q "$CURRENT_SCRIPT" "$TEMP_SCRIPT" >/dev/null 2>&1; then
            log_info "已是最新版本，无需更新"
            rm -f "$TEMP_SCRIPT"
        else
            log_step "发现新版本，正在更新..."

            # 替换脚本，确保保持原始文件名
            cat "$TEMP_SCRIPT" > "$CURRENT_SCRIPT"
            chmod +x "$CURRENT_SCRIPT"
            rm -f "$TEMP_SCRIPT"
            
            # 不需要重命名，直接使用当前文件名
            # 这样无论是原始文件名还是main，都会正确更新

            echo
            echo -e "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
            echo -e "${green}  更新完成！${re}"
            echo -e "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
            echo
            echo -e "${yellow}脚本已更新到最新版本${re}"
            echo -e "${yellow}请重新运行脚本以使用新版本${re}"
            echo
            echo -e "${skyblue}运行命令: ${white}$CURRENT_SCRIPT${re}"
            echo
            read -n 1 -s -r -p "$(echo -e ${yellow}按任意键退出...${re})" </dev/tty
            echo
            exit 0
        fi
    else
        log_error "下载失败，请检查网络连接"
        echo
        echo -e "${yellow}提示：${re}"
        echo -e "1. 检查网络连接是否正常"
        echo -e "2. 确认 GitHub 访问是否正常"
        echo -e "3. 如果在国内，可能需要配置代理"
    fi

    echo
    break_end
}

# 主程序
main() {
    check_root

    while true; do
        show_main_menu
        read choice </dev/tty

        case $choice in
            1) install_server ;;
            2) install_client ;;
            3) add_client ;;
            4) check_environment ;;
            5) show_server_info ;;
            6) show_client_info ;;
            7) manage_domains ;;
            8) show_status ;;
            9) start_service ;;
            10) stop_service ;;
            11) uninstall ;;
            99) update_script ;;
            0)
                clear
                echo -e "${green}感谢使用！${re}"
                exit 0
                ;;
            *)
                log_error "无效选择，请重新输入"
                sleep 1
                ;;
        esac
    done
}

# 运行主程序
main

#!/bin/bash
#
# VPN 管理脚本 (L2TP/IPsec)
# 用法: vpn_admin.sh {user|ippool|status} [参数]
#

set -e

# 配置文件路径
CHAP_SECRETS="/etc/ppp/chap-secrets"
XL2TPD_CONF="/etc/xl2tpd/xl2tpd.conf"
SERVICE_TYPE="l2tpd"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 请使用 sudo 运行此脚本。${NC}" >&2
    exit 1
fi

# 显示帮助
show_help() {
    cat << EOF
用法: $0 {user|ippool|status} [子命令] [参数]

用户管理 (user):
  list                    列出所有 VPN 用户
  add <用户名> <密码>      添加新用户
  del <用户名>             删除用户

IP池管理 (ippool):
  show                    显示当前 IP 池范围
  set <起始IP> <结束IP>    修改 IP 池范围 (例如: 192.168.100.10 192.168.100.100)

状态查看 (status):
  conn                    查看当前活跃的 VPN 连接
  brief                   简要连接信息 (IP、用户、时长)

示例:
  $0 user add john pass123
  $0 ippool set 192.168.200.10 192.168.200.50
  $0 status conn
EOF
}

# ==================== 用户管理 ====================
user_list() {
    echo -e "${GREEN}当前 VPN 用户列表:${NC}"
    echo "-------------------"
    if [[ -f "$CHAP_SECRETS" ]]; then
        grep " $SERVICE_TYPE " "$CHAP_SECRETS" | awk '{print "  " $1}' | sort -u
    else
        echo "  无用户"
    fi
    echo "-------------------"
}

user_add() {
    local username=$1
    local password=$2
    if [[ -z "$username" || -z "$password" ]]; then
        echo -e "${RED}错误: 需要提供用户名和密码。${NC}" >&2
        exit 1
    fi
    if grep -q "^$username[[:space:]]\+$SERVICE_TYPE" "$CHAP_SECRETS" 2>/dev/null; then
        echo -e "${RED}错误: 用户 '$username' 已存在。${NC}" >&2
        exit 1
    fi
    echo "$username  $SERVICE_TYPE  $password  *" >> "$CHAP_SECRETS"
    echo -e "${GREEN}用户 '$username' 添加成功。${NC}"
}

user_del() {
    local username=$1
    if [[ -z "$username" ]]; then
        echo -e "${RED}错误: 需要提供用户名。${NC}" >&2
        exit 1
    fi
    if sed -i.bak "/^$username[[:space:]]\+$SERVICE_TYPE/d" "$CHAP_SECRETS"; then
        echo -e "${GREEN}用户 '$username' 已删除 (备份: ${CHAP_SECRETS}.bak)。${NC}"
    else
        echo -e "${RED}删除失败。${NC}" >&2
        exit 1
    fi
}

# ==================== IP池管理 ====================
ippool_show() {
    if [[ ! -f "$XL2TPD_CONF" ]]; then
        echo -e "${RED}错误: 找不到 xl2tpd 配置文件。${NC}" >&2
        exit 1
    fi
    local range=$(grep -E "^ip range" "$XL2TPD_CONF" | awk '{print $3}')
    echo -e "${GREEN}当前 IP 池范围:${NC} $range"
}

ippool_set() {
    local start_ip=$1
    local end_ip=$2
    if [[ -z "$start_ip" || -z "$end_ip" ]]; then
        echo -e "${RED}错误: 需要提供起始IP和结束IP。${NC}" >&2
        exit 1
    fi
    # 简单IP格式验证
    if ! [[ $start_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ && $end_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}错误: IP 地址格式不正确。${NC}" >&2
        exit 1
    fi
    # 备份配置文件
    cp "$XL2TPD_CONF" "$XL2TPD_CONF.bak"
    # 替换 ip range 行
    sed -i "s/^ip range = .*/ip range = $start_ip-$end_ip/" "$XL2TPD_CONF"
    echo -e "${GREEN}IP 池已修改为: $start_ip - $end_ip${NC}"
    echo -e "${YELLOW}正在重启 xl2tpd 服务...${NC}"
    systemctl restart xl2tpd
    if systemctl is-active xl2tpd >/dev/null; then
        echo -e "${GREEN}xl2tpd 重启成功。${NC}"
    else
        echo -e "${RED}xl2tpd 重启失败，请检查配置。${NC}" >&2
    fi
}

# ==================== 状态查看 ====================
status_conn() {
    echo -e "${GREEN}当前活跃的 PPP 连接 (L2TP 客户端):${NC}"
    local ppp_ifaces=$(ip link show | grep -o 'ppp[0-9]*' | sort -u)
    if [[ -z "$ppp_ifaces" ]]; then
        echo "  无活跃连接"
        return
    fi
    for iface in $ppp_ifaces; do
        echo "接口: $iface"
        ip -4 addr show $iface 2>/dev/null | grep inet | awk '{print "  IP: " $2}'
        # 尝试从 ppp 统计获取对端信息（用户名）
        # 可以从 /var/log/syslog 或 pppd 进程获取，这里简单显示 ifconfig 信息
        echo "------------------------"
    done
}

status_brief() {
    echo -e "${GREEN}简要连接信息:${NC}"
    local ppp_ifaces=$(ip link show | grep -o 'ppp[0-9]*' | sort -u)
    if [[ -z "$ppp_ifaces" ]]; then
        echo "  无活跃连接"
        return
    fi
    echo "接口   IP地址            ？ 用户(无法直接显示，请查看日志)"
    for iface in $ppp_ifaces; do
        local ip=$(ip -4 addr show $iface | grep inet | awk '{print $2}' | cut -d/ -f1)
        # 无法直接从 pppd 获取用户名，但可以尝试从 pppd 进程的命令行中获取
        # pppd 进程的命令行可能包含用户名，但不可靠。建议用日志。
        echo "$iface   $ip"
    done
    echo -e "${YELLOW}注: 如需查看用户名，请运行: sudo grep pppd /var/log/syslog | grep 'user'${NC}"
}

# ==================== 主命令分发 ====================
case "$1" in
    user)
        case "$2" in
            list) user_list ;;
            add) user_add "$3" "$4" ;;
            del) user_del "$3" ;;
            *) echo -e "${RED}user 子命令错误。${NC}"; show_help; exit 1 ;;
        esac
        ;;
    ippool)
        case "$2" in
            show) ippool_show ;;
            set) ippool_set "$3" "$4" ;;
            *) echo -e "${RED}ippool 子命令错误。${NC}"; show_help; exit 1 ;;
        esac
        ;;
    status)
        case "$2" in
            conn) status_conn ;;
            brief) status_brief ;;
            *) echo -e "${RED}status 子命令错误。${NC}"; show_help; exit 1 ;;
        esac
        ;;
    *)
        show_help
        ;;
esac

exit 0

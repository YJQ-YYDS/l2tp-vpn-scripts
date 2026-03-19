#!/bin/bash
#
# L2TP/IPsec VPN 服务器一键部署脚本 (交互式)
# 适用于 Ubuntu 24.04，基于 xl2tpd + strongswan
# 用法: sudo bash deploy_l2tp.sh
#

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 检查是否以 root 运行
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 请使用 sudo 运行此脚本。${NC}" >&2
   exit 1
fi

# 检查系统是否为 Ubuntu 24.04
if ! grep -q "Ubuntu 24.04" /etc/os-release 2>/dev/null; then
    echo -e "${YELLOW}警告: 此脚本专为 Ubuntu 24.04 设计，在其他系统上可能无法正常工作。${NC}"
    read -p "是否继续？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   L2TP/IPsec VPN 服务器部署脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# 交互式信息收集
echo -e "${YELLOW}请提供以下配置信息 (直接回车使用默认值):${NC}"

# 服务器公网 IP
DEFAULT_IP=$(ip -4 route get 1 | awk '{print $NF;exit}')
read -p "服务器公网 IP [$DEFAULT_IP]: " SERVER_IP
SERVER_IP=${SERVER_IP:-$DEFAULT_IP}

# 预共享密钥 (PSK)
read -p "IPsec 预共享密钥 (PSK) [随机生成]: " PSK
if [[ -z "$PSK" ]]; then
    PSK=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 16 | head -n 1)
    echo "生成的 PSK: $PSK"
fi

# 客户端 IP 地址池
read -p "客户端 IP 地址池起始 [192.168.100.10]: " POOL_START
POOL_START=${POOL_START:-192.168.100.10}
read -p "客户端 IP 地址池结束 [192.168.100.100]: " POOL_END
POOL_END=${POOL_END:-192.168.100.100}

# 服务器 VPN 内网 IP
read -p "服务器 VPN 内网 IP [192.168.100.1]: " SERVER_VPN_IP
SERVER_VPN_IP=${SERVER_VPN_IP:-192.168.100.1}

# DNS 服务器
read -p "首选 DNS [8.8.8.8]: " DNS1
DNS1=${DNS1:-8.8.8.8}
read -p "备用 DNS [8.8.4.4]: " DNS2
DNS2=${DNS2:-8.8.4.4}

# 自动检测公网网卡名称
PUBLIC_IF=$(ip -4 route show default | awk '{print $5}' | head -1)
if [[ -z "$PUBLIC_IF" ]]; then
    echo -e "${RED}错误: 无法检测到公网网卡，请手动输入。${NC}"
    ip link show
    read -p "请输入公网网卡名称: " PUBLIC_IF
fi

# 用户管理
declare -a USERS=()
echo
echo -e "${YELLOW}现在可以添加 VPN 用户 (至少添加一个，留空用户名结束):${NC}"
while true; do
    read -p "用户名: " UNAME
    if [[ -z "$UNAME" ]]; then
        break
    fi
    read -sp "密码: " UPASS
    echo
    if [[ -z "$UPASS" ]]; then
        echo -e "${RED}密码不能为空，请重新输入。${NC}"
        continue
    fi
    USERS+=("$UNAME:$UPASS")
    echo "用户 $UNAME 添加成功。"
done

if [[ ${#USERS[@]} -eq 0 ]]; then
    echo -e "${RED}错误: 至少需要一个 VPN 用户。${NC}"
    exit 1
fi

echo
echo -e "${GREEN}配置信息汇总:${NC}"
echo "公网 IP: $SERVER_IP"
echo "预共享密钥 (PSK): $PSK"
echo "客户端 IP 池: $POOL_START - $POOL_END"
echo "服务器 VPN IP: $SERVER_VPN_IP"
echo "DNS: $DNS1, $DNS2"
echo "公网网卡: $PUBLIC_IF"
echo "用户:"
for user in "${USERS[@]}"; do
    echo "  - ${user%%:*}"
done
echo

read -p "确认无误，开始部署？(y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "部署已取消。"
    exit 0
fi

# 备份配置文件函数
backup_file() {
    local file=$1
    if [[ -f "$file" ]]; then
        cp "$file" "$file.bak.$(date +%Y%m%d%H%M%S)"
        echo "已备份 $file"
    fi
}

# 开始部署
echo -e "${GREEN}>>> 步骤 1: 更新系统并安装必要软件...${NC}"
apt update
apt install -y xl2tpd ppp strongswan iptables-persistent net-tools

echo -e "${GREEN}>>> 步骤 2: 配置 xl2tpd...${NC}"
backup_file /etc/xl2tpd/xl2tpd.conf
cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
ipsec saref = no
listen-addr = 0.0.0.0
port = 1701

[lns default]
ip range = $POOL_START-$POOL_END
local ip = $SERVER_VPN_IP
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

echo -e "${GREEN}>>> 步骤 3: 配置 PPP 选项...${NC}"
backup_file /etc/ppp/options.xl2tpd
cat > /etc/ppp/options.xl2tpd <<EOF
require-mschap-v2
ms-dns $DNS1
ms-dns $DNS2
asyncmap 0
auth
crtscts
lock
hide-password
modem
debug
proxyarp
lcp-echo-interval 30
lcp-echo-failure 4
+ipv6
EOF

echo -e "${GREEN}>>> 步骤 4: 配置 strongswan (IPsec)...${NC}"
backup_file /etc/ipsec.conf
cat > /etc/ipsec.conf <<EOF
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn %default
    keyexchange=ikev1
    authby=secret
    type=transport
    left=%any
    leftid=$SERVER_IP
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    auto=add

conn l2tp-psk
    type=transport
    auto=add
EOF

backup_file /etc/ipsec.secrets
cat > /etc/ipsec.secrets <<EOF
$SERVER_IP %any : PSK "$PSK"
EOF

echo -e "${GREEN}>>> 步骤 5: 添加 VPN 用户...${NC}"
backup_file /etc/ppp/chap-secrets
> /etc/ppp/chap-secrets   # 清空文件
for user in "${USERS[@]}"; do
    IFS=':' read -r uname upass <<< "$user"
    echo "$uname l2tpd $upass *" >> /etc/ppp/chap-secrets
    echo "已添加用户: $uname"
done

echo -e "${GREEN}>>> 步骤 6: 开启 IP 转发...${NC}"
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p

echo -e "${GREEN}>>> 步骤 7: 配置防火墙 NAT...${NC}"
iptables -t nat -A POSTROUTING -o $PUBLIC_IF -j MASQUERADE
iptables-save > /etc/iptables/rules.v4
netfilter-persistent save

echo -e "${GREEN}>>> 步骤 8: 启动服务并设置开机自启...${NC}"
systemctl restart xl2tpd strongswan-starter
systemctl enable xl2tpd strongswan-starter

# 检查服务状态
if systemctl is-active xl2tpd >/dev/null && systemctl is-active strongswan-starter >/dev/null; then
    echo -e "${GREEN}所有服务已成功启动。${NC}"
else
    echo -e "${RED}警告: 部分服务启动失败，请检查日志: journalctl -u xl2tpd / strongswan-starter${NC}"
fi

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   L2TP/IPsec VPN 服务器部署完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo "服务器信息:"
echo "  公网 IP: $SERVER_IP"
echo "  预共享密钥 (PSK): $PSK"
echo "  客户端 IP 池: $POOL_START - $POOL_END"
echo "  DNS: $DNS1, $DNS2"
echo
echo "用户列表:"
for user in "${USERS[@]}"; do
    IFS=':' read -r uname upass <<< "$user"
    echo "  - 用户名: $uname , 密码: $upass"
done
echo
echo -e "${YELLOW}使用客户端连接时请注意:${NC}"
echo "  1. 服务器类型: L2TP/IPsec with pre-shared key"
echo "  2. 输入以上用户名/密码和 PSK"
echo "  3. 如果连接后无法访问互联网，请检查服务器 iptables 规则和 IP 转发。"
echo
echo -e "${GREEN}部署脚本执行完毕。${NC}"

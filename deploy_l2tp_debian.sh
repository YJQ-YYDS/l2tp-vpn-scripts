#!/bin/bash
#
# L2TP/IPsec VPN 服务器一键部署脚本 (Debian 11/12 专用)
# 基于 xl2tpd + strongswan
# 用法: 以 root 执行 ./deploy_l2tp_debian.sh
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 检查是否以 root 运行
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 请在 root 用户下执行此脚本（或使用 sudo，但 Debian 可能未安装 sudo）。${NC}" >&2
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   L2TP/IPsec VPN 服务器部署脚本 (Debian)${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# 交互式信息收集（与原脚本相同）
DEFAULT_IP=$(ip -4 route get 1 | awk '{print $NF;exit}')
read -p "服务器公网 IP [$DEFAULT_IP]: " SERVER_IP
SERVER_IP=${SERVER_IP:-$DEFAULT_IP}

read -p "IPsec 预共享密钥 (PSK) [随机生成]: " PSK
if [[ -z "$PSK" ]]; then
    PSK=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 16 | head -n 1)
    echo "生成的 PSK: $PSK"
fi

read -p "客户端 IP 地址池起始 [192.168.100.10]: " POOL_START
POOL_START=${POOL_START:-192.168.100.10}
read -p "客户端 IP 地址池结束 [192.168.100.100]: " POOL_END
POOL_END=${POOL_END:-192.168.100.100}

read -p "服务器 VPN 内网 IP [192.168.100.1]: " SERVER_VPN_IP
SERVER_VPN_IP=${SERVER_VPN_IP:-192.168.100.1}

read -p "首选 DNS [8.8.8.8]: " DNS1
DNS1=${DNS1:-8.8.8.8}
read -p "备用 DNS [8.8.4.4]: " DNS2
DNS2=${DNS2:-8.8.4.4}

PUBLIC_IF=$(ip -4 route show default | awk '{print $5}' | head -1)
if [[ -z "$PUBLIC_IF" ]]; then
    echo -e "${RED}错误: 无法检测到公网网卡，请手动输入。${NC}"
    ip link show
    read -p "请输入公网网卡名称: " PUBLIC_IF
fi

# 用户收集
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
echo "PSK: $PSK"
echo "IP 池: $POOL_START - $POOL_END"
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

# 备份函数
backup_file() {
    local file=$1
    if [[ -f "$file" ]]; then
        cp "$file" "$file.bak.$(date +%Y%m%d%H%M%S)"
    fi
}

# 1. 安装软件包
echo -e "${GREEN}>>> 安装必要软件...${NC}"
apt update
apt install -y xl2tpd ppp strongswan iptables-persistent

# 2. 配置 xl2tpd
echo -e "${GREEN}>>> 配置 xl2tpd...${NC}"
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

# 3. 配置 PPP
echo -e "${GREEN}>>> 配置 PPP 选项...${NC}"
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

# 4. 配置 strongswan
echo -e "${GREEN}>>> 配置 strongswan (IPsec)...${NC}"
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

# 5. 添加用户
echo -e "${GREEN}>>> 添加 VPN 用户...${NC}"
backup_file /etc/ppp/chap-secrets
> /etc/ppp/chap-secrets
for user in "${USERS[@]}"; do
    IFS=':' read -r uname upass <<< "$user"
    echo "$uname l2tpd $upass *" >> /etc/ppp/chap-secrets
done

# 6. 开启 IP 转发
echo -e "${GREEN}>>> 开启 IP 转发...${NC}"
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p

# 7. 配置 NAT
echo -e "${GREEN}>>> 配置防火墙 NAT...${NC}"
iptables -t nat -A POSTROUTING -o $PUBLIC_IF -j MASQUERADE
iptables-save > /etc/iptables/rules.v4
netfilter-persistent save

# 8. 启动服务（适配 Debian 的服务名）
echo -e "${GREEN}>>> 启动服务...${NC}"
# 检测 strongswan 服务名
if systemctl list-unit-files | grep -q strongswan-starter.service; then
    STRONGSWAN_SVC="strongswan-starter"
elif systemctl list-unit-files | grep -q strongswan.service; then
    STRONGSWAN_SVC="strongswan"
else
    echo -e "${RED}错误: 无法找到 strongswan 服务，请手动检查。${NC}"
    exit 1
fi

systemctl restart xl2tpd $STRONGSWAN_SVC
systemctl enable xl2tpd $STRONGSWAN_SVC

# 检查服务状态
if systemctl is-active xl2tpd >/dev/null && systemctl is-active $STRONGSWAN_SVC >/dev/null; then
    echo -e "${GREEN}所有服务已成功启动。${NC}"
else
    echo -e "${RED}警告: 部分服务启动失败，请检查日志。${NC}"
fi

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   L2TP/IPsec VPN 服务器部署完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo "服务器信息:"
echo "  公网 IP: $SERVER_IP"
echo "  PSK: $PSK"
echo "  客户端 IP 池: $POOL_START - $POOL_END"
echo "  DNS: $DNS1, $DNS2"
echo
echo "用户列表:"
for user in "${USERS[@]}"; do
    IFS=':' read -r uname upass <<< "$user"
    echo "  - 用户名: $uname , 密码: $upass"
done
echo
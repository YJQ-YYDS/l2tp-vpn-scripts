#!/bin/bash
#
# 安全防火墙配置脚本 (仅放行 SSH + IPsec)
# 适用于 L2TP/IPsec VPN 服务器
#

# 你的 SSH 端口 (默认22)
SSH_PORT=22

# 清理所有现有规则
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# 默认策略：拒绝所有入站，允许所有出站和转发
iptables -P INPUT DROP
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# 允许本地回环
iptables -A INPUT -i lo -j ACCEPT

# 允许已建立的连接及相关连接
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 允许 SSH
iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT

# 允许 IPsec (UDP 500, 4500)
iptables -A INPUT -p udp --dport 500 -j ACCEPT
iptables -A INPUT -p udp --dport 4500 -j ACCEPT

# 可选：允许 L2TP 控制端口 (UDP 1701)，如果客户端需要
iptables -A INPUT -p udp --dport 1701 -j ACCEPT

# 允许 IPsec ESP 协议 (如果使用 ESP，通常已包含在策略中，但可明确允许)
iptables -A INPUT -p esp -j ACCEPT

# 记录被拒绝的包（可选，用于调试）
iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "FW-DROP: " --log-level 4

# 配置 NAT (MASQUERADE)，假设公网网卡为 eth0，请根据实际修改
PUBLIC_IF=$(ip -4 route show default | awk '{print $5}' | head -1)
if [[ -n "$PUBLIC_IF" ]]; then
    iptables -t nat -A POSTROUTING -o $PUBLIC_IF -j MASQUERADE
    echo "已添加 MASQUERADE 规则，出接口: $PUBLIC_IF"
else
    echo "警告: 未检测到公网网卡，请手动添加 NAT 规则。"
fi

# 保存规则（需安装 iptables-persistent）
iptables-save > /etc/iptables/rules.v4
netfilter-persistent save

echo "防火墙配置完成。"

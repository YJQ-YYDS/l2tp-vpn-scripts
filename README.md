# l2tp-vpn-scripts
一键部署 L2TP/IPsec VPN 服务器的脚本集 (支持 Ubuntu/Debian)
# L2TP/IPsec VPN 一键部署与管理脚本集

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

本项目提供了一套轻量级的 Shell 脚本，用于在 **Ubuntu 22.04/24.04** 和 **Debian 11/12** 系统上快速部署 L2TP/IPsec VPN 服务器，并提供了便捷的日常管理功能。

## ✨ 功能特性

- **一键交互式部署**：运行脚本后只需回答几个简单问题，即可自动安装和配置 `xl2tpd` + `strongswan`。
- **多系统支持**：完美支持 Ubuntu 22.04/24.04 和 Debian 11/12。
- **用户管理**：提供专用脚本，轻松实现 VPN 用户的增、删、查。
- **IP 池管理**：支持动态修改客户端 IP 地址池。
- **状态查看**：快速查看当前活跃的 VPN 连接。
- **防火墙辅助**：包含安全防火墙配置指南，仅放行 SSH 和 VPN 端口。

## 🚀 快速开始

在你的海外 VPS 上，只需一行命令即可下载并开始部署。

### 1. 下载脚本
你可以使用 `wget` 或 `curl` 下载所有脚本：
```bash
# 创建一个专用目录并进入
mkdir ~/vpn-setup && cd ~/vpn-setup

# 下载部署脚本 (下载对应系统部署脚本和vpn_admin管理脚本)
wget https://raw.githubusercontent.com/YJQ-YYDS/l2tp-vpn-scripts/main/deploy_l2tp.sh
wget https://raw.githubusercontent.com/YJQ-YYDS/l2tp-vpn-scripts/main/deploy_l2tp.debian.sh
wget https://raw.githubusercontent.com/YJQ-YYDS/l2tp-vpn-scripts/main/vpn_admin.sh

# 赋予执行权限
chmod +x deploy_l2tp.sh vpn_admin.sh

# 运行部署脚本 (Ubuntu 24.04/22.04 用户可直接运行)
# Debian 用户请使用专用脚本 deploy_l2tp_debian.sh
sudo ./deploy_l2tp.sh

根据提示输入服务器 IP、PSK 密钥、IP 池和至少一个用户信息，等待脚本执行完成即可。

📖 日常管理 (vpn_admin.sh)
部署完成后，使用 vpn_admin.sh 脚本进行管理。
# 查看所有命令帮助
sudo ./vpn_admin.sh

# 列出所有 VPN 用户
sudo ./vpn_admin.sh user list

# 添加一个新用户 (用户名: john, 密码: pass123)
sudo ./vpn_admin.sh user add john pass123

# 删除一个用户
sudo ./vpn_admin.sh user del john

# 显示当前 IP 池
sudo ./vpn_admin.sh ippool show

# 修改 IP 池 (例如改为 192.168.200.10-192.168.200.100)
sudo ./vpn_admin.sh ippool set 192.168.200.10 192.168.200.100

# 查看当前活跃连接
sudo ./vpn_admin.sh status conn


🛡️ 防火墙配置 (推荐)
为了服务器安全，建议仅放行必要端口。可以参考仓库中的 secure_firewall.sh 脚本，或手动执行以下命令：

# 示例：仅放行 SSH(22), IPsec(500,4500) 和 L2TP(1701)
iptables -F
iptables -P INPUT DROP
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p udp --dport 500 -j ACCEPT
iptables -A INPUT -p udp --dport 4500 -j ACCEPT
iptables -A INPUT -p udp --dport 1701 -j ACCEPT
# 保存规则
apt install iptables-persistent -y
netfilter-persistent save


📁 脚本文件说明
deploy_l2tp.sh: Ubuntu 22.04/24.04 一键部署脚本。
deploy_l2tp_debian.sh: Debian 11/12 一键部署脚本。
vpn_admin.sh: 通用 VPN 管理脚本（用户、IP池、状态）。
secure_firewall.sh: 安全防火墙配置脚本（可选）。

📝 客户端连接信息
服务器地址: 你的 VPS 公网 IP

IPsec 预共享密钥 (PSK): 部署时设置的密钥

用户名/密码: 部署时添加的用户


📄 开源协议
本项目采用 MIT 协议。
---

## 🎯 在海外 VPS 上的一键下载命令

```bash
# 下载并执行 Ubuntu 部署脚本
wget -O - https://raw.githubusercontent.com/YJQ-YYDS/l2tp-vpn-scripts/main/deploy_l2tp.sh | sudo bash

或者更稳妥一点，分步执行：
git clone https://github.com/YJQ-YYDS/l2tp-vpn-scripts.git
cd l2tp-vpn-scripts
sudo ./deploy_l2tp.sh

#!/bin/bash
# ═══════════════════════════════════════════════
# Termux 一键开启 SSH 服务 + frp 反向隧道
# 在平板上运行: bash termux_ssh_setup.sh
# ═══════════════════════════════════════════════

echo "========================================"
echo "  Termux SSH + frp 远程访问一键脚本"
echo "========================================"

# 检测 Termux
if [ ! -d /data/data/com.termux ]; then
    echo "⚠️ 未检测到 Termux 环境，继续但不保证兼容..."
fi

# 1. 安装必要软件
echo ""
echo "[1/4] 安装 openssh ..."
pkg update -y 2>/dev/null
pkg install -y openssh 2>/dev/null || apt install -y openssh-server 2>/dev/null

# 2. 设置 SSH
echo ""
echo "[2/4] 配置 SSH ..."

SSH_DIR="$HOME/.ssh"
mkdir -p "$SSH_DIR"

# 允许密码登录（初次方便）
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' $PREFIX/etc/ssh/sshd_config 2>/dev/null || true
echo "PasswordAuthentication yes" >> $PREFIX/etc/ssh/sshd_config 2>/dev/null || echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config 2>/dev/null

# 设置 SSH 端口 (2222 避免冲突)
sed -i 's/^Port 8022/Port 2222/' $PREFIX/etc/ssh/sshd_config 2>/dev/null || true
sed -i 's/^#Port 22/Port 2222/' $PREFIX/etc/ssh/sshd_config 2>/dev/null || true
echo "Port 2222" >> $PREFIX/etc/ssh/sshd_config 2>/dev/null || true

# 3. 设置密码（可自定义）
echo ""
echo "[3/4] 设置登录密码..."
CURRENT_USER=$(whoami)
if [ "$CURRENT_USER" = "root" ]; then
    echo "当前是 root 用户"
    echo "设置 root 密码（用于 SSH 登录）："
    passwd
else
    echo "设置 $CURRENT_USER 密码（用于 SSH 登录）："
    passwd $CURRENT_USER
fi

# 4. 启动 SSH 服务端
echo ""
echo "[4/4] 启动 SSH 服务..."
sshd 2>/dev/null || {
    echo "重启 sshd..."
    pkill sshd 2>/dev/null
    sleep 1
    sshd 2>/dev/null || echo "⚠️ sshd 启动失败，试试手动: sshd"
}

# 检查 sshd 是否在运行
if pgrep sshd > /dev/null 2>&1; then
    echo "✅ SSH 服务已启动 (端口 2222)"
else
    echo "❌ SSH 服务启动失败"
fi

# 获取本地 IP
echo ""
echo "========== 连接信息 =========="
echo "平板上本地 SSH 连接："
echo "  ssh $(whoami)@localhost -p 2222"
echo ""
echo "局域网连接（同一WiFi下）："
IP=$(ip addr show 2>/dev/null | grep -oP 'inet \K192\.168\.[\d.]+' | head -1)
if [ -z "$IP" ]; then
    IP=$(ip addr show 2>/dev/null | grep -oP 'inet \K10\.[\d.]+' | head -1)
fi
if [ -n "$IP" ]; then
    echo "  ssh $(whoami)@$IP -p 2222"
else
    echo "  (无法获取 IP，请自行查看)"
fi
echo ""
echo "⚠️ frp 反向隧道（如需外网连接）："
echo "  然后在平板上安装 frp:"
echo "  pkg install -y frp"
echo "  然后创建 frpc.toml（已下载）:"
echo '    serverAddr = "fegrous.top"'
echo '    serverPort = 7000'
echo '    auth.token = "mc2026server"'
echo ''
echo '    [[proxies]]'
echo '    name = "termux-ssh"'
echo '    type = "tcp"'
echo '    localIP = "127.0.0.1"'
echo '    localPort = 2222'
echo '    remotePort = 2222'
echo ""
echo "  运行: frpc -c frpc.toml"
echo "  之后我就可以连接:"
echo "    ssh $(whoami)@fegrous.top -p 2222"
echo ""
echo "==============================="
echo "✅ 完成！平板 SSH 服务已就绪"
echo "==============================="

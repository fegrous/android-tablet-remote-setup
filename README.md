# 安卓平板远程接入 Hermes Agent 全记录

> 本文记录了如何从零开始在安卓平板上部署 Termux 环境、配置 SSH 远程访问 + FRP 内网穿透，实现通过 Hermes Agent（AI 助手）远程控制平板的过程。

---

## 写在前面

### 为什么需要这个？

我有台安卓平板（Android 13，已 root），平时用手机比较多，平板经常吃灰。但如果能让我的 AI 助手（Hermes Agent）直接连上平板，就可以：

- 帮我跑 Python 脚本
- 管理平板上的文件
- 通过 root 权限安装/卸载 App
- 作为额外的计算节点跑定时任务

### 方案概览

![完整链路图](https://fegrous.top/img/chain_diagram.jpg)
> 完整控制链路：主人通过 QQ 与 AI 交互，AI SSH 直连云服务器，经 FRP 隧道穿透到平板 Termux，最终通过 sysfs 控制硬件。


整条链路：你或 AI → [云服务器:映射端口] → FRP 隧道 → 平板 Termux 的 SSH 服务 → 操作终端。

关键组件：
- **Termux** — 安卓上的 Linux 终端模拟器
- **OpenSSH** — SSH 服务端，接收远程连接
- **FRPC** — 内网穿透客户端，打通平板到公网的隧道
- **SSH 密钥认证** — 免密安全登录
- **开机自启脚本** — 重启后自动恢复连接

---

## 一、准备工作

### 1.1 安装 Termux

> ⚠️ **注意**：不要从 Google Play 装 Termux！
>
> Play 版已经停更多年，版本老旧，而且 Termux 相关的插件（如 Termux:API）签名和 Play 版不一致，会装不上。
>
> ✅ **推荐从 F-Droid 安装：**
> - 下载 [F-Droid](https://f-droid.org/) 客户端
> - 搜索 Termux、Termux:API、Termux:Boot 安装
> - F-Droid 版签名一致，插件随便装

### 1.2 基础准备

- **平板已 root**（本文基于 KernelSU / SukiSU Ultra 框架）
- **平板有稳定的网络连接**（WiFi 或移动数据）
- **云服务器一台**（需要有公网 IP，本文用的是阿里云 ECS）
- **FRP 服务端已在服务器上配置好**（参考 FRP 官方文档）

---

## 二、Termux 环境配置

### 2.1 安装基础包

打开 Termux，先更新包管理器并安装必要的工具：

```bash
pkg update && pkg upgrade -y
pkg install openssh curl wget python -y
```

关键包说明：
- `openssh` — 提供 SSH 服务端（sshd）和客户端
- `curl` / `wget` — 文件下载
- `python` — 跑脚本

### 2.2 配置 SSH 密钥认证

安全起见，我们使用密钥登录，禁用密码登录。

**在平板上生成密钥对：**

```bash
ssh-keygen -t ed25519 -a 100
# 一路回车使用默认路径 (~/.ssh/id_ed25519)
```

**将公钥加入授权列表：**

```bash
cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
```

**把私钥传到服务器上**（后续用于服务器连接平板）：

```bash
# 在服务器上执行
scp -P [映射端口] [用户名]@[服务器域名]:~/.ssh/id_ed25519 ~/.ssh/tablet_ed25519
chmod 600 ~/.ssh/tablet_ed25519
```

### 2.3 配置 SSHD

编辑 `$PREFIX/etc/ssh/sshd_config`：

```bash
# 关键配置项
Port 8022                    # 使用非标准端口，避免冲突
PasswordAuthentication no    # 只允许密钥登录
PubkeyAuthentication yes     # 开启密钥认证
PermitRootLogin no           # 不允许 root SSH（Termux 本身也不是 root）
```

启动 SSHD：

```bash
sshd
```

验证：

```bash
# 本机测试（在 Termux 里执行）
ssh -p 8022 127.0.0.1 "echo 'SSH OK'"
```

---

## 三、FRP 内网穿透

要让外网访问平板的 SSH，需要把平板的 SSH 端口通过 FRP 映射到公网服务器上。

### 3.1 安装 FRPC

```bash
# 下载 ARM64 版本 FRP 客户端
wget https://github.com/fatedier/frp/releases/download/v0.61.2/frp_0.61.2_linux_arm64.tar.gz
tar xzf frp_0.61.2_linux_arm64.tar.gz
cp frp_0.61.2_linux_arm64/frpc $PREFIX/bin/
chmod +x $PREFIX/bin/frpc
```

### 3.2 配置 FRPC

创建配置文件 `~/.frpc.toml`：

```toml
serverAddr = "[你的服务器域名/IP]"
serverPort = [FRP 服务端端口]           # 默认 7000
auth.token = "[你的 FRP Token]"

[[proxies]]
name = "android-ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 8022                # Termux SSHD 端口
remotePort = [映射端口]          # 服务器上暴露的端口
```

> **注意**：`auth.token` 需要和服务器上 `/etc/frps.toml` 的 token 一致。

### 3.3 启动 FRPC

```bash
frpc -c ~/.frpc.toml
```

看到输出如下说明隧道通了：

```
202x/xx/xx xx:xx:xx [I] [proxy_manager.go:xxx] [xxx] login to server success
202x/xx/xx xx:xx:xx [I] [proxy_manager.go:xxx] [xxx] [android-ssh] start proxy success
```

### 3.4 验证远程连接

从服务器（或任意能访问公网的机器）测试：

```bash
ssh -p [映射端口] [用户名]@[服务器域名]
```

如果进了 Termux 的 shell，说明整条链路通了。

---

## 四、开机自启

安卓重启后，Termux 会被杀掉，SSHD 和 FRPC 都需要重新启动。我们需要让它们自动复活。

### 4.1 .bashrc 守护脚本

在 `~/.bashrc` 末尾添加以下内容。这个脚本在 Termux 启动时自动运行，检查并拉起 SSHD 和 FRPC：

```bash
# ===== Auto-start: SSHD + FRPC =====
start_sshd() {
    if ! pgrep -x sshd >/dev/null 2>&1; then
        sshd
        echo "[$(date '+%H:%M:%S')] sshd started"
    fi
}

start_frpc() {
    if ! pgrep -f "frpc -c ~/.frpc.toml" >/dev/null 2>&1; then
        nohup frpc -c ~/.frpc.toml > /dev/null 2>&1 &
        echo "[$(date '+%H:%M:%S')] frpc started"
    fi
}

start_sshd
start_frpc
```

这个脚本每次 Termux 启动时自动检查并拉起两个服务。

### 4.2 开机自启方案（Root 方式）

安卓系统层面，即使 Termux 被系统杀掉，我们需要一个更高层级的保活方式。

**方案 A：service.d 脚本**（推荐，需要 root + KernelSU/Magisk）

在 `/data/adb/service.d/` 下创建脚本 `sshd_frpc.sh`：

```bash
#!/system/bin/sh

# 等待系统启动完成
sleep 30

# 启动 Termux 的 SSHD 和 FRPC
# (通过 am start 触发 Termux 打开，.bashrc 负责拉起服务)
am start -n com.termux/.app.TermuxActivity > /dev/null 2>&1
```

设置权限：

```bash
chmod 755 /data/adb/service.d/sshd_frpc.sh
```

**方案 B：Termux:Boot**（需要从 F-Droid 安装 Termux:Boot）

安装 Termux:Boot 后，在 `~/.termux/boot/` 目录下创建启动脚本：

```bash
#!/data/data/com.termux/files/usr/bin/bash
sshd
frpc -c ~/.frpc.toml &
```

这个方案的优点是无需 root，但缺点是需要用户手动打开一下 Termux 才能触发 Boot 插件。

### 4.3 最终方案（混合）

实际使用的是杂交方案：

1. **service.d** 负责系统开机后启动 Termux App
2. **.bashrc** 守护脚本负责拉起 SSHD 和 FRPC
3. **termux-wake-lock** 保持 Termux 在后台不被杀

效果：平板只要开机且联网，等待约 30 秒后自动打通 SSH 隧道。

---

## 五、接入 Hermes Agent

隧道通了之后，AI 助手可以直接通过 SSH 连接到平板执行操作。

### 5.1 配置 SSH 连接

在 Hermes Agent 运行的服务器上配置 SSH 快捷连接：

```bash
# ~/.ssh/config 添加
Host android-tablet
    HostName [你的服务器域名/IP]
    Port [映射端口]
    User [Termux 用户名]
    IdentityFile ~/.ssh/tablet_ed25519
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

测试：

```bash
ssh android-tablet "uname -a && uptime"
# 输出类似: Linux localhost 4.14.xxx-android aarch64 Android
```

### 5.2 日常用途示例

连接建立后，AI 助手可以：

**管理 App：**
```bash
# 在平板上通过 SSH 执行
su -c pm list packages | grep game    # 列出游戏
su -c pm disable com.bloatware.app     # 停用预装软件
su -c pm install /sdcard/Download/app.apk  # 安装 APK
```

**跑 Python 脚本：**
```bash
# 写脚本 → 传到平板 → 运行
cat << 'EOF' | ssh android-tablet python3
import psutil
for proc in psutil.process_iter(['name', 'memory_info']):
    print(f"{proc.info['name']}: {proc.info['memory_info'].rss/1024/1024:.1f} MB")
EOF
```

**文件操作：**
```bash
# 从平板拉取文件
scp android-tablet:/sdcard/DCIM/Camera/photo.jpg /tmp/

# 推文件到平板
scp /tmp/script.py android-tablet:~/
```

---

## 六、FAQ / 踩坑记录

### Q1：SSH 连不上，连接被拒绝

最常见原因：**平板不在线。**

FRP 服务端日志（服务器上 `journalctl -u frps`）看不到平板端注册，说明 frpc 没连上来。先确认平板：
- 开了 Termux 没
- 有没有网络（WiFi 是否正常）
- frpc 进程是否在运行

### Q2：Termux 用一会就自动退出

安卓的省电策略会杀掉后台进程。需要：
1. **在系统设置里关闭 Termux 的省电优化**（设置 → 应用 → Termux → 省电策略 → 无限制）
2. **锁定 Termux 在最近任务列表**（下拉应用卡片，点锁图标）
3. **使用 termux-wake-lock**：`pkg install termux-api && termux-wake-lock`

### Q3：Termux:API 安装提示签名冲突

如果 Termux 本体从 Google Play 装，而 Termux:API 从 GitHub 下载，签名会不一致。解决办法：
- **全部从 F-Droid 安装**（本体和插件签名一致）
- 或者全部从 Google Play 安装

### Q4：从 sdcard 安装 APK 失败（SELinux 限制）

```
Failed to install: INSTALL_FAILED_MEDIA_UNAVAILABLE
```

SELinux 政策限制了从 `/sdcard` 安装。需要先复制到 `/data/local/tmp/`：

```bash
cp /sdcard/Download/app.apk /data/local/tmp/
su -c pm install /data/local/tmp/app.apk
rm /data/local/tmp/app.apk
```

### Q5：电脑/服务器重启后，平板端不用动

这是这套方案的优势——**服务端重启不影响平板端**。平板端的 frpc 会一直尝试连接服务器，只要 frps 恢复，隧道自动重建。

---

## 七、总结

这套方案的核心思路：

1. **Termux** 提供 Linux 用户空间环境
2. **SSH 密钥认证** 保证安全
3. **FRP 内网穿透** 打通 NAT
4. **.bashrc + service.d** 实现开机自启

目前这套方案稳定运行中，AI 助手可以随时 SSH 到平板执行命令、跑脚本、管理软件。唯一的弱点是**平板不能断电**（没电了 Termux 自然挂掉），不过平板本身的续航一般能撑一整天，日常够用了。

---

> *最后更新：2026年6月*
> *分类：学习记录*

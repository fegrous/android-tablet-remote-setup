# Android Tablet Remote Access Setup Files

安卓平板远程接入 Hermes Agent 的配套文件。

## 文件列表

| 文件 | 说明 |
|------|------|
| [`frpc_android.toml`](frpc_android.toml) | 平板端 FRP 内网穿透配置文件，用于打通公网到平板的 SSH 隧道 |
| [`termux_ssh_setup.sh`](termux_ssh_setup.sh) | Termux 一键配置脚本，自动安装包、生成 SSH 密钥、配置 SSHD |

## 使用方法

### 1. 配置 FRP

下载 `frpc_android.toml` 放到 `~/.frpc.toml`，修改以下字段：

- `serverAddr` — 你的云服务器域名或 IP
- `serverPort` — FRP 服务端端口（默认 7000）
- `auth.token` — 与服务器 `/etc/frps.toml` 一致的 token
- `remotePort` — 服务器上要暴露的端口

启动：`frpc -c ~/.frpc.toml`

### 2. 配置 Termux SSH

在 Termux 中运行：

```bash
chmod +x termux_ssh_setup.sh
./termux_ssh_setup.sh
```

或者手动操作详见博客文章。

---

> 完整教程：[fegrous.top](https://fegrous.top/post.php?slug=android-tablet-remote-access-hermes-agent)

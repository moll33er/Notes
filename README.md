# Notes 脚本使用说明

本仓库收集了一些 Linux 服务器初始化和系统安装脚本，并添加了一些内容：

| 脚本 | 用途 |
| --- | --- |
| `install-docker.sh` | 在 Debian / Ubuntu 上安装 Docker CE 和 Docker Compose 插件 |
| `install-nginx-official.sh` | 在 Debian 上添加 nginx.org 官方源并安装 nginx |
| `install-zsh.sh` | 安装 zsh、Oh My Zsh、常用补全和高亮插件 |
| `InstallNET.sh` | 通过网络重装 Debian / Ubuntu / CentOS，或通过 DD 镜像安装系统 |

## 目录

- [安装 Docker](#安装-docker)
- [安装 nginx 官方版](#安装-nginx-官方版)
- [安装 zsh 自动补全环境](#安装-zsh-自动补全环境)
- [网络重装系统](#网络重装系统)
- [快速检查](#快速检查)

## 安装 Docker

脚本：`install-docker.sh`

支持系统：

- Debian
- Ubuntu

功能：

- 更新系统并安装基础依赖
- 添加 Docker 官方源或清华 TUNA 源
- 安装 `docker-ce`、`docker-ce-cli`、`containerd.io`、`docker-compose-plugin`
- 启用并重启 Docker 服务
- 安装 `docker-ce-rootless-extras`
- 写入 `/etc/docker/daemon.json`
- 可选：将指定用户加入 `docker` 组

用法：

```bash
# 使用 Docker 官方源
sudo bash install-docker.sh

# 使用清华 TUNA 源
sudo bash install-docker.sh tuna

# 使用清华 TUNA 源，并将 www-data 加入 docker 组
sudo bash install-docker.sh tuna www-data
```

远程执行：

```bash
# curl
sudo bash <(curl -Ls https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/install-docker.sh)
sudo bash <(curl -Ls https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/install-docker.sh) tuna www-data

# wget
sudo bash <(wget -qO- https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/install-docker.sh)
sudo bash <(wget -qO- https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/install-docker.sh) tuna www-data
```

参数：

| 参数位置 | 默认值 | 说明 |
| --- | --- | --- |
| `$1` | `official` | 软件源类型。传入 `tuna` 时使用清华 TUNA 源，其他值使用 Docker 官方源 |
| `$2` | 空 | 要加入 `docker` 组的用户名 |

注意：

- 必须使用 root 权限运行。
- 脚本只会更新 apt 缓存并安装 Docker 相关依赖，不会执行全系统升级。
- 如果 `/etc/docker/daemon.json` 已存在，会自动备份为 `daemon.json.bak.<时间戳>`。
- 新加入 `docker` 组的用户需要重新登录，或执行 `newgrp docker` 后权限才会生效。

## 安装 nginx 官方版

脚本：`install-nginx-official.sh`

支持系统：

- Debian

功能：

- 安装依赖
- 下载 nginx 官方签名 key
- 解析并显示签名 key 指纹
- 可选：校验指定可信指纹
- 写入 nginx.org 官方 apt 源
- 设置 apt pin，优先使用 nginx.org 官方包
- 安装并启动 nginx

用法：

```bash
# 安装 stable 分支
sudo bash install-nginx-official.sh

# 明确安装 stable 分支
sudo bash install-nginx-official.sh stable

# 安装 mainline 分支
sudo bash install-nginx-official.sh mainline
```

远程执行：

```bash
# curl
sudo bash <(curl -Ls https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/install-nginx-official.sh)
sudo bash <(curl -Ls https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/install-nginx-official.sh) mainline

# wget
sudo bash <(wget -qO- https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/install-nginx-official.sh)
sudo bash <(wget -qO- https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/install-nginx-official.sh) mainline
```

强制校验 nginx 官方 key 指纹：

```bash
sudo NGINX_EXPECTED_FINGERPRINT=573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62 \
  bash install-nginx-official.sh stable
```

参数：

| 参数位置 | 默认值 | 可选值 | 说明 |
| --- | --- | --- | --- |
| `$1` | `stable` | `stable` / `mainline` | nginx 分支 |

环境变量：

| 变量 | 说明 |
| --- | --- |
| `NGINX_EXPECTED_FINGERPRINT` | 指定可信 GPG 指纹。设置后，脚本会校验下载到的 key 是否包含该指纹 |

安装后常用命令：

```bash
nginx -v
systemctl status nginx
systemctl restart nginx
```

注意：

- 必须使用 root 权限运行。
- 当前脚本写入的是 Debian 官方 nginx 仓库地址，不适用于 Ubuntu。
- apt 源文件为 `/etc/apt/sources.list.d/nginx.list`。
- keyring 文件为 `/usr/share/keyrings/nginx-archive-keyring.gpg`。

## 安装 zsh 自动补全环境

脚本：`install-zsh.sh`

支持包管理器：

- `apt` / `apt-get`
- `dnf`
- `yum`
- `pacman`
- `apk`
- `brew`

功能：

- 安装 `zsh`、`git`、`curl`、`ca-certificates`
- 自动测试 GitHub 直连和 `gh-proxy.org` 速度
- 安装 Oh My Zsh
- 安装插件：
  - `zsh-autosuggestions`
  - `zsh-syntax-highlighting`
  - `zsh-completions`
- 尝试安装 `fzf`
- 重写 `~/.zshrc`
- 尝试将默认 shell 改为 zsh

用法：

```bash
bash install-zsh.sh
```

远程执行：

```bash
# curl
bash <(curl -Ls https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/install-zsh.sh)

# wget
bash <(wget -qO- https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/install-zsh.sh)
```

强制使用 GitHub 直连：

```bash
FORCE_GH_PROXY=0 bash install-zsh.sh
```

强制使用 `gh-proxy.org`：

```bash
FORCE_GH_PROXY=1 bash install-zsh.sh
```

环境变量：

| 变量 | 可选值 | 说明 |
| --- | --- | --- |
| `FORCE_GH_PROXY` | `0` / `1` | `0` 表示强制 GitHub 直连，`1` 表示强制使用 `gh-proxy.org` |
| `ZSH_CUSTOM` | 路径 | 指定 Oh My Zsh 自定义目录，默认是 `$HOME/.oh-my-zsh/custom` |

安装完成后：

```bash
exec zsh
```

注意：

- 如果当前用户不是 root，系统需要安装 `sudo`。
- 脚本会备份已有 `~/.zshrc` 为 `~/.zshrc.backup.<时间戳>`，然后重写新的 `~/.zshrc`。
- 如果自动修改默认 shell 失败，可手动执行：

```bash
chsh -s "$(command -v zsh)"
```

## 网络重装系统

脚本：`InstallNET.sh`

该脚本会下载网络安装器，修改 GRUB 引导项，并在重启后自动安装系统。执行前请确认已经备份数据，且确认当前机器可通过控制台、VNC、救援系统或云厂商面板恢复。

支持模式：

- 网络重装 Debian
- 网络重装 Ubuntu
- 网络重装 CentOS
- 使用远程镜像 DD 安装系统
- 只生成 loader 文件，不直接修改 GRUB 和重启

默认值：

| 项目 | 默认值 |
| --- | --- |
| 默认系统 | Debian |
| 默认 Debian 版本 | `buster` |
| 默认 Ubuntu 版本 | `bionic` |
| 默认 CentOS 版本 | `6.10` |
| 默认架构 | 自动识别当前机器架构 |
| 默认 root 密码 | `MoeClub.org` |
| 默认 SSH 端口 | `22` |
| 默认 DNS | `8.8.8.8` |

基本用法：

```bash
# 重装 Debian 12 amd64，设置 root 密码
sudo bash InstallNET.sh -d 12 -v 64 -p 'YourStrongPassword'

# 重装 Debian bookworm amd64
sudo bash InstallNET.sh --debian bookworm --ver amd64 -p 'YourStrongPassword'

# 重装 Ubuntu 20.04 amd64
sudo bash InstallNET.sh --ubuntu 20.04 --ver 64 -p 'YourStrongPassword'

# 重装 CentOS 6.10 x86_64
sudo bash InstallNET.sh --centos 6.10 --ver 64 -p 'YourStrongPassword'
```

远程执行：

```bash
# curl
sudo bash <(curl -Ls https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/InstallNET.sh) -d 12 -v 64 -p 'YourStrongPassword'

# wget
sudo bash <(wget -qO- https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/InstallNET.sh) -d 12 -v 64 -p 'YourStrongPassword'
```

指定静态网络：

```bash
sudo bash InstallNET.sh \
  -d 12 -v 64 -p 'YourStrongPassword' \
  --ip-addr 192.0.2.10 \
  --ip-mask 255.255.255.0 \
  --ip-gate 192.0.2.1 \
  --ip-dns 8.8.8.8
```

指定镜像源：

```bash
sudo bash InstallNET.sh \
  -d 12 -v 64 -p 'YourStrongPassword' \
  --mirror https://mirrors.tuna.tsinghua.edu.cn/debian
```

DD 远程镜像：

```bash
sudo bash InstallNET.sh \
  --image https://example.com/windows-or-linux-image.gz \
  -p 'YourStrongPassword' \
  --ip-addr 192.0.2.10 \
  --ip-mask 255.255.255.0 \
  --ip-gate 192.0.2.1
```

只生成 loader 文件：

```bash
sudo bash InstallNET.sh --loader -d 12 -v 64 -p 'YourStrongPassword'
```

生成的文件位于：

```text
$HOME/loader/initrd.img
$HOME/loader/vmlinuz
```

常用参数：

| 参数 | 说明 |
| --- | --- |
| `-d`, `--debian <版本>` | 指定 Debian 版本或代号，例如 `12`、`bookworm` |
| `-u`, `--ubuntu <版本>` | 指定 Ubuntu 版本或代号，例如 `20.04`、`focal` |
| `-c`, `--centos <版本>` | 指定 CentOS 版本，例如 `6.10` |
| `-v`, `--ver <架构>` | 指定架构，支持 `32` / `i386` / `64` / `amd64` |
| `-p`, `--password <密码>` | 设置新系统 root 密码 |
| `-port <端口>` | 设置新系统 SSH 端口 |
| `--ip-addr <IP>` | 指定静态 IP |
| `--ip-mask <掩码>` | 指定子网掩码 |
| `--ip-gate <网关>` | 指定网关 |
| `--ip-dns <DNS>` | 指定 DNS，默认 `8.8.8.8` |
| `-i`, `--interface <网卡>` | 指定安装器使用的网卡 |
| `--dev-net` | 添加 `net.ifnames=0 biosdevname=0`，使用传统网卡命名 |
| `--noipv6` | 禁用 IPv6 |
| `--loader` | 只生成 loader 文件，不修改 GRUB，不自动重启 |
| `-apt`, `-yum`, `--mirror <URL>` | 指定镜像源 |
| `-dd`, `--image <URL>` | 使用远程镜像 DD 安装 |
| `-rdp <端口>` | DD Windows 镜像时设置远程桌面端口 |
| `-cmd <命令>` | 新系统首次启动后执行的命令 |
| `-console <控制台>` | 追加内核 console 参数 |
| `-firmware` | Debian 安装时附加 non-free firmware |

风险提示：

- 必须使用 root 权限运行。
- 默认模式会修改 GRUB、复制内核和 initrd 到 `/boot`，然后自动重启。
- 安装过程会重新分区并覆盖系统盘数据。
- 静态网络参数错误会导致重装后无法联网。
- DD 模式只接受 `http://`、`https://` 或 `ftp://` 镜像 URL。
- 生产机器执行前请先确认云厂商控制台、救援模式和备份可用。

## 快速检查

执行脚本前，可以先查看帮助或触发参数提示：

```bash
bash InstallNET.sh --help
```

查看脚本内容：

```bash
sed -n '1,120p' install-docker.sh
sed -n '1,120p' install-nginx-official.sh
sed -n '1,160p' install-zsh.sh
sed -n '1,120p' InstallNET.sh
```

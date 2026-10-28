# Notes 脚本使用说明

本仓库收集了一些 Linux 服务器初始化和系统安装脚本，并添加了一些内容：

| 脚本 | 用途 |
| --- | --- |
| `install-docker.sh` | 在 Debian / Ubuntu 上安装 Docker CE 和 Docker Compose 插件 |
| `install-nginx-official.sh` | 在 Debian 上添加 nginx.org 官方源并安装 nginx |
| `install-zsh.sh` | 安装 zsh、Oh My Zsh、常用补全和高亮插件 |
| `InstallNET.sh` | 通过网络重装 Debian / Ubuntu / CentOS，或通过 DD 镜像安装系统 |

## 目录

- [国内网络与自动加速](#国内网络与自动加速)
- [安装 Docker](#安装-docker)
- [安装 nginx 官方版](#安装-nginx-官方版)
- [安装 zsh 自动补全环境](#安装-zsh-自动补全环境)
- [网络重装系统](#网络重装系统)
- [快速检查](#快速检查)

## 国内网络与自动加速

脚本下载到服务器后，直接按下面各节运行即可。四个脚本默认查询出口 IP 所在地区：**中国大陆（`CN`）优先加速，其他地区优先直连**。

| 脚本 | 国内出口的默认行为 | 失败处理 |
| --- | --- | --- |
| Docker | 软件包及密钥使用 TUNA，备用 USTC，再备用官方站 | 自动选源时按序切换；密钥指纹不符直接停止 |
| zsh | Oh My Zsh 和插件通过 `https://gh-proxy.com/` 浅克隆 | 实际克隆失败再试直连；海外则先直连、失败再试代理 |
| nginx | 保留 nginx.org 官方软件包；有自定义仓库时使用指定地址 | 没有可信官方包镜像时显示提示，不替换成第三方构建 |
| InstallNET | 安装器及可选 firmware 优先国内镜像 | 下载失败换源；kernel 与 initrd 必须来自同一镜像 |

地区识别先查询 `https://ipapi.co/country/`，失败再查询 Cloudflare trace。仅返回 `CN` 才按国内处理；识别接口不可用时提示并使用直连优先。设置已有 HTTP(S) 代理时，识别结果可能是代理出口地区。

手动指定地区可以跳过查询。显式软件源、自定义地址以及 zsh 的 `FORCE_GH_PROXY` 优先于自动判断：

```bash
# 国内机器无法访问地区识别接口时
sudo INSTALL_REGION=cn bash install-docker.sh

# 按海外出口策略运行
sudo INSTALL_REGION=global bash install-docker.sh

# zsh 配置安装到当前用户，通常不要加 sudo
INSTALL_REGION=cn bash install-zsh.sh
```

`INSTALL_REGION` 支持 `auto`（默认）、`cn`、`global`。这是候选线路的优先顺序，不是禁止访问其他地区；需要锁定 Docker 源时传 `official` / `tuna` / `ustc`，需要锁定 GitHub 线路时设置 `FORCE_GH_PROXY=0/1`。

### 先下载脚本，再由脚本自动选线路

**IP 判断只能在脚本启动后进行，无法加速脚本自身的首次下载。** 下文远程示例先用 GitHub 第三方代理下载文件，下载成功后才执行；代理会转发脚本内容，请使用你信任的服务。不要关闭 HTTPS 证书校验。

海外服务器可将示例中的下载地址前缀 `https://gh-proxy.com/` 删除，改为直连 GitHub。也可以先在能访问 GitHub 的电脑下载，再上传脚本。

若只有 wget，可选定脚本后先下载，再按对应章节运行：

```bash
SCRIPT=install-docker.sh  # 也可换成其他三个脚本名
wget --timeout=20 --tries=3 \
  -O "$SCRIPT" "https://gh-proxy.com/https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/$SCRIPT" &&
  bash -n "$SCRIPT"
```

首次安装依赖仍沿用服务器现有的 apt / dnf 等系统源，不会自动重写系统源。若这一步慢，应先使用云厂商已有的软件源或自行配置合适的发行版镜像。Docker 和 nginx 的 apt 操作设置了网络超时及有限重试；zsh 的 Git 克隆设置了低速退出，系统有 `timeout` 时每条线路最多运行 180 秒。

## 安装 Docker

脚本：`install-docker.sh`

支持系统：

- Debian
- Ubuntu

功能：

- 更新 apt 缓存并安装基础依赖，不升级整个系统
- 根据出口 IP 自动选择 Docker 官方源 / TUNA / USTC，也可显式指定
- 安装 `docker-ce`、`docker-ce-cli`、`containerd.io`、`docker-compose-plugin`
- 启用并重启 Docker 服务
- 安装 `docker-ce-rootless-extras`
- 合并 `/etc/docker/daemon.json`，保留已有镜像加速、代理和其他配置
- 可选：将指定用户加入 `docker` 组

用法：

```bash
# 自动识别出口 IP 并选源
sudo bash install-docker.sh

# 强制使用 Docker 官方源
sudo bash install-docker.sh official

# 使用清华 TUNA 源
sudo bash install-docker.sh tuna

# 使用 USTC 源
sudo bash install-docker.sh ustc

# 使用清华 TUNA 源，并将 www-data 加入 docker 组
sudo bash install-docker.sh tuna www-data
```

远程执行：

```bash
curl -fL --connect-timeout 8 --max-time 120 --retry 2 --retry-max-time 180 \
  -o install-docker.sh \
  https://gh-proxy.com/https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/install-docker.sh &&
  sudo bash install-docker.sh
```

下载后也可运行 `sudo bash install-docker.sh auto www-data`，自动选源并添加用户。

参数：

| 参数位置 | 默认值 | 说明 |
| --- | --- | --- |
| `$1` | `auto` | `auto` 自动选源；`official` / `tuna` / `ustc` 锁定源；其他值兼容旧版，提示后使用官方源 |
| `$2` | 空 | 要加入 `docker` 组的用户名 |

环境变量：

| 变量 | 说明 |
| --- | --- |
| `INSTALL_REGION` | `auto` / `cn` / `global`，控制默认软件源优先顺序 |
| `DOCKER_REPO_URL` | 完整的 Docker CE 仓库根路径，例如 `https://mirrors.ustc.edu.cn/docker-ce/linux/debian`；覆盖选源参数 |
| `DOCKER_GPG_URL` | 单独指定密钥地址；默认从所选仓库的 `/gpg` 下载 |
| `DOCKER_EXPECTED_FINGERPRINT` | 信任的签名密钥指纹；默认校验 Docker 的 `9DC858229FC7DD38854AE2D88D81803C0EBFCD88`，不匹配或夹带其他主密钥则停止 |
| `DOCKER_REGISTRY_MIRRORS` | 你信任的 Docker Hub HTTPS 加速地址，以逗号或空格分隔；显式设置时替换该字段，未设置则保留原值 |

**安装软件包加速和 Docker 拉镜像加速是两回事。** 脚本不内置未经验证的公共 Docker Hub 加速地址。已有的 `registry-mirrors` 和 daemon `proxies` 会保留；如果你有可信的加速服务，可这样配置：

```bash
sudo INSTALL_REGION=cn \
  DOCKER_REGISTRY_MIRRORS='https://your-registry-mirror.example.com' \
  bash install-docker.sh
```

上面的镜像地址是占位示例，必须替换为真实服务。`registry-mirrors` 用于 Docker Hub，不会加速所有第三方注册表；其他注册表可使用你已有的 Docker daemon 代理配置。不要把 GitHub 下载代理填入这里。

注意：

- 必须使用 root 权限运行。
- 脚本只会更新 apt 缓存并安装 Docker 相关依赖，不会执行全系统升级。
- 已有 daemon、key 和软件源配置会备份为原路径加 `.bak.<时间戳>.<进程号>`。daemon 配置先合并并用 `dockerd --validate` 检查；重启失败则恢复原配置。
- apt 更新或安装失败会恢复原 key 和软件源文件，不回退已经部分安装的软件包。
- 全新 daemon 配置沿用日志轮转和 IPv6 等默认设置；已有配置字段不被覆盖，只有显式提供的 `DOCKER_REGISTRY_MIRRORS` 会替换对应字段。
- 新加入 `docker` 组的用户需要重新登录，或执行 `newgrp docker` 后权限才会生效。

## 安装 nginx 官方版

脚本：`install-nginx-official.sh`

支持系统：

- Debian

功能：

- 安装依赖
- 自动识别出口 IP；默认保留官方包来源，可显式指定同分支镜像
- 下载 nginx 官方签名 key，设置超时和有限重试
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
curl -fL --connect-timeout 8 --max-time 120 --retry 2 --retry-max-time 180 \
  -o install-nginx-official.sh \
  https://gh-proxy.com/https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/install-nginx-official.sh &&
  sudo bash install-nginx-official.sh stable
```

安装 mainline 时，将最后一个参数改为 `mainline`。

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
| `INSTALL_REGION` | `auto` / `cn` / `global`；国内且没有自定义镜像时提示继续使用官方源 |
| `NGINX_REPO_URL` | 同分支的官方包镜像完整根路径，覆盖默认仓库；需与 `stable` / `mainline` 参数一致 |
| `NGINX_KEY_URL` | HTTPS 密钥下载地址；非默认地址必须同时设置可信指纹 |
| `NGINX_EXPECTED_FINGERPRINT` | 指定可信 GPG 指纹。校验后只将匹配的 key 导出给 apt，不信任同文件夹带的其他主密钥 |

安装后常用命令：

```bash
nginx -v
systemctl status nginx
systemctl restart nginx
```

注意：

- 必须使用 root 权限运行。
- 默认使用 nginx.org 提供的 Debian 软件包，不适用于 Ubuntu。国内 IP 不会自动切换成发行版 nginx 或第三方构建。
- 没有内置可信国内 apt 镜像时，使用你提供的 `NGINX_REPO_URL` 或已配置的 curl/apt 网络代理；GitHub 代理不能转发 nginx apt 源。
- apt 更新或安装失败会恢复旧 key、源列表和 pin 文件；不回退已经部分安装的软件包。
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
- 根据出口 IP 决定 GitHub 直连 / 代理优先级，实际克隆失败时再切换，不额外测速
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
curl -fL --connect-timeout 8 --max-time 120 --retry 2 --retry-max-time 180 \
  -o install-zsh.sh \
  https://gh-proxy.com/https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/install-zsh.sh &&
  bash install-zsh.sh
```

强制使用 GitHub 直连：

```bash
FORCE_GH_PROXY=0 bash install-zsh.sh
```

强制使用 GitHub 代理：

```bash
FORCE_GH_PROXY=1 bash install-zsh.sh
```

环境变量：

| 变量 | 可选值 | 说明 |
| --- | --- | --- |
| `INSTALL_REGION` | `auto` / `cn` / `global` | 默认按出口 IP 选优先线路 |
| `FORCE_GH_PROXY` | `0` / `1` | `0` 只直连，`1` 只使用代理；覆盖地区判断，失败不切换 |
| `GH_PROXY_URL` | HTTPS URL 前缀 | 默认 `https://gh-proxy.com/`，可换成你信任且支持 Git Clone 的 GitHub 代理 |
| `ZSH_CUSTOM` | 路径 | 指定 Oh My Zsh 自定义目录，默认是 `$HOME/.oh-my-zsh/custom` |

安装完成后：

```bash
exec zsh
```

注意：

- 如果当前用户不是 root，系统需要安装 `sudo`。
- Oh My Zsh 和插件均通过浅克隆安装；失败的临时克隆会清理，不留下半成品安装目录。
- `fzf` 安装失败只会警告，不中断后续 zsh 配置。
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
curl -fL --connect-timeout 8 --max-time 120 --retry 2 --retry-max-time 180 \
  -o InstallNET.sh \
  https://gh-proxy.com/https://raw.githubusercontent.com/moll33er/Notes/refs/heads/master/InstallNET.sh &&
  sudo bash InstallNET.sh --loader -d 12 -v 64 -p 'YourStrongPassword'
```

远程示例使用 `--loader`，只生成安装文件。正式重装前阅读风险提示；去掉 `--loader` 会进入修改引导、自动重启和覆盖系统盘的流程。

指定静态网络：

```bash
sudo bash InstallNET.sh \
  -d 12 -v 64 -p 'YourStrongPassword' \
  --ip-addr 192.0.2.10 \
  --ip-mask 255.255.255.0 \
  --ip-gate 192.0.2.1 \
  --ip-dns 8.8.8.8
```

地区识别与安装资源下载：

- `INSTALL_REGION=auto` 根据出口 IP 选优先顺序；`cn` 优先国内镜像，`global` 优先官方站。
- `--mirror` 始终优先，失败后会提示并尝试其他候选。安装器成对下载成功后，将最终镜像写入安装配置。
- 初始安装器和可选 firmware 下载使用超时、有限重试与临时文件，不再跳过 HTTPS 证书校验。旧系统若缺 CA 证书，请先安装 `ca-certificates`。
- 重启后的安装器使用最终选中的镜像主机与目录；当前服务器的 HTTP(S) 代理环境不会自动带入安装器。
- DD 镜像仍从你传入的 `--image` URL 下载，不会被系统镜像候选替换。大镜像应放在目标服务器可快速访问的存储上。
- 保留旧版 HTTP / FTP 自定义镜像兼容性；建议优先使用 HTTPS。

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

开发时可执行离线回归检查，需 Python 3 和 Bash；Windows 使用 Git for Windows 自带 Bash。检查只运行提取的函数并模拟网络、包管理器和服务，不运行安装或重装入口：

```bash
python3 tests/test_installers.py
```

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

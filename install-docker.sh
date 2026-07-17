#!/usr/bin/env bash

set -e

# ============================================================
# Docker 一键安装脚本
# 支持系统：Debian / Ubuntu
# 支持源：
#   官方源：bash install-docker.sh
#   清华源：bash install-docker.sh tuna
#
# 可选：添加用户到 docker 组
#   bash install-docker.sh tuna www-data
# ============================================================

SOURCE_TYPE="${1:-official}"
DOCKER_USER="${2:-}"

DOCKER_DAEMON_JSON="/etc/docker/daemon.json"
DOCKER_GPG_KEY="/usr/share/keyrings/docker-ce.gpg"
DOCKER_APT_LIST="/etc/apt/sources.list.d/docker.list"

echo "============================================================"
echo " Docker 安装脚本"
echo "============================================================"

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 root 用户运行此脚本"
    echo "例如：sudo -i 后再执行"
    exit 1
fi

# 检查系统
if [ ! -f /etc/os-release ]; then
    echo "错误：无法识别当前系统"
    exit 1
fi

. /etc/os-release

OS_ID="${ID}"
OS_CODENAME=""

if command -v lsb_release >/dev/null 2>&1; then
    OS_CODENAME="$(lsb_release -sc)"
else
    OS_CODENAME="${VERSION_CODENAME:-}"
fi

if [ -z "$OS_CODENAME" ]; then
    echo "错误：无法获取系统代号"
    exit 1
fi

if [ "$OS_ID" != "debian" ] && [ "$OS_ID" != "ubuntu" ]; then
    echo "错误：当前系统不是 Debian 或 Ubuntu"
    echo "当前系统：$OS_ID"
    exit 1
fi

echo "系统类型：$OS_ID"
echo "系统代号：$OS_CODENAME"
echo "软件源类型：$SOURCE_TYPE"

# 安装基础依赖
echo
echo "正在更新 apt 缓存并安装基础依赖..."

apt update

apt install -y \
    curl \
    vim \
    wget \
    gnupg \
    dpkg \
    apt-transport-https \
    lsb-release \
    ca-certificates

# 创建 keyrings 目录
mkdir -p /usr/share/keyrings

# 添加 Docker GPG 公钥和软件源
echo
echo "正在添加 Docker GPG 公钥和 apt 源..."

rm -f "$DOCKER_GPG_KEY"
rm -f "$DOCKER_APT_LIST"

if [ "$SOURCE_TYPE" = "tuna" ]; then
    # 清华 TUNA 源
    if [ "$OS_ID" = "debian" ]; then
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor > "$DOCKER_GPG_KEY"
        echo "deb [arch=$(dpkg --print-architecture) signed-by=$DOCKER_GPG_KEY] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian $OS_CODENAME stable" > "$DOCKER_APT_LIST"
    elif [ "$OS_ID" = "ubuntu" ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor > "$DOCKER_GPG_KEY"
        echo "deb [arch=$(dpkg --print-architecture) signed-by=$DOCKER_GPG_KEY] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu $OS_CODENAME stable" > "$DOCKER_APT_LIST"
    fi
else
    # Docker 官方源
    if [ "$OS_ID" = "debian" ]; then
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor > "$DOCKER_GPG_KEY"
        echo "deb [arch=$(dpkg --print-architecture) signed-by=$DOCKER_GPG_KEY] https://download.docker.com/linux/debian $OS_CODENAME stable" > "$DOCKER_APT_LIST"
    elif [ "$OS_ID" = "ubuntu" ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor > "$DOCKER_GPG_KEY"
        echo "deb [arch=$(dpkg --print-architecture) signed-by=$DOCKER_GPG_KEY] https://download.docker.com/linux/ubuntu $OS_CODENAME stable" > "$DOCKER_APT_LIST"
    fi
fi

chmod 644 "$DOCKER_GPG_KEY"

# 安装 Docker
echo
echo "正在安装 Docker CE..."

apt update

apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-compose-plugin

# 启动并设置开机自启
echo
echo "正在启动 Docker 服务..."

systemctl enable docker
systemctl restart docker

# 安装 rootless extras
echo
echo "正在安装 docker-ce-rootless-extras..."

apt install -y docker-ce-rootless-extras

# 可选：添加用户到 docker 组
if [ -n "$DOCKER_USER" ]; then
    echo
    echo "正在将用户 $DOCKER_USER 添加到 docker 组..."

    if id "$DOCKER_USER" >/dev/null 2>&1; then
        usermod -aG docker "$DOCKER_USER"
        echo "用户 $DOCKER_USER 已加入 docker 组"
        echo "注意：该用户需要重新登录后权限才会生效"
    else
        echo "警告：用户 $DOCKER_USER 不存在，跳过添加 docker 组"
    fi
fi

# 配置 Docker daemon.json
echo
echo "正在配置 Docker daemon.json..."

mkdir -p /etc/docker

if [ -f "$DOCKER_DAEMON_JSON" ]; then
    BACKUP_FILE="${DOCKER_DAEMON_JSON}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$DOCKER_DAEMON_JSON" "$BACKUP_FILE"
    echo "已备份原配置到：$BACKUP_FILE"
fi

cat > "$DOCKER_DAEMON_JSON" << EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "20m",
        "max-file": "3"
    },
    "ipv6": true,
    "fixed-cidr-v6": "fd00:dead:beef:c0::/80",
    "experimental": true,
    "ip6tables": true
}
EOF

# 重启 Docker
echo
echo "正在重启 Docker..."

systemctl restart docker

# 检查安装结果
echo
echo "============================================================"
echo " Docker 安装完成"
echo "============================================================"

echo
echo "Docker 版本信息："
docker version

echo
echo "Docker Compose 插件版本信息："
docker compose version

echo
echo "============================================================"
echo " 安装完成"
echo "============================================================"

if [ -n "$DOCKER_USER" ]; then
    echo
    echo "提示：用户 $DOCKER_USER 已加入 docker 组"
    echo "请退出当前登录会话并重新登录，或执行："
    echo
    echo "  newgrp docker"
    echo
fi

#!/usr/bin/env bash

set -Eeuo pipefail

# 用法：
#   ./install-nginx-official.sh
#   ./install-nginx-official.sh stable
#   ./install-nginx-official.sh mainline
#
# 可选：指定可信指纹进行强校验
#   NGINX_EXPECTED_FINGERPRINT=573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62 ./install-nginx-official.sh stable

NGINX_BRANCH="${1:-stable}"

KEY_URL="https://nginx.org/keys/nginx_signing.key"
KEYRING="/usr/share/keyrings/nginx-archive-keyring.gpg"
SOURCE_LIST="/etc/apt/sources.list.d/nginx.list"
PREFERENCES_FILE="/etc/apt/preferences.d/99nginx"

echo "==> 检查 root 权限"
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 root 用户运行此脚本，或使用 sudo 执行。"
    exit 1
fi

case "$NGINX_BRANCH" in
    stable)
        REPO_URL="https://nginx.org/packages/debian"
        ;;
    mainline)
        REPO_URL="https://nginx.org/packages/mainline/debian"
        ;;
    *)
        echo "错误：未知 nginx 分支：$NGINX_BRANCH"
        echo "用法："
        echo "  $0 stable"
        echo "  $0 mainline"
        exit 1
        ;;
esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TMP_KEY="$TMP_DIR/nginx_signing.key"
TMP_GNUPGHOME="$TMP_DIR/gnupg"

install -d -m 700 "$TMP_GNUPGHOME"

echo "==> 安装先决条件"
apt update
apt install -y curl gnupg2 ca-certificates lsb-release debian-archive-keyring

echo "==> 联网下载 nginx 官方签名密钥"
curl -fsSL \
    --proto '=https' \
    --tlsv1.2 \
    "$KEY_URL" \
    -o "$TMP_KEY"

echo "==> 从下载的 key 中解析当前指纹"

FINGERPRINTS="$(
    GNUPGHOME="$TMP_GNUPGHOME" \
    gpg --batch --show-keys --with-colons --fingerprint "$TMP_KEY" \
    | awk -F: '/^fpr:/ {print toupper($10)}'
)"

if [ -z "$FINGERPRINTS" ]; then
    echo "错误：未能从 nginx 签名密钥中解析出指纹。"
    exit 1
fi

echo
echo "检测到 nginx 签名 key 指纹："
echo "$FINGERPRINTS" | sed 's/^/  /'
echo

LATEST_FINGERPRINT="$(
    GNUPGHOME="$TMP_GNUPGHOME" \
    gpg --batch --show-keys --with-colons --fingerprint "$TMP_KEY" \
    | awk -F: '
        /^pub:/ {
            created=$6
        }
        /^fpr:/ {
            print created ":" toupper($10)
        }
    ' \
    | sort -t: -k1,1nr \
    | head -n1 \
    | cut -d: -f2
)"

echo "最新指纹：$LATEST_FINGERPRINT"
echo

if [ -n "${NGINX_EXPECTED_FINGERPRINT:-}" ]; then
    EXPECTED_NORMALIZED="$(
        echo "$NGINX_EXPECTED_FINGERPRINT" \
        | tr '[:lower:]' '[:upper:]' \
        | tr -d '[:space:]'
    )"

    echo "==> 校验指定的可信指纹"
    echo "期望指纹：$EXPECTED_NORMALIZED"

    if ! echo "$FINGERPRINTS" | grep -qx "$EXPECTED_NORMALIZED"; then
        echo "错误：下载到的 nginx 签名 key 不包含指定的可信指纹！"
        echo
        echo "下载到的指纹："
        echo "$FINGERPRINTS" | sed 's/^/  /'
        exit 1
    fi

    echo "可信指纹校验通过。"
else
    echo "提示：未设置 NGINX_EXPECTED_FINGERPRINT，跳过手动可信指纹强校验。"
fi

echo "==> 生成 apt 使用的 keyring 文件"
rm -f "$KEYRING"

GNUPGHOME="$TMP_GNUPGHOME" \
gpg --batch --yes --dearmor \
    -o "$KEYRING" \
    "$TMP_KEY"

chmod 644 "$KEYRING"

echo "==> 获取 Debian 发行版代号"
CODENAME="$(lsb_release -cs)"
echo "当前系统代号：$CODENAME"

echo "==> 写入 nginx 官方 apt 仓库"
cat > "$SOURCE_LIST" <<EOF
deb [signed-by=$KEYRING] $REPO_URL $CODENAME nginx
EOF

echo "已写入：$SOURCE_LIST"
cat "$SOURCE_LIST"

echo "==> 设置 apt pin，优先使用 nginx.org 官方包"
cat > "$PREFERENCES_FILE" <<EOF
Package: *
Pin: origin nginx.org
Pin: release o=nginx
Pin-Priority: 900
EOF

echo "已写入：$PREFERENCES_FILE"

echo "==> 更新 apt 缓存"
apt update

echo "==> 安装 nginx"
apt install -y nginx

echo "==> 启动并设置 nginx 开机自启"
systemctl enable nginx
systemctl restart nginx

echo
echo "==> nginx 安装完成"
nginx -v

echo
echo "nginx 分支：$NGINX_BRANCH"
echo "apt 源文件：$SOURCE_LIST"
echo "keyring 文件：$KEYRING"
echo "当前最新指纹：$LATEST_FINGERPRINT"
echo
echo "查看 nginx 状态："
echo "  systemctl status nginx"

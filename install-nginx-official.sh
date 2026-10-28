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

KEY_URL="${NGINX_KEY_URL:-https://nginx.org/keys/nginx_signing.key}"
KEYRING="/usr/share/keyrings/nginx-archive-keyring.gpg"
SOURCE_LIST="/etc/apt/sources.list.d/nginx.list"
PREFERENCES_FILE="/etc/apt/preferences.d/99nginx"

# 各脚本保持可独立下载；此小段有意不依赖仓库中的公共文件。
region_get() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 3 --max-time 6 "$1"
    else
        wget -qO- --timeout=3 --tries=1 "$1"
    fi
}

detect_region() {
    case "${INSTALL_REGION:-auto}" in
        cn|global)
            echo "==> 手动指定网络区域：$INSTALL_REGION" >&2
            return
            ;;
        auto) ;;
        *)
            echo "错误：INSTALL_REGION 只支持 auto、cn、global。" >&2
            return 1
            ;;
    esac

    local country
    country="$(region_get https://ipapi.co/country/ 2>/dev/null | tr -d '\r\n')" || country=""
    if ! [[ "$country" =~ ^[A-Z]{2}$ ]]; then
        country="$(region_get https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | sed -n 's/^loc=//p' | tr -d '\r\n')" || country=""
    fi
    if [ "$country" = CN ]; then
        INSTALL_REGION=cn
        echo "==> 出口 IP 地区：CN，优先使用国内加速。" >&2
    else
        INSTALL_REGION=global
        if [[ "$country" =~ ^[A-Z]{2}$ ]]; then
            echo "==> 出口 IP 地区：$country，优先直连。" >&2
        else
            echo "警告：无法识别出口 IP 地区，使用直连；国内机器可设置 INSTALL_REGION=cn。" >&2
        fi
    fi
}

install_nginx_packages() {
    local i file backup stamp
    local -a targets=("$KEYRING" "$SOURCE_LIST" "$PREFERENCES_FILE")
    local -a staged=("$TMP_DIR/nginx.gpg" "$TMP_DIR/nginx.list" "$TMP_DIR/99nginx")
    local -a backups=()
    stamp="$(date +%Y%m%d%H%M%S).$$"
    for i in "${!targets[@]}"; do
        file="${targets[$i]}"
        backup=""
        if [ -f "$file" ]; then
            backup="$file.bak.$stamp"
            cp -p "$file" "$backup" || return 1
        fi
        backups+=("$backup")
    done
    # 命令链中任一步失败，都恢复本次操作前的源配置；不回退已安装的软件包。
    if install -m 644 "${staged[0]}" "${targets[0]}" &&
       install -m 644 "${staged[1]}" "${targets[1]}" &&
       install -m 644 "${staged[2]}" "${targets[2]}" &&
       apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 update &&
       apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 install -y nginx; then
        return 0
    fi
    echo "错误：软件源更新或安装失败，恢复原有源配置；软件包可能已部分安装，请检查上方 apt 输出。" >&2
    for i in "${!targets[@]}"; do
        if [ -n "${backups[$i]}" ]; then
            cp -p "${backups[$i]}" "${targets[$i]}" || return 1
        else
            rm -f "${targets[$i]}" || return 1
        fi
    done
    return 1
}

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

if [ ! -f /etc/os-release ]; then
    echo "错误：无法识别系统，仅支持 Debian。" >&2
    exit 1
fi
. /etc/os-release
if [ "$ID" != debian ]; then
    echo "错误：此脚本仅支持 Debian。" >&2
    exit 1
fi
case "${INSTALL_REGION:-auto}" in auto|cn|global) ;; *) echo "错误：INSTALL_REGION 只支持 auto、cn、global。" >&2; exit 1 ;; esac
REPO_URL="${NGINX_REPO_URL:-$REPO_URL}"
for url in "$REPO_URL" "$KEY_URL"; do
    if [[ "$url" != https://* || "$url" =~ [[:space:]] ]]; then
        echo "错误：nginx 仓库和密钥地址必须是无空白字符的 HTTPS URL。" >&2
        exit 1
    fi
done
if [ "$KEY_URL" != https://nginx.org/keys/nginx_signing.key ] && [ -z "${NGINX_EXPECTED_FINGERPRINT:-}" ]; then
    echo "错误：自定义密钥地址时必须设置 NGINX_EXPECTED_FINGERPRINT。" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TMP_KEY="$TMP_DIR/nginx_signing.key"
TMP_GNUPGHOME="$TMP_DIR/gnupg"

install -d -m 700 "$TMP_GNUPGHOME"

echo "==> 安装先决条件"
apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 update
apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 install -y curl gnupg2 ca-certificates lsb-release debian-archive-keyring

detect_region
if [ "$INSTALL_REGION" = cn ] && [ -z "${NGINX_REPO_URL:-}" ]; then
    echo "==> 国内出口：尚未配置可信的 nginx 官方包镜像，保留 nginx.org 官方源。"
    echo "==> 可通过 NGINX_REPO_URL 指定同分支镜像，或使用已有的 curl/apt 网络代理。"
fi

echo "==> 联网下载 nginx 官方签名密钥"
curl -fsSL \
    --connect-timeout 8 --max-time 30 --retry 2 --retry-max-time 90 \
    --speed-limit 1024 --speed-time 15 \
    --proto '=https' --proto-redir '=https' \
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
if [ -n "${NGINX_EXPECTED_FINGERPRINT:-}" ]; then
    # 只信任已校验的 key，不把下载文件里夹带的其他主密钥一并交给 apt。
    GNUPGHOME="$TMP_GNUPGHOME" gpg --batch --import "$TMP_KEY"
    GNUPGHOME="$TMP_GNUPGHOME" gpg --batch --export "$EXPECTED_NORMALIZED" > "$TMP_DIR/nginx.gpg"
    test -s "$TMP_DIR/nginx.gpg"
else
    GNUPGHOME="$TMP_GNUPGHOME" gpg --batch --yes --dearmor -o "$TMP_DIR/nginx.gpg" "$TMP_KEY"
fi

echo "==> 获取 Debian 发行版代号"
CODENAME="$(lsb_release -cs)"
echo "当前系统代号：$CODENAME"
cat > "$TMP_DIR/nginx.list" <<EOF
deb [signed-by=$KEYRING] $REPO_URL $CODENAME nginx
EOF
cat > "$TMP_DIR/99nginx" <<EOF
Package: *
Pin: release o=nginx
Pin-Priority: 900
EOF
install -d -m 755 /usr/share/keyrings
echo "==> 安装 nginx，仓库：$REPO_URL"
install_nginx_packages

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

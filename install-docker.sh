#!/usr/bin/env bash
set -eo pipefail

# Debian / Ubuntu。无参数自动选源；仍支持 official/tuna/ustc [用户名]。
SOURCE_TYPE="${1:-auto}"
DOCKER_USER="${2:-}"
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"
DOCKER_GPG_KEY="/usr/share/keyrings/docker-ce.gpg"
DOCKER_APT_LIST="/etc/apt/sources.list.d/docker.list"

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

fetch() {
    curl -fsSL --proto '=https' --proto-redir '=https' \
        --connect-timeout 8 --max-time 60 --retry 2 --retry-max-time 120 \
        --speed-limit 1024 --speed-time 15 "$1" -o "$2"
}

prepare_repository() {
    local base key_url expected fingerprints
    local -a candidates
    if [ -n "${DOCKER_REPO_URL:-}" ]; then
        candidates=("${DOCKER_REPO_URL%/}")
    else
        case "$SOURCE_TYPE" in
            auto)
                if [ "$INSTALL_REGION" = cn ]; then
                    candidates=("https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/$OS_ID"
                                "https://mirrors.ustc.edu.cn/docker-ce/linux/$OS_ID"
                                "https://download.docker.com/linux/$OS_ID")
                else
                    candidates=("https://download.docker.com/linux/$OS_ID")
                fi
                ;;
            official) candidates=("https://download.docker.com/linux/$OS_ID") ;;
            tuna) candidates=("https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/$OS_ID") ;;
            ustc) candidates=("https://mirrors.ustc.edu.cn/docker-ce/linux/$OS_ID") ;;
        esac
    fi
    expected="${DOCKER_EXPECTED_FINGERPRINT:-9DC858229FC7DD38854AE2D88D81803C0EBFCD88}"
    expected="$(printf '%s' "$expected" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')"
    for base in "${candidates[@]}"; do
        if [[ "$base" != https://* || "$base" =~ [[:space:]] ]]; then
            echo "错误：Docker 仓库必须是无空白字符的 HTTPS URL。" >&2
            return 1
        fi
        key_url="${DOCKER_GPG_URL:-$base/gpg}"
        echo "==> 尝试 Docker 仓库：$base" >&2
        if fetch "$base/dists/$OS_CODENAME/Release" "$TMP_DIR/Release" &&
           fetch "$key_url" "$TMP_DIR/docker.asc"; then
            fingerprints="$(gpg --batch --show-keys --with-colons --fingerprint "$TMP_DIR/docker.asc" | awk -F: '/^pub:/ {primary=1; next} /^sub:/ {primary=0} /^fpr:/ && primary {print toupper($10); primary=0}')" || fingerprints=""
            if [ "$fingerprints" != "$expected" ]; then
                echo "错误：Docker 签名密钥指纹不匹配，停止，不替换现有配置。" >&2
                return 1
            fi
            gpg --batch --yes --dearmor -o "$TMP_DIR/docker.gpg" "$TMP_DIR/docker.asc" || return 1
            printf 'deb [arch=%s signed-by=%s] %s %s stable\n' \
                "$(dpkg --print-architecture)" "$DOCKER_GPG_KEY" "$base" "$OS_CODENAME" > "$TMP_DIR/docker.list"
            echo "==> 已选 Docker 仓库：$base" >&2
            return 0
        fi
        echo "警告：仓库或密钥下载失败：$base" >&2
    done
    echo "错误：Docker 仓库均不可用；原 key 和源文件未替换。" >&2
    return 1
}

install_docker_packages() {
    local i file backup stamp
    local -a targets=("$DOCKER_GPG_KEY" "$DOCKER_APT_LIST")
    local -a staged=("$TMP_DIR/docker.gpg" "$TMP_DIR/docker.list")
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
       apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 update &&
       apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-ce-rootless-extras; then
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

merge_daemon_config() {
    python3 - "$DOCKER_DAEMON_JSON" "$TMP_DIR/daemon.json" "${DOCKER_REGISTRY_MIRRORS:-}" <<'PY'
import json
import sys
from pathlib import Path
from urllib.parse import urlsplit

source, target, mirrors = sys.argv[1:]
path = Path(source)
config = json.loads(path.read_text()) if path.exists() else {}
if not isinstance(config, dict):
    raise SystemExit("错误：daemon.json 必须是 JSON 对象。")
config.setdefault("log-driver", "json-file")
if config["log-driver"] == "json-file":
    opts = config.setdefault("log-opts", {})
    opts.setdefault("max-size", "20m")
    opts.setdefault("max-file", "3")
for key, value in {"ipv6": True, "experimental": True, "ip6tables": True}.items():
    config.setdefault(key, value)
if config["ipv6"]:
    config.setdefault("fixed-cidr-v6", "fd00:dead:beef:c0::/80")
if mirrors:
    urls = mirrors.replace(",", " ").split()
    if not urls:
        raise SystemExit("错误：DOCKER_REGISTRY_MIRRORS 不能为空白。")
    for url in urls:
        parsed = urlsplit(url)
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise SystemExit("错误：镜像加速地址必须是无凭据、查询参数和片段的 HTTPS URL。")
    config["registry-mirrors"] = list(dict.fromkeys(url.rstrip("/") for url in urls))
Path(target).write_text(json.dumps(config, indent=4) + "\n")
PY
}

configure_daemon() {
    local backup=""
    mkdir -p /etc/docker
    merge_daemon_config || return 1
    dockerd --validate --config-file "$TMP_DIR/daemon.json" || return 1
    if [ -f "$DOCKER_DAEMON_JSON" ]; then
        backup="${DOCKER_DAEMON_JSON}.bak.$(date +%Y%m%d%H%M%S).$$"
        cp -p "$DOCKER_DAEMON_JSON" "$backup" || return 1
        echo "==> 已备份 Docker 配置：$backup"
    fi
    install -m 644 "$TMP_DIR/daemon.json" "${DOCKER_DAEMON_JSON}.new" || return 1
    mv -f "${DOCKER_DAEMON_JSON}.new" "$DOCKER_DAEMON_JSON" || return 1
    if ! systemctl restart docker; then
        echo "错误：Docker 重启失败，恢复本次修改前的配置。" >&2
        if [ -n "$backup" ]; then
            cp -p "$backup" "$DOCKER_DAEMON_JSON"
        else
            rm -f "$DOCKER_DAEMON_JSON"
        fi
        systemctl restart docker || echo "错误：恢复配置后仍无法启动，请检查 journalctl -u docker。" >&2
        return 1
    fi
}

if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 root 或 sudo 运行。" >&2
    exit 1
fi
case "$SOURCE_TYPE" in
    auto|official|tuna|ustc) ;;
    *) echo "警告：未知软件源 $SOURCE_TYPE，按旧版行为使用 official。" >&2; SOURCE_TYPE=official ;;
esac
if [ ! -f /etc/os-release ]; then
    echo "错误：无法识别当前系统。" >&2
    exit 1
fi
. /etc/os-release
OS_ID="$ID"
OS_CODENAME="${VERSION_CODENAME:-}"
if [ -z "$OS_CODENAME" ] && command -v lsb_release >/dev/null 2>&1; then
    OS_CODENAME="$(lsb_release -sc)"
fi
if [[ "$OS_ID" != debian && "$OS_ID" != ubuntu ]] || [ -z "$OS_CODENAME" ]; then
    echo "错误：仅支持能识别发行版代号的 Debian / Ubuntu。" >&2
    exit 1
fi
case "${INSTALL_REGION:-auto}" in auto|cn|global) ;; *) echo "错误：INSTALL_REGION 只支持 auto、cn、global。" >&2; exit 1 ;; esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export GNUPGHOME="$TMP_DIR/gnupg"
install -d -m 700 "$GNUPGHOME"
echo "==> 安装基础依赖（沿用当前系统软件源）"
apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 update
apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 install -y curl gnupg ca-certificates python3
detect_region
prepare_repository
mkdir -p /usr/share/keyrings
install_docker_packages
systemctl enable docker
configure_daemon

if [ -n "$DOCKER_USER" ]; then
    if id "$DOCKER_USER" >/dev/null 2>&1; then
        usermod -aG docker "$DOCKER_USER"
        echo "==> $DOCKER_USER 已加入 docker 组，请重新登录或执行 newgrp docker。"
    else
        echo "警告：用户 $DOCKER_USER 不存在，未加入 docker 组。" >&2
    fi
fi
if [ "$INSTALL_REGION" = cn ] && [ -z "${DOCKER_REGISTRY_MIRRORS:-}" ]; then
    echo "==> 国内软件包源不等于 Docker Hub 加速；已保留现有镜像配置。"
    echo "==> 如需新增镜像加速，请设置 DOCKER_REGISTRY_MIRRORS 为你信任的 HTTPS 地址。"
fi
docker version
docker compose version
echo "==> Docker 安装完成"

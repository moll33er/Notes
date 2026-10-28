#!/usr/bin/env bash

set -eo pipefail

echo "==> 开始安装 zsh 自动补全环境"

GH_PROXY="${GH_PROXY_URL:-https://gh-proxy.com/}"
GH_PROXY="${GH_PROXY%/}/"

USE_GH_PROXY=0

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# sudo 兼容处理
setup_sudo() {
  if command_exists sudo; then
    SUDO="sudo"
  else
    if [ "$(id -u)" -eq 0 ]; then
      SUDO=""
    else
      echo "错误：当前不是 root 用户，且系统没有 sudo。"
      echo "请先切换到 root 后再运行："
      echo "su -"
      exit 1
    fi
  fi
}

install_dependencies() {
  echo "==> 安装依赖"

  if command_exists apt; then
    $SUDO apt update
    $SUDO apt install -y zsh git curl ca-certificates

  elif command_exists apt-get; then
    $SUDO apt-get update
    $SUDO apt-get install -y zsh git curl ca-certificates

  elif command_exists dnf; then
    $SUDO dnf install -y zsh git curl ca-certificates

  elif command_exists yum; then
    $SUDO yum install -y zsh git curl ca-certificates

  elif command_exists pacman; then
    $SUDO pacman -Sy --noconfirm zsh git curl ca-certificates

  elif command_exists apk; then
    $SUDO apk add --no-cache zsh git curl ca-certificates

  elif command_exists brew; then
    brew install zsh git curl

  else
    echo "无法识别包管理器，请手动安装：zsh git curl ca-certificates"
    exit 1
  fi
}

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

# 强制线路优先于 IP 判断；自动模式只决定优先顺序，不做额外测速。
detect_github_proxy() {
  case "${FORCE_GH_PROXY:-}" in
    1) USE_GH_PROXY=1 ;;
    0) USE_GH_PROXY=0 ;;
    "")
      detect_region
      if [ "$INSTALL_REGION" = cn ]; then USE_GH_PROXY=1; else USE_GH_PROXY=0; fi
      ;;
    *) echo "错误：FORCE_GH_PROXY 只支持 0 或 1。" >&2; return 1 ;;
  esac
  if [[ "$GH_PROXY" != https://* || "$GH_PROXY" =~ [[:space:]] ]]; then
    echo "错误：GH_PROXY_URL 必须是无空白字符的 HTTPS URL 前缀。" >&2
    return 1
  fi
  if [ "$USE_GH_PROXY" = 1 ]; then
    echo "==> GitHub 优先使用第三方代理：$GH_PROXY"
  else
    echo "==> GitHub 优先直连"
  fi
}

git_clone_github() {
  local repo_url="$1" target_dir="$2" url staging
  local -a urls clone_cmd
  if [ "$USE_GH_PROXY" = 1 ]; then
    urls=("${GH_PROXY}${repo_url}")
    if [ -z "${FORCE_GH_PROXY:-}" ]; then urls+=("$repo_url"); fi
  else
    urls=("$repo_url")
    if [ -z "${FORCE_GH_PROXY:-}" ]; then urls+=("${GH_PROXY}${repo_url}"); fi
  fi
  mkdir -p "$(dirname "$target_dir")" || return 1
  for url in "${urls[@]}"; do
    staging="$(mktemp -d "${target_dir}.clone.XXXXXX")" || return 1
    echo "==> 克隆：$url"
    clone_cmd=(git -c http.lowSpeedLimit=1024 -c http.lowSpeedTime=20 clone --depth=1 "$url" "$staging/repo")
    if command_exists timeout; then clone_cmd=(timeout 180 "${clone_cmd[@]}"); fi
    if GIT_TERMINAL_PROMPT=0 "${clone_cmd[@]}"; then
      if mv "$staging/repo" "$target_dir"; then
        rmdir "$staging"
        return 0
      fi
      rm -rf "$staging"
      return 1
    fi
    rm -rf "$staging"
    echo "警告：克隆失败：$url；自动模式将尝试备用线路。" >&2
  done
  echo "错误：无法克隆 $repo_url。可设置 GH_PROXY_URL 或检查网络。" >&2
  return 1
}

install_oh_my_zsh() {
  if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "==> Oh My Zsh 已存在，跳过安装"
  else
    echo "==> 安装 Oh My Zsh"
    # 本脚本自行生成 zshrc 和设置 shell，无需再执行上游安装器的嵌套下载。
    git_clone_github https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
  fi
}

install_plugins() {
  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

  mkdir -p "$ZSH_CUSTOM/plugins"

  echo "==> 安装 zsh-autosuggestions"
  if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git_clone_github \
      https://github.com/zsh-users/zsh-autosuggestions.git \
      "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  else
    echo "zsh-autosuggestions 已存在，跳过"
  fi

  echo "==> 安装 zsh-syntax-highlighting"
  if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    git_clone_github \
      https://github.com/zsh-users/zsh-syntax-highlighting.git \
      "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  else
    echo "zsh-syntax-highlighting 已存在，跳过"
  fi

  echo "==> 安装 zsh-completions"
  if [ ! -d "$ZSH_CUSTOM/plugins/zsh-completions" ]; then
    git_clone_github \
      https://github.com/zsh-users/zsh-completions.git \
      "$ZSH_CUSTOM/plugins/zsh-completions"
  else
    echo "zsh-completions 已存在，跳过"
  fi
}

install_fzf() {
  echo "==> 尝试安装 fzf"

  if command_exists fzf; then
    echo "fzf 已安装，跳过"
    return
  fi

  if command_exists apt; then
    $SUDO apt install -y fzf
  elif command_exists apt-get; then
    $SUDO apt-get install -y fzf
  elif command_exists dnf; then
    $SUDO dnf install -y fzf
  elif command_exists yum; then
    $SUDO yum install -y fzf
  elif command_exists pacman; then
    $SUDO pacman -Sy --noconfirm fzf
  elif command_exists apk; then
    $SUDO apk add --no-cache fzf
  elif command_exists brew; then
    brew install fzf
  else
    echo "未找到可用包管理器安装 fzf，可之后手动安装"
  fi
}

configure_zshrc() {
  ZSHRC="$HOME/.zshrc"

  echo "==> 配置 ~/.zshrc"

  if [ -f "$ZSHRC" ]; then
    cp "$ZSHRC" "$ZSHRC.backup.$(date +%Y%m%d%H%M%S)"
    echo "==> 已备份原配置文件"
  fi

  cat > "$ZSHRC" <<'ZSHRC_EOF'
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(
  git
  zsh-completions
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

autoload -Uz compinit
compinit

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history

setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt AUTO_CD
setopt AUTO_LIST
setopt AUTO_MENU
setopt COMPLETE_IN_WORD

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
ZSHRC_EOF
}

change_default_shell() {
  ZSH_PATH="$(command -v zsh)"

  echo "==> zsh 路径: $ZSH_PATH"

  if [ "$SHELL" = "$ZSH_PATH" ]; then
    echo "==> 当前默认 shell 已经是 zsh"
    return
  fi

  echo "==> 尝试设置 zsh 为默认 shell"

  if command_exists chsh; then
    chsh -s "$ZSH_PATH" || {
      echo "==> 自动修改默认 shell 失败，请手动执行："
      echo "chsh -s $ZSH_PATH"
    }
  else
    echo "==> 未找到 chsh，请手动修改默认 shell"
  fi
}

case "${INSTALL_REGION:-auto}" in auto|cn|global) ;; *) echo "错误：INSTALL_REGION 只支持 auto、cn、global。" >&2; exit 1 ;; esac
case "${FORCE_GH_PROXY:-}" in ""|0|1) ;; *) echo "错误：FORCE_GH_PROXY 只支持 0 或 1。" >&2; exit 1 ;; esac
setup_sudo
install_dependencies
detect_github_proxy
install_oh_my_zsh
install_plugins
if ! install_fzf; then
  echo "警告：fzf 安装失败，继续完成 zsh 配置；之后可用系统包管理器补装。" >&2
fi
configure_zshrc
change_default_shell

echo
echo "======================================"
echo "安装完成！"
echo
echo "GitHub 首选下载方式（实际切换见上方日志）："
if [ "${USE_GH_PROXY:-0}" = "1" ]; then
  echo "代理：$GH_PROXY"
else
  echo "使用 GitHub 直连"
fi
echo
echo "请重新打开终端，或者执行："
echo "exec zsh"
echo
echo "如果默认 shell 未修改成功，请手动执行："
echo "chsh -s $(command -v zsh)"
echo "======================================"

#!/usr/bin/env bash

set -e

echo "==> 开始安装 zsh 自动补全环境"

GH_PROXY="https://gh-proxy.org/"
GH_TEST_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

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

# 下载测速，成功返回耗时，失败返回空
test_download_time() {
  local url="$1"
  local result
  local http_code
  local time_total

  result="$(curl -L -sS -o /dev/null \
    --connect-timeout 5 \
    --max-time 20 \
    -w "%{http_code} %{time_total}" \
    "$url" 2>/dev/null)" || return 0

  http_code="${result%% *}"
  time_total="${result##* }"

  if [ "$http_code" = "200" ]; then
    echo "$time_total"
  fi
}

# 自动判断是否使用 gh-proxy
detect_github_proxy() {
  echo "==> 测试 GitHub 直连和 gh-proxy.org 速度"

  # 支持环境变量强制指定
  # FORCE_GH_PROXY=1 ./install-zsh.sh 强制使用代理
  # FORCE_GH_PROXY=0 ./install-zsh.sh 强制不用代理
  if [ "${FORCE_GH_PROXY:-}" = "1" ]; then
    USE_GH_PROXY=1
    echo "==> 已通过 FORCE_GH_PROXY=1 强制启用 gh-proxy.org"
    return
  fi

  if [ "${FORCE_GH_PROXY:-}" = "0" ]; then
    USE_GH_PROXY=0
    echo "==> 已通过 FORCE_GH_PROXY=0 强制使用 GitHub 直连"
    return
  fi

  DIRECT_TIME="$(test_download_time "$GH_TEST_URL")"
  PROXY_TIME="$(test_download_time "${GH_PROXY}${GH_TEST_URL}")"

  echo "==> GitHub 直连耗时: ${DIRECT_TIME:-失败} 秒"
  echo "==> gh-proxy 耗时: ${PROXY_TIME:-失败} 秒"

  if [ -z "$DIRECT_TIME" ] && [ -z "$PROXY_TIME" ]; then
    echo "错误：GitHub 直连和 gh-proxy.org 都不可用"
    exit 1
  fi

  if [ -z "$DIRECT_TIME" ]; then
    USE_GH_PROXY=1
    echo "==> GitHub 直连失败，使用 gh-proxy.org"
    return
  fi

  if [ -z "$PROXY_TIME" ]; then
    USE_GH_PROXY=0
    echo "==> gh-proxy.org 失败，使用 GitHub 直连"
    return
  fi

  if awk "BEGIN {exit !($PROXY_TIME < $DIRECT_TIME)}"; then
    USE_GH_PROXY=1
    echo "==> gh-proxy.org 更快，使用代理"
  else
    USE_GH_PROXY=0
    echo "==> GitHub 直连更快，使用直连"
  fi
}

# 根据检测结果处理 GitHub URL
github_url() {
  local url="$1"

  if [ "${USE_GH_PROXY:-0}" = "1" ]; then
    echo "${GH_PROXY}${url}"
  else
    echo "$url"
  fi
}

curl_github() {
  local url="$1"
  curl -fsSL "$(github_url "$url")"
}

git_clone_github() {
  local repo_url="$1"
  local target_dir="$2"

  git clone --depth=1 "$(github_url "$repo_url")" "$target_dir"
}

install_oh_my_zsh() {
  if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "==> Oh My Zsh 已存在，跳过安装"
  else
    echo "==> 安装 Oh My Zsh"

    RUNZSH=no \
    CHSH=no \
    KEEP_ZSHRC=yes \
    REMOTE="$(github_url https://github.com/ohmyzsh/ohmyzsh.git)" \
      sh -c "$(curl_github https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
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

setup_sudo
install_dependencies
detect_github_proxy
install_oh_my_zsh
install_plugins
install_fzf
configure_zshrc
change_default_shell

echo
echo "======================================"
echo "安装完成！"
echo
echo "GitHub 下载方式："
if [ "${USE_GH_PROXY:-0}" = "1" ]; then
  echo "已启用 gh-proxy.org"
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

#!/bin/bash
# ==================================================================
# PVE Ubuntu 虚拟机初始化脚本
# 适用环境: Ubuntu 24.04 / 26.04 Server (PVE 内网虚拟机)
# 网络环境: OpenWrt 透明代理，无需额外代理配置
# 目标: Root SSH → 系统基础 → [可选] Docker / Node.js / Miniconda
# ==================================================================

set -euo pipefail

# ---- 自动提权: 非 root 用户自动通过 sudo 重新执行 ----
if [[ $EUID -ne 0 ]]; then
    echo "Not root. Re-running with sudo..."
    # 传递环境变量给 sudo 下的脚本
    exec sudo env ROOT_PASSWORD="${ROOT_PASSWORD:-root}" \
              NODE_MAJOR="${NODE_MAJOR:-24}" \
              ENABLE_DOCKER="${ENABLE_DOCKER:-}" \
              ENABLE_NODE="${ENABLE_NODE:-}" \
              ENABLE_MINICONDA="${ENABLE_MINICONDA:-}" \
              SKIP_SELECT="${SKIP_SELECT:-}" \
              bash "$0" "$@"
fi

# ---- 全局配置 (按需修改) ----
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"       # 可通过环境变量覆盖: ROOT_PASSWORD=xxx bash init.sh
NODE_MAJOR="${NODE_MAJOR:-24}"               # Node.js 主版本号
CONDA_DIR="/opt/miniconda3"
TIMEZONE="Asia/Shanghai"
ENABLE_DOCKER="${ENABLE_DOCKER:-}"           # 空=交互选择；true/false 可跳过菜单
ENABLE_NODE="${ENABLE_NODE:-}"
ENABLE_MINICONDA="${ENABLE_MINICONDA:-}"
SKIP_SELECT="${SKIP_SELECT:-false}"          # true 时跳过交互菜单，使用默认/环境变量

# ==========================================
# Interactive component selection (whiptail)
# English UI (PVE console safe) + NEWT theme
# Target look: bg #262626 / accent #e95420
# (newt only supports named colors; mapped to black/red)
# ==========================================

# Approximate #262626 (black) + #e95420 (red) for whiptail/newt
apply_newt_theme() {
    export NEWT_COLORS='
root=white,black
border=red,black
window=white,black
shadow=black,black
title=white,red
button=black,red
actbutton=white,red
compactbutton=white,black
checkbox=white,black
actcheckbox=white,red
entry=white,black
label=white,black
listbox=white,black
actlistbox=white,red
sellistbox=black,white
actsellistbox=white,red
textbox=white,black
roottext=red,black
emptyscale=,black
disabledentry=black,black
'
}

# Decide whether to show the interactive menu
should_show_select_menu() {
    [[ "$SKIP_SELECT" == "true" ]] && return 1
    [[ ! -t 0 ]] && return 1
    if [[ -n "$ENABLE_DOCKER" && -n "$ENABLE_NODE" && -n "$ENABLE_MINICONDA" ]]; then
        return 1
    fi
    return 0
}

# Normalize a bool string to true/false; empty falls back to default
normalize_bool() {
    local value="${1:-}"
    local defaultValue="${2:-true}"
    if [[ -z "$value" ]]; then
        echo "$defaultValue"
    elif [[ "$value" =~ ^(true|1|yes|y|on)$ ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Return English help text for PVE components
get_install_help_text() {
    cat <<EOF
REQUIRED (always installed, cannot disable)

1. System Base Setup
   - Root password: silently set to "root" (no prompt;
     override with ROOT_PASSWORD=xxx)
   - Timezone: Asia/Shanghai
   - Locales: en_US.UTF-8 / zh_CN.UTF-8
   - Enable Root SSH login (PermitRootLogin yes)

2. System Update & Base Packages
   - apt update / upgrade
   - Tools: curl wget git jq unzip htop build-essential ...
   - qemu-guest-agent (PVE graceful shutdown / IP report)

OPTIONAL (next screen: Up/Down move, Space toggle, Enter confirm)

3. Docker
   - Official Docker Engine + Compose plugin
   - Log rotation (20MB x 3 files)

4. Node.js Ecosystem
   - Node.js (default v${NODE_MAJOR})
   - pnpm + PM2 with systemd startup

5. Miniconda
   - Install to /opt/miniconda3
   - Init bash; disable auto-activate base
EOF
}

# Show English help via whiptail/dialog, or plain text
show_install_help() {
    local helpText
    helpText=$(get_install_help_text)
    apply_newt_theme

    if command -v whiptail &>/dev/null; then
        whiptail --title "PVE Ubuntu Init - Component Guide" \
            --scrolltext "$helpText" 24 78 2>/dev/null \
            || whiptail --title "PVE Ubuntu Init - Component Guide" \
                --msgbox "$helpText" 24 78 \
            || true
    elif command -v dialog &>/dev/null; then
        dialog --title "PVE Ubuntu Init - Component Guide" --msgbox "$helpText" 24 78 || true
        clear
    else
        echo ""
        echo "$helpText"
        echo ""
        read -r -p "Press Enter to continue..." _
    fi
}

# whiptail/dialog checklist; returns selected tags in SELECTED_TAGS
show_checklist_tui() {
    local title="$1"
    local text="$2"
    local height="$3"
    local width="$4"
    local listHeight="$5"
    shift 5
    local checklistArgs=("$@")
    local result=""

    apply_newt_theme

    if command -v whiptail &>/dev/null; then
        result=$(whiptail --title "$title" --checklist "$text" \
            "$height" "$width" "$listHeight" \
            "${checklistArgs[@]}" 3>&1 1>&2 2>&3) || return 1
    elif command -v dialog &>/dev/null; then
        result=$(dialog --stdout --title "$title" --checklist "$text" \
            "$height" "$width" "$listHeight" \
            "${checklistArgs[@]}") || return 1
        clear
    else
        return 1
    fi

    SELECTED_TAGS="$result"
    return 0
}

# Plain y/n fallback when whiptail/dialog is unavailable
prompt_yn_options() {
    local dockerDefault nodeDefault condaDefault answer
    dockerDefault=$(normalize_bool "$ENABLE_DOCKER" true)
    nodeDefault=$(normalize_bool "$ENABLE_NODE" true)
    condaDefault=$(normalize_bool "$ENABLE_MINICONDA" true)

    echo ""
    echo "=========================================="
    echo " PVE Ubuntu Init - Select Components"
    echo "=========================================="
    get_install_help_text
    echo "------------------------------------------"
    echo " Optional (Enter keeps default)"
    echo ""

    read -r -p " Install Docker?              [default: ${dockerDefault}] (y/n): " answer
    ENABLE_DOCKER=$(normalize_bool "${answer:-$dockerDefault}" "$dockerDefault")

    read -r -p " Install Node.js ecosystem?  [default: ${nodeDefault}] (y/n): " answer
    ENABLE_NODE=$(normalize_bool "${answer:-$nodeDefault}" "$nodeDefault")

    read -r -p " Install Miniconda?          [default: ${condaDefault}] (y/n): " answer
    ENABLE_MINICONDA=$(normalize_bool "${answer:-$condaDefault}" "$condaDefault")
}

# Show help + checklist; write ENABLE_* variables
select_install_options() {
    local dockerOn="OFF" nodeOn="OFF" condaOn="OFF"
    [[ "$(normalize_bool "$ENABLE_DOCKER" true)" == "true" ]] && dockerOn="ON"
    [[ "$(normalize_bool "$ENABLE_NODE" true)" == "true" ]] && nodeOn="ON"
    [[ "$(normalize_bool "$ENABLE_MINICONDA" true)" == "true" ]] && condaOn="ON"

    show_install_help

    local menuText
    menuText=$(cat <<'EOF'
REQUIRED items always run (see previous screen).
OPTIONAL: Up/Down to move, Space to toggle, Enter to confirm.
EOF
)

    SELECTED_TAGS=""
    if show_checklist_tui "PVE Ubuntu Init - Optional Components" "$menuText" 16 78 5 \
        "docker" "Docker: Engine + Compose + log rotation" "$dockerOn" \
        "node" "Node.js: Node + pnpm + PM2 startup" "$nodeOn" \
        "miniconda" "Miniconda: Python envs at /opt/miniconda3" "$condaOn"; then

        ENABLE_DOCKER="false"
        ENABLE_NODE="false"
        ENABLE_MINICONDA="false"
        # shellcheck disable=SC2086
        for tag in $SELECTED_TAGS; do
            tag="${tag//\"/}"
            case "$tag" in
                docker)    ENABLE_DOCKER="true" ;;
                node)      ENABLE_NODE="true" ;;
                miniconda) ENABLE_MINICONDA="true" ;;
            esac
        done
    else
        prompt_yn_options
    fi
}

# Apply defaults or show interactive menu
if should_show_select_menu; then
    select_install_options
else
    ENABLE_DOCKER=$(normalize_bool "$ENABLE_DOCKER" true)
    ENABLE_NODE=$(normalize_bool "$ENABLE_NODE" true)
    ENABLE_MINICONDA=$(normalize_bool "$ENABLE_MINICONDA" true)
fi

# ---- 日志 ----
LOG_FILE="/var/log/ubuntu-pve-init-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Log file: $LOG_FILE"

# 防止 apt 交互式弹窗 (GRUB、内核升级提示等)
export DEBIAN_FRONTEND=noninteractive
# apt 锁等待: unattended-upgrades 等后台进程可能持有锁，等待 60 秒而非立即失败
echo 'DPkg::Lock::Timeout "60";' > /etc/apt/apt.conf.d/99lock-timeout

# ---- 检测 SSH 运行模式 ----
# Ubuntu 24.04+ 默认使用 ssh.socket (systemd socket 激活)
HAS_SSH_SOCKET=false
if systemctl list-unit-files ssh.socket &>/dev/null 2>&1; then
    HAS_SSH_SOCKET=true
fi

# ---- SSH 重启辅助函数 ----
# 兼容 ssh.socket (Ubuntu 24.04+) 和传统 ssh.service (20.04/22.04) 两种模式
restart_ssh() {
    systemctl daemon-reload
    if $HAS_SSH_SOCKET; then
        systemctl restart ssh.socket
    fi
    # ssh.service 可能是 socket-triggered 而非独立运行，仅在 active 时重启
    if systemctl is-active ssh.service &>/dev/null; then
        systemctl restart ssh.service
    fi
}

# 动态计算总步骤: 基础 2 步 + 可选组件
TOTAL_STEPS=2
[[ "$ENABLE_DOCKER" == "true" ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
[[ "$ENABLE_NODE" == "true" ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
[[ "$ENABLE_MINICONDA" == "true" ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
CURRENT_STEP=0

# 输出当前步骤完成提示
step_ok() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo -e "\n[OK] [$CURRENT_STEP/$TOTAL_STEPS] $1 done"
}

echo ""
echo "=========================================="
echo " Selected options"
echo "=========================================="
echo " System base setup:     required"
echo " System update & deps:  required (incl. qemu-guest-agent)"
echo " Docker:               $ENABLE_DOCKER"
echo " Node.js ecosystem:    $ENABLE_NODE"
echo " Miniconda:            $ENABLE_MINICONDA"
echo "=========================================="

# ==========================================
# 1. 基础设置与 Root SSH 配置
# ==========================================
echo -e "\n>>> Configuring system base setup..."

# 1a. Root 密码
echo "root:${ROOT_PASSWORD}" | chpasswd

# 1b. 时区 & Locale
timedatectl set-timezone "$TIMEZONE"
locale-gen en_US.UTF-8 zh_CN.UTF-8 > /dev/null 2>&1 || true
update-locale LANG=en_US.UTF-8

# 1c. SSH 允许 Root 登录及密码认证
SSHD_DROP="/etc/ssh/sshd_config.d/99-root-login.conf"
DESIRED_SSH_CONFIG="PermitRootLogin yes
PasswordAuthentication yes"

mkdir -p /etc/ssh/sshd_config.d
if [[ ! -f "$SSHD_DROP" ]] || [[ "$(cat "$SSHD_DROP")" != "$DESIRED_SSH_CONFIG" ]]; then
    echo "$DESIRED_SSH_CONFIG" > "$SSHD_DROP"
    restart_ssh
    echo " -> Root SSH and password login enabled via drop-in config"
else
    echo " -> Root SSH already configured, skip"
fi

step_ok "System base setup"

# ==========================================
# 2. 系统更新与基础依赖包
# ==========================================
echo -e "\n>>> Updating system and installing base packages..."

apt-get update -y
apt-get upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"

apt-get install -y \
    curl wget git jq unzip htop \
    build-essential ca-certificates \
    python3-pip software-properties-common \
    qemu-guest-agent                          # PVE 必备: 优雅关机、IP 上报

# qemu-guest-agent 由 PVE 通过 udev/socket 激活，无需 enable
# 只需确保服务已启动即可
systemctl start qemu-guest-agent 2>/dev/null || true

step_ok "System update & base packages"

# ==========================================
# 3. 安装 Docker & Docker Compose (官方 APT 源)
# ==========================================
if [[ "$ENABLE_DOCKER" == "true" ]]; then
    echo -e "\n>>> Installing Docker..."

    if ! command -v docker &> /dev/null; then
        # GPG 密钥
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL --connect-timeout 10 --max-time 30 https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        # 获取 codename，并检测 Docker 是否已收录该版本
        CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
        if ! curl -fsSL --head --connect-timeout 10 --max-time 30 "https://download.docker.com/linux/ubuntu/dists/${CODENAME}/Release" &>/dev/null; then
            CODENAME="noble"   # 26.04 等新版本回退到 24.04 (noble)
            echo " [WARN] Docker unsupported on this release, fallback to ${CODENAME}"
        fi

        # deb822 格式源配置
        cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

        apt-get update -y
        apt-get install -y \
            docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin

        systemctl enable --now docker

        # Docker 日志滚动 (防止日志吃满磁盘)
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<'DAEMON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "3"
  }
}
DAEMON
        systemctl restart docker

        echo " -> Docker $(docker --version | awk '{gsub(/,/,""); print $3}') installed"
    else
        echo " -> Docker already installed ($(docker --version | awk '{gsub(/,/,""); print $3}')), skip"
    fi

    step_ok "Docker"
else
    echo -e "\n>>> Docker skipped (ENABLE_DOCKER=false)"
fi

# ==========================================
# 4. 安装 Node.js (NodeSource), pnpm, pm2
# ==========================================
if [[ "$ENABLE_NODE" == "true" ]]; then
    echo -e "\n>>> Installing Node.js ecosystem..."

    # 4a. Node.js
    if ! command -v node &> /dev/null; then
        curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" -o /tmp/nodesource_setup.sh
        bash /tmp/nodesource_setup.sh
        rm -f /tmp/nodesource_setup.sh
        apt-get install -y nodejs
        echo " -> Node.js $(node -v) installed"
    else
        echo " -> Node.js $(node -v) already installed, skip"
    fi

    # 4b. pnpm (via corepack)
    if ! command -v pnpm &> /dev/null; then
        # Node 24 自带 corepack；若缺失则手动安装并用绝对路径调用
        if command -v corepack &> /dev/null; then
            COREPACK="corepack"
        else
            npm install -g corepack
            hash -r
            COREPACK="$(npm prefix -g)/bin/corepack"
        fi
        "$COREPACK" enable
        "$COREPACK" prepare pnpm@latest --activate
        hash -r
        echo " -> pnpm $(pnpm -v) installed"
    else
        echo " -> pnpm $(pnpm -v) already installed, skip"
    fi

    # 4c. PM2
    if ! command -v pm2 &> /dev/null; then
        npm install -g pm2
        env PATH="$PATH:/usr/bin" pm2 startup systemd -u root --hp /root
        pm2 save
        echo " -> PM2 $(pm2 -v) installed"
    else
        echo " -> PM2 $(pm2 -v) already installed, skip"
    fi

    step_ok "Node.js ecosystem"
else
    echo -e "\n>>> Node.js ecosystem skipped (ENABLE_NODE=false)"
fi

# ==========================================
# 5. 安装 Miniconda (Python 环境管理)
# ==========================================
if [[ "$ENABLE_MINICONDA" == "true" ]]; then
    echo -e "\n>>> Installing Miniconda..."

    if [ ! -d "$CONDA_DIR" ]; then
        CONDA_INSTALLER="/tmp/miniconda.sh"
        ARCH=$(uname -m)
        case "$ARCH" in
            aarch64) CONDA_ARCH="aarch64" ;;
            *)       CONDA_ARCH="x86_64"  ;;
        esac
        wget -q "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${CONDA_ARCH}.sh" \
            -O "$CONDA_INSTALLER"
        bash "$CONDA_INSTALLER" -b -u -p "$CONDA_DIR"
        rm -f "$CONDA_INSTALLER"

        # 初始化所有已安装的 shell
        "$CONDA_DIR/bin/conda" init bash
        # 禁止 conda 默认激活 base 环境 (避免干扰系统 python)
        "$CONDA_DIR/bin/conda" config --set auto_activate_base false

        echo " -> Miniconda $(${CONDA_DIR}/bin/conda -V | awk '{print $2}') installed"
    else
        echo " -> Miniconda already exists ($(${CONDA_DIR}/bin/conda -V 2>/dev/null || echo 'unknown version')), skip"
    fi

    step_ok "Miniconda"
else
    echo -e "\n>>> Miniconda skipped (ENABLE_MINICONDA=false)"
fi

# ==========================================
# 完成摘要
# ==========================================
echo ""
echo "=========================================="
echo " Init completed!"
echo "=========================================="
echo " Timezone:    $(timedatectl show -p Timezone --value)"
echo " Docker:     $(docker --version 2>/dev/null | awk '{gsub(/,/,""); print $3}' || echo 'not installed/skipped')"
echo " Node.js:    $(node -v 2>/dev/null || echo 'not installed/skipped')"
echo " pnpm:       $(pnpm -v 2>/dev/null || echo 'not installed/skipped')"
echo " PM2:        $(pm2 -v 2>/dev/null || echo 'not installed/skipped')"
echo " Conda:      $(${CONDA_DIR}/bin/conda -V 2>/dev/null || echo 'not installed/skipped')"
GA_STATUS=$(systemctl is-active qemu-guest-agent 2>/dev/null || true)
echo " Guest Agent: ${GA_STATUS:-not installed} (activates when enabled on PVE)"
echo " Log:         $LOG_FILE"
echo "=========================================="
echo " Tip: run 'source ~/.bashrc' or reconnect SSH to activate env"
echo "=========================================="

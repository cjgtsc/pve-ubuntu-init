#!/bin/bash
# ==================================================================
# 普通 Ubuntu 服务器初始化脚本
# 适用环境: Ubuntu 24.04 / 26.04 Server (物理机 / 云服务器 / 通用 VM)
# 目标: 安全加固 → 系统基础 → [可选] Docker / Node.js / Miniconda
# ==================================================================

set -euo pipefail

# ---- 自动提权: 非 root 用户自动通过 sudo 重新执行 ----
if [[ $EUID -ne 0 ]]; then
    echo "Not root. Re-running with sudo..."
    exec sudo env NODE_MAJOR="${NODE_MAJOR:-24}" \
              ENABLE_UFW="${ENABLE_UFW:-}" \
              ENABLE_FAIL2BAN="${ENABLE_FAIL2BAN:-}" \
              ENABLE_AUTO_UPDATES="${ENABLE_AUTO_UPDATES:-}" \
              ENABLE_DOCKER="${ENABLE_DOCKER:-}" \
              ENABLE_NODE="${ENABLE_NODE:-}" \
              ENABLE_MINICONDA="${ENABLE_MINICONDA:-}" \
              SSH_PORT="${SSH_PORT:-8022}" \
              LOGIN_GRACE_TIME="${LOGIN_GRACE_TIME:-120}" \
              ROOT_PASSWORD="${ROOT_PASSWORD:-}" \
              SKIP_SELECT="${SKIP_SELECT:-}" \
              bash "$0" "$@"
fi

# ---- 全局配置 (按需修改) ----
ROOT_PASSWORD="${ROOT_PASSWORD:-}"                # 可通过环境变量预设: ROOT_PASSWORD=xxx bash init.sh
NODE_MAJOR="${NODE_MAJOR:-24}"                   # Node.js 主版本号
CONDA_DIR="/opt/miniconda3"
TIMEZONE="Asia/Shanghai"
ENABLE_UFW="${ENABLE_UFW:-}"                     # 空=交互选择；true/false 可跳过菜单
ENABLE_FAIL2BAN="${ENABLE_FAIL2BAN:-}"
ENABLE_AUTO_UPDATES="${ENABLE_AUTO_UPDATES:-}"
ENABLE_DOCKER="${ENABLE_DOCKER:-}"
ENABLE_NODE="${ENABLE_NODE:-}"
ENABLE_MINICONDA="${ENABLE_MINICONDA:-}"
SSH_PORT="${SSH_PORT:-8022}"                      # SSH 端口 (默认 8022，避免 22 被扫描)
LOGIN_GRACE_TIME="${LOGIN_GRACE_TIME:-120}"       # SSH 认证超时秒数 (跨国连接建议 ≥120)
SKIP_SELECT="${SKIP_SELECT:-false}"               # true 时跳过交互菜单，使用默认/环境变量

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
    if [[ -n "$ENABLE_UFW" && -n "$ENABLE_FAIL2BAN" && -n "$ENABLE_AUTO_UPDATES" \
       && -n "$ENABLE_DOCKER" && -n "$ENABLE_NODE" && -n "$ENABLE_MINICONDA" ]]; then
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

# Return English help text for server components
get_install_help_text() {
    cat <<EOF
REQUIRED (always installed, cannot disable)

1. System Base Setup
   - Root password: keep existing; if locked and ROOT_PASSWORD
     is unset, prompt interactively to set one
   - Timezone: Asia/Shanghai
   - Locales: en_US.UTF-8 / zh_CN.UTF-8
   - SSH: default port 8022, allow Root login, limit auth tries
     (briefly listens on 22 during transition)

2. System Update & Base Packages
   - apt update / upgrade
   - Tools: curl wget git jq unzip htop build-essential ...

OPTIONAL (next screen: Up/Down move, Space toggle, Enter confirm)

3. UFW Firewall
   - Deny inbound by default; allow SSH / 80 / 443

4. Fail2ban
   - SSH brute-force shield: 5 fails / 10 min -> ban 1 hour

5. Automatic Security Updates
   - unattended-upgrades: install security patches daily

6. Docker
   - Official Docker Engine + Compose plugin
   - Log rotation (20MB x 3 files)

7. Node.js Ecosystem
   - Node.js (default v${NODE_MAJOR})
   - pnpm + PM2 with systemd startup

8. Miniconda
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
        whiptail --title "Ubuntu Server Init - Component Guide" \
            --scrolltext "$helpText" 28 78 2>/dev/null \
            || whiptail --title "Ubuntu Server Init - Component Guide" \
                --msgbox "$helpText" 28 78 \
            || true
    elif command -v dialog &>/dev/null; then
        dialog --title "Ubuntu Server Init - Component Guide" --msgbox "$helpText" 28 78 || true
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
    local ufwDefault f2bDefault autoDefault dockerDefault nodeDefault condaDefault answer
    ufwDefault=$(normalize_bool "$ENABLE_UFW" true)
    f2bDefault=$(normalize_bool "$ENABLE_FAIL2BAN" true)
    autoDefault=$(normalize_bool "$ENABLE_AUTO_UPDATES" true)
    dockerDefault=$(normalize_bool "$ENABLE_DOCKER" true)
    nodeDefault=$(normalize_bool "$ENABLE_NODE" true)
    condaDefault=$(normalize_bool "$ENABLE_MINICONDA" true)

    echo ""
    echo "=========================================="
    echo " Ubuntu Server Init - Select Components"
    echo "=========================================="
    get_install_help_text
    echo "------------------------------------------"
    echo " Optional (Enter keeps default)"
    echo ""

    read -r -p " Enable UFW firewall?              [default: ${ufwDefault}] (y/n): " answer
    ENABLE_UFW=$(normalize_bool "${answer:-$ufwDefault}" "$ufwDefault")

    read -r -p " Enable Fail2ban?                  [default: ${f2bDefault}] (y/n): " answer
    ENABLE_FAIL2BAN=$(normalize_bool "${answer:-$f2bDefault}" "$f2bDefault")

    read -r -p " Enable automatic security updates?[default: ${autoDefault}] (y/n): " answer
    ENABLE_AUTO_UPDATES=$(normalize_bool "${answer:-$autoDefault}" "$autoDefault")

    read -r -p " Install Docker?                   [default: ${dockerDefault}] (y/n): " answer
    ENABLE_DOCKER=$(normalize_bool "${answer:-$dockerDefault}" "$dockerDefault")

    read -r -p " Install Node.js ecosystem?        [default: ${nodeDefault}] (y/n): " answer
    ENABLE_NODE=$(normalize_bool "${answer:-$nodeDefault}" "$nodeDefault")

    read -r -p " Install Miniconda?                [default: ${condaDefault}] (y/n): " answer
    ENABLE_MINICONDA=$(normalize_bool "${answer:-$condaDefault}" "$condaDefault")
}

# Show help + checklist; write ENABLE_* variables
select_install_options() {
    local ufwOn="OFF" f2bOn="OFF" autoOn="OFF" dockerOn="OFF" nodeOn="OFF" condaOn="OFF"
    [[ "$(normalize_bool "$ENABLE_UFW" true)" == "true" ]] && ufwOn="ON"
    [[ "$(normalize_bool "$ENABLE_FAIL2BAN" true)" == "true" ]] && f2bOn="ON"
    [[ "$(normalize_bool "$ENABLE_AUTO_UPDATES" true)" == "true" ]] && autoOn="ON"
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
    if show_checklist_tui "Ubuntu Server Init - Optional Components" "$menuText" 18 78 8 \
        "ufw" "UFW: firewall, allow SSH/80/443" "$ufwOn" \
        "fail2ban" "Fail2ban: SSH brute-force protection" "$f2bOn" \
        "auto_updates" "Auto security updates (unattended-upgrades)" "$autoOn" \
        "docker" "Docker: Engine + Compose + log rotation" "$dockerOn" \
        "node" "Node.js: Node + pnpm + PM2 startup" "$nodeOn" \
        "miniconda" "Miniconda: Python envs at /opt/miniconda3" "$condaOn"; then

        ENABLE_UFW="false"
        ENABLE_FAIL2BAN="false"
        ENABLE_AUTO_UPDATES="false"
        ENABLE_DOCKER="false"
        ENABLE_NODE="false"
        ENABLE_MINICONDA="false"
        # shellcheck disable=SC2086
        for tag in $SELECTED_TAGS; do
            tag="${tag//\"/}"
            case "$tag" in
                ufw)          ENABLE_UFW="true" ;;
                fail2ban)     ENABLE_FAIL2BAN="true" ;;
                auto_updates) ENABLE_AUTO_UPDATES="true" ;;
                docker)       ENABLE_DOCKER="true" ;;
                node)         ENABLE_NODE="true" ;;
                miniconda)    ENABLE_MINICONDA="true" ;;
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
    ENABLE_UFW=$(normalize_bool "$ENABLE_UFW" true)
    ENABLE_FAIL2BAN=$(normalize_bool "$ENABLE_FAIL2BAN" true)
    ENABLE_AUTO_UPDATES=$(normalize_bool "$ENABLE_AUTO_UPDATES" true)
    ENABLE_DOCKER=$(normalize_bool "$ENABLE_DOCKER" true)
    ENABLE_NODE=$(normalize_bool "$ENABLE_NODE" true)
    ENABLE_MINICONDA=$(normalize_bool "$ENABLE_MINICONDA" true)
fi

# ---- 日志 ----
LOG_FILE="/var/log/ubuntu-server-init-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Log file: $LOG_FILE"

# 防止 apt 交互式弹窗 (GRUB、内核升级提示等)
export DEBIAN_FRONTEND=noninteractive
# apt 锁等待: unattended-upgrades 等后台进程可能持有锁，等待 60 秒而非立即失败
echo 'DPkg::Lock::Timeout "60";' > /etc/apt/apt.conf.d/99lock-timeout

# 动态计算总步骤: 基础 2 步 + 可选组件
# 安全加固: UFW 或 Fail2ban 任一启用则计为 1 步
TOTAL_STEPS=2
if [[ "$ENABLE_UFW" == "true" || "$ENABLE_FAIL2BAN" == "true" ]]; then
    TOTAL_STEPS=$((TOTAL_STEPS + 1))
fi
[[ "$ENABLE_AUTO_UPDATES" == "true" ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
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
echo " System update & deps:  required"
echo " UFW firewall:         $ENABLE_UFW"
echo " Fail2ban:             $ENABLE_FAIL2BAN"
echo " Auto security updates:$ENABLE_AUTO_UPDATES"
echo " Docker:               $ENABLE_DOCKER"
echo " Node.js ecosystem:    $ENABLE_NODE"
echo " Miniconda:            $ENABLE_MINICONDA"
echo "=========================================="

# ---- 检测 SSH 运行模式 ----
# Ubuntu 24.04+ 默认使用 ssh.socket (systemd socket 激活)
HAS_SSH_SOCKET=false
SOCKET_OVERRIDE_DIR="/etc/systemd/system/ssh.socket.d"
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

# ==========================================
# 1. 基础设置
# ==========================================
echo -e "\n>>> Configuring system base setup..."

# 1a. Root 密码
#   优先级: 环境变量 > 交互输入 > 已有密码则跳过
ROOT_LOCKED=false
if passwd -S root 2>/dev/null | grep -qE '^root (L|NP)'; then
    ROOT_LOCKED=true
fi

if [[ -n "$ROOT_PASSWORD" ]]; then
    # 用户通过环境变量指定了密码
    echo "root:${ROOT_PASSWORD}" | chpasswd
    echo " -> Root password set from environment variable"
elif $ROOT_LOCKED; then
    # Root 账户被锁定且未提供密码 → 交互式提示
    echo ""
    echo " [WARN] Root account has no password (locked)"
    echo "    Set a Root password for VNC/console access:"
    echo ""
    while true; do
        read -s -p "    Enter Root password: " pw1; echo
        read -s -p "    Confirm Root password: " pw2; echo
        if [[ -z "$pw1" ]]; then
            echo "    [X] Password cannot be empty, try again"
        elif [[ "$pw1" != "$pw2" ]]; then
            echo "    [X] Passwords do not match, try again"
        else
            echo "root:${pw1}" | chpasswd
            echo " -> Root password set"
            break
        fi
    done
else
    echo " -> Root password already set, skip"
fi
# 1b. 时区 & Locale
timedatectl set-timezone "$TIMEZONE"
locale-gen en_US.UTF-8 zh_CN.UTF-8 > /dev/null 2>&1 || true
update-locale LANG=en_US.UTF-8

# 1c. SSH 配置 (幂等: 仅在配置变更时写入并重启)
SSHD_DROP="/etc/ssh/sshd_config.d/99-server-hardening.conf"
mkdir -p /etc/ssh/sshd_config.d

# ⚠ 安全策略: 过渡期同时监听 22 和目标端口，防止脚本执行中途断连
# 脚本最后会移除 22 端口，仅保留目标端口
SSH_CHANGED=false

# --- ssh.socket 端口管理 (Ubuntu 24.04+) ---
if $HAS_SSH_SOCKET; then
    # 若旧版脚本曾禁用 ssh.socket，重新启用
    if ! systemctl is-enabled ssh.socket &>/dev/null 2>&1; then
        systemctl enable ssh.socket &>/dev/null 2>&1 || true
        echo " -> Re-enabled ssh.socket (may have been disabled by older script)"
    fi
    echo " -> Detected ssh.socket mode (Ubuntu 24.04+), managing port via systemd override"

    mkdir -p "$SOCKET_OVERRIDE_DIR"
    if [[ "$SSH_PORT" != "22" ]]; then
        DESIRED_SOCKET="[Socket]
ListenStream=
ListenStream=0.0.0.0:22
ListenStream=[::]:22
ListenStream=0.0.0.0:${SSH_PORT}
ListenStream=[::]:${SSH_PORT}"
    else
        DESIRED_SOCKET="[Socket]
ListenStream=
ListenStream=0.0.0.0:22
ListenStream=[::]:22"
    fi

    if [[ ! -f "${SOCKET_OVERRIDE_DIR}/override.conf" ]] || \
       [[ "$(cat "${SOCKET_OVERRIDE_DIR}/override.conf")" != "$DESIRED_SOCKET" ]]; then
        echo "$DESIRED_SOCKET" > "${SOCKET_OVERRIDE_DIR}/override.conf"
        SSH_CHANGED=true
        if [[ "$SSH_PORT" != "22" ]]; then
            echo " -> ssh.socket transition: listening on 22 and ${SSH_PORT}"
        fi
    fi
fi

# --- sshd_config.d: 认证与安全设置 ---
# ssh.socket 模式下端口由 systemd 管理，sshd_config 不写 Port
# 传统模式下端口由 sshd_config 管理
if $HAS_SSH_SOCKET; then
    DESIRED_SSH_CONFIG="# Server hardening (port managed by ssh.socket)
PermitRootLogin yes
PasswordAuthentication yes
MaxAuthTries 5
LoginGraceTime ${LOGIN_GRACE_TIME}"
else
    if [[ "$SSH_PORT" != "22" ]]; then
        DESIRED_SSH_CONFIG="# Server hardening (transition: listen on 22 and ${SSH_PORT})
Port 22
Port ${SSH_PORT}
PermitRootLogin yes
PasswordAuthentication yes
MaxAuthTries 5
LoginGraceTime ${LOGIN_GRACE_TIME}"
    else
        DESIRED_SSH_CONFIG="# Server hardening
Port 22
PermitRootLogin yes
PasswordAuthentication yes
MaxAuthTries 5
LoginGraceTime ${LOGIN_GRACE_TIME}"
    fi
fi

if [[ ! -f "$SSHD_DROP" ]] || [[ "$(cat "$SSHD_DROP")" != "$DESIRED_SSH_CONFIG" ]]; then
    echo "$DESIRED_SSH_CONFIG" > "$SSHD_DROP"
    SSH_CHANGED=true
fi

if $SSH_CHANGED; then
    restart_ssh
    echo " -> SSH hardened (Root login allowed)"
else
    echo " -> SSH config unchanged, skip"
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

# apt-get install -y 天然幂等，重复执行安全
apt-get install -y \
    curl wget git jq unzip htop \
    build-essential ca-certificates \
    python3-pip software-properties-common

step_ok "System update & base packages"

# ==========================================
# 3. 安全加固 (UFW + Fail2ban)
# ==========================================
if [[ "$ENABLE_UFW" == "true" || "$ENABLE_FAIL2BAN" == "true" ]]; then
    echo -e "\n>>> Security hardening..."

    # 3a. UFW 防火墙 (幂等: 仅添加缺失规则，不重置已有配置)
    if [[ "$ENABLE_UFW" == "true" ]]; then
        if ! command -v ufw &> /dev/null; then
            apt-get install -y ufw
        fi

        UFW_CHANGED=false

        # 确保默认策略正确
        ufw default deny incoming > /dev/null 2>&1
        ufw default allow outgoing > /dev/null 2>&1

        # 放行 SSH — 过渡期保留 22 端口，防止断连
        if [[ "$SSH_PORT" != "22" ]]; then
            ufw allow 22/tcp comment "SSH-legacy (auto-close after script)" 2>/dev/null | grep -q "Skipping" || UFW_CHANGED=true
        fi
        ufw allow "${SSH_PORT}/tcp" comment "SSH" 2>/dev/null | grep -q "Skipping" || UFW_CHANGED=true

        # 放行常用服务端口
        ufw allow 80/tcp comment "HTTP" 2>/dev/null | grep -q "Skipping" || UFW_CHANGED=true
        ufw allow 443/tcp comment "HTTPS" 2>/dev/null | grep -q "Skipping" || UFW_CHANGED=true

        # 启用 UFW (如果未启用)
        if ! ufw status | grep -q "Status: active"; then
            ufw --force enable
            UFW_CHANGED=true
        fi

        if $UFW_CHANGED; then
            echo " -> UFW configured (allow SSH:${SSH_PORT}, HTTP:80, HTTPS:443)"
        else
            echo " -> UFW already in desired state, skip"
        fi
    else
        echo " -> UFW skipped (ENABLE_UFW=false)"
    fi

    # 3b. Fail2ban
    if [[ "$ENABLE_FAIL2BAN" == "true" ]]; then
        if ! command -v fail2ban-server &> /dev/null; then
            apt-get install -y fail2ban
        fi

        # 过渡期需同时保护 22 和目标端口；最终切换阶段会更新为仅目标端口
        if [[ "$SSH_PORT" != "22" ]]; then
            F2B_PORTS="22,${SSH_PORT}"
        else
            F2B_PORTS="${SSH_PORT}"
        fi

        if [[ -f /etc/fail2ban/jail.local ]] && grep -q "port    = ${F2B_PORTS}" /etc/fail2ban/jail.local; then
            echo " -> Fail2ban already configured (ports: ${F2B_PORTS}), skip"
        else
            cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port    = ${F2B_PORTS}
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF

            systemctl enable --now fail2ban
            systemctl restart fail2ban
            echo " -> Fail2ban enabled (SSH brute-force protection, ports: ${F2B_PORTS}, 5 fails -> ban 1h)"
        fi
    else
        echo " -> Fail2ban skipped (ENABLE_FAIL2BAN=false)"
    fi

    step_ok "Security hardening"
else
    echo -e "\n>>> Security hardening skipped (UFW/Fail2ban both off)"
fi

# ==========================================
# 4. 自动安全更新
# ==========================================
if [[ "$ENABLE_AUTO_UPDATES" == "true" ]]; then
    echo -e "\n>>> Configuring automatic security updates..."

    apt-get install -y unattended-upgrades
    apt-get install -y apt-listchanges 2>/dev/null || true

    DESIRED_AUTO_UPGRADES='APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";'

    if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]] && \
       [[ "$(cat /etc/apt/apt.conf.d/20auto-upgrades)" == "$DESIRED_AUTO_UPGRADES" ]]; then
        echo " -> Auto security updates already configured, skip"
    else
        echo "$DESIRED_AUTO_UPGRADES" > /etc/apt/apt.conf.d/20auto-upgrades
        systemctl enable --now unattended-upgrades
        echo " -> Auto security updates configured (daily security patches)"
    fi

    step_ok "Automatic security updates"
else
    echo -e "\n>>> Auto security updates skipped (ENABLE_AUTO_UPDATES=false)"
fi

# ==========================================
# 5. 安装 Docker & Docker Compose (官方 APT 源)
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
# 6. 安装 Node.js (NodeSource), pnpm, pm2
# ==========================================
if [[ "$ENABLE_NODE" == "true" ]]; then
    echo -e "\n>>> Installing Node.js ecosystem..."

    # 6a. Node.js
    if ! command -v node &> /dev/null; then
        curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" -o /tmp/nodesource_setup.sh
        bash /tmp/nodesource_setup.sh
        rm -f /tmp/nodesource_setup.sh
        apt-get install -y nodejs
        echo " -> Node.js $(node -v) installed"
    else
        echo " -> Node.js $(node -v) already installed, skip"
    fi

    # 6b. pnpm (via corepack)
    if ! command -v pnpm &> /dev/null; then
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

    # 6c. PM2
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
# 7. 安装 Miniconda (Python 环境管理)
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
# 8. 最终切换: SSH 仅保留目标端口
# ==========================================
if [[ "$SSH_PORT" != "22" ]]; then
    FINAL_CHANGED=false

    # ssh.socket 模式: 更新 override 为仅目标端口
    if $HAS_SSH_SOCKET; then
        FINAL_SOCKET="[Socket]
ListenStream=
ListenStream=0.0.0.0:${SSH_PORT}
ListenStream=[::]:${SSH_PORT}"

        if [[ ! -f "${SOCKET_OVERRIDE_DIR}/override.conf" ]] || \
           [[ "$(cat "${SOCKET_OVERRIDE_DIR}/override.conf")" != "$FINAL_SOCKET" ]]; then
            echo "$FINAL_SOCKET" > "${SOCKET_OVERRIDE_DIR}/override.conf"
            FINAL_CHANGED=true
        fi
    else
        # 传统模式: 更新 sshd_config.d 为仅目标端口
        FINAL_SSH_CONFIG="# Server hardening (final)
Port ${SSH_PORT}
PermitRootLogin yes
PasswordAuthentication yes
MaxAuthTries 5
LoginGraceTime ${LOGIN_GRACE_TIME}"

        if [[ ! -f "$SSHD_DROP" ]] || \
           [[ "$(cat "$SSHD_DROP")" != "$FINAL_SSH_CONFIG" ]]; then
            echo "$FINAL_SSH_CONFIG" > "$SSHD_DROP"
            FINAL_CHANGED=true
        fi
    fi

    if $FINAL_CHANGED; then
        echo -e "\n>>> Final switch: remove SSH port 22, keep only ${SSH_PORT}..."
        restart_ssh
        echo " -> SSH now listens only on ${SSH_PORT}"
    else
        echo -e "\n>>> SSH already final config (listen only on ${SSH_PORT}), skip"
    fi

    # UFW 中移除旧的 22 端口规则
    if [[ "$ENABLE_UFW" == "true" ]]; then
        ufw --force delete allow 22/tcp > /dev/null 2>&1 || true
    fi

    # Fail2ban 切换为仅监听目标端口
    if [[ "$ENABLE_FAIL2BAN" == "true" ]] && [[ -f /etc/fail2ban/jail.local ]]; then
        if grep -q "port    = 22,${SSH_PORT}" /etc/fail2ban/jail.local; then
            sed -i "s/port    = 22,${SSH_PORT}/port    = ${SSH_PORT}/" /etc/fail2ban/jail.local
            systemctl restart fail2ban
            echo " -> Fail2ban switched to listen only on ${SSH_PORT}"
        fi
    fi
fi

# ==========================================
# 完成摘要
# ==========================================
echo ""
echo "=========================================="
echo " Server init completed!"
echo "=========================================="
echo " Timezone:     $(timedatectl show -p Timezone --value)"
echo " SSH port:     ${SSH_PORT}"
echo " UFW firewall:  $( [[ "$ENABLE_UFW" == "true" ]] && command -v ufw &>/dev/null && ufw status 2>/dev/null | head -1 || echo 'not installed/skipped')"
echo " Fail2ban:    $( [[ "$ENABLE_FAIL2BAN" == "true" ]] && systemctl is-active fail2ban 2>/dev/null || echo 'not installed/skipped')"
echo " Docker:      $(docker --version 2>/dev/null | awk '{gsub(/,/,""); print $3}' || echo 'not installed/skipped')"
echo " Node.js:     $(node -v 2>/dev/null || echo 'not installed/skipped')"
echo " pnpm:        $(pnpm -v 2>/dev/null || echo 'not installed/skipped')"
echo " PM2:         $(pm2 -v 2>/dev/null || echo 'not installed/skipped')"
echo " Conda:       $(${CONDA_DIR}/bin/conda -V 2>/dev/null || echo 'not installed/skipped')"
echo " Auto updates:  $( [[ "$ENABLE_AUTO_UPDATES" == "true" ]] && systemctl is-active unattended-upgrades 2>/dev/null || echo 'not enabled/skipped')"
echo " Log:          $LOG_FILE"
echo "=========================================="
echo " Tip: run 'source ~/.bashrc' or reconnect SSH to activate env"
if [[ "$SSH_PORT" != "22" ]]; then
    echo " [WARN] SSH port changed to ${SSH_PORT}, use: ssh -p ${SSH_PORT} user@host"
fi
echo "=========================================="

#!/bin/bash
# ==================================================================
# 普通 Ubuntu 服务器初始化脚本
# 适用环境: Ubuntu 24.04 / 26.04 Server (物理机 / 云服务器 / 通用 VM)
# 目标: 安全加固 → 系统基础 → [可选] Docker / Node.js / Miniconda
# ==================================================================

set -euo pipefail

# ---- 自动提权: 非 root 用户自动通过 sudo 重新执行 ----
if [[ $EUID -ne 0 ]]; then
    echo "当前用户非 root，正在通过 sudo 提权..."
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
# 交互式功能选择
# ==========================================

# 判断是否应弹出交互式安装菜单
should_show_select_menu() {
    [[ "$SKIP_SELECT" == "true" ]] && return 1
    [[ ! -t 0 ]] && return 1
    # 六项均已通过环境变量明确指定时，不再弹菜单
    if [[ -n "$ENABLE_UFW" && -n "$ENABLE_FAIL2BAN" && -n "$ENABLE_AUTO_UPDATES" \
       && -n "$ENABLE_DOCKER" && -n "$ENABLE_NODE" && -n "$ENABLE_MINICONDA" ]]; then
        return 1
    fi
    return 0
}

# 将布尔字符串规范为 true/false；空值回落默认
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

# 用 whiptail/dialog 展示复选框；失败则返回非 0
show_checklist_tui() {
    local title="$1"
    local text="$2"
    shift 2
    local checklistArgs=("$@")
    local result=""

    if command -v whiptail &>/dev/null; then
        result=$(whiptail --title "$title" --checklist "$text" 20 70 8 \
            "${checklistArgs[@]}" 3>&1 1>&2 2>&3) || return 1
    elif command -v dialog &>/dev/null; then
        result=$(dialog --stdout --title "$title" --checklist "$text" 20 70 8 \
            "${checklistArgs[@]}") || return 1
        clear
    else
        return 1
    fi

    SELECTED_TAGS="$result"
    return 0
}

# 逐项 y/n 回退选择（无 TUI 工具时使用）
prompt_yn_options() {
    local ufwDefault f2bDefault autoDefault dockerDefault nodeDefault condaDefault
    ufwDefault=$(normalize_bool "$ENABLE_UFW" true)
    f2bDefault=$(normalize_bool "$ENABLE_FAIL2BAN" true)
    autoDefault=$(normalize_bool "$ENABLE_AUTO_UPDATES" true)
    dockerDefault=$(normalize_bool "$ENABLE_DOCKER" true)
    nodeDefault=$(normalize_bool "$ENABLE_NODE" true)
    condaDefault=$(normalize_bool "$ENABLE_MINICONDA" true)

    echo ""
    echo "=========================================="
    echo " 请选择要安装的组件 (直接回车保持默认)"
    echo "=========================================="

    local answer
    read -r -p "  [1] UFW 防火墙           [默认: ${ufwDefault}] (y/n): " answer
    ENABLE_UFW=$(normalize_bool "${answer:-$ufwDefault}" "$ufwDefault")

    read -r -p "  [2] Fail2ban             [默认: ${f2bDefault}] (y/n): " answer
    ENABLE_FAIL2BAN=$(normalize_bool "${answer:-$f2bDefault}" "$f2bDefault")

    read -r -p "  [3] 自动安全更新         [默认: ${autoDefault}] (y/n): " answer
    ENABLE_AUTO_UPDATES=$(normalize_bool "${answer:-$autoDefault}" "$autoDefault")

    read -r -p "  [4] Docker 环境          [默认: ${dockerDefault}] (y/n): " answer
    ENABLE_DOCKER=$(normalize_bool "${answer:-$dockerDefault}" "$dockerDefault")

    read -r -p "  [5] Node.js 生态         [默认: ${nodeDefault}] (y/n): " answer
    ENABLE_NODE=$(normalize_bool "${answer:-$nodeDefault}" "$nodeDefault")

    read -r -p "  [6] Miniconda            [默认: ${condaDefault}] (y/n): " answer
    ENABLE_MINICONDA=$(normalize_bool "${answer:-$condaDefault}" "$condaDefault")
}

# 弹出安装选项复选框并写入 ENABLE_* 变量
select_install_options() {
    local ufwOn="OFF" f2bOn="OFF" autoOn="OFF" dockerOn="OFF" nodeOn="OFF" condaOn="OFF"
    [[ "$(normalize_bool "$ENABLE_UFW" true)" == "true" ]] && ufwOn="ON"
    [[ "$(normalize_bool "$ENABLE_FAIL2BAN" true)" == "true" ]] && f2bOn="ON"
    [[ "$(normalize_bool "$ENABLE_AUTO_UPDATES" true)" == "true" ]] && autoOn="ON"
    [[ "$(normalize_bool "$ENABLE_DOCKER" true)" == "true" ]] && dockerOn="ON"
    [[ "$(normalize_bool "$ENABLE_NODE" true)" == "true" ]] && nodeOn="ON"
    [[ "$(normalize_bool "$ENABLE_MINICONDA" true)" == "true" ]] && condaOn="ON"

    SELECTED_TAGS=""
    if show_checklist_tui "Ubuntu 服务器初始化" "空格勾选，回车确认（必装项会始终执行）" \
        "ufw" "UFW 防火墙 (SSH/80/443)" "$ufwOn" \
        "fail2ban" "Fail2ban (SSH 暴力破解防护)" "$f2bOn" \
        "auto_updates" "自动安全更新 (unattended-upgrades)" "$autoOn" \
        "docker" "Docker 环境 (Engine + Compose)" "$dockerOn" \
        "node" "Node.js 生态 (Node + pnpm + PM2)" "$nodeOn" \
        "miniconda" "Miniconda (Python 环境)" "$condaOn"; then

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

# 应用默认值或弹出交互菜单
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
echo "日志文件: $LOG_FILE"

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
    echo -e "\n✅ [$CURRENT_STEP/$TOTAL_STEPS] $1 完成"
}

echo ""
echo "=========================================="
echo " 本次安装选项"
echo "=========================================="
echo " 系统基础设置:     必装"
echo " 系统更新与依赖:   必装"
echo " UFW 防火墙:       $ENABLE_UFW"
echo " Fail2ban:         $ENABLE_FAIL2BAN"
echo " 自动安全更新:     $ENABLE_AUTO_UPDATES"
echo " Docker:           $ENABLE_DOCKER"
echo " Node.js 生态:     $ENABLE_NODE"
echo " Miniconda:        $ENABLE_MINICONDA"
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
echo -e "\n>>> 配置系统基础设置..."

# 1a. Root 密码
#   优先级: 环境变量 > 交互输入 > 已有密码则跳过
ROOT_LOCKED=false
if passwd -S root 2>/dev/null | grep -qE '^root (L|NP)'; then
    ROOT_LOCKED=true
fi

if [[ -n "$ROOT_PASSWORD" ]]; then
    # 用户通过环境变量指定了密码
    echo "root:${ROOT_PASSWORD}" | chpasswd
    echo " -> Root 密码已通过环境变量设置"
elif $ROOT_LOCKED; then
    # Root 账户被锁定且未提供密码 → 交互式提示
    echo ""
    echo " ⚠  检测到 Root 账户未设置密码 (已锁定)"
    echo "    为确保 VNC/控制台可用，请设置 Root 密码:"
    echo ""
    while true; do
        read -s -p "    输入 Root 密码: " pw1; echo
        read -s -p "    确认 Root 密码: " pw2; echo
        if [[ -z "$pw1" ]]; then
            echo "    ✗ 密码不能为空，请重试"
        elif [[ "$pw1" != "$pw2" ]]; then
            echo "    ✗ 两次输入不一致，请重试"
        else
            echo "root:${pw1}" | chpasswd
            echo " -> Root 密码已设置"
            break
        fi
    done
else
    echo " -> Root 已有密码，跳过"
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
        echo " -> 重新启用 ssh.socket (可能被旧版脚本禁用)"
    fi
    echo " -> 检测到 ssh.socket 模式 (Ubuntu 24.04+)，通过 systemd override 管理端口"

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
            echo " -> ssh.socket 过渡配置: 同时监听 22 和 ${SSH_PORT}"
        fi
    fi
fi

# --- sshd_config.d: 认证与安全设置 ---
# ssh.socket 模式下端口由 systemd 管理，sshd_config 不写 Port
# 传统模式下端口由 sshd_config 管理
if $HAS_SSH_SOCKET; then
    DESIRED_SSH_CONFIG="# 服务器安全加固配置 (端口由 ssh.socket 管理)
PermitRootLogin yes
PasswordAuthentication yes
MaxAuthTries 5
LoginGraceTime ${LOGIN_GRACE_TIME}"
else
    if [[ "$SSH_PORT" != "22" ]]; then
        DESIRED_SSH_CONFIG="# 服务器安全加固配置 (过渡期: 同时监听 22 和 ${SSH_PORT})
Port 22
Port ${SSH_PORT}
PermitRootLogin yes
PasswordAuthentication yes
MaxAuthTries 5
LoginGraceTime ${LOGIN_GRACE_TIME}"
    else
        DESIRED_SSH_CONFIG="# 服务器安全加固配置
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
    echo " -> SSH 已加固 (允许 Root 登录)"
else
    echo " -> SSH 配置未变更，跳过"
fi

step_ok "系统基础设置"

# ==========================================
# 2. 系统更新与基础依赖包
# ==========================================
echo -e "\n>>> 更新系统并安装基础依赖..."

apt-get update -y
apt-get upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"

# apt-get install -y 天然幂等，重复执行安全
apt-get install -y \
    curl wget git jq unzip htop \
    build-essential ca-certificates \
    python3-pip software-properties-common

step_ok "系统更新与基础依赖"

# ==========================================
# 3. 安全加固 (UFW + Fail2ban)
# ==========================================
if [[ "$ENABLE_UFW" == "true" || "$ENABLE_FAIL2BAN" == "true" ]]; then
    echo -e "\n>>> 安全加固..."

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
            ufw allow 22/tcp comment "SSH-legacy (脚本完成后自动关闭)" 2>/dev/null | grep -q "Skipping" || UFW_CHANGED=true
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
            echo " -> UFW 防火墙已配置 (放行: SSH:${SSH_PORT}, HTTP:80, HTTPS:443)"
        else
            echo " -> UFW 防火墙已是期望状态，跳过"
        fi
    else
        echo " -> UFW 防火墙跳过 (ENABLE_UFW=false)"
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
            echo " -> Fail2ban 已配置 (端口: ${F2B_PORTS})，跳过"
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
            echo " -> Fail2ban 已启用 (SSH 暴力破解防护: 端口 ${F2B_PORTS}, 5次失败封禁1小时)"
        fi
    else
        echo " -> Fail2ban 跳过 (ENABLE_FAIL2BAN=false)"
    fi

    step_ok "安全加固"
else
    echo -e "\n>>> 安全加固跳过 (UFW/Fail2ban 均未启用)"
fi

# ==========================================
# 4. 自动安全更新
# ==========================================
if [[ "$ENABLE_AUTO_UPDATES" == "true" ]]; then
    echo -e "\n>>> 配置自动安全更新..."

    apt-get install -y unattended-upgrades
    apt-get install -y apt-listchanges 2>/dev/null || true

    DESIRED_AUTO_UPGRADES='APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";'

    if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]] && \
       [[ "$(cat /etc/apt/apt.conf.d/20auto-upgrades)" == "$DESIRED_AUTO_UPGRADES" ]]; then
        echo " -> 自动安全更新已配置，跳过"
    else
        echo "$DESIRED_AUTO_UPGRADES" > /etc/apt/apt.conf.d/20auto-upgrades
        systemctl enable --now unattended-upgrades
        echo " -> 自动安全更新已配置 (每日检查安全补丁)"
    fi

    step_ok "自动安全更新"
else
    echo -e "\n>>> 自动安全更新跳过 (ENABLE_AUTO_UPDATES=false)"
fi

# ==========================================
# 5. 安装 Docker & Docker Compose (官方 APT 源)
# ==========================================
if [[ "$ENABLE_DOCKER" == "true" ]]; then
    echo -e "\n>>> 安装 Docker 环境..."

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
            echo " ⚠ Docker 暂不支持当前发行版，回退至 ${CODENAME}"
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

        echo " -> Docker $(docker --version | awk '{gsub(/,/,""); print $3}') 安装完成"
    else
        echo " -> Docker 已安装 ($(docker --version | awk '{gsub(/,/,""); print $3}'))，跳过"
    fi

    step_ok "Docker 环境"
else
    echo -e "\n>>> Docker 环境跳过 (ENABLE_DOCKER=false)"
fi

# ==========================================
# 6. 安装 Node.js (NodeSource), pnpm, pm2
# ==========================================
if [[ "$ENABLE_NODE" == "true" ]]; then
    echo -e "\n>>> 安装 Node.js 生态..."

    # 6a. Node.js
    if ! command -v node &> /dev/null; then
        curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" -o /tmp/nodesource_setup.sh
        bash /tmp/nodesource_setup.sh
        rm -f /tmp/nodesource_setup.sh
        apt-get install -y nodejs
        echo " -> Node.js $(node -v) 安装完成"
    else
        echo " -> Node.js $(node -v) 已安装，跳过"
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
        echo " -> pnpm $(pnpm -v) 安装完成"
    else
        echo " -> pnpm $(pnpm -v) 已安装，跳过"
    fi

    # 6c. PM2
    if ! command -v pm2 &> /dev/null; then
        npm install -g pm2
        env PATH="$PATH:/usr/bin" pm2 startup systemd -u root --hp /root
        pm2 save
        echo " -> PM2 $(pm2 -v) 安装完成"
    else
        echo " -> PM2 $(pm2 -v) 已安装，跳过"
    fi

    step_ok "Node.js 生态"
else
    echo -e "\n>>> Node.js 生态跳过 (ENABLE_NODE=false)"
fi

# ==========================================
# 7. 安装 Miniconda (Python 环境管理)
# ==========================================
if [[ "$ENABLE_MINICONDA" == "true" ]]; then
    echo -e "\n>>> 安装 Miniconda..."

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

        echo " -> Miniconda $(${CONDA_DIR}/bin/conda -V | awk '{print $2}') 安装完成"
    else
        echo " -> Miniconda 已存在 ($(${CONDA_DIR}/bin/conda -V 2>/dev/null || echo '未知版本'))，跳过"
    fi

    step_ok "Miniconda"
else
    echo -e "\n>>> Miniconda 跳过 (ENABLE_MINICONDA=false)"
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
        FINAL_SSH_CONFIG="# 服务器安全加固配置 (最终版)
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
        echo -e "\n>>> 最终切换: 移除 SSH 旧端口 22，仅保留 ${SSH_PORT}..."
        restart_ssh
        echo " -> SSH 已切换至仅监听 ${SSH_PORT}"
    else
        echo -e "\n>>> SSH 已是最终配置 (仅监听 ${SSH_PORT})，跳过"
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
            echo " -> Fail2ban 已切换至仅监听 ${SSH_PORT}"
        fi
    fi
fi

# ==========================================
# 完成摘要
# ==========================================
echo ""
echo "=========================================="
echo " 🎉 服务器初始化全部完成！"
echo "=========================================="
echo " 时区:        $(timedatectl show -p Timezone --value)"
echo " SSH 端口:    ${SSH_PORT}"
echo " UFW 防火墙:  $( [[ "$ENABLE_UFW" == "true" ]] && command -v ufw &>/dev/null && ufw status 2>/dev/null | head -1 || echo '未安装/已跳过')"
echo " Fail2ban:    $( [[ "$ENABLE_FAIL2BAN" == "true" ]] && systemctl is-active fail2ban 2>/dev/null || echo '未安装/已跳过')"
echo " Docker:      $(docker --version 2>/dev/null | awk '{gsub(/,/,""); print $3}' || echo '未安装/已跳过')"
echo " Node.js:     $(node -v 2>/dev/null || echo '未安装/已跳过')"
echo " pnpm:        $(pnpm -v 2>/dev/null || echo '未安装/已跳过')"
echo " PM2:         $(pm2 -v 2>/dev/null || echo '未安装/已跳过')"
echo " Conda:       $(${CONDA_DIR}/bin/conda -V 2>/dev/null || echo '未安装/已跳过')"
echo " 自动更新:    $( [[ "$ENABLE_AUTO_UPDATES" == "true" ]] && systemctl is-active unattended-upgrades 2>/dev/null || echo '未启用/已跳过')"
echo " 日志:        $LOG_FILE"
echo "=========================================="
echo " 👉 执行 'source ~/.bashrc' 或重新连接 SSH 激活环境"
if [[ "$SSH_PORT" != "22" ]]; then
    echo " ⚠️  SSH 端口已改为 ${SSH_PORT}，请使用: ssh -p ${SSH_PORT} user@host"
fi
echo "=========================================="

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
    echo "当前用户非 root，正在通过 sudo 提权..."
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
# 交互式功能选择
# ==========================================

# 判断是否应弹出交互式安装菜单
should_show_select_menu() {
    [[ "$SKIP_SELECT" == "true" ]] && return 1
    [[ ! -t 0 ]] && return 1
    # 三项均已通过环境变量明确指定时，不再弹菜单
    if [[ -n "$ENABLE_DOCKER" && -n "$ENABLE_NODE" && -n "$ENABLE_MINICONDA" ]]; then
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
        result=$(whiptail --title "$title" --checklist "$text" 18 64 6 \
            "${checklistArgs[@]}" 3>&1 1>&2 2>&3) || return 1
    elif command -v dialog &>/dev/null; then
        result=$(dialog --stdout --title "$title" --checklist "$text" 18 64 6 \
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
    local dockerDefault nodeDefault condaDefault
    dockerDefault=$(normalize_bool "$ENABLE_DOCKER" true)
    nodeDefault=$(normalize_bool "$ENABLE_NODE" true)
    condaDefault=$(normalize_bool "$ENABLE_MINICONDA" true)

    echo ""
    echo "=========================================="
    echo " 请选择要安装的组件 (直接回车保持默认)"
    echo "=========================================="

    local answer
    read -r -p "  [1] Docker 环境          [默认: ${dockerDefault}] (y/n): " answer
    ENABLE_DOCKER=$(normalize_bool "${answer:-$dockerDefault}" "$dockerDefault")

    read -r -p "  [2] Node.js 生态         [默认: ${nodeDefault}] (y/n): " answer
    ENABLE_NODE=$(normalize_bool "${answer:-$nodeDefault}" "$nodeDefault")

    read -r -p "  [3] Miniconda            [默认: ${condaDefault}] (y/n): " answer
    ENABLE_MINICONDA=$(normalize_bool "${answer:-$condaDefault}" "$condaDefault")
}

# 弹出安装选项复选框并写入 ENABLE_* 变量
select_install_options() {
    local dockerOn="OFF" nodeOn="OFF" condaOn="OFF"
    [[ "$(normalize_bool "$ENABLE_DOCKER" true)" == "true" ]] && dockerOn="ON"
    [[ "$(normalize_bool "$ENABLE_NODE" true)" == "true" ]] && nodeOn="ON"
    [[ "$(normalize_bool "$ENABLE_MINICONDA" true)" == "true" ]] && condaOn="ON"

    SELECTED_TAGS=""
    if show_checklist_tui "PVE Ubuntu 初始化" "空格勾选，回车确认（必装项会始终执行）" \
        "docker" "Docker 环境 (Engine + Compose)" "$dockerOn" \
        "node" "Node.js 生态 (Node + pnpm + PM2)" "$nodeOn" \
        "miniconda" "Miniconda (Python 环境)" "$condaOn"; then

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

# 应用默认值或弹出交互菜单
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
echo "日志文件: $LOG_FILE"

# 防止 apt 交互式弹窗 (GRUB、内核升级提示等)
export DEBIAN_FRONTEND=noninteractive

# 动态计算总步骤: 基础 2 步 + 可选组件
TOTAL_STEPS=2
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
echo " 系统更新与依赖:   必装 (含 qemu-guest-agent)"
echo " Docker:           $ENABLE_DOCKER"
echo " Node.js 生态:     $ENABLE_NODE"
echo " Miniconda:        $ENABLE_MINICONDA"
echo "=========================================="

# ==========================================
# 1. 基础设置与 Root SSH 配置
# ==========================================
echo -e "\n>>> 配置系统基础设置..."

# 1a. Root 密码
echo "root:${ROOT_PASSWORD}" | chpasswd

# 1b. 时区 & Locale
timedatectl set-timezone "$TIMEZONE"
locale-gen en_US.UTF-8 zh_CN.UTF-8 > /dev/null 2>&1 || true
update-locale LANG=en_US.UTF-8

# 1c. SSH 允许 Root 登录
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_DROP="/etc/ssh/sshd_config.d/99-root-login.conf"
# 使用 drop-in 配置，避免直接修改主配置文件 (更干净、更易回滚)
if ! grep -qs "^PermitRootLogin yes" "$SSHD_DROP" 2>/dev/null; then
    mkdir -p /etc/ssh/sshd_config.d
    echo "PermitRootLogin yes" > "$SSHD_DROP"
    systemctl restart ssh
    echo " -> Root SSH 已通过 drop-in 配置开启"
else
    echo " -> Root SSH 已配置，跳过"
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

apt-get install -y \
    curl wget git jq unzip htop \
    build-essential ca-certificates \
    python3-pip software-properties-common \
    qemu-guest-agent                          # PVE 必备: 优雅关机、IP 上报

# qemu-guest-agent 由 PVE 通过 udev/socket 激活，无需 enable
# 只需确保服务已启动即可
systemctl start qemu-guest-agent 2>/dev/null || true

step_ok "系统更新与基础依赖"

# ==========================================
# 3. 安装 Docker & Docker Compose (官方 APT 源)
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
# 4. 安装 Node.js (NodeSource), pnpm, pm2
# ==========================================
if [[ "$ENABLE_NODE" == "true" ]]; then
    echo -e "\n>>> 安装 Node.js 生态..."

    # 4a. Node.js
    if ! command -v node &> /dev/null; then
        curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" -o /tmp/nodesource_setup.sh
        bash /tmp/nodesource_setup.sh
        rm -f /tmp/nodesource_setup.sh
        apt-get install -y nodejs
        echo " -> Node.js $(node -v) 安装完成"
    else
        echo " -> Node.js $(node -v) 已安装，跳过"
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
        echo " -> pnpm $(pnpm -v) 安装完成"
    else
        echo " -> pnpm $(pnpm -v) 已安装，跳过"
    fi

    # 4c. PM2
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
# 5. 安装 Miniconda (Python 环境管理)
# ==========================================
if [[ "$ENABLE_MINICONDA" == "true" ]]; then
    echo -e "\n>>> 安装 Miniconda..."

    if [ ! -d "$CONDA_DIR" ]; then
        CONDA_INSTALLER="/tmp/miniconda.sh"
        wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
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
# 完成摘要
# ==========================================
echo ""
echo "=========================================="
echo " 🎉 初始化全部完成！"
echo "=========================================="
echo " 时区:       $(timedatectl show -p Timezone --value)"
echo " Docker:     $(docker --version 2>/dev/null | awk '{gsub(/,/,""); print $3}' || echo '未安装/已跳过')"
echo " Node.js:    $(node -v 2>/dev/null || echo '未安装/已跳过')"
echo " pnpm:       $(pnpm -v 2>/dev/null || echo '未安装/已跳过')"
echo " PM2:        $(pm2 -v 2>/dev/null || echo '未安装/已跳过')"
echo " Conda:      $(${CONDA_DIR}/bin/conda -V 2>/dev/null || echo '未安装/已跳过')"
GA_STATUS=$(systemctl is-active qemu-guest-agent 2>/dev/null || true)
echo " Guest Agent: ${GA_STATUS:-未安装} (PVE 侧启用后自动激活)"
echo " 日志:       $LOG_FILE"
echo "=========================================="
echo " 👉 执行 'source ~/.bashrc' 或重新连接 SSH 激活环境"
echo "=========================================="

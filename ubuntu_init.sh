#!/bin/bash
# ==================================================================
# PVE Ubuntu 虚拟机初始化脚本
# 适用环境: Ubuntu 24.04 / 26.04 Server (PVE 内网虚拟机)
# 网络环境: OpenWrt 透明代理，无需额外代理配置
# 目标: Root SSH → 系统基础 → Docker → Node.js → Miniconda
# ==================================================================

set -euo pipefail

# ---- 自动提权: 非 root 用户自动通过 sudo 重新执行 ----
if [[ $EUID -ne 0 ]]; then
    echo "当前用户非 root，正在通过 sudo 提权..."
    # 传递环境变量给 sudo 下的脚本
    exec sudo ROOT_PASSWORD="${ROOT_PASSWORD:-root}" \
              NODE_MAJOR="${NODE_MAJOR:-24}" \
              bash "$0" "$@"
fi

# ---- 全局配置 (按需修改) ----
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"       # 可通过环境变量覆盖: ROOT_PASSWORD=xxx bash init.sh
NODE_MAJOR="${NODE_MAJOR:-24}"               # Node.js 主版本号
CONDA_DIR="/opt/miniconda3"
TIMEZONE="Asia/Shanghai"

# ---- 日志 ----
LOG_FILE="/var/log/ubuntu-init-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "日志文件: $LOG_FILE"

# 防止 apt 交互式弹窗 (GRUB、内核升级提示等)
export DEBIAN_FRONTEND=noninteractive

TOTAL_STEPS=5
step_ok() { echo -e "\n✅ [$1/$TOTAL_STEPS] $2 完成"; }

# ==========================================
# 1. 基础设置与 Root SSH 配置
# ==========================================
echo -e "\n>>> [1/$TOTAL_STEPS] 配置系统基础设置..."

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

step_ok 1 "系统基础设置"

# ==========================================
# 2. 系统更新与基础依赖包
# ==========================================
echo -e "\n>>> [2/$TOTAL_STEPS] 更新系统并安装基础依赖..."

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

step_ok 2 "系统更新与基础依赖"

# ==========================================
# 3. 安装 Docker & Docker Compose (官方 APT 源)
# ==========================================
echo -e "\n>>> [3/$TOTAL_STEPS] 安装 Docker 环境..."

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

step_ok 3 "Docker 环境"

# ==========================================
# 4. 安装 Node.js (NodeSource), pnpm, pm2
# ==========================================
echo -e "\n>>> [4/$TOTAL_STEPS] 安装 Node.js 生态..."

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

step_ok 4 "Node.js 生态"

# ==========================================
# 5. 安装 Miniconda (Python 环境管理)
# ==========================================
echo -e "\n>>> [5/$TOTAL_STEPS] 安装 Miniconda..."

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

step_ok 5 "Miniconda"

# ==========================================
# 完成摘要
# ==========================================
echo ""
echo "=========================================="
echo " 🎉 初始化全部完成！"
echo "=========================================="
echo " 时区:       $(timedatectl show -p Timezone --value)"
echo " Docker:     $(docker --version 2>/dev/null | awk '{gsub(/,/,""); print $3}' || echo '未安装')"
echo " Node.js:    $(node -v 2>/dev/null || echo '未安装')"
echo " pnpm:       $(pnpm -v 2>/dev/null || echo '未安装')"
echo " PM2:        $(pm2 -v 2>/dev/null || echo '未安装')"
echo " Conda:      $(${CONDA_DIR}/bin/conda -V 2>/dev/null || echo '未安装')"
GA_STATUS=$(systemctl is-active qemu-guest-agent 2>/dev/null || true)
echo " Guest Agent: ${GA_STATUS:-未安装} (PVE 侧启用后自动激活)"
echo " 日志:       $LOG_FILE"
echo "=========================================="
echo " 👉 执行 'source ~/.bashrc' 或重新连接 SSH 激活环境"
echo "=========================================="
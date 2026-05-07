# PVE Ubuntu 虚拟机初始化脚本 / PVE Ubuntu VM Initialization Script

---

## 中文说明 (Chinese)

这是一个用于 PVE (Proxmox Virtual Environment) 环境下 Ubuntu 系统的快速初始化脚本。

### 适用环境

- **操作系统**: Ubuntu 24.04 / 26.04 Server (及其他主流版本)
- **运行环境**: PVE 内网虚拟机
- **网络条件**: 建议在拥有透明代理的环境下运行，以加快软件包下载速度。

### 主要功能

本脚本将自动完成以下五个阶段的初始化：

1.  **系统基础设置**:
    - 配置 Root 密码（默认为 `root`）。
    - 设置时区为 `Asia/Shanghai`。
    - 生成并设置 `en_US.UTF-8` 和 `zh_CN.UTF-8` 语言环境。
    - 开启 Root SSH 登录权限。
2.  **系统更新与基础依赖**:
    - 执行 `apt update` & `upgrade`。
    - 安装基础工具：`curl`, `wget`, `git`, `jq`, `unzip`, `htop`, `build-essential` 等。
    - 安装 `qemu-guest-agent` (用于 PVE 优雅关机和 IP 上报)。
3.  **Docker 环境**:
    - 安装最新版 Docker Engine 及 Docker Compose 插件。
    - 配置 Docker 日志滚动限制（防止日志占满磁盘）。
4.  **Node.js 生态**:
    - 安装 Node.js (默认 v24)。
    - 启用 `pnpm`。
    - 安装并配置 `PM2` 进程管理器（并设置开机自启）。
5.  **Python 环境 (Miniconda)**:
    - 安装 Miniconda3 到 `/opt/miniconda3`。
    - 初始化 Shell 并禁用自动激活 `base` 环境。

### 使用方法

#### 1. 下载脚本
```bash
wget https://raw.githubusercontent.com/cjgtsc/pve-ubuntu-init/main/ubuntu_init.sh
# 或者
curl -O https://raw.githubusercontent.com/cjgtsc/pve-ubuntu-init/main/ubuntu_init.sh
```

#### 2. 赋予执行权限
```bash
chmod +x ubuntu_init.sh
```

#### 3. 执行脚本
脚本支持以下三种运行方式，会自动检测并申请 `root` 权限：

- **方式 A：Root 用户直接运行**
  ```bash
  ./ubuntu_init.sh
  ```
- **方式 B：普通用户运行（自动 sudo 提权）**
  ```bash
  ./ubuntu_init.sh
  ```
- **方式 C：自定义参数运行（推荐）**
  ```bash
  ROOT_PASSWORD=mypass NODE_MAJOR=24 ./ubuntu_init.sh
  ```

*提示：`exec sudo` 逻辑确保了环境变量能正确传递，且不会产生多层嵌套进程。*

### 完成后建议
1. 执行 `source ~/.bashrc` 或重新连接 SSH 以激活 Conda 和 Node.js 环境。
2. 检查 `qemu-guest-agent` 是否在 PVE 侧正常工作。

---

## English Description

This is a fast initialization script for Ubuntu systems running in a PVE (Proxmox Virtual Environment).

### Environment

- **OS**: Ubuntu 24.04 / 26.04 Server (and other major versions)
- **Runtime**: PVE internal VM
- **Network**: Transparent proxy is recommended for faster package downloads.

### Main Features

The script automatically completes initialization in five stages:

1.  **System Base Settings**:
    - Configures Root password (default: `root`).
    - Sets timezone to `Asia/Shanghai`.
    - Generates and sets `en_US.UTF-8` and `zh_CN.UTF-8` locales.
    - Enables Root SSH login.
2.  **System Update & Basic Dependencies**:
    - Executes `apt update` & `upgrade`.
    - Installs basic tools: `curl`, `wget`, `git`, `jq`, `unzip`, `htop`, `build-essential`, etc.
    - Installs `qemu-guest-agent` (for graceful shutdown and IP reporting in PVE).
3.  **Docker Environment**:
    - Installs the latest Docker Engine and Docker Compose plugin.
    - Configures Docker log rotation (prevents logs from filling up the disk).
4.  **Node.js Ecosystem**:
    - Installs Node.js (default v24).
    - Enables `pnpm`.
    - Installs and configures `PM2` process manager (with auto-start).
5.  **Python Environment (Miniconda)**:
    - Installs Miniconda3 to `/opt/miniconda3`.
    - Initializes Shell and disables auto-activation of the `base` environment.

### Usage

#### 1. Download Script
```bash
wget https://raw.githubusercontent.com/cjgtsc/pve-ubuntu-init/main/ubuntu_init.sh
# or
curl -O https://raw.githubusercontent.com/cjgtsc/pve-ubuntu-init/main/ubuntu_init.sh
```

#### 2. Grant Execution Permission
```bash
chmod +x ubuntu_init.sh
```

#### 3. Run Script
The script supports the following three ways to run, and will automatically detect and request `root` privileges:

- **Method A: Run directly as Root**
  ```bash
  ./ubuntu_init.sh
  ```
- **Method B: Run as normal user (Automatic sudo elevation)**
  ```bash
  ./ubuntu_init.sh
  ```
- **Method C: Run with custom parameters (Recommended)**
  ```bash
  ROOT_PASSWORD=mypass NODE_MAJOR=24 ./ubuntu_init.sh
  ```

*Tip: The `exec sudo` logic ensures that environment variables are passed correctly and does not create nested processes.*

### After Completion
1. Run `source ~/.bashrc` or reconnect via SSH to activate Conda and Node.js environments.
2. Check if `qemu-guest-agent` is working correctly on the PVE side.

## License
MIT

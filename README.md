# PVE Ubuntu 虚拟机初始化脚本 / PVE Ubuntu VM Initialization Script

---

## 中文说明 (Chinese)

这是一个用于 PVE (Proxmox Virtual Environment) 环境下 Ubuntu 系统的快速初始化脚本。

### 适用环境

- **操作系统**: Ubuntu 24.04 / 26.04 Server (及其他主流版本)
- **运行环境**: PVE 内网虚拟机
- **网络条件**: 建议在拥有透明代理的环境下运行，以加快软件包下载速度。

### 主要功能

本脚本会始终执行系统基础设置与依赖安装，并在启动时通过**复选框**让你选择其余组件：

| 类型 | 组件 | 说明 |
|------|------|------|
| 必装 | 系统基础设置 | Root 密码、时区、Locale、Root SSH |
| 必装 | 系统更新与基础依赖 | apt update/upgrade、基础工具、`qemu-guest-agent` |
| 可选 | Docker 环境 | Docker Engine + Compose + 日志滚动 |
| 可选 | Node.js 生态 | Node.js (默认 v24) + pnpm + PM2 |
| 可选 | Miniconda | Miniconda3 到 `/opt/miniconda3` |

启动时使用 **whiptail 英文菜单**（↑/↓ 移动，空格勾选，回车确认；主题近似背景 `#262626` / 高亮 `#e95420`）。先展示必装说明，再勾选可选项。安装过程日志同样为英文，避免 PVE 网页控制台中文乱码。无 whiptail 时回退 dialog / y/n。非交互或环境变量指定全部选项时跳过菜单。

### 使用方法

#### 1. 下载脚本
```bash
wget https://raw.githubusercontent.com/cjgtsc/pve-ubuntu-init/main/ubuntu_pve_init.sh
# 或者
curl -O https://raw.githubusercontent.com/cjgtsc/pve-ubuntu-init/main/ubuntu_pve_init.sh
```

#### 2. 赋予执行权限
```bash
chmod +x ubuntu_pve_init.sh
```

#### 3. 执行脚本
脚本支持以下三种运行方式，会自动检测并申请 `root` 权限：

- **方式 A：Root 用户直接运行**
  ```bash
  ./ubuntu_pve_init.sh
  ```
- **方式 B：普通用户运行（自动 sudo 提权）**
  ```bash
  ./ubuntu_pve_init.sh
  ```
- **方式 C：自定义参数运行（推荐）**
  ```bash
  ROOT_PASSWORD=mypass NODE_MAJOR=24 ./ubuntu_pve_init.sh
  ```

*提示：`exec sudo` 逻辑确保了环境变量能正确传递，且不会产生多层嵌套进程。*

##### 可配置环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ROOT_PASSWORD` | `root` | Root 密码 |
| `NODE_MAJOR` | `24` | Node.js 主版本号 |
| `ENABLE_DOCKER` | _(交互选择)_ | 是否安装 Docker |
| `ENABLE_NODE` | _(交互选择)_ | 是否安装 Node.js 生态 |
| `ENABLE_MINICONDA` | _(交互选择)_ | 是否安装 Miniconda |
| `SKIP_SELECT` | `false` | `true` 时跳过复选框，使用默认（全开）或已指定的环境变量 |

使用示例:
```bash
# 仅安装 Docker，跳过交互菜单
SKIP_SELECT=true ENABLE_DOCKER=true ENABLE_NODE=false ENABLE_MINICONDA=false ./ubuntu_pve_init.sh
```

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

Base system setup and dependencies always run. Optional components are selected via an interactive checklist at startup:

1. **System Base Settings** (required): Root password, timezone, locales, Root SSH.
2. **System Update & Dependencies** (required): `apt update/upgrade`, basic tools, `qemu-guest-agent`.
3. **Docker** (optional): Docker Engine + Compose + log rotation.
4. **Node.js Ecosystem** (optional): Node.js (default v24) + pnpm + PM2.
5. **Miniconda** (optional): Miniconda3 with shell initialization.

### Usage

#### 1. Download Script
```bash
wget https://raw.githubusercontent.com/cjgtsc/pve-ubuntu-init/main/ubuntu_pve_init.sh
# or
curl -O https://raw.githubusercontent.com/cjgtsc/pve-ubuntu-init/main/ubuntu_pve_init.sh
```

#### 2. Grant Execution Permission
```bash
chmod +x ubuntu_pve_init.sh
```

#### 3. Run Script
The script supports the following three ways to run, and will automatically detect and request `root` privileges:

- **Method A: Run directly as Root**
  ```bash
  ./ubuntu_pve_init.sh
  ```
- **Method B: Run as normal user (Automatic sudo elevation)**
  ```bash
  ./ubuntu_pve_init.sh
  ```
- **Method C: Run with custom parameters (Recommended)**
  ```bash
  ROOT_PASSWORD=mypass NODE_MAJOR=24 ./ubuntu_pve_init.sh
  ```

*Tip: The `exec sudo` logic ensures that environment variables are passed correctly and does not create nested processes.*

### After Completion
1. Run `source ~/.bashrc` or reconnect via SSH to activate Conda and Node.js environments.
2. Check if `qemu-guest-agent` is working correctly on the PVE side.

---

## 普通 Ubuntu 服务器初始化脚本 / General Ubuntu Server Initialization Script

### 中文说明

`ubuntu_server_init.sh` 适用于物理机、云服务器等通用 Ubuntu 服务器环境（非 PVE 虚拟机）。

#### 适用环境

- **操作系统**: Ubuntu 24.04 / 26.04 Server (及其他主流版本)
- **运行环境**: 物理机 / 云服务器 (AWS, GCP, Azure, OVH 等) / 通用虚拟机
- **网络条件**: 需要公网访问以下载软件包

#### 与 PVE 版本的区别

| 功能 | PVE 版 (`ubuntu_pve_init.sh`) | 服务器版 (`ubuntu_server_init.sh`) |
|------|--------------------------|----------------------------------|
| qemu-guest-agent | ✅ 安装 | ❌ 不需要 |
| SSH 端口 | 22 (默认) | 8022 (防扫描) |
| UFW 防火墙 | ❌ | ✅ 可选 |
| Fail2ban | ❌ | ✅ 可选 |
| 自动安全更新 | ❌ | ✅ 可选 |
| Root 密码 | 默认 `root` | 交互式设置 (或环境变量指定) |
| Docker / Node.js / Miniconda | ✅ 可选 | ✅ 可选 |
| 幂等性 (重复执行) | ✅ | ✅ 已安装的项目自动跳过 |

#### 主要功能

必装项会始终执行；其余组件通过启动时的**复选框**选择：

| 类型 | 组件 | 说明 |
|------|------|------|
| 必装 | 系统基础设置 | Root 密码、时区、Locale、SSH 端口加固 |
| 必装 | 系统更新与基础依赖 | apt update/upgrade、基础工具 |
| 可选 | UFW 防火墙 | 放行 SSH、HTTP、HTTPS |
| 可选 | Fail2ban | SSH 暴力破解防护（5 次失败封禁 1 小时） |
| 可选 | 自动安全更新 | `unattended-upgrades` 每日安全补丁 |
| 可选 | Docker 环境 | Docker Engine + Compose + 日志滚动 |
| 可选 | Node.js 生态 | Node.js + pnpm + PM2 |
| 可选 | Miniconda | Miniconda3 到 `/opt/miniconda3` |

#### 使用方法

##### 1. 下载脚本
```bash
wget https://raw.githubusercontent.com/cjgtsc/pve-ubuntu-init/main/ubuntu_server_init.sh
# 或者
curl -O https://raw.githubusercontent.com/cjgtsc/pve-ubuntu-init/main/ubuntu_server_init.sh
```

##### 2. 赋予执行权限
```bash
chmod +x ubuntu_server_init.sh
```

##### 3. 执行脚本

脚本支持以下运行方式，会自动检测并申请 `root` 权限：

- **方式 A：直接运行（交互式设置 Root 密码 + 复选框选组件）**
  ```bash
  ./ubuntu_server_init.sh
  ```
- **方式 B：自定义参数运行（推荐）**
  ```bash
  ROOT_PASSWORD=mypass NODE_MAJOR=24 ./ubuntu_server_init.sh
  ```

##### 可配置环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ROOT_PASSWORD` | _(交互式输入)_ | Root 密码，留空则检测锁定状态后交互提示 |
| `NODE_MAJOR` | `24` | Node.js 主版本号 |
| `SSH_PORT` | `8022` | SSH 监听端口 |
| `ENABLE_UFW` | _(交互选择)_ | 是否启用 UFW 防火墙 |
| `ENABLE_FAIL2BAN` | _(交互选择)_ | 是否启用 Fail2ban |
| `ENABLE_AUTO_UPDATES` | _(交互选择)_ | 是否配置自动安全更新 |
| `ENABLE_DOCKER` | _(交互选择)_ | 是否安装 Docker |
| `ENABLE_NODE` | _(交互选择)_ | 是否安装 Node.js 生态 |
| `ENABLE_MINICONDA` | _(交互选择)_ | 是否安装 Miniconda |
| `LOGIN_GRACE_TIME` | `120` | SSH 认证超时秒数 (跨国连接建议 ≥120) |
| `SKIP_SELECT` | `false` | `true` 时跳过复选框，使用默认（全开）或已指定的环境变量 |

使用示例:
```bash
# 完整参数示例：自定义 SSH 端口 2222、不装 Fail2ban/Miniconda、指定 Node.js v24
ROOT_PASSWORD=mypass SSH_PORT=2222 ENABLE_FAIL2BAN=false ENABLE_MINICONDA=false NODE_MAJOR=24 ./ubuntu_server_init.sh

# 非交互全默认安装（跳过复选框）
SKIP_SELECT=true ROOT_PASSWORD=mypass ./ubuntu_server_init.sh
```

**参数省略与作用说明：**
以上所有环境变量都是**可选的（可以全部或部分省去）**。当你省略它们时：
* **交互终端**：whiptail 英文说明 + checklist（↑/↓ + 空格）；未指定的项默认勾选。
* **非交互 / `SKIP_SELECT=true`**：未指定的可选组件默认全部安装。
* **`ROOT_PASSWORD` (可省去)**：如果省去，脚本会检测 Root 是否有密码；没有则交互输入。
* **`SSH_PORT` (可省去)**：默认改为 `8022`。

因此，最极简的运行方式就是直接执行 `./ubuntu_server_init.sh`，按提示勾选即可。

#### 幂等性 (可重复执行)

脚本支持安全地重复执行。更新脚本后重新运行时：
- 已安装的软件（Docker、Node.js、pnpm、PM2、Miniconda）会自动跳过。
- 已有的 Root 密码不会被覆盖（除非通过环境变量显式指定）。
- SSH 配置和 UFW 规则只在实际变更时才会重新应用。
- `apt-get install -y` 天然幂等，不会重复安装已有的包。

#### 完成后建议
1. 执行 `source ~/.bashrc` 或重新连接 SSH 以激活 Conda 和 Node.js 环境。
2. SSH 端口已改为 `8022`，请使用 `ssh -p 8022 user@host` 连接。

---

### English Description

`ubuntu_server_init.sh` is designed for general Ubuntu server environments (bare metal, cloud VMs, etc. — not PVE VMs).

#### Environment

- **OS**: Ubuntu 24.04 / 26.04 Server (and other major versions)
- **Runtime**: Bare metal / Cloud VMs (AWS, GCP, Azure, OVH, etc.) / General VMs
- **Network**: Public internet access required for package downloads

#### Main Features

Required base setup always runs. Optional components are selected via an interactive checklist:

1. **System Base Settings** (required): Root password, timezone, locale, SSH port (default 8022).
2. **System Update & Dependencies** (required): `apt update/upgrade`, basic tools.
3. **UFW** (optional): Firewall rules for SSH/HTTP/HTTPS.
4. **Fail2ban** (optional): SSH brute-force protection.
5. **Automatic Security Updates** (optional): `unattended-upgrades`.
6. **Docker** (optional): Docker Engine + Compose + log rotation.
7. **Node.js Ecosystem** (optional): Node.js + pnpm + PM2.
8. **Miniconda** (optional): Miniconda3 with shell initialization.

#### Usage

##### 1. Download Script
```bash
wget https://raw.githubusercontent.com/cjgtsc/pve-ubuntu-init/main/ubuntu_server_init.sh
# or
curl -O https://raw.githubusercontent.com/cjgtsc/pve-ubuntu-init/main/ubuntu_server_init.sh
```

##### 2. Grant Execution Permission
```bash
chmod +x ubuntu_server_init.sh
```

##### 3. Run Script

- **Method A: Run directly (interactive Root password + component checklist)**
  ```bash
  ./ubuntu_server_init.sh
  ```
- **Method B: Run with custom parameters (Recommended)**
  ```bash
  ROOT_PASSWORD=mypass NODE_MAJOR=24 ./ubuntu_server_init.sh
  ```

##### Configurable Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ROOT_PASSWORD` | _(interactive)_ | Root password. If empty, prompts when account is locked |
| `NODE_MAJOR` | `24` | Node.js major version |
| `SSH_PORT` | `8022` | SSH listening port |
| `ENABLE_UFW` | _(interactive)_ | Enable UFW firewall |
| `ENABLE_FAIL2BAN` | _(interactive)_ | Enable Fail2ban |
| `ENABLE_AUTO_UPDATES` | _(interactive)_ | Enable unattended-upgrades |
| `ENABLE_DOCKER` | _(interactive)_ | Install Docker |
| `ENABLE_NODE` | _(interactive)_ | Install Node.js ecosystem |
| `ENABLE_MINICONDA` | _(interactive)_ | Install Miniconda |
| `LOGIN_GRACE_TIME` | `120` | SSH authentication timeout in seconds |
| `SKIP_SELECT` | `false` | Skip checklist; use defaults or explicit env vars |

#### Idempotency (Safe to Re-run)

The script is safe to run multiple times. When re-running after updates:
- Already installed software (Docker, Node.js, pnpm, PM2, Miniconda) is automatically skipped.
- Existing Root passwords are preserved (unless explicitly set via environment variable).
- SSH config and UFW rules are only reapplied when changes are detected.
- `apt-get install -y` is naturally idempotent.

#### After Completion
1. Run `source ~/.bashrc` or reconnect via SSH to activate environments.
2. SSH port has been changed to `8022`. Use `ssh -p 8022 user@host` to connect.

## License
MIT

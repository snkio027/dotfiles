# 2026 Personal Developer Platform (DevSecOps Grade)

> **一套可重构、可审计、自愈、可观测、跨平台（macOS / Linux / DevContainer）的个人 DevSecOps 开发基础设施。**  
> 基于原生 `chezmoi` 驱动，集成了声明式 Runtime 管理、一键环境自检自愈 (`devdoctor`)、密钥防泄露安全防线与规范化 DevContainer 开发规范。

---

## 🏗️ 架构总览

```text
Observability    │  devdoctor (自检自愈诊断) · chezmoi diff (Side-by-Side 差异高亮) · CI Dry-Run 校验
─────────────────┼─────────────────────────────────────────────────────────────────────────────
Identity Plane   │  1Password SSH Agent · Ed25519 Commit Signing · SSH Allowed Signers Trust Chain
─────────────────┼─────────────────────────────────────────────────────────────────────────────
Security Plane   │  age (chezmoi native encryption) · 1Password CLI · SOPS · gitleaks (凭据防泄漏)
─────────────────┼─────────────────────────────────────────────────────────────────────────────
State Plane      │  chezmoi (source dir) · chezmoi external (zinit) · Brew Bundle · DevContainer
─────────────────┼─────────────────────────────────────────────────────────────────────────────
Runtime Plane    │  mise.toml (声明式最新语言包) · direnv · zoxide · Carapace (跨 CLI 自动补全)
```

---

## 📁 目录结构

```text
dotfiles/
├── .chezmoi.toml.tmpl                       ★ 全局模版与 OS / 1Password / delta 差异比对匹配
├── .chezmoidata.yaml                        ★ 静态全局配置字典与 Machine Profile 角色分层
├── .chezmoiexternal.toml                    ★ 声明式外部依赖 (zinit 等)
├── .chezmoiignore                           ★ 部署隔离配置文件
├── .devcontainer/                           ★ 容器化 Disposable 基础设施声明
│   ├── Dockerfile                           # 统一 Ubuntu 开发环境 Docker 镜像
│   └── devcontainer.json                    # VS Code / Codespaces 挂载规范
├── Brewfile                                 ★ 声明式包定义 (Brew bundle, gitleaks, carapace)
├── README.md
│
├── .chezmoitemplates/                       ★ 可复用组件模版
│   ├── os_detect.tmpl                       # 平台与 CPU 架构推断
│   └── shell_header.tmpl                    # 标准文件 Header 声明
│
├── dot_gitconfig.tmpl                       → ~/.gitconfig (Catppuccin Mocha Delta 差异高亮)
├── dot_zshrc.tmpl                           → ~/.zshrc (Atuin 行编辑器前置 + 瞬时提示符兼容)
│
├── private_dot_ssh/                         → ~/.ssh/ (自动继承 700 权限)
│   ├── private_config.tmpl                  → ~/.ssh/config (1Password Agent 600)
│   ├── private_allowed_signers.tmpl        → ~/.ssh/allowed_signers (Git 信任链)
│   └── config.d/                            → ~/.ssh/config.d/ (模块化 Host 配置)
│       ├── github.conf                      # GitHub 专门路由
│       └── work.conf.example                # 企业网 Host 示例
│
├── dot_config/                              → ~/.config/ (XDG 规范配置)
│   ├── mise/config.toml.tmpl                → ~/.config/mise/config.toml (声明式 Runtime 版本)
│   ├── nvim/                                → ~/.config/nvim/ (init.lua & lazy-lock.json 锁定)
│   ├── starship.toml                        → Starship 提示符 (Catppuccin Mocha 调色板)
│   ├── ghostty/config                       → Ghostty 终端 (Quake 下拉/后台通知/Vim分屏)
│   ├── zellij/config.kdl                    → Zellij (Alt+h/j/k/l 盲操分屏 + Alt+i 悬浮工作区)
│   ├── yazi/yazi.toml                       → Yazi (1:3:4 黄金三栏 + 独立打开规则)
│   ├── atuin/config.toml                    → Atuin (Up 键目录历史 + Ctrl+R 全局历史)
│   └── zsh/                                 → Zsh 脚本与插件
│       └── scripts/doctor.sh                ★ devdoctor 环境自检自愈诊断系统
│
└── .chezmoiscripts/                         ★ 原生生命周期控制
    ├── run_once_before_10_install_brew.sh.tmpl  # 前置：Homebrew 引导与 gcc 编译依赖保证
    ├── run_onchange_after_20_brew_bundle.sh.tmpl    # 增量：Brewfile 哈希感知重构
    ├── run_once_after_20_git_identity.sh.tmpl      # 后置：git.tar 功能全量融合
    ├── run_once_after_30_setup_neovim.sh.tmpl       # 后置：Neovim Headless 插件构建
    └── run_once_after_90_macos_defaults.sh.tmpl    # 后置：macOS 自动化偏好
```

---

## 🚀 快速开始与 DevEx 命令

### 裸机一键恢复 (Chezmoi 原生方式)

```bash
chezmoi init --apply https://github.com/snkio027/dotfiles
```

### 🩺 环境自检与修复 (devdoctor)

在终端运行以下快捷命令即可进行全方位平台健康度检查：

```bash
devdoctor
# 或
doctor
```

输出项覆盖：操作系统与架构、Homebrew 状态、chezmoi 部署同步与 diff、1Password SSH Agent、Git SSH 签名与信任链、gitleaks 极速安全扫描、mise 声明式 Runtime 语言版本及所有 CLI 工具链就绪度。

### 🔒 秘钥防泄漏扫描

```bash
scan-secrets
```

### 🛠️ 日常管理与维护

- **查看差异** (Side-by-Side 语法高亮对比)：
  ```bash
  chezmoi diff
  ```
- **应用更新**：
  ```bash
  chezmoi apply
  ```
- **修改配置**：
  ```bash
  chezmoi edit ~/.zshrc
  ```

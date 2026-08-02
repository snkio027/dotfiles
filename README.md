# 2026 Developer Workstation chezmoi Production Profile (DevSecOps Grade)

> **一套可重构、可审计、跨平台（macOS / Linux）的个人 DevSecOps 开发基础设施。**  
> 基于原生 `chezmoi` 架构驱动，新机器只需运行一条命令完成全量配置部署。

---

## 🏗️ 架构总览

```text
Identity Plane   │  1Password SSH Agent · Ed25519 Commit Signing · SSH Allowed Signers Trust Chain
─────────────────┼─────────────────────────────────────────────────────────────────────────────
Secret Plane     │  age (chezmoi native encryption) · 1Password CLI · SOPS
─────────────────┼─────────────────────────────────────────────────────────────────────────────
State Plane      │  chezmoi (source dir) · chezmoi external (zinit) · Brew Bundle
─────────────────┼─────────────────────────────────────────────────────────────────────────────
Runtime Plane    │  direnv / mise (runtime & env) · zoxide (navigation) · Catppuccin Mocha TUI
```

---

## 📁 目录结构

```text
dotfiles/
├── .chezmoi.toml.tmpl                       ★ 全局模版与 OS / 1Password / delta 差异比对匹配
├── .chezmoidata.yaml                        ★ 静态全局配置字典与 Machine Profile 角色分层
├── .chezmoiexternal.toml                    ★ 声明式外部依赖 (zinit 等)
├── .chezmoiignore                           ★ 部署隔离配置文件
├── .gitignore
├── Brewfile                                 ★ 声明式包定义 (Brew bundle, 显式前置 gcc 编译链)
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
│   ├── starship.toml                        → Starship 提示符 (Catppuccin Mocha 调色板)
│   ├── ghostty/config                       → Ghostty 终端 (Quake 下拉/后台通知/Vim分屏)
│   ├── zellij/config.kdl                    → Zellij (Alt+h/j/k/l 盲操分屏 + Alt+i 悬浮工作区)
│   ├── yazi/yazi.toml                       → Yazi (1:3:4 黄金三栏 + 独立打开规则)
│   ├── atuin/config.toml                    → Atuin (Up 键目录历史 + Ctrl+R 全局历史)
│   ├── nvim/init.lua                        → Neovim (Telescope/Treesitter/Which-Key 人机工程)
│   └── zsh/ (exports.zsh.tmpl / aliases.zsh / plugins.zsh)
│
└── .chezmoiscripts/                         ★ 原生生命周期控制
    ├── run_once_before_10_install_packages.sh.tmpl  # 前置：Homebrew 引导与 gcc 编译依赖保证
    ├── run_onchange_after_00_brew_bundle.sh.tmpl    # 增量：Brewfile 哈希感知重构
    ├── run_once_after_20_git_identity.sh.tmpl      # 后置：git.tar 功能全量融合（密钥生成+gh注册+信任链）
    ├── run_once_after_30_setup_neovim.sh.tmpl       # 后置：Neovim Headless 插件构建
    └── run_once_after_90_macos_defaults.sh.tmpl    # 后置：macOS 自动化偏好
```

---

## 🚀 快速开始

### 裸机一键恢复 (Chezmoi 原生方式)

```bash
chezmoi init --apply https://github.com/nekoreb/dotfiles
```

### 日常管理与维护

- 查看差异 (Side-by-Side 语法高亮对比)：
  ```bash
  chezmoi diff
  ```
- 应用更新：
  ```bash
  chezmoi apply
  ```
- 修改配置：
  ```bash
  chezmoi edit ~/.zshrc
  ```

### macOS 打包发布规范

为防止 macOS 产生 AppleDouble (`._*`) 扩展属性文件污染归档包，建议使用以下命令打包：

```bash
COPYFILE_DISABLE=1 tar -cvf dotfiles.tar dotfiles/
```

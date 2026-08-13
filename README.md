# Personal Developer Platform

一套由 `chezmoi` 驱动、面向 Apple Silicon macOS、Linux 与 Dev Container 的开发环境。设计重点是低延迟 Shell、一致的视觉语言、清晰的工具归属，以及本地与 CI 使用同一套验证标准。

## 技术栈

```text
State       │ chezmoi · Homebrew Bundle · Dev Container
Runtime     │ Homebrew latest（Python · Node · Go · Rust · uv · Terraform · Kubernetes）
Shell       │ Zsh · Starship · Atuin · direnv · zoxide · Carapace · fzf
Terminal    │ Ghostty · Zellij（按需）· Yazi · LazyGit
Editor      │ Neovim 0.12 · LazyVim 16 · Catppuccin · fzf-lua · Snacks
Security    │ age · SOPS · SSH signing · gitleaks · Zizmor
Validation  │ actionlint · ShellCheck · shfmt · Taplo · Hadolint · StyLua
```

Homebrew 是系统工具和语言 Runtime 的唯一安装来源。Brewfile 不固定公式版本：每次先执行 `brew update`，再安装或升级到 Homebrew 当前提供的最新稳定版。不使用 mise、asdf、nvm、pyenv 或运行时锁文件。

## 体验设计

- `.zshenv` 只定义 XDG Base Directory；`.zprofile` 只初始化登录环境；`.zshrc` 只处理交互功能。
- Starship、Atuin、fzf、direnv、zoxide 与 Carapace 的生成脚本按二进制修改时间缓存，升级后自动刷新。
- Starship 只在对应项目中显示 Node、Go、Rust、Python 与 Terraform 的实际版本。
- Ghostty 自动跟随系统浅色/深色主题，使用 Maple Mono NF CN 的圆润连字、Nerd 图标与 CJK 2:1 对齐，并提供 GPU 渲染和原生分屏。
- Zellij 默认处于 locked mode，避免占用 Shell、Neovim 和 macOS 的 Alt 快捷键。
- Atuin 以 daemon fuzzy 模式提供 `Ctrl-R` 全局检索，方向键保留原生历史行为。
- Neovim 是唯一编辑器；Git、Yazi、sudo、systemd 与 kubectl 的编辑入口统一指向 Neovim。
- Neovim/LazyVim、LazyGit、Yazi 与全部颜色配置均由 chezmoi 纳管。
- Markdown 在普通模式渲染标题、任务、表格与代码块，插入模式自动显示原文；Ghostty 直连会话支持文档内图片、数学公式与 Mermaid 预览。
- markdownlint 全局保留结构与语义检查，仅关闭对表格、URL 和 CJK 文档噪音较大的 `MD013` 行宽规则。
- uv 项目中存在 `uv.lock` 和 `.venv` 时，Neovim 会自动将 Pyright、Ruff、DAP、Neotest 与内置终端统一到项目 Python。

## 目录

```text
dotfiles/
├── .chezmoiroot                    # 将 chezmoi source state 指向 home/
├── .devcontainer/                  # Ubuntu 24.04 + Linuxbrew 开发环境
├── .github/
│   ├── Brewfile                    # CI 最新稳定版校验工具
│   └── workflows/ci.yml            # 模板、配置、安全与供应链校验
├── Brewfile                        # Runtime、CLI、应用与字体
└── home/                           # 唯一会映射到 $HOME 的 source state
    ├── .chezmoi.toml.tmpl          # 本机数据与仓库 sourceDir
    ├── .chezmoidata.yaml           # Git 默认值与功能开关
    ├── .chezmoiscripts/            # Homebrew、身份、迁移、hook、macOS defaults
    ├── dot_zshenv.tmpl             # 最小 XDG 引导层
    ├── dot_zprofile.tmpl           # 登录 Shell 入口
    ├── dot_zshrc.tmpl              # 交互式 Shell 入口
    ├── private_dot_ssh/             # OpenSSH 原生固定目录
    └── dot_config/
        ├── atuin/                  # 历史检索
        ├── ghostty/                # 终端外观与快捷键
        ├── git/                    # Git 全局配置与 ignore
        ├── lazygit/                # Git TUI 与 Catppuccin 主题
        ├── markdownlint-cli2/      # Markdown 全局规则
        ├── nvim/                   # LazyVim 16 与插件锁
        ├── starship.toml
        ├── yazi/yazi.toml
        ├── zellij/config.kdl
        └── zsh/                    # Shell 模块、缓存逻辑与诊断脚本
```

## XDG 目录策略

| 类型 | 默认目录 | 当前用途 |
| --- | --- | --- |
| 配置 | `~/.config` | Neovim、Ghostty、Git、Zsh 模块及所有支持 XDG 的 TUI |
| 数据 | `~/.local/share` | Atuin 数据库、Neovim 插件和工具持久数据 |
| 状态 | `~/.local/state` | Neovim 日志及可跨会话恢复的状态 |
| 缓存 | `~/.cache` | Zsh 初始化缓存、补全、uv 与可安全重建的数据 |
| 可执行文件 | `~/.local/bin` | 用户级引导程序与脚本 |

`~/.zshenv`、`~/.zprofile`、`~/.zshrc` 是 Zsh 原生启动入口，`~/.ssh` 是 OpenSSH 固定发现位置，因此保留在 HOME。Markdownlint 的 Zsh alias 与 Neovim 都显式加载 XDG 主配置，项目内规则仍可覆盖。Cargo、Go 与 ZVM 保留各自官方数据目录，避免破坏已安装工具和升级机制。

## 初始化

```bash
chezmoi init --apply https://github.com/snkio027/dotfiles
```

初始化会询问 Git 姓名和邮箱，安装 Homebrew/Linuxbrew，更新公式元数据，同步 Brewfile，配置本地 SSH 签名与 gitleaks hook，并在 macOS 上应用键盘、Finder、Dock 和截图偏好。

Dev Container 使用 `CHEZMOI_PROFILE=devcontainer`，通过 Linuxbrew 获得同样的最新工具链，但不会生成宿主密钥、修改宿主 Git hooks 或应用 macOS 偏好。可用 `GIT_AUTHOR_NAME` 与 `GIT_AUTHOR_EMAIL` 覆盖缺省身份。

## 日常维护

```bash
devdoctor                         # 只读环境与工具来源诊断
scan-secrets                      # 扫描暂存内容中的凭据泄漏
chezmoi diff                      # 审核目标状态差异
chezmoi apply                     # 应用已审核配置
brew bundle --file="$(chezmoi source-path)/../Brewfile"
brewup                            # update + upgrade + cleanup
```

`devdoctor` 检查 Homebrew、chezmoi、age、SSH、gitleaks、语言 Runtime、IaC/Kubernetes CLI 和终端工具，并确认 Runtime 的实际路径来自 Homebrew；它不会自动修改系统。

## Neovim 文档与 Python 工作流

- Markdown 使用 `<leader>um` 切换 Neovim 内渲染，使用 `<leader>cp` 切换浏览器预览。Ghostty 支持内联图片；Zellij 暂不支持 Kitty Graphics Protocol 透传，在 Zellij 中使用浮动/浏览器预览。
- 新 uv 项目先运行 `uv sync`，再直接打开 `nvim`。`.venv/bin/python` 会自动激活；需要临时切换环境时使用 `<leader>cv`。

## SSH 与提交签名

- GitHub 认证和 Git 提交签名使用 `~/.ssh/keys/` 下相互独立的 Ed25519 key。
- 签名公钥会加入 `~/.ssh/allowed_signers`；`gh` 已登录时，初始化脚本会尝试注册公钥。
- `features.use_1password` 只控制 SSH Agent 集成；Git 签名使用本地 OpenSSH key。
- 可在初始化前通过 `OP_SSH_AUTH_SOCK` 覆盖 1Password Agent socket。

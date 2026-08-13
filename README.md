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
- Atuin 以 daemon fuzzy 模式持续记录、同步历史，FZF 接管 `Ctrl-R` 检索界面，方向键保留原生历史行为。
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

## 功能与快捷键速查

Neovim 的 `<leader>` 是空格键；Ghostty 的 `Cmd` 快捷键属于 macOS，Zellij 默认 locked mode，不会在启动后立即占用 Shell 或 Neovim 按键。以下只记录本仓库显式配置或当前上游配置实际提供的高频功能。

### Shell 与终端工具

经典命令会在对应现代工具存在时自动升级：`ls` → `eza`、`cat` → `bat`、`find` → `fd`、`grep` → `rg`、`top` → `btop`、`cd` → `zoxide`、`vi`/`vim` → `nvim`。

| 快捷键或命令 | 功能 |
| --- | --- |
| `Ctrl-R` | 使用 FZF 检索 Shell 历史；Atuin 在后台负责持久记录与同步 |
| `Ctrl-T` | 使用 FZF 选择文件并插入命令行 |
| `Alt-C` | 使用 FZF 选择并进入目录 |
| `Ctrl-F` | 接受完整的 Zsh 自动建议 |
| `Alt-F` | 向前移动/接受一个单词 |
| `ll` / `lt` | 详细文件列表 / 目录树 |
| `z <keyword>` / `cdi` | 按使用频率跳转目录 / 交互式选择目录 |
| `y` | 启动 Yazi，退出后进入最后访问的目录 |
| `mkcd <dir>` / `up <n>` | 创建并进入目录 / 向上跳转 n 层 |
| `port <port>` / `fkill` | 查找端口占用 / 模糊选择并结束进程 |
| `ghc <owner/repo>` | 克隆 GitHub 仓库 |
| `dotenv [file]` | 将 `.env` 或指定文件安全加载到当前 Shell |
| `reload` | 重新加载 Zsh 配置 |

### Neovim 导航与检索

| 快捷键 | 功能 |
| --- | --- |
| `<leader><space>` / `<leader>ff` | 查找项目根目录中的文件 |
| `<leader>fF` / `<leader>fg` | 查找当前目录文件 / Git 文件 |
| `<leader>fr` / `<leader>fb` | 最近文件 / Buffer 列表 |
| `<leader>e` / `<leader>fE` | 打开项目根目录 / 当前目录文件树 |
| `<leader>/` / `<leader>sg` | 在项目根目录全文检索 |
| `<leader>sG` | 在当前目录全文检索 |
| `<leader>sk` / `<leader>sR` | 搜索所有快捷键 / 恢复上一次搜索 |
| `s` / `S` | Flash 跳转 / Tree-sitter 结构跳转 |
| `H` / `L` | 上一个 / 下一个 Buffer |
| `Ctrl-H/J/K/L` | 在 Neovim 窗口间移动 |
| `<leader>uW` | 切换当前窗口的自动换行 |

### 代码、LSP 与诊断

| 快捷键 | 功能 |
| --- | --- |
| `grn` / `gra` | 重命名符号 / Code Action |
| `grr` / `gri` / `grt` | 查找引用 / 实现 / 类型定义 |
| `gO` | 文档符号与大纲 |
| `[d` / `]d` | 上一个 / 下一个诊断 |
| `<leader>sd` / `<leader>sD` | Buffer / 工作区诊断检索 |
| `<leader>xx` / `<leader>xX` | Trouble 工作区 / Buffer 诊断 |
| `gcc` / `gc` | 注释当前行 / 选区或动作范围 |
| `gsa` / `gsd` / `gsr` | 添加 / 删除 / 替换包围符号 |
| `<leader>p` | 打开 Yank 历史；`[y`、`]y` 切换记录 |

### 测试、调试与 Git

| 快捷键 | 功能 |
| --- | --- |
| `<leader>tr` / `<leader>tt` | 运行最近测试 / 当前文件测试 |
| `<leader>tT` / `<leader>tl` | 运行全部测试文件 / 重新运行上次测试 |
| `<leader>td` / `<leader>ts` | 调试最近测试 / 测试摘要 |
| `<leader>tw` / `<leader>to` | Watch 模式 / 测试输出 |
| `<leader>db` / `<leader>dc` | 设置断点 / 继续调试 |
| `<leader>di` / `<leader>dO` / `<leader>do` | 步入 / 步过 / 步出 |
| `<leader>du` / `<leader>de` / `<leader>dt` | DAP UI / 计算表达式 / 终止调试 |
| `<leader>gs` / `<leader>gd` | Git 状态 / 当前文件 Diff |
| `<leader>gc` / `<leader>gS` | 提交历史 / Stash |
| `lg` | 在终端中启动 LazyGit |

### Markdown 与 Python

Markdown 在普通、命令和终端模式渲染标题、任务、表格、代码块、图片和数学公式，进入插入模式后显示原始文本，兼顾阅读与编辑。

| 快捷键 | 功能 |
| --- | --- |
| `<leader>um` | 切换 Neovim 内 Markdown 渲染 |
| `<leader>cp` | 切换 Markdown 浏览器预览，适合 Mermaid 和 Zellij 会话 |
| `[[` / `]]` | 跳转到上一节 / 下一节 |
| `gO` | 打开 Markdown 文档大纲 |
| `<leader>cv` | 在 Python Buffer 中手动选择虚拟环境 |

打开 uv 项目的 Python 文件时，会依据 `uv.lock` 自动激活 `.venv/bin/python`，并把同一环境交给 Pyright、Ruff、DAP 与 Neotest；Ruff 负责 Lint 和 Import，Pyright 专注类型分析，避免重复诊断。

### Ghostty 与 Zellij

Ghostty 自动跟随系统浅色/深色主题，使用 Maple Mono NF CN 与 PingFang SC 回退、透明模糊背景、10 万行回滚、复制即选中，并在失焦窗口中的长命令结束时发送系统通知。

| 快捷键 | 功能 |
| --- | --- |
| `Cmd-Alt-Space` | 显示/隐藏 Ghostty Quick Terminal |
| `Cmd-D` / `Cmd-Shift-D` | 向右 / 向下创建 Ghostty 分屏 |
| `Cmd-H/J/K/L` | 在 Ghostty 分屏间移动 |
| `Cmd-Z` | 放大/恢复当前 Ghostty 分屏 |
| `Ctrl-G` | 解锁或重新锁定 Zellij |
| `Alt-H/J/K/L` | 在已解锁的 Zellij Pane 间移动 |
| `Alt-N` / `Alt-F` | 新建 Pane / 切换浮动 Pane |
| `Ctrl-P` / `Ctrl-T` | 进入 Zellij Pane / Tab 模式 |
| `Ctrl-S`，然后 `e` | 进入滚动模式并用 Neovim 编辑滚动缓冲区 |
| `Ctrl-O`，然后 `w` / `d` | 打开 Session Manager / Detach |

Ghostty 直连会话适合内联图片；Zellij 当前不透传 Kitty Graphics Protocol，应使用 Neovim 浮动窗口或浏览器预览。

### Git、chezmoi 与维护

| 命令 | 功能 |
| --- | --- |
| `git lg` / `git st` / `git dfs` | 图形日志 / 状态 / 已暂存 Diff |
| `git amend` / `git undo` | 修改上次提交 / 撤销提交并保留文件 |
| `git sync` / `git rescue` | Rebase 同步 / 查看 Reflog |
| `cz` / `cza` / `czd` | chezmoi 命令入口 / 应用目标状态 / 查看目标差异 |
| `cze` / `czu` | 编辑受管文件 / 更新并应用仓库 |
| `brewup` / `devup` | 更新并清理 Homebrew / 更新 Homebrew 工具链 |
| `devdoctor` | 只读检查配置、Runtime 来源、签名和关键工具 |
| `scan-secrets` | 使用 gitleaks 扫描暂存内容 |

## Neovim 文档与 Python 工作流

- Markdown 使用 `<leader>um` 切换 Neovim 内渲染，使用 `<leader>cp` 切换浏览器预览。Ghostty 支持内联图片；Zellij 暂不支持 Kitty Graphics Protocol 透传，在 Zellij 中使用浮动/浏览器预览。
- 新 uv 项目先运行 `uv sync`，再直接打开 `nvim`。`.venv/bin/python` 会自动激活；需要临时切换环境时使用 `<leader>cv`。

## SSH 与提交签名

- GitHub 认证和 Git 提交签名使用 `~/.ssh/keys/` 下相互独立的 Ed25519 key。
- 签名公钥会加入 `~/.ssh/allowed_signers`；`gh` 已登录时，初始化脚本会尝试注册公钥。
- `features.use_1password` 只控制 SSH Agent 集成；Git 签名使用本地 OpenSSH key。
- 可在初始化前通过 `OP_SSH_AUTH_SOCK` 覆盖 1Password Agent socket。

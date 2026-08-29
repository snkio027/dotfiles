# Personal Developer Platform

一套由 `chezmoi` 驱动、面向 Apple Silicon macOS、Linux 与 Dev Container 的开发环境。设计重点是低延迟 Shell、一致的视觉语言、清晰的工具归属，以及本地与 CI 使用同一套验证标准。

## 技术栈

```text
State       │ chezmoi · Homebrew Bundle · Dev Container
Runtime     │ LLVM/CMake/Ninja · Zig · Go · Rust · Node · uv 项目 Python
Shell       │ Zsh · Starship · Atuin · direnv · zoxide · Carapace · fzf
Terminal    │ Ghostty（macOS）· Zellij（跨平台、按需）· Yazi · LazyGit
Editor      │ Neovim 0.12 · LazyVim 16 · LSP · Overseer · Neotest · DAP
Security    │ age · SOPS · SSH signing · gitleaks · Zizmor
Validation  │ actionlint · ShellCheck · shfmt · Taplo · Hadolint · StyLua
```

Homebrew 负责全局 CLI 与语言 Runtime；uv 负责项目 Python、虚拟环境、依赖，以及 Python 原生全局 CLI 的隔离工具环境（当前为 cxx-init）；Lazy 与 Mason 只管理 Neovim 内部插件和编辑器工具。Brewfile 与 uv tool 都不固定工具版本，更新时选择当前最新稳定版。Mason 每 24 小时检查并更新编辑器工具；Lazy 每天提示插件更新。不使用 mise、asdf、nvm、pyenv；项目仍应提交自身的版本声明与依赖锁文件。

## 平台支持边界

| 配置层 | macOS | Linux 工作站 | Dev Container |
| --- | --- | --- | --- |
| Homebrew/Linuxbrew、Zsh、CLI 与语言工具链 | 支持 | 支持 | 支持 |
| Neovim、LSP、格式化、测试与 DAP | 支持 | 支持 | 支持 |
| Zellij、Yazi 与 LazyGit | 支持 | 支持 | 支持 |
| Ghostty 安装、Cmd 快捷键与 Quick Terminal | 支持 | 不纳管 | 不纳管 |
| 1Password GUI、OrbStack、字体与系统偏好 | 支持 | 不纳管 | 不纳管 |

因此，“跨平台”指核心终端开发环境与编辑器工作流一致，不表示各系统的 GUI 应用完全相同。Linux 保留用户已有的终端模拟器；本仓库不会为 Linux 安装 Ghostty，也不会占用桌面环境的 Super 键。

## 体验设计

- `.zshenv` 只定义 XDG Base Directory；`.zprofile` 只初始化登录环境；`.zshrc` 只处理交互功能。
- Starship、Atuin、fzf、direnv、zoxide 与 Carapace 的生成脚本按二进制修改时间缓存，升级后自动刷新。
- Starship 使用 Quiet Ops Prompt：默认只显示目录、Git 状态和低频高价值反馈；语言、构建工具、包版本、Python 环境、容器、Docker context 与 Kubernetes 保持静默。非零退出只将输入箭头变红，后台任务数与超过 2 秒的命令耗时显示在第二行右侧。
- Ghostty 固定使用 Catppuccin Mocha 暗色主题；MonoLisa customizer 输出的 `MonoLisaCode Variable-cv04-cv08-ss03-ss07-ss11` 变量字体负责拉丁文字与真实字重/斜体，PingFang SC 负责中文，Maple Mono NF CN 是 Nerd Font 图标的首选 fallback，`Symbols Nerd Font Mono` 保留为单字符宽度末级兜底，并提供 GPU 渲染和原生分屏。
- Zellij 默认处于 locked mode，避免在 macOS 和 Linux 上占用 Shell、Neovim 的 Alt 快捷键。
- Zsh 将原生历史持久化到 `$XDG_STATE_HOME/zsh/history`；Atuin 独占 `Ctrl-R` 并负责加密同步，选中命令只回填供复核，fzf 仅管理 `Ctrl-T/Alt-C`。
- Neovim 是唯一编辑器；Git、Yazi、sudo、systemd 与 kubectl 的编辑入口统一指向 Neovim。
- Neovim/LazyVim、LazyGit、Yazi 与全部颜色配置均由 chezmoi 纳管。
- `icons/contract.toml` 是 Neovim `mini.icons` 与 eza 的版本化图标契约；87 项显式映射使用“精确文件名 > 扩展名 > 消费者默认值”的优先级，glyph 和 Catppuccin 语义 RGB 由同一份数据生成，不跟随任一工具的实时内置表漂移。
- Markdown 在普通模式渲染标题、任务、表格与代码块，插入模式自动显示原文；Ghostty 直连及其承载的 Zellij 0.45+ 会话均支持文档内图片、数学公式与 Mermaid 预览。
- markdownlint 全局保留结构与语义检查，仅关闭对表格、URL 和 CJK 文档噪音较大的 `MD013` 行宽规则。
- `CMakeLists.txt` 是 CMake 源文件而非 Markdown；neocmake 负责语义和 100 列诊断，gersemi 按同一宽度统一格式。
- `cxx init <name>` 从离线内置模板创建 C++23/CMake/Ninja 项目，生成后直接使用标准工具链，不依赖 cxx-init 运行。
- uv 项目中存在 `uv.lock` 和 `.venv` 时，Neovim 会自动将 Pyright、Ruff、DAP、Neotest 与内置终端统一到项目 Python。
- C/C++、Python、Zig、Go 与 Rust 共用 LSP、格式化、测试、任务和 DAP 工作流；项目的 `.vscode/launch.json` 也可直接复用。

## 目录

```text
dotfiles/
├── .chezmoiroot                    # 将 chezmoi source state 指向 home/
├── .devcontainer/                  # Ubuntu 26.04 + Linuxbrew 开发环境
├── .github/
│   ├── Brewfile                    # CI 最新稳定版校验工具
│   └── workflows/ci.yml            # 模板、配置、安全与供应链校验
├── Brewfile                        # Runtime、CLI、应用与字体
├── fonts/                          # 授权字体的公开特性清单（不包含字体文件）
├── icons/                           # 跨 Neovim/eza 的声明式 Icon Contract 与生成器
├── tests/fonts/                    # MonoLisa 清单与授权字体构建验证
├── tests/icons/                     # 72 类审计、87 项显式映射、字体与宽度验证
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
        ├── eza/theme.yml           # 由 Icon Contract 生成的文件图标主题
        ├── ghostty/                # macOS Ghostty 外观与宿主快捷键
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
| 状态 | `~/.local/state` | Zsh 历史、Neovim 日志及可跨会话恢复的状态 |
| 缓存 | `~/.cache` | Zsh 初始化缓存、补全、uv 与可安全重建的数据 |
| 可执行文件 | `~/.local/bin` | 用户级引导程序与脚本 |

`~/.zshenv`、`~/.zprofile`、`~/.zshrc` 是 Zsh 原生启动入口，`~/.ssh` 是 OpenSSH 固定发现位置，因此保留在 HOME。首次应用会把旧 `~/.zsh_history` 无损迁移到 XDG state，并保留兼容 symlink。Markdownlint 的 Zsh alias 与 Neovim 都显式加载 XDG 主配置，项目内规则仍可覆盖。Cargo 与 Go 保留各自官方数据目录，避免破坏已安装工具和升级机制。

## 初始化

```bash
chezmoi init --apply https://github.com/snkio027/dotfiles
```

初始化会询问 Git 姓名和邮箱，安装 Homebrew/Linuxbrew，按现有元数据安装 Brewfile 缺失依赖，配置 SSH 签名与 gitleaks hook，并在 macOS 上安装 Ghostty 及应用键盘、Finder、Dock 和截图偏好。日常 `chezmoi apply` 不更新 Homebrew 元数据、不主动批量升级已安装工具，也不会因 Ghostty 配置变化而重新应用 macOS defaults；安装新依赖所必需的依赖链升级仍由 Homebrew 决定，全量更新由 `brewup` 或 `devup` 显式触发。Linux 使用现有终端模拟器，只部署跨平台的 Shell、TUI 与 Neovim 配置。本地新建的长期 SSH key 必须由用户设置口令；启用 1Password Agent 时不会生成磁盘私钥。

Dev Container 使用 `CHEZMOI_PROFILE=devcontainer`，通过 Linuxbrew 获得同样的最新工具链，但不会生成宿主密钥、修改宿主 Git hooks 或应用 macOS 偏好。可用 `GIT_AUTHOR_NAME` 与 `GIT_AUTHOR_EMAIL` 覆盖缺省身份。

## 日常维护

```bash
devdoctor                         # 只读环境与工具来源诊断
scan-secrets                      # 扫描暂存内容中的凭据泄漏
chezmoi diff                      # 审核目标状态差异
chezmoi apply                     # 应用配置、安装缺失依赖；不主动全局升级
HOMEBREW_NO_AUTO_UPDATE=1 brew bundle install --no-upgrade --file="$(chezmoi source-path)/../Brewfile"
brewup                            # update + upgrade + cleanup
devup                             # 更新 Homebrew、cxx-init、Lazy lock 与 Mason 工具
python3 icons/generate.py --write # 修改契约后重建 Neovim、eza 与测试制品
python3 icons/generate.py --check # 验证生成制品未漂移
```

`devdoctor` 检查 Homebrew、chezmoi、age、SSH、gitleaks、语言 Runtime、LLVM/CMake/Ninja、cxx-init、IaC/Kubernetes CLI 和终端工具，并确认 Runtime 的实际路径来自 Homebrew；它不会自动修改系统。

Icon Contract 固定采用“精确文件名 > 扩展名 > 消费者默认值”的解析顺序。生成器拒绝重复键、非法码点、缺失颜色角色和非单字符宽度 glyph；CI 验证 `72/72` 审计范围、`87/87` 显式消费者映射、`47/72` 真实项目观察与 `45/45` 唯一 glyph 字体覆盖，并解析 Neovim 最终 highlight RGB。eza 的未知无扩展名文件、空目录、`.github` 与 `build` 专用图标，以及 `mini.icons` 的对应默认值，明确属于消费者上游观察，不进入 87 项共享映射；两者无法表达的空目录差异不会被假装成已统一。其余 25 类合成 fixture 不表述为真实项目样本；升级 eza 或 `mini.icons` 时只报告上游差异，不自动改写本仓库拥有的契约。

GitHub Actions 会在每次提交验证模板、Shell 行为、安全策略、macOS 配置、cxx-init 最新发布版的完整生成/构建/测试流程和 Dev Container 构建；每周一还会从空缓存同步上游最新 Neovim 插件与 Mason 工具，运行语义冒烟测试，并在插件锁落后时提示执行 `devup`。Dependabot 每周更新 GitHub Actions、Dev Container 与 Docker 基础镜像引用。

## 功能与快捷键速查

修饰键按作用层解释，不把 macOS 的物理按键名称与终端协议混用：

| 文档记法 | macOS | Linux | 作用范围 |
| --- | --- | --- | --- |
| `Cmd` | Command（⌘） | 无对应绑定 | 仅 macOS Ghostty 宿主快捷键 |
| `Alt` | Ghostty 中的左 Option（⌥）；右 Option 保留字符输入 | Alt | Shell 与 Zellij 收到的 Alt/Meta |
| `Ctrl` | Control | Ctrl | Shell、Neovim 与 Zellij |
| `<leader>` | 空格 | 空格 | 仅 Neovim |

除明确标为 macOS Ghostty 的 `Cmd` 项以外，本节的 Shell、Neovim 与 Zellij 快捷键均适用于 macOS 和 Linux。在 macOS 上换用其他终端模拟器时，需要自行启用“Option 作为 Alt/Meta”，否则 `Alt-C`、`Alt-F` 和 Zellij 的 Alt 快捷键可能不会发送预期序列。Zellij 默认处于 locked mode，不会在启动后立即占用 Shell 或 Neovim 按键。

### Shell 与终端工具

兼容性敏感的 `find`、`grep` 与 `cd` 保留原始语义；现代搜索使用 `ff`（fd）、`rgg`（ripgrep）和 `z`（zoxide）。交互展示命令仍会在工具存在时增强：`ls` → `eza`、`cat` → `bat`、`top` → `btop`、`vi`/`vim` → `nvim`。

Quiet Ops Prompt 将第一行留给位置与 Git 状态，第二行留给命令输入。Node、Go、Rust、Zig、C/C++、CMake、Helm、package、Python 环境、容器与 Kubernetes 信息默认永不显示；需要时使用对应工具的专用命令查询。

| 快捷键或命令 | 功能 |
| --- | --- |
| `Ctrl-R` | 使用 Atuin 检索加密同步历史；Enter 只回填命令行，复核后再执行 |
| `Ctrl-T` | 使用 FZF 选择文件并插入命令行 |
| `Alt-C` | 使用 FZF 选择并进入目录 |
| `Ctrl-F` | 接受完整的 Zsh 自动建议 |
| `Alt-F` | 向前移动/接受一个单词 |
| `ll` / `lt` | 详细文件列表 / 目录树 |
| `ff` / `rgg` | 使用 fd 查找路径 / 使用 ripgrep 检索内容 |
| `z <keyword>` / `cdi` | 按使用频率跳转目录 / 交互式选择目录 |
| `y` | 启动 Yazi，退出后进入最后访问的目录 |
| `mkcd <dir>` / `up <n>` | 创建并进入目录 / 向上跳转 n 层 |
| `port <port>` / `fkill [signal]` | 查找端口占用 / 模糊选择进程并默认发送 SIGTERM |
| `ghc <owner/repo>` | 克隆 GitHub 仓库 |
| `dotenv [file]` | 导出 `.env` 的字面量赋值；支持空值、整行注释和成对引号，拒绝命令替换、续行与非法键名 |
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
| `<leader>oo` / `<leader>ow` / `<leader>ot` | 运行任务 / 任务列表 / 对任务执行操作 |
| `<leader>gs` / `<leader>gd` | Git 状态 / 当前文件 Diff |
| `<leader>gc` / `<leader>gS` | 提交历史 / Stash |
| `lg` | 在终端中启动 LazyGit |

### 多语言开发环境

| 语言 | 语义、检查与格式化 | 构建、测试与调试 |
| --- | --- | --- |
| C/C++ | clangd、clang-tidy、clang-format | cxx-init、CMake、Ninja、ccache、Overseer、codelldb |
| Python | uv、Pyright、Ruff；`<leader>cT` 运行 `ty check` | pytest、Neotest、debugpy |
| Zig | zls、`zig fmt` | `zig build test`、Neotest、codelldb |
| Go | gopls、gofumpt、goimports、golangci-lint | `go test`、Neotest、Delve |
| Rust | rust-analyzer、rustaceanvim、rustfmt、Clippy | Cargo、Neotest、codelldb |

Mason 只安装编辑器侧的 LSP、格式化器与调试适配器；编译器和构建系统仍由 Homebrew 提供。C/C++ 的 clangd 与 clang-format 是例外：两者显式使用 Homebrew LLVM 的同一滚动版本，避免 Mason 与终端工具链发生版本漂移。CMake 使用 neocmake 与 gersemi，两者统一为 100 列；neocmake 保留内置语义和样式诊断，不再额外启动固定 80 列且维护停滞的 cmakelint。CMake 和通用任务输出统一进入 Overseer，测试统一进入 Neotest，原生语言统一使用 codelldb。调试配置优先读取项目的 `.vscode/launch.json`，也可以使用内置的 launch/attach 配置。

新建规范 C++ 项目时直接运行：

```bash
cxx init hello
cd hello
cmake --workflow --preset dev
```

模板内置 C++23、CMake Presets、Ninja、clangd、clang-format、clang-tidy、CTest 与 Sanitizer 配置；创建过程不访问网络，生成项目也不依赖 `cxx` 命令。

### Markdown 与 Python

Markdown 在普通、命令和终端模式渲染标题、任务、表格、代码块、图片和数学公式，进入插入模式后显示原始文本，兼顾阅读与编辑。

| 快捷键 | 功能 |
| --- | --- |
| `<leader>um` | 切换 Neovim 内 Markdown 渲染 |
| `<leader>cp` | 切换 Markdown 浏览器预览，适合 Mermaid 和 Zellij 会话 |
| `[[` / `]]` | 跳转到上一节 / 下一节 |
| `gO` | 打开 Markdown 文档大纲 |
| `<leader>cv` | 在 Python Buffer 中手动选择虚拟环境 |
| `<leader>cT` | 使用 ty 对整个 Python 项目做补充类型检查 |

打开 uv 项目的 Python 文件时，会依据 `uv.lock` 自动激活 `.venv/bin/python`，并把同一环境交给 Pyright、Ruff、DAP 与 Neotest；Ruff 负责 Lint 和 Import，Pyright 专注类型分析，避免重复诊断。

### Ghostty（macOS）与 Zellij（macOS/Linux）

Ghostty 固定使用 Catppuccin Mocha 暗色主题，并使用职责明确的字体栈：MonoLisa customizer 输出的 `MonoLisaCode Variable-cv04-cv08-ss03-ss07-ss11` 变量字体负责拉丁文字、代码、字重与斜体，PingFang SC 负责中文，Maple Mono NF CN 是 Nerd Font 图标的首选 fallback，`Symbols Nerd Font Mono` 保留为单字符宽度末级符号兜底。默认字面使用 MonoLisa 原生 `wght=600 / GRAD=25`，ANSI 强调使用 `wght=800 / GRAD=25`，斜体由独立 Italic 字形文件提供并使用相同的对应端点。OpenType 偏好记录在 `fonts/monolisa-opentype.toml`：启用标准/上下文连字、`cv04` 往返箭头、`cv08` 箭头、`ss03` 直立体 alternate g、`ss07` traditional `*` 与 `ss11` alternate braces；禁用 discretionary coding ligatures、slashed zero，以及其余 alternates。该策略由 MonoLisa customizer 固化到用户授权字体，并通过 `tests/fonts/test_monolisa_manifest.py --upright <font> --italic <font>` 验证；Ghostty 1.3 的 feature 会作用于全部 fallback，因此终端配置不直接设置 `font-feature`。配置同时关闭字体增重和合成字形，不额外缩放图标；fallback 仅按缺字与配置顺序发生，不按 Git、Prompt 或 Neovim 等语义强制分配，也不维护脆弱的码点映射。MonoLisa 字体文件不进入本仓库；Maple 与 Symbols Nerd Font 由 Brewfile 管理。终端同时提供透明模糊背景、10 万行回滚、剪贴板读取确认和失焦窗口长命令完成通知。Zellij 保留会话结构恢复，但不把 Pane 可见内容序列化到缓存。

Ghostty 标题文字同样使用授权的 MonoLisa customizer family；保留 macOS 红黄绿窗口按钮，隐藏只能显示或关闭、无法自定义的当前目录代理文件夹图标。

| 平台与程序 | 快捷键 | 功能 |
| --- | --- | --- |
| macOS · Ghostty | `Cmd-Alt-Space` | 显示/隐藏 Quick Terminal；此处 Alt 是左 Option |
| macOS · Ghostty | `Cmd-D` / `Cmd-Shift-D` | 向右 / 向下创建分屏 |
| macOS · Ghostty | `Cmd-H/J/K/L` | 在分屏间移动 |
| macOS · Ghostty | `Cmd-Z` | 放大/恢复当前分屏 |
| macOS/Linux · Zellij | `Ctrl-G` | 解锁或重新锁定 Zellij |
| macOS/Linux · Zellij | `Alt-H/J/K/L` | 在已解锁的 Pane 间移动 |
| macOS/Linux · Zellij | `Alt-N` / `Alt-F` | 新建 Pane / 切换浮动 Pane |
| macOS/Linux · Zellij | `Ctrl-P` / `Ctrl-T` | 进入 Pane / Tab 模式 |
| macOS/Linux · Zellij | `Ctrl-S`，然后 `e` | 进入滚动模式并用 Neovim 编辑滚动缓冲区 |
| macOS/Linux · Zellij | `Ctrl-O`，然后 `w` / `d` | 打开 Session Manager / Detach |

Ghostty 与 Zellij 0.45+ 均支持 Kitty Graphics Protocol；Zellij 会按 Pane 跟踪图片位置，因此内联图片在缩放、重排、滚动、全屏和浮动 Pane 中仍能正确显示。浏览器预览继续作为 Mermaid 交互查看和非兼容终端的通用回退。

### Git 同步、chezmoi 与维护

`git pull` 仅允许 fast-forward，不会隐式创建 Merge Commit 或自动 Rebase。需要把当前分支显式更新到远端主干时，分步执行：

```bash
git fetch origin
git rebase origin/main
```

`fetch.prune` 会在同步时清理已经从远端删除的跟踪引用；`rerere` 会复用曾经人工解决过的冲突；`zdiff3` 冲突标记会同时展示共同祖先。新分支首次执行 `git push` 时会自动建立 upstream，新仓库默认使用 `main`。

| 命令 | 功能 |
| --- | --- |
| `git lg` / `git st` / `git dfs` | 图形日志 / 状态 / 已暂存 Diff |
| `git amend` / `git undo` | 修改上次提交 / 撤销提交并保留文件 |
| `git rescue` | 查看 Reflog |
| `cz` / `cza` / `czd` | chezmoi 命令入口 / 应用目标状态 / 查看目标差异 |
| `cze` / `czu` | 编辑受管文件 / 更新并应用仓库 |
| `brewup` / `devup` | 更新并清理 Homebrew / 更新 Homebrew、cxx-init、Neovim 插件锁与 Mason 工具 |
| `devdoctor` | 只读检查配置、Runtime 来源、签名和关键工具 |
| `scan-secrets` | 使用 gitleaks 扫描暂存内容 |

## Neovim 文档与 Python 工作流

- Markdown 使用 `<leader>um` 切换 Neovim 内渲染，使用 `<leader>cp` 切换浏览器预览。Ghostty 与 Zellij 0.45+ 支持 Kitty Graphics Protocol，可在 Zellij Pane 中显示内联图片；浏览器预览适合 Mermaid 交互查看，也作为其他终端的回退方案。
- 新 uv 项目先运行 `uv sync`，再直接打开 `nvim`。`.venv/bin/python` 会自动激活；需要临时切换环境时使用 `<leader>cv`。

## SSH 与提交签名

- Workstation 默认启用 SSH 提交签名，但不再把所有 GitHub HTTPS URL 全局改写为 SSH；`ghc` 仍显式使用 SSH 克隆。
- Dev Container 不强制签名、不固定本地 IdentityFile，也不改写 URL，允许使用转发凭据或项目级 Git 配置。
- 本地模式使用 `~/.ssh/keys/` 下相互独立且有口令的 Ed25519 认证/签名 key；已有无口令 key 不会被脚本自动轮换。
- 缺少本地 key 时，非交互 `chezmoi apply` 会立即失败并提示操作方式，不会等待 `ssh-keygen` 输入。
- 启用 `features.use_1password` 后，SSH 统一使用 1Password Agent 且初始化脚本不生成私钥；导出的 `~/.ssh/keys/git_signing.pub` 会内联为 Git `key::` 配置，并在 apply 时验证 Agent 确实提供同一 key。
- `git.rewrite_github_https_to_ssh` 是显式 opt-in，默认关闭；可在初始化前通过 `OP_SSH_AUTH_SOCK` 覆盖 1Password Agent socket。
- 全局 Git ignore 只处理 OS 与编辑器垃圾；依赖缓存、环境文件和 SOPS/age 文件由仓库级 `.gitignore` 与 gitleaks 管理。

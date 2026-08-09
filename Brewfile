# ------------------------------------------------------------------------------
# 2026 Staff+ macOS Developer Workstation - Brewfile
# 基于 Homebrew Bundle 的声明式软件包管理
# 使用方式: brew bundle --file=~/dotfiles/Brewfile
# ------------------------------------------------------------------------------

# --- 核心基础设施与安全平面 ---
brew "chezmoi"          # Dotfiles 配置管理引擎
brew "age"              # 现代高性能加密工具
brew "sops"             # 结构化文件秘钥加密管理
brew "gitleaks"         # 本地与 CI 秘钥泄漏安全检测工具
cask "1password-cli"    # 1Password 命令行工具 (op)

# --- 编译工具链与基础依赖 (Neovim Treesitter 编译必需) ---
brew "gcc"              # GNU 编译器套件 (提供 C/C++ 语法树编译支持)

# --- 多语言运行时版本管理器 (替代 asdf / nvm / pyenv) ---
brew "mise"             # 基于 Rust 的多语言运行时管理器

# --- Shell 交互与提示符增强 ---
brew "starship"         # 极速响应式跨 Shell 提示符
brew "direnv"           # 基于目录的环境变量自动切换器
brew "atuin"            # 端到端加密 Shell 历史数据库
brew "carapace"         # 跨 CLI 现代上下文自动补全引擎
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"

# --- 路径跳转 ---
brew "zoxide"           # 智能目录跳转工具 (替代 cd)

# --- 现代 CLI 工具链替代方案 ---
brew "eza"              # 替代 ls (带图标与 Git 状态)
brew "bat"              # 替代 cat (带语法高亮与行号)
brew "fd"               # 替代 find (极速多线程搜索)
brew "ripgrep"          # 替代 grep (基于 Rust 的极速正则搜索)
brew "fzf"              # 通用命令行模糊搜索器
brew "jq"               # 命令行 JSON 处理工具
brew "yq"               # 命令行 YAML 处理工具
brew "htop"             # 交互式进程监控器
brew "btop"             # 现代图形化资源监控器

# --- Git 生态增强 ---
brew "git-delta"        # 语法高亮 Git Pager (Side-by-Side 对比)
brew "lazygit"          # Git 终端 GUI 客户端 (可视交互与 Rebase)

# --- 开发者工具链 ---
brew "git"              # 分布式版本控制系统
brew "gh"               # GitHub 官方命令行工具
brew "zellij"           # 终端工作区复用器 (替代 tmux)
brew "yazi"             # 极速 TUI 文件管理器 (带图片预览)
brew "neovim"           # 高度可扩展的现代 Vim 编辑器
brew "uv"               # 极速 Python 包与虚拟环境管理器
brew "rustup-init"      # Rust 工具链安装器

# --- macOS Cask 图形化应用 ---
cask "ghostty"          # GPU 加速的原生终端模拟器
cask "1password"        # 密码管理器与 SSH Agent 凭据提供商
cask "orbstack"         # 轻量极速 Docker 容器与 Linux 虚拟机运行时

# --- Terminal & Starship Nerd Fonts ---
cask "font-jetbrains-mono-nerd-font"
cask "font-inter"

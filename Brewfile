# ------------------------------------------------------------------------------
# macOS / Linux Developer Workstation Brewfile
# 基于 Homebrew Bundle 的跨平台声明式软件包管理
# 使用方式: brew bundle --file="$(chezmoi source-path)/../Brewfile"
# ------------------------------------------------------------------------------

# --- 核心基础设施与安全平面 ---
brew "chezmoi"          # Dotfiles 配置管理引擎
brew "age"              # 现代高性能加密工具
brew "sops"             # 结构化文件秘钥加密管理
brew "gitleaks"         # 本地与 CI 秘钥泄漏安全检测工具
cask "1password-cli" if OS.mac?  # 1Password 命令行工具 (op)

# --- 最新稳定版语言 Runtime、编译工具与平台工具（不固定版本）---
tap "hashicorp/tap"
brew "node"                      # 最新稳定版 Node.js
brew "python"                    # 最新稳定版 Python
brew "go"                        # 最新稳定版 Go
brew "rust"                      # 最新稳定版 Rust 与 Cargo
brew "rust-analyzer"             # Rust IDE / Neovim 语义支持
brew "zig"                       # 最新稳定版 Zig 编译器
brew "llvm"                      # C/C++ Clang/LLVM 工具链
brew "cmake"                     # 跨平台 C/C++ 构建系统
brew "ninja"                     # CMake 高性能构建后端
brew "ccache"                    # C/C++ 增量编译缓存
brew "pkgconf"                   # 跨平台原生依赖发现
brew "uv"                        # 极速 Python 包与虚拟环境管理器
brew "hashicorp/tap/terraform"   # 最新稳定版 Terraform
brew "kubernetes-cli"            # 最新稳定版 kubectl
brew "helm"                      # 最新稳定版 Helm

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
brew "btop"             # 现代图形化资源监控器
brew "duf"              # 现代磁盘空间概览
brew "dust"             # 可视化目录空间分析
brew "sd"               # 直观的 sed 替代品
brew "xh"               # 现代 HTTP 客户端
brew "wget"             # Mason/CI 下载器与 curl 故障回退

# --- Git 生态增强 ---
brew "git-delta"        # 语法高亮 Git Pager (Side-by-Side 对比)
brew "lazygit"          # Git 终端 GUI 客户端 (可视交互与 Rebase)

# --- 开发者工具链 ---
brew "git"              # 分布式版本控制系统
brew "gh"               # GitHub 官方命令行工具
brew "zellij"           # 终端工作区复用器 (替代 tmux)
brew "yazi"             # 极速 TUI 文件管理器 (带图片预览)
brew "neovim"           # 高度可扩展的现代 Vim 编辑器
brew "tree-sitter-cli"  # Neovim Tree-sitter 解析器工具链
brew "imagemagick"      # Snacks/Yazi 文档与图片预览转换
brew "mermaid-cli"      # Markdown Mermaid 图表渲染
brew "typst"            # Markdown 数学公式与现代文档渲染

# --- 配置质量、性能基准与供应链检查 ---
brew "hyperfine"        # 命令行性能基准
brew "watchexec"        # 文件变化驱动任务执行
brew "shellcheck"       # Shell 静态分析
brew "shfmt"            # Shell 格式化
brew "stylua"           # Lua 格式化与语法一致性
brew "actionlint"       # GitHub Actions 校验
brew "taplo"            # TOML 校验与格式化
brew "hadolint"         # Dockerfile 静态分析
brew "zizmor"           # GitHub Actions 安全审计

# --- macOS Cask 图形化应用 ---
cask "ghostty" if OS.mac?    # GPU 加速的原生终端模拟器
cask "1password" if OS.mac?  # 密码管理器与 SSH Agent 凭据提供商
cask "orbstack" if OS.mac?   # 轻量极速 Docker 容器与 Linux 虚拟机运行时

# --- Terminal & Starship Nerd Fonts ---
cask "font-maple-mono-nf-cn" if OS.mac?          # Ghostty 首选 Nerd 图标 fallback 及 CJK 备选
cask "font-jetbrains-mono-nerd-font" if OS.mac?
cask "font-symbols-only-nerd-font" if OS.mac?     # Ghostty 单字符宽度末级 fallback
cask "font-inter" if OS.mac?

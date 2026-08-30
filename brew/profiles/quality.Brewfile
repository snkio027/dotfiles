# ------------------------------------------------------------------------------
# Generated Brewfile profile: quality
# GitHub Actions 使用的最小验证工具链
# Source of truth: brew/ownership.toml (run: python3 brew/generate.py --write)
# ------------------------------------------------------------------------------

# --- owner: core ---
brew "chezmoi"  # Dotfiles 配置管理引擎
brew "cmake"  # 跨平台 C/C++ 构建系统
brew "llvm"  # C/C++ Clang/LLVM 工具链
brew "neovim"  # Neovim
brew "ninja"  # CMake 高性能构建后端
brew "python"  # 最新稳定版 Python
brew "tree-sitter-cli"  # Tree-sitter 解析器工具链
brew "uv"  # Python 包与虚拟环境管理

# --- owner: workstation ---
brew "atuin"  # Shell 历史
brew "eza"  # 现代 ls
brew "fd"  # 文件搜索
brew "fzf"  # 模糊搜索
brew "lazygit"  # Git TUI
brew "ripgrep"  # 文本搜索
brew "starship"  # Quiet Ops Prompt
brew "yazi"  # 文件管理器
brew "zellij"  # 终端工作区复用器
brew "zsh-autosuggestions"  # Zsh 自动建议
brew "zsh-syntax-highlighting"  # Zsh 语法高亮
cask "font-maple-mono-nf-cn" if OS.mac?  # Nerd 图标与 CJK fallback
cask "font-symbols-only-nerd-font" if OS.mac?  # 末级 Nerd Symbols fallback
cask "ghostty" if OS.mac?  # macOS 终端与配置验证

# --- owner: devcontainer ---
brew "wget"  # Mason/CI 下载器与 curl 故障回退
brew "zsh"  # Linux 工作站与 Dev Container Shell；不修改登录 Shell

# --- owner: quality ---
brew "actionlint"  # GitHub Actions 校验
brew "devcontainer"  # CI Dev Container lifecycle 客户端
brew "gitleaks"  # 凭据泄漏扫描
brew "hadolint"  # Dockerfile 静态分析
brew "shellcheck"  # Shell 静态分析
brew "shfmt"  # Shell 格式化
brew "stylua"  # Lua 格式化
brew "taplo"  # TOML 校验与格式化
brew "zizmor"  # GitHub Actions 安全审计

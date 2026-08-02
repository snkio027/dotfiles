# ------------------------------------------------------------------------------
# Zsh 别名与人机工程学快捷键
# 现代 CLI 工具映射与高频开发命令
# 由 chezmoi 托管
# ------------------------------------------------------------------------------

# --- 1. 快速目录层级穿梭 ---
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../../.."

# --- 1.5 个人标准 7 大工作区快速导航 (Workspace Shortcuts) ---
alias ws="cd ~/Workspace"
alias w1="cd ~/Workspace/01_Vault"
alias w2="cd ~/Workspace/02_Platform"
alias w3="cd ~/Workspace/03_Projects"
alias w4="cd ~/Workspace/04_Lab"
alias w5="cd ~/Workspace/05_Architecture"
alias w6="cd ~/Workspace/06_Data"
alias w7="cd ~/Workspace/07_Archive"
alias dataclean="rm -rf ~/Workspace/06_Data/scratch/*"

# --- 2. 现代 Rust CLI 工具链映射 ---
if command -v eza &>/dev/null; then
    alias ls="eza --icons=auto --group-directories-first"
    alias ll="eza -la --icons=auto --git --group-directories-first"
    alias lt="eza --tree --level=2 --icons=auto"
fi

if command -v bat &>/dev/null; then
    alias cat="bat --paging=never --style=plain"
fi

if command -v fd &>/dev/null; then
    alias find="fd"
fi

if command -v rg &>/dev/null; then
    alias grep="rg"
fi

if command -v btop &>/dev/null; then
    alias top="btop"
    alias htop="btop"
fi

if command -v nvim &>/dev/null; then
    alias vi="nvim"
    alias vim="nvim"
fi

# --- 3. zoxide 智能目录跳转 (替代 cd) ---
if command -v zoxide &>/dev/null; then
    alias cd="z"
    alias cdi="zi"
fi

# --- 4. chezmoi 配置管理快捷别名 ---
alias cz="chezmoi"
alias cza="chezmoi apply"
alias czcd="chezmoi cd"
alias czd="chezmoi diff"
alias cze="chezmoi edit"
alias czu="chezmoi update"
alias cm="chezmoi"
alias cma="chezmoi apply"

# --- 5. 高效率 Git 操作快捷键 ---
alias g="git"
alias gs="git status"
alias gd="git diff"
alias gds="git diff --staged"
alias gl="git lg"          # 使用 dot_gitconfig.tmpl 中定义的格式化日志别名
alias gla="git lla"
alias gco="git checkout"
alias gcb="git checkout -b"
alias gcm="git commit -m"
alias gcan="git commit --amend --no-edit"
alias gpf="git push --force-with-lease"
alias gst="git stash"
alias gstp="git stash pop"

# --- 6. Lazygit 终端客户端 ---
if command -v lazygit &>/dev/null; then
    alias lg="lazygit"
fi

# --- 7. 开发者实用快捷命令 ---
alias reload="exec zsh"
alias brewup="brew update && brew upgrade && brew cleanup"
alias mise-up="mise self-update && mise upgrade"

# --- 8. Yazi 推出自动切换目录 Hook (离开 Yazi 时自动 cd 至最后所在的目录) ---
function y() {
    local tmp cwd
    tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}

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
    alias ff="fd"
fi

if command -v rg &>/dev/null; then
    alias rgg="rg"
fi

if command -v btop &>/dev/null; then
    alias top="btop"
    alias htop="btop"
fi

if command -v nvim &>/dev/null; then
    alias vi="nvim"
    alias vim="nvim"
fi

if command -v markdownlint-cli2 &>/dev/null; then
    # --config 作为基础配置；仓库内更近的配置仍会按 markdownlint-cli2 规则覆盖。
    alias markdownlint-cli2='markdownlint-cli2 --config "${XDG_CONFIG_HOME:-$HOME/.config}/markdownlint-cli2/config.yaml"'
fi

# --- 3. zoxide 智能目录跳转 ---
if command -v zoxide &>/dev/null; then
    alias cdi="zi"
fi

# --- 4. chezmoi 配置管理快捷别名 ---
alias cz="chezmoi"
alias cza="chezmoi apply"
alias czcd="chezmoi cd"
alias czd="chezmoi diff"
alias czu="chezmoi update"
alias cm="chezmoi"
alias cma="chezmoi apply"

# --- 5. 高效率 Git 操作快捷键 ---
alias g="git"
alias gs="git status"
alias gd="git diff"
alias gds="git diff --staged"
alias gl="git lg"          # 使用 XDG Git 全局配置中定义的格式化日志别名
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

# --- 7. 开发者实用快捷命令与平台诊断 ---
alias reload="exec zsh"
alias brewup="brew update && brew upgrade && brew cleanup"
alias doctor='bash "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/scripts/doctor.sh"'
alias devdoctor='bash "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/scripts/doctor.sh"'
alias scan-secrets="gitleaks git --pre-commit --staged --redact --verbose ."

# 更新全局 Homebrew 工具、Neovim 插件锁和 Mason 编辑器工具。Lazy 在
# chezmoi source state 上运行，确保更新后的 lockfile 可直接审阅和提交。
function devup() {
    local source_config
    brew update && brew upgrade || return
    source_config="$(chezmoi source-path)/dot_config" || return
    XDG_CONFIG_HOME="$source_config" nvim --headless "+Lazy! sync" +qa &&
        XDG_CONFIG_HOME="$source_config" nvim --headless "+MasonToolsUpdateSync" +qa
}

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

# --- 9. 高频 Developer DX 快捷函数 ---
function mkcd() { mkdir -p "$1" && builtin cd -- "$1"; }
function up() {
    local count="${1:-1}" destination="" index
    [[ "$count" =~ '^[1-9][0-9]*$' ]] || {
        print -u2 "用法: up <正整数>"
        return 2
    }
    for ((index = 0; index < count; index++)); do
        destination+="../"
    done
    builtin cd -- "$destination"
}
function port() { lsof -i :"$1"; }
function ghc() { git clone "git@github.com:$1.git"; }
# 支持空行、整行注释、可选 export、KEY=value、空值及成对单/双引号。
# 值按字面量导出；拒绝命令替换、反引号、续行、非法键名与不成对引号。
function dotenv() {
    local file="${1:-.env}" line trimmed key value
    local -A values

    [[ -f "$file" && -r "$file" && ! -L "$file" ]] || {
        print -u2 "dotenv: 需要可读的非符号链接文件: $file"
        return 1
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -n "$line" && "${line[-1]}" == "\\" ]] && {
            print -u2 "dotenv: 不支持续行: $line"
            return 2
        }
        trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$trimmed" || "${trimmed[1]}" == "#" ]] && continue

        if [[ "$trimmed" == export[[:space:]]* ]]; then
            trimmed="${trimmed#export}"
            trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
        fi
        [[ "$trimmed" == *"="* ]] || {
            print -u2 "dotenv: 非法赋值: $line"
            return 2
        }

        key="${trimmed%%=*}"
        value="${trimmed#*=}"
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        [[ "$key" =~ '^[A-Za-z_][A-Za-z0-9_]*$' ]] || {
            print -u2 "dotenv: 非法变量名: $key"
            return 2
        }

        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        [[ "$value" == *'$('* || "$value" == *'`'* ]] && {
            print -u2 "dotenv: 不允许命令替换: $key"
            return 2
        }
        if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
            value="${value[2,-2]}"
        elif [[ "$value" == \"* || "$value" == *\" || "$value" == \'* || "$value" == *\' ]]; then
            print -u2 "dotenv: 引号不匹配: $key"
            return 2
        fi
        values[$key]="$value"
    done < "$file"

    for key in "${(@k)values}"; do
        export "$key=${values[$key]}"
    done
}
function cze() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        command -v fzf &>/dev/null || {
            print -u2 "cze: 未安装 fzf"
            return 1
        }
        target="$(chezmoi managed | fzf --prompt='chezmoi edit> ')" || return
    fi
    [[ -n "$target" ]] && chezmoi edit "$target"
}
function dataclean() {
    local scratch="$HOME/Workspace/06_Data/scratch"
    [[ -d "$scratch" ]] || { print -u2 "目录不存在: $scratch"; return 1; }
    read -q "REPLY?确认清空 $scratch？[y/N] " || { print; return 1; }
    print
    command rm -rf -- "$scratch"/*(DN)
}
function fkill() {
    local signal="${1:-TERM}" selection pid
    [[ "$signal" =~ '^[A-Za-z][A-Za-z0-9]*$|^[0-9]+$' ]] || {
        print -u2 "fkill: 非法信号: $signal"
        return 2
    }
    selection="$(ps -Ao pid=,command= | fzf --no-multi --prompt='kill> ')" || return
    pid="$(awk '{print $1}' <<< "$selection")"
    [[ "$pid" =~ '^[0-9]+$' ]] && kill -"$signal" "$pid"
}

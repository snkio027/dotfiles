# ------------------------------------------------------------------------------
# Zsh 插件、Shell 选项、钩子与瞬时提示符
# 由 chezmoi 托管 | DevSecOps 生产级 Profile
# ------------------------------------------------------------------------------

# --- 1. Zsh Shell 行为选项设置 ---
setopt AUTO_CD              # 输入目录路径直接 cd 进入
setopt HIST_IGNORE_DUPS     # 忽略连续重复的历史命令
setopt HIST_REDUCE_BLANKS   # 移除历史命令中多余的空格
setopt SHARE_HISTORY        # 多个终端会话间实时共享历史
setopt EXTENDED_HISTORY     # 记录命令执行的时间戳
setopt INTERACTIVE_COMMENTS # 允许在交互式命令行中使用 # 注释

# 环境变量卫生
export HOMEBREW_NO_ENV_HINTS=1
export PYTHONWARNINGS="ignore::SyntaxWarning"

# 自动从 macOS Keychain 钥匙串加载已保存的 SSH Key 到 agent
ssh-add --apple-load-keychain 2>/dev/null || true

# --- 2. 补全引擎缓存加速与美化 ---
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'

# --- 3. 键盘按键绑定与 zsh-autosuggestions 渐进式接受按键 ---
bindkey '^[[A' up-line-or-search
bindkey '^[[B' down-line-or-search

# zsh-autosuggestions 快捷键: Ctrl+F 接受整行建议，Alt+F 接受下一个单词
bindkey '^F' autosuggest-accept
bindkey '^[f' autosuggest-accept-word

# --- 4. 运行时与工具链钩子 ---

# mise: 多语言版本管理器
if command -v mise &>/dev/null; then
    eval "$(mise activate zsh)"
fi

# zoxide: 智能目录跳转
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
fi

# --- 5. Starship 瞬时提示符 (Transient Prompt) ---
# 确保在 Atuin 之后加载，避免 ZLE 钩子碰撞，按下回车后将已执行的历史行强行收缩为 ❯ 静态短箭头
if command -v starship &>/dev/null; then
    eval "$(starship init zsh)"

    export STARSHIP_THEME="$PROMPT"

    _starship_transient_precmd() {
        PROMPT="$STARSHIP_THEME"
    }

    _starship_transient_accept_line() {
        [[ -n "$POSTDISPLAY" ]] && POSTDISPLAY=""
        PROMPT="%(?.%F{green}❯%f.%F{red}❯%f) "
        RPROMPT=""
        zle .reset-prompt
        zle .accept-line
    }

    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _starship_transient_precmd
    zle -N accept-line _starship_transient_accept_line
fi

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
unsetopt PROMPT_SP          # 关闭无换行符脚本输出时的 % 符号与空格填充
# 注意: PROMPT_CR 必须保留启用 (不 unsetopt) —— 它负责在绘制提示符前输出 \r 将光标归位第 0 列
# 关闭 PROMPT_CR 会导致子进程输出末尾无 \n 时光标停在中间列，造成后续文字右移错位

# 环境变量与 Hook 卫生
export HOMEBREW_NO_ENV_HINTS=1
export DIRENV_LOG_FORMAT=""  # 屏蔽 direnv 进入目录时的冗长日志输出
export MISE_QUIET=1          # 屏蔽 mise 内部钩子静默输出
export PYTHONWARNINGS="ignore::SyntaxWarning"

# 自动从 macOS Keychain 钥匙串加载已保存的 SSH Key 到 agent
ssh-add --apple-load-keychain 2>/dev/null || true

# --- 2. 补全引擎缓存加速与美化 ---
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
autoload -Uz compinit
ZCOMPDUMP="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
if [[ -n "${ZCOMPDUMP}"(#qN.mh+24) ]]; then
    compinit -d "${ZCOMPDUMP}"
else
    compinit -C -d "${ZCOMPDUMP}"
fi

zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'

# --- 3. 键盘按键绑定与 zsh-autosuggestions 渐进式接受按键 ---
bindkey '^[[A' up-line-or-search
bindkey '^[[B' down-line-or-search

# zsh-autosuggestions 快捷键: Ctrl+F 接受整行建议，Alt+F 接受下一个单词
bindkey '^F' autosuggest-accept
bindkey '^[f' forward-word

# --- 4. 运行时与工具链钩子 ---

# mise: 多语言版本管理器
if command -v mise &>/dev/null; then
    eval "$(mise activate zsh)"
fi

# zoxide: 智能目录跳转
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
fi

# carapace: 跨 CLI 现代上下文自动补全引擎
if command -v carapace &>/dev/null; then
    export CARAPACE_BRIDGES='zsh,fish,bash'
    eval "$(carapace _carapace)"
fi

# 避免末尾缺少换行符的命令输出在行首打出反色 % 符号
PROMPT_EOL_MARK=""

# --- 5. Starship 响应式提示符 ---
if command -v starship &>/dev/null; then
    eval "$(starship init zsh)"
fi

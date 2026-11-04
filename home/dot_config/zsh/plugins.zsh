# ------------------------------------------------------------------------------
# Zsh 插件、Shell 选项、钩子与瞬时提示符
# 由 chezmoi 托管 | DevSecOps 生产级 Profile
# ------------------------------------------------------------------------------

# --- 1. Zsh 原生历史持久化与 Shell 行为选项 ---
typeset -g HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
typeset -g HISTSIZE=200000
typeset -g SAVEHIST=100000

# 旧 Shell 仍持有 ~/.zsh_history，默认原子重写会替换旧迁移留下的 symlink。
# 新会话沿用同一路径，不在启动时移动、合并或删除任一历史文件。
# 只接管普通旧文件与指向当前 XDG 历史的绝对 symlink；自定义链接保持原样。
_zsh_history_dir="${HISTFILE:h}"
_zsh_legacy_history="$HOME/.zsh_history"
if [[ -L "$_zsh_legacy_history" ]]; then
    _zsh_history_target="$(command readlink "$_zsh_legacy_history" 2>/dev/null)" || _zsh_history_target=''
    # '..' 穿过目录 symlink 时不能按字符串折叠；这类路径只接受完全相同的目标。
    if [[ "$_zsh_history_target" == /* && ( "$_zsh_history_target" == "$HISTFILE" ||
        ( "$_zsh_history_target/" != */../* && "$HISTFILE/" != */../* &&
          "${_zsh_history_target:a}" == "${HISTFILE:a}" ) ) ]]; then
        HISTFILE="$_zsh_legacy_history"
    fi
fi
# 同时涵盖读取 symlink 期间被旧 Shell 原子重写为普通文件的情况。
if [[ ! -L "$_zsh_legacy_history" && -f "$_zsh_legacy_history" ]]; then
    HISTFILE="$_zsh_legacy_history"
    _zsh_history_dir="$HOME"
fi
unset _zsh_legacy_history _zsh_history_target

# Atuin 是主要检索界面，但原生历史仍是 Shell 降级与 fzf/`fc` 的可恢复底座。
if [[ ! -d "$_zsh_history_dir" ]]; then
    command mkdir -p -- "$_zsh_history_dir" 2>/dev/null || true
    command chmod 700 -- "$_zsh_history_dir" 2>/dev/null || true
fi
unset _zsh_history_dir

setopt AUTO_CD              # 输入目录路径直接 cd 进入
setopt APPEND_HISTORY       # 追加写入而不覆盖现有历史
setopt HIST_IGNORE_DUPS     # 忽略连续重复的历史命令
setopt HIST_SAVE_NO_DUPS    # 持久化时不重复写入已有命令
setopt HIST_EXPIRE_DUPS_FIRST # 容量收缩时优先清理重复项
setopt HIST_FIND_NO_DUPS    # 原生检索不重复展示同一命令
setopt HIST_FCNTL_LOCK      # 使用 fcntl 降低多会话并发写入冲突
setopt HIST_REDUCE_BLANKS   # 移除历史命令中多余的空格
setopt SHARE_HISTORY        # 多个终端会话间实时共享历史
setopt EXTENDED_HISTORY     # 记录命令执行的时间戳
setopt INTERACTIVE_COMMENTS # 允许在交互式命令行中使用 # 注释
setopt PROMPT_SP            # 保留没有末尾换行的输出；提示标记由 PROMPT_EOL_MARK 单独隐藏
# 注意: PROMPT_CR 必须保留启用 (不 unsetopt) —— 它负责在绘制提示符前输出 \r 将光标归位第 0 列
# 关闭 PROMPT_CR 会导致子进程输出末尾无 \n 时光标停在中间列，造成后续文字右移错位

# 环境变量与 Hook 卫生
export HOMEBREW_NO_ENV_HINTS=1

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

# 避免末尾缺少换行符的命令输出在行首打出反色 % 符号
PROMPT_EOL_MARK=""

-- ------------------------------------------------------------------------------
-- Neovim Lua Starter 基础配置与 lazy.nvim 插件引导
# 由 chezmoi 托管 | DevSecOps 生产级 Profile
-- ------------------------------------------------------------------------------

-- 1. 自动 Bootstrap lazy.nvim 插件管理器
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local lazyrepo = "https://github.com/folke/lazy.nvim.git"
    local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({
            { "克隆 lazy.nvim 失败:\n", "ErrorMsg" },
            { out, "WarningMsg" },
            { "\n按任意键退出..." },
        }, true, {})
        vim.fn.getchar()
        os.exit(1)
    end
end
vim.opt.rtp:prepend(lazypath)

-- 2. 编辑器基础行为选项
vim.opt.number = true           -- 显示绝对行号
vim.opt.relativenumber = true   -- 显示相对行号 (方便 Vim 相对跳转)
vim.opt.expandtab = true        -- 空格替代 Tab
vim.opt.shiftwidth = 4          -- 缩进空格数
vim.opt.tabstop = 4             -- Tab 对应空格数
vim.opt.smartindent = true      -- 智能缩进
vim.opt.termguicolors = true   -- 开启 24 位真彩色
vim.opt.ignorecase = true       -- 搜索忽略大小写
vim.opt.smartcase = true        -- 包含大写字母时自动转为大小写敏感
vim.opt.updatetime = 250        -- 提高磁盘写入与 UI 刷新响应速率
vim.opt.signcolumn = "yes"      -- 始终显示左侧标记列 (防止 Git 标志闪烁)
vim.opt.clipboard = "unnamedplus" -- 与系统剪贴板共享

-- 3. Leader 前缀键配置
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- 4. 肌肉记忆人机工程学快捷键
local map = vim.keymap.set
map("n", "<Leader>w", ":w<CR>", { desc = "保存当前文件" })
map("n", "<Leader>q", ":q<CR>", { desc = "退出 Neovim" })
map("n", "<Leader>bd", ":bdelete<CR>", { desc = "安全关闭当前 Buffer" })
map("n", "<Leader>e", ":Explore<CR>", { desc = "唤出 Netrw 文件管理器" })
map("n", "<Esc>", ":noh<CR>", { desc = "高亮搜索结果清除" })

-- 5. 初始化 Lazy 插件套件
require("lazy").setup({
    -- Catppuccin 色彩主题
    { "catppuccin/nvim", name = "catppuccin", priority = 1000, config = function()
        vim.cmd.colorscheme("catppuccin-mocha")
    end },
    -- 底部状态栏
    { "nvim-lualine/lualine.nvim", config = function()
        require("lualine").setup({ options = { theme = "catppuccin" } })
    end },
    -- 快捷键提示面板
    { "folke/which-key.nvim", event = "VeryLazy", config = true },
    -- Telescope 模糊搜索器
    {
        "nvim-telescope/telescope.nvim",
        dependencies = { "nvim-lua/plenary.nvim" },
        keys = {
            { "<Leader>ff", "<cmd>Telescope find_files<cr>", desc = "全局查找文件" },
            { "<Leader>fg", "<cmd>Telescope live_grep<cr>", desc = "全局搜索文本 (Live Grep)" },
            { "<Leader>fb", "<cmd>Telescope buffers<cr>", desc = "展开已打开 Buffer 列表" },
        },
    },
    -- Treesitter 语法高亮引擎
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        config = function()
            require("nvim-treesitter.configs").setup({
                ensure_installed = { "lua", "vim", "bash", "json", "yaml", "toml", "markdown", "rust", "zig", "python", "go" },
                highlight = { enable = true },
            })
        end,
    },
}, {})

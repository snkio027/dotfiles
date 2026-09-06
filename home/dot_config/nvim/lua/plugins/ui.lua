return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd.colorscheme("tokyonight-storm")
    end,
    opts = {
      style = "storm",
      on_highlights = function(highlights, colors)
        require("theme").apply_host_overlay(highlights, colors)
      end,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "tokyonight-storm" },
  },
  {
    "folke/noice.nvim",
    opts = {
      -- Language servers can emit frequent progress completions while editing.
      -- Diagnostics, completion, hover and signature help remain enabled.
      lsp = { progress = { enabled = false } },
    },
  },
  {
    "nvim-mini/mini.icons",
    opts = require("config.icon_contract"),
  },
  {
    "folke/snacks.nvim",
    opts = {
      indent = { enabled = true, animate = { enabled = false } },
      picker = {
        icons = {
          files = {
            dir = " ",
            dir_open = " ",
          },
        },
      },
      scroll = { enabled = true, animate = { duration = { step = 10, total = 120 } } },
    },
  },
}

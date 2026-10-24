return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    config = function(_, opts)
      require("catppuccin").setup(opts)
      vim.cmd.colorscheme("catppuccin")
    end,
    opts = {
      flavour = "mocha",
      -- Snacks uses diagnostic groups for Git status filenames. Keep their
      -- colors without switching Maple Mono to its cursive italic face.
      lsp_styles = {
        virtual_text = {
          errors = { "nocombine" },
          hints = { "nocombine" },
          warnings = { "nocombine" },
          information = { "nocombine" },
          ok = { "nocombine" },
        },
        inlay_hints = {
          background = false,
        },
      },
      custom_highlights = function(colors)
        return require("theme").highlights(colors)
      end,
      integrations = {
        blink_cmp = true,
        fzf = false,
        gitsigns = true,
        mason = true,
        native_lsp = { enabled = true },
        render_markdown = true,
        snacks = true,
        treesitter = true,
        which_key = true,
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "catppuccin" },
  },
  {
    "folke/noice.nvim",
    init = function()
      LazyVim.on_load("noice.nvim", function()
        require("config.clangd_documentation").setup_noice()
      end)
    end,
    opts = {
      -- Language servers can emit frequent progress completions while editing.
      -- Diagnostics, completion, hover and signature help remain enabled.
      lsp = {
        progress = { enabled = false },
        -- K documentation and signature help share the same reading surface.
        documentation = {
          opts = {
            border = { style = "rounded" },
            position = { row = 2, col = 2 },
            size = { max_width = 90 },
          },
        },
      },
    },
  },
  {
    "saghen/blink.cmp",
    opts = {
      completion = {
        menu = { border = "rounded" },
        documentation = {
          window = { border = "rounded" },
          draw = function(opts)
            require("config.clangd_documentation").draw(opts)
          end,
        },
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        float = { border = "rounded", max_width = 90 },
      },
    },
  },
  {
    "folke/which-key.nvim",
    opts = {
      -- Auto-triggering Normal-mode `g` can split native gcc into gc + c
      -- (upstream #968). Keep native dispatch; :WhichKey g still shows help.
      triggers = {
        { "<auto>", mode = "xso" },
        { "<leader>", mode = "n" },
        { "<localleader>", mode = "n" },
        { "<C-w>", mode = "n" },
        { "z", mode = "n" },
        { "[", mode = "n" },
        { "]", mode = "n" },
        { "<", mode = "n" },
        { ">", mode = "n" },
      },
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

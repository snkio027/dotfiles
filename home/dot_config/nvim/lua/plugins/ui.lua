return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      flavour = "mocha",
      integrations = {
        blink_cmp = true,
        fzf = true,
        gitsigns = true,
        mason = true,
        native_lsp = { enabled = true },
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
    "nvim-mini/mini.icons",
    opts = {
      default = {
        directory = { glyph = "", hl = "MiniIconsAzure" },
      },
      directory = {
        doc = { glyph = "", hl = "MiniIconsAzure" },
        docs = { glyph = "", hl = "MiniIconsAzure" },
        lib = { glyph = "", hl = "MiniIconsAzure" },
        test = { glyph = "", hl = "MiniIconsAzure" },
        tests = { glyph = "", hl = "MiniIconsAzure" },
      },
      extension = {
        sh = { glyph = "", hl = "MiniIconsGreen" },
        txt = { glyph = "", hl = "MiniIconsGrey" },
        yaml = { glyph = "", hl = "MiniIconsGrey" },
        yml = { glyph = "", hl = "MiniIconsGrey" },
      },
      file = {
        [".gitignore"] = { glyph = "󰊢", hl = "MiniIconsGrey" },
        LICENSE = { glyph = "", hl = "MiniIconsGrey" },
        ["README.md"] = { glyph = "󰂺", hl = "MiniIconsYellow" },
      },
    },
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

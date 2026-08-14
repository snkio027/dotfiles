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
      },
      custom_highlights = function(colors)
        return {
          -- Markdown should read like a document, not a collection of badges.
          RenderMarkdownCodeInline = { fg = colors.peach, bg = "NONE" },
          RenderMarkdownDash = { fg = colors.surface1 },
          RenderMarkdownQuote = { fg = colors.mauve },
        }
      end,
      integrations = {
        blink_cmp = true,
        fzf = true,
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

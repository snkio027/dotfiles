local markdownlint_config = vim.fs.joinpath(vim.fn.stdpath("config"), "..", "markdownlint-cli2", "config.yaml")

return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      -- Render in reading/navigation modes and expose the source while typing.
      render_modes = { "n", "c", "t" },
      completions = { lsp = { enabled = true } },
      heading = {
        sign = false,
        icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
        position = "inline",
        width = "block",
        right_pad = 2,
      },
      code = {
        sign = false,
        width = "block",
        right_pad = 1,
        border = "thin",
      },
      checkbox = { enabled = true },
      pipe_table = { preset = "round" },
      -- Snacks owns formula rendering so there is one visual pipeline instead
      -- of a second converter managed by render-markdown.
      latex = { enabled = false },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = { "css", "scss", "svelte", "typst", "vue" },
    },
  },
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          prepend_args = { "--config", markdownlint_config },
        },
      },
    },
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters = {
        ["markdownlint-cli2"] = {
          prepend_args = { "--config", markdownlint_config },
        },
      },
    },
  },
  {
    "folke/snacks.nvim",
    opts = {
      image = {
        enabled = true,
        doc = {
          enabled = true,
          inline = true,
          float = true,
          max_width = 80,
          max_height = 40,
        },
        math = { enabled = true },
      },
    },
  },
}

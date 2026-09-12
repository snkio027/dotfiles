return {
  {
    "nvim-mini/mini.pairs",
    enabled = false,
  },
  {
    "saghen/blink.pairs",
    version = "v0.7.1",
    dependencies = { "saghen/blink.lib" },
    build = function()
      require("blink.pairs").download():pwait(60000)
    end,
    opts = {
      highlights = {
        enabled = false,
      },
    },
  },
}

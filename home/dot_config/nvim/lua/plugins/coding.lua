return {
  {
    "L3MON4D3/LuaSnip",
    config = function(_, opts)
      local luasnip = require("luasnip")
      luasnip.setup(opts)

      local safe_snippets = require("snippets.cpp")
      luasnip.add_snippets("cpp", safe_snippets, { key = "dotfiles-cpp-safety" })
      local safe_ids = {}
      for _, snippet in ipairs(safe_snippets) do
        safe_ids[snippet.id] = true
      end

      local function remove_unsafe_reverse_loops()
        local removed = false
        for _, snippet in ipairs(luasnip.get_snippets("cpp")) do
          if snippet.trigger == "forr" and not safe_ids[snippet.id] then
            snippet:invalidate()
            removed = true
          end
        end
        if removed then
          luasnip.clean_invalidated()
        end
      end

      remove_unsafe_reverse_loops()
      local group = vim.api.nvim_create_augroup("DotfilesLuaSnipSafety", { clear = true })
      vim.api.nvim_create_autocmd("User", {
        pattern = "LuasnipSnippetsAdded",
        callback = remove_unsafe_reverse_loops,
        desc = "Keep only the safe C++ reverse-loop snippet",
        group = group,
      })
    end,
  },
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

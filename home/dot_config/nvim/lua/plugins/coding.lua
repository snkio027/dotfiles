local function luasnip_choice(direction)
  return function()
    local loaded, luasnip = pcall(require, "luasnip")
    -- An active LuaSnip choice owns Tab even if Blink auto-opened its menu.
    -- Outside a choice this returns false, preserving menu-first completion.
    if not loaded or not luasnip.choice_active() then
      return false
    end
    luasnip.change_choice(direction)
    return true
  end
end

local function accept_luasnip_choice()
  local loaded, luasnip = pcall(require, "luasnip")
  if not loaded or not luasnip.choice_active() then
    return false
  end
  luasnip.jump(1)
  return true
end

return {
  {
    "saghen/blink.cmp",
    opts = {
      keymap = {
        preset = "enter",
        ["<Tab>"] = { luasnip_choice(1), "select_next", "snippet_forward", "fallback" },
        ["<S-Tab>"] = { luasnip_choice(-1), "select_prev", "snippet_backward", "fallback" },
        ["<CR>"] = { accept_luasnip_choice, "accept", "fallback" },
      },
      completion = {
        list = {
          selection = {
            preselect = false,
            auto_insert = false,
          },
        },
        menu = {
          draw = {
            columns = {
              { "kind_icon" },
              { "label", "label_description", gap = 1 },
              { "source_name" },
            },
          },
        },
      },
    },
  },
  {
    "L3MON4D3/LuaSnip",
    version = "v2.5.0",
    opts = function(_, opts)
      opts.history = false
      opts.region_check_events = "CursorMoved,CursorMovedI"
      opts.delete_check_events = "TextChanged,TextChangedI"
      opts.exit_roots = true
      return opts
    end,
    config = function(_, opts)
      local luasnip = require("luasnip")
      luasnip.setup(opts)
      luasnip.add_snippets("cpp", require("snippets.cpp"), { key = "dotfiles-cpp" })
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

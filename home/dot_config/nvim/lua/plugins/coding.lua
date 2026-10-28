return {
  {
    "saghen/blink.cmp",
    opts = function(_, opts)
      local context = require("config.completion_context")
      opts.keymap = opts.keymap or {}
      opts.keymap["<Tab>"] = {
        function()
          return context.jump(1)
        end,
        LazyVim.cmp.map({ "ai_nes", "ai_accept" }),
        "fallback",
      }
      opts.keymap["<S-Tab>"] = {
        function()
          return context.jump(-1)
        end,
        "fallback",
      }
      local snippets = opts.sources.providers.snippets or {}
      local transform_snippets = snippets.transform_items
      snippets.transform_items = function(ctx, items)
        if transform_snippets then
          items = transform_snippets(ctx, items)
        end
        return context.snippet_items(ctx, items)
      end
      opts.sources.providers.snippets = snippets
      opts.completion.menu.draw.columns = {
        { "kind_icon" },
        { "label", "label_description", gap = 1 },
        { "source_name" },
      }
      local provider = opts.sources.providers.lsp or {}
      local previous = provider.transform_items
      provider.transform_items = function(ctx, items)
        if previous then
          items = previous(ctx, items)
        end
        return require("config.clangd_completion").transform_items(ctx, items)
      end
      opts.sources.providers.lsp = provider
    end,
  },
  {
    "L3MON4D3/LuaSnip",
    config = function(_, opts)
      local luasnip = require("luasnip")
      luasnip.setup(opts)

      local safe_snippets = require("snippets.cpp")
      luasnip.add_snippets("cpp", safe_snippets, { key = "dotfiles-cpp-safety" })
      local safe_ids = {}
      local declarations = require("config.completion_context").declarations
      for _, snippet in ipairs(safe_snippets) do
        safe_ids[snippet.id] = true
      end

      local function remove_replaced_snippets()
        local removed = false
        for _, snippet in ipairs(luasnip.get_snippets("cpp")) do
          local replaced = snippet.trigger == "forr" or declarations[snippet.trigger]
          if replaced and not safe_ids[snippet.id] then
            snippet:invalidate()
            removed = true
          end
        end
        if removed then
          luasnip.clean_invalidated()
        end
      end

      remove_replaced_snippets()
      local group = vim.api.nvim_create_augroup("DotfilesLuaSnipSafety", { clear = true })
      vim.api.nvim_create_autocmd("User", {
        pattern = "LuasnipSnippetsAdded",
        callback = remove_replaced_snippets,
        desc = "Keep the maintained C++ loop and declaration snippets",
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

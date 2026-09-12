local function native_choice(direction)
  return function()
    if vim.fn.pumvisible() ~= 1 or not MiniSnippets or MiniSnippets.session.get(false) == nil then
      return false
    end

    local key = direction == "next" and "<C-n>" or "<C-p>"
    return vim.api.nvim_replace_termcodes(key, true, false, true)
  end
end

local function accept_native_choice()
  if vim.fn.pumvisible() ~= 1 or not MiniSnippets or MiniSnippets.session.get(false) == nil then
    return false
  end

  if vim.fn.complete_info({ "selected" }).selected < 0 then
    return false
  end

  return vim.api.nvim_replace_termcodes("<C-y>", true, false, true)
end

return {
  {
    "saghen/blink.cmp",
    opts = {
      keymap = {
        preset = "enter",
        ["<Tab>"] = { native_choice("next"), "select_next", "snippet_forward", "fallback" },
        ["<S-Tab>"] = { native_choice("prev"), "select_prev", "snippet_backward", "fallback" },
        ["<CR>"] = { accept_native_choice, "accept", "fallback" },
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
    "nvim-mini/mini.snippets",
    opts = function(_, opts)
      local snippets = require("mini.snippets")
      local reverse_cpp_loop = {
        prefix = "forr",
        body = {
          "for (auto ${1:it} = ${2:container}.rbegin(); ${1:it} != ${2:container}.rend(); ++${1:it}) {",
          "\t${0}",
          "}",
        },
        desc = "Safe iterator-based reverse loop",
      }

      opts.snippets = {
        snippets.gen_loader.from_lang(),
        function(context)
          return context.lang == "cpp" and { reverse_cpp_loop } or {}
        end,
      }

      local group = vim.api.nvim_create_augroup("DotfilesMiniSnippets", { clear = true })
      -- <C-c> remains the explicit cancellation path. Normal completion stops
      -- automatically instead of leaving a session that a later Tab can resume.
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "MiniSnippetsSessionJump",
        desc = "Stop a snippet session when its final tabstop is reached",
        callback = function(args)
          if args.data.tabstop_to == "0" then
            MiniSnippets.session.stop()
          end
        end,
      })

      return opts
    end,
  },
}

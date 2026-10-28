local M = {}

M.declarations = { struct = true, class = true, enum = true, ["enum class"] = true }

function M.jump(direction)
  local ls = require("luasnip")
  if not ls.locally_jumpable(direction) then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  vim.schedule(function()
    if vim.api.nvim_get_current_buf() == buf and ls.locally_jumpable(direction) then
      ls.jump(direction)
    end
  end)
  return true
end

local function cpp_context(ctx)
  -- Inspect the byte immediately before the insertion point. At the end of a
  -- comment/string, the insertion point itself may belong to its parent node.
  local ok, node = pcall(function()
    local parser = vim.treesitter.get_parser(ctx.bufnr, "cpp")
    if not parser then
      return
    end
    parser:parse()
    return vim.treesitter.get_node({
      bufnr = ctx.bufnr,
      pos = { ctx.cursor[1] - 1, math.max(0, ctx.cursor[2] - 1) },
      ignore_injections = true,
    })
  end)
  if not ok then
    return -- A missing parser must not disable completion altogether.
  end
  while node do
    local kind = node:type()
    if kind == "comment" then
      return "comment"
    end
    if kind == "string_literal" or kind == "raw_string_literal" or kind == "char_literal" then
      return "string"
    end
    node = node:parent()
  end
end

function M.declaration_line(ctx)
  local before = ctx.line:sub(1, ctx.cursor[2])
  return before:match("^%s*[%a_]+$") ~= nil and ctx.line:sub(ctx.cursor[2] + 1):match("^%s*$") ~= nil
end

function M.snippet_items(ctx, items)
  if vim.bo[ctx.bufnr].filetype ~= "cpp" then
    return items
  end
  local context = cpp_context(ctx)
  local ls = require("luasnip")
  return vim.tbl_filter(function(item)
    local snippet = item.data and item.data.snip_id and ls.get_id_snippet(item.data.snip_id)
    if context == "string" then
      return false
    elseif context == "comment" then
      -- Keep documentation snippets whose output is itself a comment. Paths
      -- and LSP candidates use different providers and are never filtered here.
      local first = snippet and snippet:get_docstring()[1] or ""
      return first:match("^%s*//") ~= nil or first:match("^%s*/%*") ~= nil
    end
    if M.declarations[item.label] then
      if not M.declaration_line(ctx) then
        return false
      end
      -- Prefer a complete declaration to the same spelling's bare keyword;
      -- leave other LSP symbols, AI policy and general snippet ranking alone.
      item.score_offset = math.max(item.score_offset or 0, 10)
    end
    return true
  end, items)
end

return M

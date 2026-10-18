--- DX Semantic Color System (DX-COLOR-003)
--- clangd extensions and C/C++ taxonomy-loss handling.

local authority = require("theme.authority")

local M = {}

function M.attach(client, buf)
  require("theme.adapters.clangd_callable").attach(client, buf)
  if client.name ~= "clangd" or vim.bo[buf].filetype ~= "cpp" then
    return
  end
  local group = vim.api.nvim_create_augroup("dx_clangd_inactive_" .. client.id .. "_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("LspTokenUpdate", {
    group = group,
    buffer = buf,
    callback = function(event)
      local data = event.data
      if data.client_id == client.id and data.token.type == "comment" then
        -- clangd alone decides inactivity. Use the native token namespace so
        -- edits, refreshes and detach clear the override with the original.
        -- Inactive code outranks our special-member/callable projection (128).
        vim.lsp.semantic_tokens.highlight_token(data.token, buf, client.id, "@lsp.type.comment.cpp", {
          priority = vim.hl.priorities.semantic_tokens + 4,
        })
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "LspDetach", "BufWipeout" }, {
    group = group,
    buffer = buf,
    callback = function(event)
      if event.event == "BufWipeout" or event.data.client_id == client.id then
        vim.api.nvim_del_augroup_by_id(group)
      end
    end,
  })
end

---@return table<string, vim.api.keyset.highlight>
function M.groups()
  return {
    ["@lsp.type.concept"] = { link = "DxType" },

    -- clangd uses class tokens for constructor/destructor names. Their explicit
    -- modifier identifies a callable without recoloring ordinary type references.
    ["@lsp.typemod.class.constructorOrDestructor.cpp"] = { link = "DxCallable" },

    -- clangd's generic type token loses the builtin/user-defined distinction.
    ["@lsp.type.type.c"] = authority.suppress_foreground(),
    ["@lsp.type.type.cpp"] = authority.suppress_foreground(),

    -- clangd projects its StaticField taxonomy as variable + classScope plus
    -- orthogonal storage, mutability, and provenance modifiers. For C++, type
    -- ownership defines the foreground identity; the other modifiers must not
    -- compete with classScope at semantic-token modifier priority.
    ["@lsp.typemod.variable.classScope.cpp"] = { link = "DxMember" },
    ["@lsp.typemod.variable.static.cpp"] = authority.suppress_foreground(),
    ["@lsp.typemod.variable.readonly.cpp"] = authority.suppress_foreground(),
    ["@lsp.typemod.variable.defaultLibrary.cpp"] = authority.suppress_foreground(),
  }
end

return M

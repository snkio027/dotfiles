--- DX Semantic Color System (DX-COLOR-003)
--- Deterministic assembly of the DX semantic overlay.

local domain = require("theme.domain")

local M = {}

M.layers = {
  { name = "authority", module = require("theme.authority"), entrypoint = "base_groups" },
  { name = "visual", entrypoint = "roles" },
  { name = "treesitter", module = require("theme.bindings.treesitter"), entrypoint = "groups" },
  { name = "lsp", module = require("theme.bindings.lsp"), entrypoint = "groups" },
  { name = "zls", module = require("theme.adapters.zls"), entrypoint = "groups" },
  { name = "clangd", module = require("theme.adapters.clangd"), entrypoint = "groups" },
  { name = "rust_analyzer", module = require("theme.adapters.rust_analyzer"), entrypoint = "groups" },
  { name = "pyright", module = require("theme.adapters.pyright"), entrypoint = "groups" },
}

local function assert_visual_closure(roles)
  for role in pairs(domain.roles) do
    assert(roles[role] ~= nil, ("visual profile is missing domain role %s"):format(role))
  end
  for role in pairs(roles) do
    assert(domain.roles[role] ~= nil, ("visual profile defines unknown domain role %s"):format(role))
  end
end

---@param p table Unified palette returned by palette.resolve()
---@param visual table Visual profile exposing roles(p)
---@return table<string, vim.api.keyset.highlight>
function M.highlights(p, visual)
  local graph = {}

  for _, layer in ipairs(M.layers) do
    local owner = layer.module or visual
    local groups = owner[layer.entrypoint](p)
    if layer.name == "visual" then
      assert_visual_closure(groups)
    end

    for group, spec in pairs(groups) do
      assert(graph[group] == nil, ("highlight group %s has more than one composition owner"):format(group))
      graph[group] = spec
    end
  end

  return graph
end

return M

local M = {}
local catalog_path

function M.before_init(_, config)
  local settings = config.settings or {}
  local toml = settings.evenBetterToml or {}
  local schema = toml.schema or {}
  -- Explicit catalog choices (including an empty list) and disabled schema
  -- support belong to the user/project, not this default.
  if schema.enabled == false or schema.catalogs ~= nil then
    return
  end

  if not catalog_path or vim.fn.filereadable(catalog_path) == 0 then
    -- Taplo 0.10 requires this exact historical catalog identifier. Reuse the
    -- installed SchemaStore snapshot without changing entries or native glob
    -- matching, schema fetching, caching, or association priorities.
    local catalog = {
      ["$schema"] = "https://json.schemastore.org/schema-catalog.json",
      schemas = require("schemastore").json.schemas(),
    }
    local path = vim.fn.tempname()
    assert(vim.fn.writefile({ vim.json.encode(catalog) }, path) == 0, "Cannot write Taplo schema catalog")
    -- Neovim owns this process-local temporary file and removes it on exit.
    catalog_path = path
  end

  schema.catalogs = { vim.uri_from_fname(catalog_path) }
  toml.schema = schema
  settings.evenBetterToml = toml
  config.settings = settings
end

return M

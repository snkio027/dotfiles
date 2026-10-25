local M = {}

function M.tool_name(tool)
  local name = type(tool) == "table" and tool[1] or tool
  assert(type(name) == "string" and name ~= "", "Mason tool entries must have a package name")
  return name
end

function M.unique(tools)
  local result = {}
  local seen = {}
  for _, tool in ipairs(tools or {}) do
    local name = M.tool_name(tool)
    if not seen[name] then
      seen[name] = true
      result[#result + 1] = tool
    end
  end
  return result
end

-- Consume LazyVim's compiled LSP install list, which already excludes disabled
-- and externally managed servers. Do not infer it from installed
-- packages: a user's manually installed server is not an installation policy.
function M.required_tools()
  local tools = vim.deepcopy(LazyVim.opts("mason.nvim").ensure_installed or {})
  local mapping = require("mason-lspconfig.mappings").get_mason_map().lspconfig_to_package
  local servers = require("mason-lspconfig.settings").current.ensure_installed
  local by_name = {}
  for _, tool in ipairs(tools) do
    by_name[M.tool_name(tool)] = tool
  end
  for _, server in ipairs(servers) do
    local name, version = require("mason-core.package").Parse(server)
    local package_name = assert(mapping[name], "Unmapped Mason LSP server: " .. name)
    local existing = by_name[package_name]
    if existing and version then
      local pin = type(existing) == "table" and existing.version or nil
      assert(not pin or pin == version, "Conflicting Mason versions: " .. package_name)
      if not pin then
        -- Keep other tool options while applying the explicit LSP version.
        local entry = type(existing) == "table" and existing or { existing }
        entry.version = version
        for index, tool in ipairs(tools) do
          if M.tool_name(tool) == package_name then
            tools[index] = entry
          end
        end
        by_name[package_name] = entry
      end
    elseif not existing then
      local entry = version and { package_name, version = version } or package_name
      tools[#tools + 1] = entry
      by_name[package_name] = entry
    end
  end
  return M.unique(tools)
end

-- Preview only. Neither a language extra being disabled nor a manual install
-- is consent to uninstall a tool; removal stays explicit in Mason's own UI.
function M.preview_clean(tools)
  local required = {}
  for _, tool in ipairs(tools) do
    required[M.tool_name(tool)] = true
  end
  local candidates = vim.tbl_filter(function(name)
    return not required[name]
  end, require("mason-registry").get_installed_package_names())
  table.sort(candidates)
  local message = #candidates == 0 and "No unlisted Mason packages."
    or (
      "Unlisted Mason packages (not removed):\n"
      .. table.concat(candidates, ", ")
      .. "\nUse :Mason to review them or :MasonUninstall <package> to remove a specific package."
    )
  vim.notify(message, vim.log.levels.INFO, { title = "Mason tools" })
  return candidates
end

function M.pending(tools)
  local registry = require("mason-registry")
  local pending = {}
  for _, tool in ipairs(M.unique(tools)) do
    local name = M.tool_name(tool)
    local ok, package = pcall(registry.get_package, name)
    if not ok or not package:is_installed() or package:is_installing() or not package:get_receipt():is_present() then
      pending[#pending + 1] = name
    end
  end
  table.sort(pending)
  return pending
end

function M.wait_for_installed(tools, timeout_ms)
  local expected = M.unique(tools)
  local pending = {}
  local completed = vim.wait(tonumber(timeout_ms) or 900000, function()
    pending = M.pending(expected)
    return #pending == 0
  end, 200)

  assert(completed, "Timed out waiting for Mason tools: " .. table.concat(pending, ", "))
  return #expected
end

function M.wait_for_idle(tools, timeout_ms)
  local registry = require("mason-registry")
  local expected = M.unique(tools)
  local installing = {}
  local completed = vim.wait(tonumber(timeout_ms) or 900000, function()
    installing = {}
    for _, tool in ipairs(expected) do
      local name = M.tool_name(tool)
      local ok, package = pcall(registry.get_package, name)
      -- A missing/unregistered package needs the installer, not a wait.
      if ok and package:is_installing() then
        installing[#installing + 1] = name
      end
    end
    return #installing == 0
  end, 200)
  assert(completed, "Timed out waiting for active Mason installs: " .. table.concat(installing, ", "))
end

return M

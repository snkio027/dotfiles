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

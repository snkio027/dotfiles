-- Keep native rustaceanvim startup and runnables, but isolate project clients.
-- The pinned plugin otherwise adds a new root to any existing Rust client before
-- Neovim's reuse_client policy can compare their settings.
local M = {}
local installed = false
local readiness = {}

function M.ready(client)
  return client.initialized and not client:is_stopped() and readiness[client.id] == true
end

local function canonical(path)
  return path and (vim.uv.fs_realpath(path) or vim.fs.normalize(path)) or nil
end

local function pack(...)
  return { n = select("#", ...), ... }
end

local function restored_call(callback, restore, ...)
  local result = pack(pcall(callback, ...))
  restore()
  if not result[1] then
    error(result[2], 0)
  end
  return unpack(result, 2, result.n)
end

function M.setup()
  if installed then
    return
  end
  -- Called by auto_attach after the plugin has received its final configuration.
  local lsp = require("rustaceanvim.lsp")
  local cargo = require("rustaceanvim.cargo")
  local analyzer = require("rustaceanvim.rust_analyzer")
  local status = require("rustaceanvim.server_status")
  local handler = status.handler
  status.handler = function(err, result, ctx, config)
    if ctx and ctx.client_id and type(result) == "table" then
      readiness[ctx.client_id] = result.quiescent == true
    end
    return handler(err, result, ctx, config)
  end
  -- With separate clients, sibling prefixes and nested roots must not route a
  -- Neotest request to the first client whose name merely shares a prefix.
  analyzer.get_client_for_file = function(filename, method)
    local file = canonical(filename)
    local best, length
    for _, client in ipairs(analyzer.get_active_rustaceanvim_clients(nil, { method = method })) do
      local root = canonical(client.config.root_dir)
      local prefix = root and root:gsub("/+$", "") .. "/"
      if root and file and (file == root or file:sub(1, #prefix) == prefix) and (not length or #root > length) then
        best, length = client, #root
      end
    end
    return best
  end
  local start = lsp.start
  local unfiltered_clients
  lsp.start = function(buf)
    local resolve = cargo.get_config_root_dir
    cargo.get_config_root_dir = function(config, filename, callback)
      if not callback then
        return resolve(config, filename)
      end
      -- The root resolver may be asynchronous. Capture the startup callback and
      -- scope the client filter to its synchronous execution, not the wait.
      return resolve(config, filename, function(root)
        local target = canonical(root or vim.fs.dirname(filename))
        local clients = analyzer.get_active_rustaceanvim_clients
        local previous_unfiltered = unfiltered_clients
        unfiltered_clients = unfiltered_clients or clients
        local source = unfiltered_clients
        analyzer.get_active_rustaceanvim_clients = function(bufnr, filter)
          local active = source(bufnr, filter)
          if bufnr ~= nil or filter ~= nil then
            return active
          end
          return vim.tbl_filter(function(client)
            return canonical(client.config.root_dir) == target
          end, active)
        end
        return restored_call(callback, function()
          analyzer.get_active_rustaceanvim_clients = clients
          unfiltered_clients = previous_unfiltered
        end, root)
      end)
    end
    return restored_call(start, function()
      cargo.get_config_root_dir = resolve
    end, buf)
  end
  installed = true
end

return M

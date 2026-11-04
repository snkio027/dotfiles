-- Native Rust discovery depends on the target analyzer finishing initial indexing.
-- Do not cache an empty file before that client can return its real runnables.
local M = {}
local routing_installed = false

function M.adapter()
  M.install_routing()
  local native = require("rustaceanvim.neotest")
  local adapter = vim.tbl_extend("force", {}, native)
  adapter.discover_positions = function(filename)
    local analyzer = require("rustaceanvim.rust_analyzer")
    local nio = require("nio")
    local boundary = require("config.rust_clients")
    -- BufAdd can precede BufRead/FileType during :edit. Yield once so an opening
    -- Rust buffer reaches its real startup path; unopened files still return nil.
    nio.scheduler()
    local deadline = vim.uv.hrtime() + 30 * 1e9
    local client
    while true do
      client = analyzer.get_client_for_file(filename)
      if client and boundary.ready(client) then
        break
      end
      local buf = vim.fn.bufnr(filename)
      if not client and (buf < 0 or not vim.api.nvim_buf_is_loaded(buf) or vim.bo[buf].buftype ~= "") then
        return nil
      end
      assert(vim.uv.hrtime() < deadline, "Rust test discovery is waiting for rust-analyzer: " .. filename)
      nio.sleep(20)
    end
    if not client:supports_method("experimental/runnables") then
      return nil
    end
    local connection = assert(nio.lsp.get_client_by_id(client.id), "Rust test discovery client stopped")
    local buf = vim.fn.bufnr(filename)
    local err, runnables = connection.request.experimental_runnables({
      textDocument = { uri = vim.uri_from_fname(filename) },
      position = nil,
    }, buf >= 0 and buf or 0, { timeout = 100000 })
    assert(not err, "Rust test discovery failed: " .. vim.inspect(err))
    assert(type(runnables) == "table", "Rust test discovery returned an invalid runnable list")
    if #runnables == 0 then
      return nil
    end
    -- Keep native conversion, Cargo commands, debugger setup and result parsing.
    -- The preflight errors above remain explicit. The second request and tree
    -- conversion retain the pinned adapter's own concurrent-change behavior.
    return native.discover_positions(filename)
  end
  return adapter
end

local function canonical(path)
  return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function attach_routing(client)
  local run_tree = client.run_tree
  client.run_tree = function(self, tree, args)
    local position = tree:data()
    if
      position.type == "file"
      and position.id == position.path
      and position.path:match("%.rs$")
      and not position.runnable
      and not position.range
      and #tree:children() == 0
    then
      local id, adapter = self:_get_adapter(position.id, args and args.adapter)
      if adapter and adapter.name == "rustaceanvim" then
        -- A directory scan publishes placeholder files before async parsing.
        -- Refresh this explicit run once in its authoritative registry, even
        -- when another registry has already discovered the same source file.
        self:_update_positions(position.path, { adapter = id })
        local discovered = self._state:positions(id, position.id)
        local data = discovered and discovered:data()
        assert(
          discovered and (data.runnable or data.range or #discovered:children() > 0),
          "Rust test discovery produced no parsed tests for: " .. position.path
        )
        tree = discovered
      end
    end
    return run_tree(self, tree, args)
  end
  local original = client._get_adapter
  client._get_adapter = function(self, position_id, adapter_id)
    if adapter_id or not position_id then
      return original(self, position_id, adapter_id)
    end
    -- Known test/namespace IDs are opaque. Never pass their :: suffix to a
    -- filesystem root resolver; RunLast must retain the original exact target.
    local exact_id, exact_adapter, depth
    for id, adapter in pairs(self._adapters) do
      local position = adapter.name == "rustaceanvim" and self._state:positions(id, position_id)
      local kind = position and position:data().type
      if kind == "test" or kind == "namespace" then
        local root = canonical(id:sub(#adapter.name + 2))
        if not depth or #root > depth then
          exact_id, exact_adapter, depth = id, adapter, #root
        end
      end
    end
    if exact_id then
      return exact_id, exact_adapter
    end
    local path = position_id:match("^(.-%.rs)::") or position_id
    local directory = vim.fn.isdirectory(path) == 1
    if not path:match("%.rs$") and not (directory and vim.fs.root(path, { "Cargo.toml", "rust-project.json" })) then
      return original(self, position_id, adapter_id)
    end
    local dir = directory and path or vim.fs.dirname(path)
    local target
    -- Use the native adapter group's project configuration and Cargo workspace
    -- resolver, rather than inferring a workspace from filename prefixes.
    for _, entry in ipairs(self._adapter_group:adapters_with_root_dir(dir)) do
      if entry.adapter.name == "rustaceanvim" then
        target = canonical(entry.root)
        break
      end
    end
    if not target then
      return original(self, position_id, adapter_id)
    end
    local function find()
      for id, adapter in pairs(self._adapters) do
        if adapter.name == "rustaceanvim" then
          -- Position trees may cover only a discovered subdirectory. The native
          -- registry ID retains the workspace identity used at registration.
          local root = id:sub(#adapter.name + 2)
          if canonical(root) == target then
            return id, adapter
          end
        end
      end
    end
    local id, adapter = find()
    if id then
      return id, adapter
    end
    if self._started then
      -- Native registration/discovery is safe once directed to the actual root;
      -- no shared adapter registry is temporarily hidden across an async yield.
      self:_update_adapters(dir)
      return find()
    end
  end
end

function M.install_routing()
  if routing_installed then
    return
  end
  local create_client = require("neotest.client")
  -- Neotest consumers receive a read-through proxy: assigning a method there
  -- cannot change the actual client. Wrap its published factory before setup.
  package.loaded["neotest.client"] = function(...)
    local client = create_client(...)
    attach_routing(client)
    return client
  end
  routing_installed = true
end

return M

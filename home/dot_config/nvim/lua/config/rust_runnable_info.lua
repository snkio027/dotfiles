-- Inspect native rust-analyzer runnables without executing or rewriting them.
local M = {}
local method = "experimental/runnables"

local function text(value)
  return type(value) == "string" and value ~= "" and value or "unavailable"
end

local function strings(value)
  if type(value) ~= "table" or not vim.islist(value) then
    return false
  end
  for _, item in ipairs(value) do
    if type(item) ~= "string" then
      return false
    end
  end
  return true
end

local function cargo_flags(argv)
  local result = { features = {}, targets = {}, all_features = false, no_default_features = false }
  local index = 1
  while index <= #argv and argv[index] ~= "--" do
    local arg = argv[index]
    if arg == "--features" or arg == "-F" or arg == "--target" then
      local value = argv[index + 1]
      if value and value ~= "--" then
        table.insert(arg == "--target" and result.targets or result.features, value)
        index = index + 1
      end
    elseif arg:match("^%-%-features=") then
      table.insert(result.features, arg:sub(12))
    elseif arg:match("^%-F.+") then
      table.insert(result.features, arg:sub(3))
    elseif arg:match("^%-%-target=") then
      table.insert(result.targets, arg:sub(10))
    elseif arg == "--all-features" then
      result.all_features = true
    elseif arg == "--no-default-features" then
      result.no_default_features = true
    end
    index = index + 1
  end
  return result
end

function M.describe(runnable, origin)
  runnable = type(runnable) == "table" and runnable or {}
  origin = origin or {}
  local args = type(runnable.args) == "table" and runnable.args or {}
  local cargo = strings(args.cargoArgs)
  local located = type(runnable.location) == "table"
    and type(runnable.location.targetRange or runnable.location.targetSelectionRange) == "table"
  local report = {
    label = text(runnable.label),
    kind = cargo
        and (located and "source Cargo runnable" or (runnable.location == nil and "generic Cargo runnable (no source location)" or "Cargo runnable (source location unavailable)"))
      or "shell/unknown runnable",
    request_uri = text(origin.uri),
    client_id = origin.id,
    client_root = text(origin.root),
    workspace = text(args.workspaceRoot),
    source_uri = located and text(runnable.location.targetUri) or "unavailable",
    source_range = located and vim.deepcopy(runnable.location.targetSelectionRange or runnable.location.targetRange)
      or nil,
    command_source = "rust-analyzer response -> rustaceanvim.runnables.get_command (run/test)",
  }
  local tools = require("rustaceanvim.config.internal").tools
  -- Native nextest conversion may create its cache config. A read-only view
  -- must not invoke that branch or temporarily change the user's settings.
  local nextest = cargo
    and tools.enable_nextest
    and not tools.cargo_override
    and args.cargoArgs[1] == "test"
    and not report.label:match("^doctest")
    and vim.fn.executable("cargo-nextest") == 1
  if nextest then
    report.unavailable = "Native nextest conversion may write its cache; command was not evaluated."
  else
    local ok, command, argv, cwd = pcall(require("rustaceanvim.runnables").get_command, vim.deepcopy(runnable))
    if ok and type(command) == "string" and strings(argv) then
      report.command, report.argv, report.cwd = command, vim.deepcopy(argv), text(cwd)
    else
      report.unavailable = "Native command unavailable: " .. (ok and "unsupported response" or tostring(command))
    end
  end
  if cargo then
    local raw = vim.deepcopy(args.cargoArgs)
    if strings(args.cargoExtraArgs) then
      vim.list_extend(raw, args.cargoExtraArgs)
    end
    report.cargo_arguments = raw
    report.flags = cargo_flags(raw)
  end
  return report
end

function M.lines(report)
  local function quoted(value)
    return vim.json.encode(value)
  end
  local lines = {
    "Rust runnable inspection (read only)",
    "Kind: " .. report.kind,
    "Label: " .. quoted(report.label),
    "Requested file: " .. quoted(report.request_uri),
    "Client: " .. tostring(report.client_id or "unavailable"),
    "Client root: " .. quoted(report.client_root),
    "Runnable workspace: " .. quoted(report.workspace),
    "Source location: " .. quoted(report.source_uri),
    "Source range (zero based): " .. quoted(report.source_range or vim.NIL),
    "Command source: " .. report.command_source,
  }
  if report.command then
    vim.list_extend(lines, {
      "Executable: " .. quoted(report.command),
      "Arguments (exact array): " .. quoted(report.argv),
      "Execution cwd: " .. quoted(report.cwd),
    })
  else
    lines[#lines + 1] = report.unavailable
  end
  if report.flags then
    vim.list_extend(lines, {
      "RA Cargo arguments: " .. quoted(report.cargo_arguments),
      "Declared features: " .. quoted(report.flags.features),
      "--all-features: " .. tostring(report.flags.all_features),
      "--no-default-features: " .. tostring(report.flags.no_default_features),
      "Declared target: " .. quoted(report.flags.targets),
      "Absent flags mean not declared in this runnable; Cargo config/environment may still affect the result.",
    })
  end
  vim.list_extend(lines, {
    "",
    "This view does not run a command or change a selection. Re-open it after project/source changes.",
    "Use the native RustLsp actions to execute. DAP separately transforms the build command and resolves its artifact.",
    "No environment values are displayed. Arguments may contain sensitive data; review before sharing.",
  })
  return lines
end

local function clients(buf)
  return require("rustaceanvim.rust_analyzer").get_active_rustaceanvim_clients(buf, { method = method })
end

function M.summary_lines(buf)
  local result = { "Rust runnable facts: :RustRunnableInfo (read only; does not select or execute a task)" }
  for _, client in ipairs(clients(buf)) do
    result[#result + 1] = "Rust client " .. client.id .. " root: " .. vim.json.encode(text(client.config.root_dir))
  end
  return result
end

local function show(report)
  local lines = M.lines(report)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden, vim.bo[buf].swapfile, vim.bo[buf].modifiable = "wipe", false, false
  vim.bo[buf].filetype = "rust-runnable-info"
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = 1,
    col = 2,
    width = math.max(1, math.min(110, vim.o.columns - 4)),
    height = math.max(1, math.min(#lines, vim.o.lines - 4)),
    style = "minimal",
    border = "rounded",
  })
  vim.wo[win].wrap = false
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true })
end

function M.inspect(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "rust" then
    vim.notify("Rust runnable inspection needs a Rust source buffer.", vim.log.levels.WARN)
    return
  end
  local uri, tick = vim.uri_from_bufnr(buf), vim.api.nvim_buf_get_changedtick(buf)
  local window = vim.api.nvim_get_current_win()
  local function valid(client)
    return vim.api.nvim_buf_is_valid(buf)
      and vim.api.nvim_win_is_valid(window)
      and vim.api.nvim_get_current_win() == window
      and vim.api.nvim_win_get_buf(window) == buf
      and vim.uri_from_bufnr(buf) == uri
      and vim.api.nvim_buf_get_changedtick(buf) == tick
      and vim.lsp.get_client_by_id(client.id) == client
      and not not client.attached_buffers[buf]
  end
  local function stale()
    vim.notify(
      "Rust runnable inspection expired: source or attached client changed. Inspect again.",
      vim.log.levels.WARN
    )
  end
  local function request(client)
    if not valid(client) then
      return stale()
    end
    local origin = { uri = uri, id = client.id, root = client.config.root_dir }
    local accepted = client:request(method, { textDocument = { uri = uri } }, function(err, runnables)
      if not valid(client) then
        return stale()
      end
      if err or type(runnables) ~= "table" or #runnables == 0 then
        vim.notify(
          "Rust runnable response unavailable: " .. tostring(err and err.message or "no runnables"),
          vim.log.levels.WARN
        )
        return
      end
      local reports = {}
      for _, runnable in ipairs(runnables) do
        reports[#reports + 1] = M.describe(runnable, origin)
      end
      vim.ui.select(reports, {
        prompt = "Inspect Rust runnable · " .. uri,
        kind = "rust-runnable-info",
        format_item = function(report)
          return (report.kind .. " | " .. report.label):gsub("[\r\n]", " ")
        end,
      }, function(report)
        if not report then
          return
        end
        if not valid(client) then
          return stale()
        end
        show(report)
      end)
    end, buf)
    if not accepted then
      vim.notify("Rust runnable request was not accepted by the attached client.", vim.log.levels.WARN)
    end
  end
  local active = clients(buf)
  if #active == 0 then
    vim.notify("No attached Rust client can provide runnables for this file.", vim.log.levels.WARN)
  elseif #active == 1 then
    request(active[1])
  else
    vim.ui.select(active, {
      prompt = "Inspect Rust client · " .. uri,
      format_item = function(client)
        return client.id .. " | " .. text(client.config.root_dir)
      end,
    }, function(client)
      if client then
        request(client)
      end
    end)
  end
end

return M

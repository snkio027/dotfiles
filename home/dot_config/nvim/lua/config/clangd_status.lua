-- On-demand observations only. Database records are inputs, not a claim about
-- clangd's effective command after .clangd edits, driver queries or header inference.
local M = {}
local filetypes = { c = true, cpp = true, objc = true, objcpp = true, cuda = true }
local max_database_bytes = 4 * 1024 * 1024
local max_entries = 8

local function canonical(path)
  return type(path) == "string" and path ~= "" and (vim.uv.fs_realpath(path) or vim.fs.normalize(path)) or nil
end

local function absolute(path)
  return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

local function readable_file(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.type == "file"
end

local function database_records(path, filename)
  -- Nonblocking open also rejects a path replaced with a FIFO after stat.
  local fd = vim.uv.fs_open(path, vim.uv.constants.O_RDONLY + vim.uv.constants.O_NONBLOCK, 0)
  if not fd then
    return nil, "not readable"
  end
  local stat = vim.uv.fs_fstat(fd)
  if not stat or stat.type ~= "file" or stat.size > max_database_bytes then
    vim.uv.fs_close(fd)
    return nil, stat and stat.type == "file" and "larger than 4 MiB; not inspected" or "not a regular file"
  end
  local content = vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)
  local ok, records = pcall(vim.json.decode, content or "")
  if not ok or type(records) ~= "table" or not vim.islist(records) then
    return nil, "invalid compilation database"
  end
  local matches = {}
  for _, record in ipairs(records) do
    if
      type(record) == "table"
      and type(record.directory) == "string"
      and absolute(record.directory)
      and type(record.file) == "string"
    then
      local source = absolute(record.file) and record.file or vim.fs.joinpath(record.directory, record.file)
      if canonical(source) == canonical(filename) then
        if #matches == max_entries then
          return matches, "more than 8 exact records; showing first 8"
        end
        local item = { directory = record.directory }
        if
          type(record.arguments) == "table"
          and vim.islist(record.arguments)
          and vim.iter(record.arguments):all(function(value)
            return type(value) == "string"
          end)
        then
          item.arguments = vim.deepcopy(record.arguments)
          item.compiler = record.arguments[1]
        elseif type(record.command) == "string" then
          item.command = record.command -- Do not parse shell text or infer a compiler from it.
        else
          item.error = "record has no supported arguments or command"
        end
        matches[#matches + 1] = item
      end
    end
  end
  return matches, #matches == 0 and "no exact file record; header inference is not reproduced" or nil
end

local function overrides(config)
  local result = {}
  for index, arg in ipairs(type(config.cmd) == "table" and config.cmd or {}) do
    if type(arg) == "string" then
      local value = arg:match("^%-%-compile%-commands%-dir=(.*)$")
      if arg == "--compile-commands-dir" then
        value = config.cmd[index + 1]
      end
      if type(value) == "string" then
        result[#result + 1] = { source = "command-line override", directory = value }
      end
    end
  end
  local value = type(config.init_options) == "table" and config.init_options.compilationDatabasePath
  if type(value) == "string" then
    local owned = config._dotfiles_clangd_database
    local inferred = type(owned) == "table"
      and owned.path == value
      and canonical(owned.root) == canonical(config.root_dir)
    result[#result + 1] =
      { source = inferred and "managed startup pin" or "initialization override", directory = value }
  end
  return result
end

function M.snapshot(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) or not filetypes[vim.bo[bufnr].filetype] then
    return { applicable = false }
  end
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local result = { applicable = true, bufnr = bufnr, filename = filename, clients = {} }
  for _, client in ipairs(vim.lsp.get_clients({ name = "clangd", bufnr = bufnr })) do
    local item =
      { id = client.id, root = client.root_dir, initialized = client.initialized, databases = overrides(client.config) }
    for _, database in ipairs(item.databases) do
      if absolute(database.directory) then
        database.path = vim.fs.joinpath(database.directory, "compile_commands.json")
        database.records, database.note = database_records(database.path, filename)
      else
        database.note = "relative override; process working directory not inferred"
      end
    end
    if type(client.root_dir) == "string" then
      item.clangd_config = readable_file(vim.fs.joinpath(client.root_dir, ".clangd"))
          and vim.fs.joinpath(client.root_dir, ".clangd")
        or nil
      if readable_file(vim.fs.joinpath(client.root_dir, ".cxx.toml")) then
        item.managed_default = require("config.cpp").compile_database(client.root_dir)
        item.managed_default_exists = readable_file(item.managed_default) or false
      end
    end
    result.clients[#result.clients + 1] = item
  end
  table.sort(result.clients, function(a, b)
    return a.id < b.id
  end)
  local cmake = package.loaded["cmake-tools"]
  if type(cmake) == "table" and type(cmake.get_config) == "function" then
    local ok, config = pcall(cmake.get_config)
    if ok and config and type(config.cwd) == "string" then
      local same = #result.clients == 1 and canonical(config.cwd) == canonical(result.clients[1].root)
      result.cmake = { root = config.cwd, same_project = same }
      if same then
        result.cmake.configure = config.configure_preset
        result.cmake.build = config.build_preset
        result.cmake.test = config.test_preset
        result.cmake.build_type = config.build_type
        result.cmake.directory = config.build_directory and config.build_directory.filename or nil
      end
    end
  end
  return result
end

local function display(value)
  local text = type(value) == "table" and vim.inspect(value) or tostring(value)
  text = text:gsub("[%c]", function(character)
    return string.format("\\x%02X", string.byte(character))
  end)
  return #text > 2000 and text:sub(1, 2000) .. " … [truncated]" or text
end

function M.lines(snapshot)
  if not snapshot.applicable then
    return {}
  end
  local lines = { "C/C++ compilation context" }
  if #snapshot.clients == 0 then
    lines[#lines + 1] = "clangd: not attached to this file"
  end
  for _, client in ipairs(snapshot.clients) do
    lines[#lines + 1] = "clangd #" .. client.id .. " root: " .. display(client.root or "unknown")
    if client.clangd_config then
      lines[#lines + 1] = ".clangd: " .. display(client.clangd_config) .. " (native configuration; not parsed here)"
    end
    if #client.databases == 0 then
      lines[#lines + 1] = "Database: native discovery; effective database not exposed by LSP"
    end
    for _, database in ipairs(client.databases) do
      lines[#lines + 1] = "Database input (" .. database.source .. "): " .. display(database.path or database.directory)
      if database.note then
        lines[#lines + 1] = "  " .. database.note
      end
      for index, record in ipairs(database.records or {}) do
        lines[#lines + 1] = "  Exact record " .. index .. " cwd: " .. display(record.directory)
        if record.compiler then
          lines[#lines + 1] = "  Recorded compiler: " .. display(record.compiler)
        end
        lines[#lines + 1] = "  Recorded command: " .. display(record.arguments or record.command or record.error)
      end
    end
    if client.managed_default then
      lines[#lines + 1] = "Managed default (not effective-command proof): "
        .. display(client.managed_default)
        .. (client.managed_default_exists and " [present]" or " [missing]")
    end
  end
  if snapshot.cmake then
    if snapshot.cmake.same_project then
      lines[#lines + 1] = "CMakeTools editor selection: configure="
        .. display(snapshot.cmake.configure or "none")
        .. ", build="
        .. display(snapshot.cmake.build or "none")
        .. ", test="
        .. display(snapshot.cmake.test or "none")
      lines[#lines + 1] = "CMakeTools build directory: " .. display(snapshot.cmake.directory or "unknown")
    else
      lines[#lines + 1] = "CMakeTools selection belongs to another project; not used for this file"
    end
  end
  lines[#lines + 1] =
    "Recorded database inputs are not clangd's final flags; custom configuration and header inference remain native."
  return lines
end

function M.refresh(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  if
    not vim.api.nvim_buf_is_valid(bufnr)
    or bufnr ~= vim.api.nvim_get_current_buf()
    or vim.bo[bufnr].buftype ~= ""
    or not filetypes[vim.bo[bufnr].filetype]
  then
    return false, "Select the source file before refreshing its clangd"
  end
  local clients = vim.lsp.get_clients({ name = "clangd", bufnr = bufnr })
  if #clients ~= 1 then
    return false, "Expected exactly one clangd attached to this file"
  end
  local client = clients[1]
  if not client.initialized or client:is_stopped() or client._handle_restart then
    return false, "clangd is starting, stopping or already restarting"
  end
  if type(client._restart) ~= "function" then
    return false, "This Neovim does not provide the supported native client restart"
  end
  if
    type(client.root_dir) ~= "string"
    or client.root_dir == ""
    or canonical(client.root_dir) ~= canonical(client.config.root_dir)
  then
    return false, "clangd project identity changed; select the source file again"
  end
  local original = client.config
  local config = vim.deepcopy(original)
  local owned = config._dotfiles_clangd_database
  if
    type(owned) == "table"
    and canonical(owned.root) == canonical(config.root_dir)
    and type(config.init_options) == "table"
    and config.init_options.compilationDatabasePath == owned.path
  then
    config.init_options.compilationDatabasePath = nil
    config._dotfiles_clangd_database = nil
  end
  -- Neovim 0.12's :lsp restart uses this native boundary, retaining attached
  -- buffers. Name-based :lsp restart clangd would restart unrelated projects.
  client.config = config
  local ok, err = pcall(client._restart, client, client.exit_timeout)
  if not ok then
    client.config = original
    return false, tostring(err)
  end
  return true, "Refreshing clangd for " .. client.root_dir
end

return M

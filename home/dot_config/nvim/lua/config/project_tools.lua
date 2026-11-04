-- An on-demand view of current buffer facts, not another tool resolver.
local M = {}

local function text(value)
  if value == nil or value == "" then
    return "not reported"
  end
  if type(value) == "table" then
    return vim.json.encode(value)
  end
  return tostring(value):gsub("[\r\n]", " ")
end

local function attempt(label, callback, errors)
  local ok, result = pcall(callback)
  if ok then
    return result
  end
  errors[#errors + 1] = label .. ": " .. text(result)
end

function M.snapshot(buf)
  buf = (not buf or buf == 0) and vim.api.nvim_get_current_buf() or buf
  assert(vim.api.nvim_buf_is_valid(buf), "ProjectTools: buffer is no longer available")
  local info = {
    buffer = buf,
    file = vim.api.nvim_buf_get_name(buf),
    filetype = vim.bo[buf].filetype,
    cwd = vim.fn.getcwd(),
    modified = vim.bo[buf].modified,
    clients = {},
    diagnostics = {},
    formatters = {},
    errors = {},
    extra = {},
  }
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    info.clients[#info.clients + 1] = {
      id = client.id,
      name = client.name,
      root = client.root_dir,
      initialized = client.initialized,
      command = type(client.config.cmd) == "table" and vim.deepcopy(client.config.cmd)
        or "custom transport (not evaluated)",
      formatting = client:supports_method("textDocument/formatting", buf),
    }
  end
  table.sort(info.clients, function(a, b)
    return a.id < b.id
  end)
  for ns, meta in pairs(vim.diagnostic.get_namespaces()) do
    local diagnostics = vim.diagnostic.get(buf, { namespace = ns })
    if #diagnostics > 0 then
      local counts, sources = { 0, 0, 0, 0 }, {}
      for _, diagnostic in ipairs(diagnostics) do
        local severity = diagnostic.severity or vim.diagnostic.severity.ERROR
        counts[severity] = (counts[severity] or 0) + 1
        sources[diagnostic.source or "not reported"] = true
      end
      local names = vim.tbl_keys(sources)
      table.sort(names)
      info.diagnostics[#info.diagnostics + 1] = { namespace = ns, name = meta.name, counts = counts, sources = names }
    end
  end
  table.sort(info.diagnostics, function(a, b)
    return a.namespace < b.namespace
  end)

  -- Use the same native source/priority resolution as :LazyFormatInfo. This
  -- may lazily load the installed formatter integration, but never formats.
  local format = attempt("Formatting status", function()
    return require("lazyvim.util.format")
  end, info.errors)
  if format then
    info.autoformat = format.enabled(buf)
    local resolved = attempt("Formatting sources", function()
      return format.resolve(buf)
    end, info.errors)
    for _, formatter in ipairs(resolved or {}) do
      if #formatter.resolved > 0 then
        info.formatters[#info.formatters + 1] = {
          name = formatter.name,
          active = formatter.active,
          sources = vim.deepcopy(formatter.resolved),
        }
      end
    end
  end
  local conform = package.loaded.conform
  if conform then
    info.conform = attempt("Conform plan", function()
      local planned, lsp = conform.list_formatters_to_run(buf)
      return { planned = planned, lsp = lsp }
    end, info.errors)
  end
  local python = package.loaded["config.python_context"]
  if info.filetype == "python" and python then
    local result = attempt("Python context", function()
      local context, err = python.resolve(buf)
      return { context = context, error = err }
    end, info.errors)
    if result and result.context then
      local context = result.context
      info.python = { root = context.root, python = context.python, source = context.source }
    elseif result then
      info.errors[#info.errors + 1] = "Python context: " .. text(result.error)
    end
  end
  if vim.tbl_contains({ "c", "cpp", "objc", "objcpp", "cuda" }, info.filetype) then
    local lines = attempt("C/C++ context", function()
      local status = require("config.clangd_status")
      return status.lines(status.snapshot(buf))
    end, info.errors)
    if lines then
      info.extra[#info.extra + 1] = { title = "C/C++ context", lines = lines }
    end
  elseif info.filetype == "rust" then
    local lines = attempt("Rust context", function()
      return require("config.rust_runnable_info").summary_lines(buf)
    end, info.errors)
    if lines then
      info.extra[#info.extra + 1] = { title = "Rust context", lines = lines }
    end
  end
  return info
end

function M.lines(info)
  local lines = {
    "Project tools — current file",
    "File: " .. text(info.file),
    "Filetype: " .. text(info.filetype),
    "Editor cwd: " .. text(info.cwd),
    "Unsaved changes: " .. tostring(info.modified),
    "",
    "Attached language services (client-reported roots; no root is inferred):",
  }
  if #info.clients == 0 then
    lines[#lines + 1] = "  None attached."
  end
  for _, client in ipairs(info.clients) do
    lines[#lines + 1] = ("  %s #%d — %s"):format(
      client.name,
      client.id,
      client.initialized and "initialized" or "starting"
    )
    lines[#lines + 1] = "    Root: " .. text(client.root)
    lines[#lines + 1] = "    Configured command: " .. text(client.command)
    lines[#lines + 1] = "    Whole-file formatting capability: " .. tostring(client.formatting)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Formatting on save: "
    .. (info.autoformat == nil and "unknown" or info.autoformat and "enabled" or "disabled")
  if #info.formatters == 0 then
    lines[#lines + 1] = "  No formatter currently available; an attached server may still be starting."
  end
  for _, formatter in ipairs(info.formatters) do
    lines[#lines + 1] = ("  %s [%s]: %s"):format(
      formatter.name,
      formatter.active and "selected" or "lower priority",
      table.concat(formatter.sources, ", ")
    )
  end
  if info.conform then
    lines[#lines + 1] = "  Conform plan (if formatting is requested; no formatter was run):"
    for _, formatter in ipairs(info.conform.planned) do
      lines[#lines + 1] = "    " .. formatter.name .. " — " .. text(formatter.command)
      lines[#lines + 1] = "      Cwd: " .. text(formatter.cwd)
    end
    lines[#lines + 1] = "    Use LSP: " .. tostring(info.conform.lsp)
  end
  lines[#lines + 1] = "  Native details: :LazyFormatInfo / :ConformInfo"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Published diagnostics for this file (stored counts, not duplicate detection):"
  if #info.diagnostics == 0 then
    lines[#lines + 1] = "  No stored diagnostics; this does not prove analysis is complete."
  end
  for _, diagnostic in ipairs(info.diagnostics) do
    local c = diagnostic.counts
    lines[#lines + 1] = ("  %s: %d error, %d warning, %d info, %d hint — sources: %s"):format(
      text(diagnostic.name),
      c[1],
      c[2],
      c[3],
      c[4],
      table.concat(diagnostic.sources, ", ")
    )
  end
  if info.python then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Python target project: " .. text(info.python.root)
    lines[#lines + 1] = "  Interpreter: " .. text(info.python.python)
    lines[#lines + 1] = "  Selection source: " .. text(info.python.source)
  end
  for _, section in ipairs(info.extra) do
    lines[#lines + 1] = ""
    lines[#lines + 1] = section.title .. ":"
    vim.list_extend(lines, section.lines)
  end
  if #info.errors > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Unavailable inspection details:"
    for _, err in ipairs(info.errors) do
      lines[#lines + 1] = "  " .. err
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Snapshot only. Close with q; rerun :ProjectTools from the source buffer to refresh."
  return lines
end

function M.open(buf)
  local info = M.snapshot(buf)
  local report = vim.api.nvim_create_buf(false, true)
  vim.bo[report].buftype = "nofile"
  vim.bo[report].bufhidden = "wipe"
  vim.bo[report].swapfile = false
  vim.bo[report].filetype = "text"
  vim.api.nvim_buf_set_lines(report, 0, -1, false, M.lines(info))
  vim.bo[report].modifiable = false
  local win = vim.api.nvim_open_win(report, true, {
    relative = "editor",
    width = math.max(1, math.min(110, vim.o.columns - 4)),
    height = math.max(1, math.min(32, vim.o.lines - 4)),
    row = 1,
    col = 1,
    style = "minimal",
    border = "rounded",
    title = " Project tools ",
  })
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = report, desc = "Close project tools" })
  return report, info
end

return M

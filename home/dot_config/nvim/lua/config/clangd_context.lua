local M = {}

local function managed_database(root)
  if not root or vim.fn.filereadable(root .. "/.cxx.toml") ~= 1 then
    return
  end
  local database = require("config.cpp").compile_database(root)
  local config_file = root .. "/.clangd"
  if vim.fn.filereadable(database) ~= 1 or vim.fn.filereadable(config_file) ~= 1 then
    return
  end
  -- Recognize cxx's old/new stock layouts, not arbitrary YAML. Pinning a
  -- client-wide database overrides .clangd's lookup policy, so customized or
  -- conditional configurations must retain native clangd discovery instead.
  local config = table.concat(vim.fn.readfile(config_file), "\n")
  -- A single quoted IgnoreHeader scalar changes diagnostics, not database lookup.
  -- Accept only this appended shape; other custom YAML retains native discovery.
  config = config:gsub("\n  Includes:\n    IgnoreHeader: '[^'\n]*'$", "")
  local build = "CompileFlags:\n  CompilationDatabase: build/dev\n\n"
  local scope = "---\nIf:\n  PathMatch: [(src|include|tests)/.*, '[^/]+\\.(c|cc|cpp|cxx|h|hh|hpp|hxx|inc)']\n\n"
  for _, prefix in ipairs({ build, build .. scope }) do
    local stock = prefix .. "Diagnostics:\n  MissingIncludes: "
    if config == stock .. "Strict" or config == stock .. "None" then
      return vim.fs.dirname(database)
    end
  end
end

function M.root_dir(bufnr, on_dir)
  local markers = vim.list_extend({ ".clangd", ".cxx.toml" }, vim.lsp.config.clangd.root_markers or {})
  local root = vim.fs.root(bufnr, markers)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local extension = vim.fn.fnamemodify(filename, ":e")
  local header = extension == "" or vim.tbl_contains({ "h", "hh", "hpp", "hxx", "inc" }, extension)

  -- A definition jump into an external header must stay on the originating
  -- clangd: its HeaderIncluderCache owns the source file's compile command.
  -- Never borrow another project's root or force a language standard.
  if not root and header then
    -- One buffer has one compilation context, even when two projects are open.
    local clients = vim.lsp.get_clients({ name = "clangd", bufnr = bufnr })
    if #clients == 0 then
      local origin = vim.api.nvim_get_current_buf()
      if origin == bufnr then
        origin = vim.fn.bufnr("#")
      end
      clients = origin > 0 and vim.lsp.get_clients({ name = "clangd", bufnr = origin }) or {}
    end
    if #clients == 1 and not clients[1]:is_stopped() then
      root = clients[1].root_dir
    end
    -- Also support opening an SDK header first from a managed project's cwd.
    if not root then
      local cwd_root = vim.fs.root(vim.fn.getcwd(), ".cxx.toml")
      if managed_database(cwd_root) then
        root = cwd_root
      end
    end
  end
  on_dir(root)
end

function M.before_init(params, config)
  if config.init_options and config.init_options.compilationDatabasePath then
    return
  end
  for _, arg in ipairs(type(config.cmd) == "table" and config.cmd or {}) do
    if arg == "--compile-commands-dir" or arg:match("^%-%-compile%-commands%-dir=") then
      return
    end
  end
  local database = managed_database(config.root_dir)
  if database then
    config.init_options = config.init_options or {}
    config.init_options.compilationDatabasePath = database
    params.initializationOptions = config.init_options
  end
end

return M

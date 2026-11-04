-- Resolve tools from their target project, never the last globally activated venv.
local M = {}
local selections = {}
local explicit_choices = {}
local automatic = {}
local activating = false
local markers = { "pyproject.toml", "setup.cfg", "mypy.ini", "pytest.ini", "setup.py", "uv.lock", ".git" }
local initial_venv = vim.env.VIRTUAL_ENV ~= "" and vim.env.VIRTUAL_ENV or nil
local initial_conda = vim.env.CONDA_PREFIX ~= "" and vim.env.CONDA_PREFIX or nil
local initial_kind = initial_venv and "venv" or "anaconda"
local initial_env = initial_venv or initial_conda
local initial_path = vim.env.PATH or ""
local clean_path = {}
for directory in initial_path:gmatch("[^:]+") do
  if not initial_env or directory ~= vim.fs.joinpath(initial_env, "bin") then
    clean_path[#clean_path + 1] = directory
  end
end
local base_path = table.concat(clean_path, ":")

function M.root(source)
  source = source or 0
  if type(source) == "number" then
    source = vim.api.nvim_buf_get_name(source)
  end
  if source == "" then
    source = vim.fn.getcwd()
  end
  source = vim.fs.normalize(vim.fn.fnamemodify(source, ":p"))
  local root = vim.fs.root(source, markers) or (vim.fn.isdirectory(source) == 1 and source or vim.fs.dirname(source))
  return vim.uv.fs_realpath(root) or root
end

local initial_root = M.root(vim.fn.getcwd())

local function interpreter(environment)
  return vim.fs.joinpath(environment, "bin", "python")
end

local function discovered(root)
  local uv_root = vim.fs.root(root, "uv.lock")
  if uv_root then
    local environment = vim.env.UV_PROJECT_ENVIRONMENT
    if not environment or environment == "" then
      environment = ".venv"
    end
    if environment:sub(1, 1) ~= "/" then
      environment = vim.fs.joinpath(uv_root, environment)
    end
    return { python = interpreter(vim.fs.normalize(environment)), kind = "venv", source = "uv" }
  end
  for _, directory in ipairs({ ".venv", "venv", "env", ".env" }) do
    local environment = vim.fs.joinpath(root, directory)
    if vim.fn.filereadable(vim.fs.joinpath(environment, "pyvenv.cfg")) == 1 then
      return { python = interpreter(environment), kind = "venv", source = "project" }
    end
  end
end

local function system_python()
  for _, name in ipairs({ "python3", "python" }) do
    for _, directory in ipairs(clean_path) do
      local candidate = vim.fs.joinpath(directory, name)
      if vim.fn.executable(candidate) == 1 then
        return candidate
      end
    end
  end
end

-- Selections restored by venv-selector are scoped to the buffer's project.
-- Automatic uv activation is deliberately not saved as a manual selection.
function M.remember(python, kind, buf, explicit)
  if activating or not python or not buf or not vim.api.nvim_buf_is_valid(buf) then
    return 0
  end
  local root = M.root(buf)
  if not explicit and automatic[root] and automatic[root].python == python then
    return 0
  end
  selections[root] = { python = python, kind = kind, source = "selected" }
  if explicit then
    explicit_choices[root] = { python = python, kind = kind }
  end
  return 0
end

function M.resolve(source)
  local root = M.root(source)
  local choice = selections[root]
  if choice == false then
    choice = { python = system_python(), source = "deactivated" }
  elseif not choice then
    -- A currently edited project sees changes to UV_PROJECT_ENVIRONMENT at once.
    -- Background/RunLast targets retain their own last activated project context.
    choice = (root == M.root(0) and discovered(root)) or automatic[root] or discovered(root)
  end
  if not choice and initial_env and root == initial_root then
    choice = { python = interpreter(initial_env), kind = initial_kind, source = "shell" }
  end
  choice = choice or { python = system_python(), source = "system" }
  if not choice.python or vim.fn.executable(choice.python) ~= 1 then
    return nil,
      ("Python environment for %s is unavailable: %s. Create it outside Neovim or select an existing environment with :VenvSelect."):format(
        root,
        choice.python or "python3/python"
      )
  end
  local environment = choice.kind and vim.fs.dirname(vim.fs.dirname(choice.python)) or nil
  return {
    root = root,
    python = choice.python,
    source = choice.source,
    env = {
      VIRTUAL_ENV = choice.kind == "venv" and environment or "",
      CONDA_PREFIX = choice.kind == "anaconda" and environment or "",
      PATH = vim.fs.dirname(choice.python) .. ":" .. base_path,
    },
  }
end

function M.require_context(source)
  local context, err = M.resolve(source)
  if not context then
    error(err, 0)
  end
  return context
end

function M.activate(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "python" or vim.bo[buf].buftype ~= "" then
    return
  end
  -- Respect explicit deactivation; do not turn a user's disabled buffer back on.
  if vim.b[buf].venv_selector_disabled or buf ~= vim.api.nvim_get_current_buf() then
    return
  end
  local root = M.root(buf)
  if selections[root] == false then
    return
  end
  local choice = selections[root] or discovered(root)
  if not choice or vim.fn.executable(choice.python) ~= 1 then
    return
  end
  if not selections[root] then
    automatic[root] = choice
  end
  activating = true
  local ok, err =
    pcall(require("venv-selector.venv").activate_for_buffer, choice.python, choice.kind, buf, { save_cache = false })
  activating = false
  if not ok then
    vim.notify(err, vim.log.levels.ERROR, { title = "Python" })
  end
end

function M.setup_selector(opts)
  local selector = require("venv-selector")
  selector.setup(opts)
  local project_root = require("venv-selector.project_root")
  local key_for_buf = project_root.key_for_buf
  project_root.key_for_buf = function(buf, markers)
    buf = buf or vim.api.nvim_get_current_buf()
    if
      vim.api.nvim_buf_is_valid(buf)
      and vim.bo[buf].buftype == ""
      and vim.bo[buf].filetype == "python"
      and vim.api.nvim_buf_get_name(buf) ~= ""
    then
      -- Generic clients such as Copilot can share an unrelated cwd across projects.
      -- Cache saves and restores must use the same target root as Python tools.
      return M.root(buf)
    end
    return key_for_buf(buf, markers)
  end
  local deactivate = selector.deactivate
  selector.deactivate = function()
    local root = M.root(0)
    selections[root] = false
    explicit_choices[root] = false
    automatic[root] = nil
    return deactivate()
  end
  -- Observe the buffer-aware API after activation. Its same-interpreter fast path
  -- skips hooks, so hooks alone lose an explicit selection in another project.
  local venv = require("venv-selector.venv")
  local activate = venv.activate_for_buffer
  venv.activate_for_buffer = function(python, kind, buf, activation_opts)
    kind = kind or "venv"
    local explicit = not activation_opts or activation_opts.save_cache ~= false
    if not explicit and buf and vim.api.nvim_buf_is_valid(buf) then
      local choice = explicit_choices[M.root(buf)]
      -- A queued cache restore must not undo a newer user choice or deactivation.
      -- Reject it before the plugin changes PATH, buffer state or LSP/DAP hooks.
      if choice == false or (choice and (choice.python ~= python or choice.kind ~= kind)) then
        return false
      end
    end
    local same = selector.python() == python
    local result = activate(python, kind, buf, activation_opts)
    if result then
      M.remember(python, kind, buf, explicit)
      if same and explicit and buf and vim.api.nvim_buf_is_valid(buf) then
        vim.b[buf].venv_selector_last_python = python
        vim.b[buf].venv_selector_last_type = kind
        require("venv-selector.cached_venv").save(python, kind, buf)
      end
    end
    return result
  end
  local group = vim.api.nvim_create_augroup("dotfiles_uv_venv", { clear = true })
  local function schedule(args)
    vim.schedule(function()
      M.activate(args.buf)
    end)
  end
  vim.api.nvim_create_autocmd("BufEnter", { group = group, pattern = "*.py", callback = schedule })
  vim.api.nvim_create_autocmd("FileType", { group = group, pattern = "python", callback = schedule })
  local buf = vim.api.nvim_get_current_buf()
  vim.schedule(function()
    M.activate(buf)
  end)
end

function M.neotest_adapter(opts)
  opts = vim.tbl_extend("keep", opts or {}, { runner = "pytest" })
  local function for_target(source)
    local root = M.root(source)
    local command = opts.python
    if type(command) == "function" then
      command = command(root)
    end
    local context
    if command then
      local python = type(command) == "table" and command[1] or command
      assert(type(python) == "string", "Python adapter option must return a command string or list")
      if python:find("/", 1, true) and python:sub(1, 1) ~= "/" then
        python = vim.fs.normalize(vim.fs.joinpath(root, python))
        if type(command) == "table" then
          command = vim.deepcopy(command)
          command[1] = python
        else
          command = python
        end
      end
      local executable = vim.fn.exepath(python)
      assert(executable ~= "", "Explicit Python interpreter is unavailable: " .. python)
      local prefix = vim.fs.dirname(vim.fs.dirname(executable))
      local venv = vim.fn.filereadable(vim.fs.joinpath(prefix, "pyvenv.cfg")) == 1
      local conda = vim.fn.isdirectory(vim.fs.joinpath(prefix, "conda-meta")) == 1
      context = {
        root = root,
        env = {
          VIRTUAL_ENV = venv and prefix or "",
          CONDA_PREFIX = conda and prefix or "",
          PATH = vim.fs.dirname(executable) .. ":" .. base_path,
        },
      }
    else
      context = M.require_context(source)
      command = context.python
    end
    -- The upstream adapter can fall back to cwd for .git/uv.lock-only projects.
    -- Bind each discovery/run to its file instead, without shared mutable state.
    local configured = vim.tbl_extend("force", opts, {
      python = function()
        return command
      end,
    })
    return require("neotest-python")(configured), context
  end
  local adapter = require("neotest-python")(opts)
  adapter.root = M.root
  adapter.discover_positions = function(path)
    local target = for_target(path)
    return target.discover_positions(path)
  end
  adapter.build_spec = function(args)
    local target, context = for_target(args.tree:data().path)
    local spec = target.build_spec(args)
    spec.cwd = context.root
    spec.env = vim.tbl_extend("force", context.env, spec.env or {})
    if type(spec.strategy) == "table" then
      spec.strategy.cwd = context.root
      spec.strategy.env = vim.tbl_extend("force", context.env, spec.strategy.env or {})
    end
    return spec
  end
  return adapter
end

function M.setup_dap()
  local dap = require("dap")
  local original = dap.adapters.python
  local adapter = function(callback, config)
    -- Explicit launch.json / Neotest interpreters have priority.
    if config.request == "launch" and not config.python and not config.pythonPath then
      local source = config.program or config.cwd or vim.api.nvim_buf_get_name(0)
      if config.program and config.cwd and config.program:sub(1, 1) ~= "/" then
        source = vim.fs.joinpath(config.cwd, config.program)
      end
      local context, err = M.resolve(source)
      if not context then
        vim.notify(err, vim.log.levels.ERROR, { title = "Python" })
        return
      end
      config.pythonPath = context.python
      config.cwd = config.cwd or context.root
      config.env = vim.tbl_extend("force", context.env, config.env or {})
    end
    if config.request == "launch" and config.envFile == nil and config.cwd then
      config.envFile = vim.fs.joinpath(config.cwd, ".env")
    end
    original(callback, config)
  end
  dap.adapters.python = adapter
  dap.adapters.debugpy = adapter
end

function M.ty_check(source)
  if vim.fn.executable("ty") ~= 1 then
    vim.notify("ty is not installed; select it in :Mason.", vim.log.levels.WARN, { title = "Python" })
    return
  end
  local context, err = M.resolve(source)
  if not context then
    vim.notify(err, vim.log.levels.ERROR, { title = "Python" })
    return
  end
  local command = { "ty", "check" }
  vim.list_extend(command, { "--project", context.root, "--python", context.python })
  return Snacks.terminal(command, { cwd = context.root, env = context.env })
end

return M

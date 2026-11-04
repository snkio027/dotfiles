local M = {}

-- DAP evaluates a callable configuration before resolving its fields. Capture
-- the editing project once, before the executable prompt can change focus.
function M.launch()
  return setmetatable({
    type = "codelldb",
    request = "launch",
    name = "Launch Zig executable",
    stopOnEntry = false,
  }, {
    __call = function(config)
      local root = LazyVim.root()
      local program = vim.fn.input("Path to executable: ", vim.fs.joinpath(root, "zig-out/bin/"), "file")
      local resolved = vim.deepcopy(config)
      setmetatable(resolved, nil)
      resolved.cwd = root
      if program == "" then
        resolved.program = require("dap").ABORT
      else
        program = vim.fn.expand(program)
        resolved.program = vim.fs.abspath(vim.fs.joinpath(root, program))
        if program:sub(1, 1) == "/" then
          resolved.program = vim.fs.normalize(program)
        end
      end
      return resolved
    end,
  })
end

local active

local function read(path)
  local file = assert(io.open(path, "rb"))
  local content = file:read("*a")
  file:close()
  return content
end

local function root_for_buffer()
  local path = vim.api.nvim_buf_get_name(0)
  local root = vim.fs.root(path, { "build.zig", ".git" })
  return root and (vim.uv.fs_realpath(root) or root)
end

local function inside(root, path)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function project_path(root, value, name)
  assert(
    type(value) == "string" and value ~= "" and not vim.startswith(value, "/"),
    name .. " must be a project-relative path"
  )
  local path = vim.fs.normalize(vim.fs.joinpath(root, value))
  assert(inside(root, path), name .. " must stay inside the project")
  local real = vim.uv.fs_realpath(path)
  assert(not real or inside(root, real), name .. " must not point outside the project")
  return path
end

local function canonical_file(path)
  if path == "" then
    return path
  end
  local real = vim.uv.fs_realpath(path)
  if real then
    return real
  end
  local parent = vim.uv.fs_realpath(vim.fs.dirname(path))
  return parent and vim.fs.joinpath(parent, vim.fs.basename(path)) or vim.fs.normalize(path)
end

local function snapshot(root)
  local files, buffers = {}, {}
  local function visit(directory)
    for name, kind in vim.fs.dir(directory) do
      local path = vim.fs.joinpath(directory, name)
      if kind == "directory" and not vim.tbl_contains({ ".git", ".zig-cache", "zig-cache", "zig-out" }, name) then
        visit(path)
      elseif kind == "file" and (name:match("%.zig$") or name:match("%.zon$") or path == root .. "/.nvim/zig.json") then
        files[path] = vim.fn.sha256(read(path))
      end
    end
  end
  visit(root)
  -- The explicit launch contract may itself (or its directory) be a symlink.
  -- Read its content directly rather than relying on directory entry kinds.
  files[root .. "/.nvim/zig.json"] = vim.fn.sha256(read(root .. "/.nvim/zig.json"))
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and inside(root, canonical_file(vim.api.nvim_buf_get_name(buf))) then
      assert(not vim.bo[buf].modified, "Save project buffers before building and debugging Zig")
      buffers[buf] = vim.api.nvim_buf_get_changedtick(buf)
    end
  end
  return { files = files, buffers = buffers }
end

function M.output()
  if not M.last_log then
    return vim.notify("No Zig build output yet", vim.log.levels.INFO)
  end
  vim.cmd("botright new")
  vim.bo.buftype, vim.bo.bufhidden, vim.bo.swapfile = "nofile", "wipe", false
  vim.api.nvim_buf_set_lines(0, 0, -1, false, M.last_log)
  vim.bo.modifiable = false
end

function M.stop()
  if active then
    active.cancelled = true
    if active.job then
      vim.fn.jobstop(active.job)
    end
  end
end

-- An explicit project contract avoids guessing build steps, target names or
-- output layouts from build.zig. The original manual DAP launch stays available.
function M.build_debug()
  assert(not active, "A Zig build/debug request is already running")
  local root = assert(root_for_buffer(), "Open a Zig project file first")
  root = assert(vim.uv.fs_realpath(root))
  local config_path = root .. "/.nvim/zig.json"
  assert(
    vim.uv.fs_stat(config_path),
    "Create .nvim/zig.json with build.argv and debug.program, or use the existing manual Zig launch"
  )
  local config = vim.json.decode(read(config_path))
  assert(
    type(config) == "table" and type(config.build) == "table" and type(config.debug) == "table",
    "Expected build.argv and debug.program in .nvim/zig.json"
  )
  local argv = config.build.argv
  assert(vim.islist(argv) and #argv >= 2, "build.argv must be a non-empty argument array")
  for _, arg in ipairs(argv) do
    assert(type(arg) == "string" and not arg:find("%z"), "build.argv contains an invalid argument")
  end
  assert(
    argv[1] == "zig" and vim.tbl_contains({ "build", "build-exe" }, argv[2]),
    "build.argv must explicitly use zig build or zig build-exe"
  )
  local program = project_path(root, config.debug.program, "debug.program")
  local cwd = project_path(root, config.debug.cwd or ".", "debug.cwd")
  assert(vim.fn.isdirectory(cwd) == 1, "debug.cwd must exist")
  local canonical_cwd = assert(vim.uv.fs_realpath(cwd))
  local args = config.debug.args or {}
  assert(vim.islist(args), "debug.args must be an argument array")
  for _, arg in ipairs(args) do
    assert(type(arg) == "string", "debug.args must contain strings")
  end
  local env = config.debug.env or vim.empty_dict()
  assert(type(env) == "table", "debug.env must be an object")
  if vim.tbl_isempty(env) then
    env = vim.empty_dict()
  end
  for key, value in pairs(env) do
    assert(type(key) == "string" and type(value) == "string", "debug.env must contain string values")
  end
  local before = snapshot(root)
  local request = { root = root, cancelled = false, program = program, before = before }
  active = request
  M.last_log = { "$ " .. table.concat(argv, " "), "cwd: " .. root }
  M.last_result = nil
  local function output(_, lines)
    for _, line in ipairs(lines) do
      if line ~= "" then
        M.last_log[#M.last_log + 1] = line
      end
    end
  end
  request.job = vim.fn.jobstart(argv, {
    cwd = root,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = output,
    on_stderr = output,
    on_exit = function(_, code)
      vim.schedule(function()
        if active ~= request then
          return
        end
        active = nil
        local ok, err = pcall(function()
          assert(not request.cancelled, "Zig build cancelled; debugger was not started")
          assert(code == 0, "Zig build failed; debugger was not started")
          assert(root_for_buffer() == root, "Editing project changed during the build; debugger was not started")
          assert(
            vim.deep_equal(before, snapshot(root)),
            "Project source, buffers or Zig configuration changed during the build; rebuild before debugging"
          )
          assert(
            vim.uv.fs_realpath(cwd) == canonical_cwd and inside(root, canonical_cwd),
            "Zig debug cwd changed during the build; debugger was not started"
          )
          assert(vim.fn.executable(program) == 1, "The configured Zig executable was not produced")
          assert(inside(root, assert(vim.uv.fs_realpath(program))), "The built executable points outside the project")
          require("lazy").load({ plugins = { "nvim-dap" } })
          assert(not require("dap").session(), "Another debugger is active; launch was stopped")
          require("dap").run({
            type = "codelldb",
            request = "launch",
            name = "Build and Debug Zig Project",
            program = program,
            cwd = cwd,
            args = args,
            env = env,
            stopOnEntry = false,
          })
        end)
        M.last_result = { code = code, launched = ok, error = not ok and tostring(err) or nil, root = root }
        if not ok then
          M.last_log[#M.last_log + 1] = tostring(err)
          vim.notify(tostring(err) .. "; :ZigBuildDebugOutput shows the build log", vim.log.levels.WARN)
        end
      end)
    end,
  })
  if request.job <= 0 then
    active = nil
    error("Could not start the configured Zig build")
  end
end

return M

-- Execution compatibility for the pinned neotest-zig discovery adapter.
-- Own all generated files; never write its fixed project neotest_build.zig.
local M = {}
local uv = vim.uv
local dap_busy = false

local function read(path)
  local file = assert(io.open(path, "rb"))
  local bytes = file:read("*a")
  file:close()
  return bytes
end

local function write(path, bytes)
  local file = assert(io.open(path, "wb"))
  file:write(bytes)
  file:close()
end

local function canonical(path)
  return uv.fs_realpath(path) or vim.fs.normalize(vim.fs.abspath(path))
end

local helper_remove

local function helper_create(root, content)
  -- mkstemp-style exclusive creation: a collision never truncates a user file.
  for _ = 1, 16 do
    local name = ".dotfiles-neotest-" .. tostring(uv.hrtime()) .. ".zig"
    local path = vim.fs.joinpath(root, name)
    local fd, err = uv.fs_open(path, "wx", 384)
    if fd then
      local stat = assert(uv.fs_fstat(fd))
      local owner = { path = path, dev = stat.dev, ino = stat.ino, content = "" }
      local ok, failure = pcall(function()
        local offset = 0
        while offset < #content do
          local written, write_error = uv.fs_write(fd, content:sub(offset + 1), offset)
          assert(written and written > 0, write_error or "Short Zig helper write")
          offset = offset + written
          owner.content = content:sub(1, offset)
        end
      end)
      uv.fs_close(fd)
      if not ok then
        pcall(helper_remove, owner)
        error(failure)
      end
      return owner
    end
    assert(tostring(err):find("EEXIST", 1, true), err)
  end
  error("Unable to reserve a unique Zig test helper")
end

helper_remove = function(owner)
  if not owner then
    return
  end
  local stat = uv.fs_lstat(owner.path)
  if stat and stat.type == "file" and stat.dev == owner.dev and stat.ino == owner.ino then
    local ok, bytes = pcall(read, owner.path)
    if ok and bytes == owner.content then
      assert(uv.fs_unlink(owner.path))
    end
  end
end

local function selected(tree, original)
  local inputs = {}
  for _, node in tree:iter_nodes() do
    local data = node:data()
    if data.type == "test" then
      inputs[#inputs + 1] = {
        id = data.id,
        name = original._get_zig_symbol_name_from_node(node),
        path = canonical(data.path),
      }
    end
  end
  assert(#inputs > 0, "No Zig tests were selected")
  return inputs
end

local function strategy(spec, context)
  local nio = require("nio")
  local integrated = require("neotest.client.strategies.integrated")
  local data = spec.context
  local done = nio.control.future()
  local active, result_code, cancelled
  write(data.output, "")
  local function append(bytes)
    local file = assert(io.open(data.output, "ab"))
    file:write(bytes)
    file:close()
  end
  local function execute(child, debugger)
    if cancelled then
      return 143
    end
    if debugger then
      active = assert(require("neotest.client.strategies.dap")(child, context), "DAP strategy did not start")
    else
      child.strategy = {}
      active = integrated(child)
    end
    local code = active.result()
    local ok, bytes = pcall(read, active.output())
    if ok then
      append(bytes)
    end
    active = nil
    return cancelled and 143 or code
  end
  nio.run(function()
    local owns_dap = false
    local ok, err = xpcall(function()
      if data.debug then
        nio.scheduler()
        -- Reserve after the scheduler boundary without yielding between check
        -- and reservation. Concurrent requests cannot both enter compilation.
        assert(not dap_busy, "Another Zig test debugger is active; stop it before starting a second one")
        dap_busy, owns_dap = true, true
        require("lazy").load({ plugins = { "nvim-dap" } })
        assert(not require("dap").session(), "A debugger is already active; stop it before debugging Zig tests")
      end
      result_code = execute({ command = spec.command, cwd = data.root, env = spec.env })
      if result_code ~= 0 or not data.debug and data.buildfile then
        return
      end
      local launches = data.buildfile and vim.json.decode(read(data.manifest))
        or {
          { program = data.program, cwd = data.root, args = data.args, env = {}, output = data.result },
        }
      assert(#launches > 0, "The Zig build produced no native test launch configuration")
      for _, launch in ipairs(launches) do
        if cancelled then
          result_code = 143
          return
        end
        local child = { cwd = launch.cwd, env = vim.tbl_extend("force", spec.env or {}, launch.env) }
        if data.debug then
          child.strategy = {
            type = "codelldb",
            request = "launch",
            name = "Zig test (project-owned artifact)",
            program = launch.program,
            cwd = launch.cwd,
            args = launch.args,
            env = child.env,
            stopOnEntry = false,
          }
        else
          child.command = vim.list_extend({ launch.program }, launch.args)
        end
        local code = execute(child, data.debug)
        if code ~= 0 then
          result_code = code
        end
      end
    end, debug.traceback)
    local clean_ok, clean_err = pcall(helper_remove, data.helper)
    if not clean_ok then
      append("\nZig helper cleanup: " .. tostring(clean_err) .. "\n")
    end
    if owns_dap then
      dap_busy = false
    end
    if not ok then
      data.error = tostring(err)
      append("\n" .. data.error .. "\n")
      result_code = 1
    end
    if cancelled then
      data.error, result_code = "Zig test run cancelled", 143
    end
    result_code = result_code or 1
    done.set()
  end)
  return {
    is_complete = done.is_set,
    output = function()
      return data.output
    end,
    result = function()
      done.wait()
      return result_code
    end,
    stop = function()
      cancelled = true
      if active then
        active.stop()
      end
    end,
    attach = function()
      if active then
        active.attach()
      end
    end,
    output_stream = function()
      local last = ""
      return function()
        while true do
          local text = read(data.output)
          if active then
            local ok, bytes = pcall(read, active.output())
            if ok then
              text = text .. bytes
            end
          end
          if #text > #last then
            local chunk = text:sub(#last + 1)
            last = text
            return chunk
          end
          if done.is_set() then
            return
          end
          nio.sleep(50)
        end
      end
    end,
  }
end

function M.adapter()
  local original = require("neotest-zig")
  local adapter = vim.tbl_extend("force", {}, original)
  adapter.name = "neotest-zig"
  adapter.root = function(path)
    path = canonical(path)
    local root = vim.fs.root(path, "build.zig")
    if root then
      return root
    end
    local stat = uv.fs_stat(path)
    if stat and stat.type == "file" then
      return path:match("%.zig$") and vim.fs.dirname(path) or nil
    end
    if stat and stat.type == "directory" then
      -- Standalone files need an explicit root too: another language adapter
      -- may claim this directory before Neotest considers open Zig buffers.
      for name, kind in vim.fs.dir(path) do
        if kind == "file" and name:match("%.zig$") then
          return path
        end
      end
    end
  end
  adapter.filter_dir = function(name)
    return not vim.tbl_contains({ ".git", ".zig-cache", "zig-cache", "zig-out" }, name)
  end
  adapter.build_spec = function(args)
    local nio = require("nio")
    nio.scheduler()
    local inputs = selected(args.tree, original)
    for _, input in ipairs(inputs) do
      local buffer = vim.fn.bufnr(input.path)
      assert(buffer == -1 or not vim.bo[buffer].modified, "Save the selected Zig test file before running it")
    end
    local root = adapter.root(args.tree:data().path) or vim.fs.dirname(inputs[1].path)
    root = canonical(root)
    local directory = assert(uv.fs_mkdtemp(vim.fn.tempname() .. "-zig-XXXXXX"))
    local source = vim.fs.joinpath(vim.fn.stdpath("config"), "zig")
    local input_path = vim.fs.joinpath(directory, "input.json")
    write(input_path, vim.json.encode(inputs))
    local data = {
      root = root,
      directory = directory,
      inputs = inputs,
      debug = args.strategy == "dap",
      buildfile = uv.fs_stat(vim.fs.joinpath(root, "build.zig")) ~= nil,
      output = vim.fs.joinpath(directory, "output.log"),
      manifest = vim.fs.joinpath(directory, "launch.json"),
      result = vim.fs.joinpath(directory, "result-0.json"),
      program = vim.fs.joinpath(directory, "tests"),
    }
    data.args = { "--dotfiles-input", input_path, "--dotfiles-output", data.result }
    local command
    if data.buildfile then
      data.helper = helper_create(root, read(vim.fs.joinpath(source, "build_adapter.zig")))
      command = {
        "zig",
        "build",
        data.debug and "dotfiles-debug-tests" or "test",
        "--build-file",
        data.helper.path,
        "--prefix",
        vim.fs.joinpath(directory, "install"),
        "-Ddotfiles-runner=" .. vim.fs.joinpath(source, "test_runner.zig"),
        "-Ddotfiles-input=" .. input_path,
        "-Ddotfiles-artifacts=" .. directory,
      }
      if data.debug then
        command[#command + 1] = "-Ddotfiles-debug=true"
      end
    else
      for _, input in ipairs(inputs) do
        assert(input.path == inputs[1].path, "A multi-file Zig project needs a native build.zig test step")
      end
      command = {
        "zig",
        "test",
        inputs[1].path,
        "--test-no-exec",
        "--test-runner",
        vim.fs.joinpath(source, "test_runner.zig"),
        "-femit-bin=" .. data.program,
      }
    end
    vim.list_extend(command, { "--cache-dir", vim.fs.joinpath(directory, "cache") })
    return {
      command = command,
      cwd = root,
      env = { ZIG_GLOBAL_CACHE_DIR = vim.fs.joinpath(vim.fn.stdpath("cache"), "zig-neotest") },
      context = data,
      strategy = strategy,
    }
  end
  adapter.results = function(spec, result)
    local data = spec.context
    local results = {}
    for _, input in ipairs(data.inputs) do
      results[input.id] = {
        status = "failed",
        output = data.output,
        short = data.error or "Selected test did not finish; inspect build/test output",
        errors = {},
      }
    end
    for _, path in ipairs(vim.fn.glob(vim.fs.joinpath(data.directory, "result-*.json"), false, true)) do
      local ok, records = pcall(function()
        return vim.json.decode(read(path))
      end)
      if ok then
        for _, record in ipairs(records) do
          if results[record.id] then
            local previous = results[record.id]
            local rank = { skipped = 1, passed = 2, failed = 3 }
            if not previous.observed or (rank[record.status] or 3) > (rank[previous.status] or 3) then
              results[record.id] = {
                status = record.status,
                output = data.output,
                short = record.short,
                errors = record.status == "failed" and {
                  { message = record.short, line = record.line and record.line - 1 },
                } or {},
                observed = true,
              }
            end
          end
        end
      end
    end
    -- A failed build with stale/partial results must never report all green.
    local reported_failure, incomplete = false, false
    for _, item in pairs(results) do
      reported_failure = reported_failure or item.observed and item.status == "failed"
      incomplete = incomplete or not item.observed
    end
    if result.code ~= 0 and (data.error or not reported_failure and not incomplete) then
      for _, item in pairs(results) do
        item.status, item.short = "failed", data.error or "Zig build/test process failed; inspect output"
      end
    end
    for _, item in pairs(results) do
      item.observed = nil
    end
    return results
  end
  return adapter
end

M._helper_create = helper_create
M._helper_remove = helper_remove
return M

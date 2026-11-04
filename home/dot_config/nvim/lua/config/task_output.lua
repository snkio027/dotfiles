local M = {}
local uv = vim.uv
local finished = { SUCCESS = true, FAILURE = true, CANCELED = true }

local function report(message, level)
  vim.notify(message, level or vim.log.levels.WARN, { title = "Task output" })
end

-- This is the selected task's retained buffer, not the current window, quickfix,
-- environment or an assertion that the process's complete byte stream survived.
local function snapshot(task)
  if task.status == "DISPOSED" then
    return nil, "This task's output is no longer available."
  end
  if not finished[task.status] then
    return nil, "Wait for the task to finish before exporting."
  end
  local buf = task:get_bufnr()
  if not buf or not vim.api.nvim_buf_is_loaded(buf) or vim.b[buf].overseer_task ~= task.id then
    return nil, "This task's output is no longer available."
  end
  return {
    schema_version = 1,
    task = {
      id = task.id,
      name = task.name,
      -- Overseer has already combined cmd/args. Preserve its actual execution
      -- representation, including list boundaries or a shell command string.
      command = vim.deepcopy(task.cmd),
      cwd = task.cwd,
      status = task.status,
      exit_code = task.exit_code == nil and vim.NIL or task.exit_code,
      started_at = task.time_start == nil and vim.NIL or task.time_start,
      finished_at = task.time_end == nil and vim.NIL or task.time_end,
    },
    captured_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    output_scope = "retained task buffer; earlier output may have been truncated",
    output_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
  }
end

-- Publish a complete private file without replacing a path created while the
-- prompt was open. link() refuses existing files, directories and symlinks.
local function write_new(path, data)
  local fd, temporary = uv.fs_mkstemp(vim.fs.dirname(path) .. "/.task-output-XXXXXX")
  if not fd then
    return nil, temporary
  end
  local ok, err = pcall(function()
    assert(uv.fs_fchmod(fd, 384)) -- 0600, independent of the user's umask
    local offset = 0
    while offset < #data do
      local written, reason = uv.fs_write(fd, data:sub(offset + 1), offset)
      assert(written and written > 0, reason or "Unable to write task output")
      offset = offset + written
    end
    assert(uv.fs_fsync(fd))
    assert(uv.fs_close(fd))
    fd = nil
    local linked, reason = uv.fs_link(temporary, path)
    assert(linked, reason)
  end)
  if fd then
    uv.fs_close(fd)
  end
  uv.fs_unlink(temporary)
  return ok, err
end

function M.export()
  local tasks = vim.tbl_filter(function(task)
    return finished[task.status]
  end, require("overseer").list_tasks({ include_ephemeral = true }))
  if #tasks == 0 then
    report("No completed tasks to export.")
    return
  end
  vim.ui.select(tasks, {
    prompt = "Export retained output (commands and output may contain sensitive data):",
    format_item = function(task)
      return ("#%s · %s · %s · %s"):format(task.id, task.status, task.name, task.cwd)
    end,
  }, function(task)
    if not task then
      return
    end
    local captured, err = snapshot(task)
    if not captured then
      report(err)
      return
    end
    -- Freeze before the asynchronous prompt: switching projects, disposing or
    -- restarting a task afterwards must not substitute a different run's data.
    local encoded, data = pcall(vim.json.encode, captured)
    if not encoded then
      report("Cannot encode this task output as JSON: " .. tostring(data), vim.log.levels.ERROR)
      return
    end
    data = data .. "\n"
    vim.ui.input({
      prompt = "Export task #" .. task.id .. " to NEW absolute JSON path: ",
      completion = "file",
    }, function(path)
      if not path or path == "" then
        return
      end
      if path:sub(1, 1) ~= "/" or path:find("%z") then
        report("Use an absolute path for a new file; existing paths are never overwritten.")
        return
      end
      local ok, reason = write_new(path, data)
      if not ok then
        report("Export failed: " .. tostring(reason), vim.log.levels.ERROR)
        return
      end
      report("Exported task #" .. task.id .. " to " .. path, vim.log.levels.INFO)
    end)
  end)
end

return M

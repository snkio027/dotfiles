-- Delegate preset inheritance/includes/conditions and step ordering to CMake.
-- The existing BuildTest entry intentionally retains its stricter pairing.
local M = {}
local active = {}

local function notify(message)
  vim.notify("CMake workflow: " .. message, vim.log.levels.ERROR)
end

function M.run(name)
  local cmake = require("cmake-tools")
  local root = vim.uv.fs_realpath(cmake.get_config().cwd)
  if not root then
    return notify("select an existing project directory first")
  end
  local function launch(preset)
    if not preset or preset == "" then
      return
    end
    if vim.uv.fs_realpath(cmake.get_config().cwd) ~= root then
      return notify("project changed while choosing a preset; choose again")
    end
    if active[root] and not active[root]:is_complete() then
      return notify("this project already has a native workflow running")
    end
    local config = cmake.get_config()
    if require("cmake-tools.utils").has_active_job(config.runner, config.executor) then
      return notify("wait for the project's current CMake task to finish")
    end
    local saved, err = require("config.cmake_workflow").save_project()
    if not saved then
      return notify(err)
    end
    if vim.uv.fs_realpath(cmake.get_config().cwd) ~= root then
      return notify("project changed during save; choose again")
    end
    local task = require("overseer").new_task({
      name = ("CMake Workflow · %s · %s"):format(vim.fs.basename(root), preset),
      cmd = require("cmake-tools.const").cmake_command,
      args = { "--workflow", "--preset", preset },
      cwd = root,
      strategy = { "jobstart", use_terminal = false },
      components = { "default", { "on_output_quickfix", open = false }, { "cmake_workflow_guard", root = root } },
      metadata = { cmake_workflow = { root = root, preset = preset } },
    })
    task:start()
    return task
  end
  if name and name ~= "" then
    return launch(name)
  end
  -- Accept a literal preset name as one argv element. CMake itself validates
  -- it, including user presets; no lossy parsing of its human-readable list.
  vim.ui.input({ prompt = "CMake workflow preset (" .. root .. "): " }, launch)
end

function M.is_active(root)
  root = vim.uv.fs_realpath(root)
  return root and active[root] and not active[root]:is_complete()
end

function M.guard(root)
  local group
  local function cleanup(_, task)
    if group then
      pcall(vim.api.nvim_del_augroup_by_id, group)
      group = nil
    end
    if active[root] == task then
      active[root] = nil
    end
  end
  return {
    on_pre_start = function(_, task)
      local ok, accepted = pcall(function()
        local cmake = require("cmake-tools")
        local config = cmake.get_config()
        if vim.uv.fs_realpath(config.cwd) ~= root then
          notify("select this task's project before restarting its workflow")
          return false
        end
        if M.is_active(root) and active[root] ~= task then
          notify("this project already has a native workflow running")
          return false
        end
        if require("cmake-tools.utils").has_active_job(config.runner, config.executor) then
          notify("wait for the current CMake task to finish")
          return false
        end
        local saved, err = require("config.cmake_workflow").save_project()
        if not saved then
          notify(err)
          return false
        end
        if vim.uv.fs_realpath(cmake.get_config().cwd) ~= root then
          notify("project changed during save")
          return false
        end
        return true
      end)
      if not ok then
        cleanup(nil, task)
        notify(tostring(accepted))
      end
      return ok and accepted or false
    end,
    -- Overseer can reject a later component or fail to start its strategy
    -- after on_pre_start. Reserve/watch only a successfully started task.
    on_start = function(_, task)
      active[root] = task
      group = vim.api.nvim_create_augroup("CMakeNativeWorkflow" .. task.id, { clear = true })
      vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        callback = function(event)
          local path = vim.uv.fs_realpath(vim.api.nvim_buf_get_name(event.buf))
          if path and vim.startswith(path, root .. "/") and not task:is_complete() then
            task:stop()
            notify("project saved during execution; workflow stopped, run it again")
          end
        end,
      })
    end,
    on_complete = cleanup,
    on_dispose = cleanup,
  }
end

function M.setup()
  vim.api.nvim_create_user_command("CMakeWorkflow", function(opts)
    M.run(opts.args)
  end, { nargs = "?", force = true, desc = "Run a native CMake workflow preset" })
end

return M

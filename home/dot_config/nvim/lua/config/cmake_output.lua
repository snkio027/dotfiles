local M = {}
local run_window, run_buffer

local function show_run(task)
  local buffer = task:get_bufnr()
  if not buffer then
    return
  end
  local current = vim.api.nvim_get_current_win()
  if
    not (
      run_window
      and vim.api.nvim_win_is_valid(run_window)
      and vim.api.nvim_win_get_tabpage(run_window) == vim.api.nvim_get_current_tabpage()
      and vim.api.nvim_win_get_buf(run_window) == run_buffer
    )
  then
    task:open_output("horizontal")
    run_window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_height(run_window, 12)
  end
  vim.api.nvim_win_set_buf(run_window, buffer)
  run_buffer = buffer
  vim.api.nvim_set_current_win(current)
end

function M.on_new_task(kind)
  return function(task)
    -- Presentation only: never rewrite argv, cwd, environment or exit status.
    local command = type(task.cmd) == "table" and table.concat(task.cmd, " ") or task.cmd
    local display = " " .. command:gsub("['\"]", "") .. " "
    local stage = kind == "runner" and "Run" or "Configure"
    if kind == "executor" then
      if display:find(" --build ", 1, true) then
        stage = "Build"
      elseif display:find(" --install ", 1, true) then
        stage = "Install"
      end
      task:add_component({ "on_output_quickfix", open_on_exit = "failure", items_only = true })
    elseif display:match("[%s/]ctest%s") then
      stage = "Test"
    end
    local cmake = require("cmake-tools")
    local config = cmake.get_config()
    local preset = kind == "executor" and stage == "Build" and config.build_preset or config.configure_preset
    local parts = { stage, vim.fs.basename(config.cwd) }
    if preset then
      parts[#parts + 1] = preset
    end
    -- The command line below shows the actual executable. launch_target can
    -- refer to a different target when CMakeQuickRun supplies an explicit one.
    task.name = table.concat(parts, " · ")
    task.metadata.cpp_workflow = true
    task:set_component({ "on_complete_notify", statuses = { "SUCCESS", "FAILURE", "CANCELED" } })
    task:set_component({
      "open_output",
      on_start = "never",
      on_complete = kind == "executor" and "failure" or "never",
      direction = "dock",
      focus = false,
    })
    if kind == "runner" then
      task:subscribe("on_start", show_run)
    end
  end
end

function M.render(task)
  local render = require("overseer.render")
  if not task.metadata.cpp_workflow then
    return render.format_standard(task)
  end
  if task.status == "SUCCESS" then
    return { render.status_and_name(task), render.duration(task) }
  end
  local lines = {
    render.status_and_name(task),
    render.join(render.duration(task), {
      { task.exit_code ~= nil and ("exit " .. task.exit_code) or "", "Comment" },
    }),
    render.cmd(task),
    { { "cwd: " .. task.cwd, "Comment" } },
  }
  vim.list_extend(lines, render.output_lines(task, { num_lines = 2 }))
  return render.remove_empty_lines(lines)
end

-- CMakeTools owns persistence and execution. Change only the chosen target's
-- working directory, on an explicit request; never guess from the current buffer.
function M.select_run_directory()
  local cmake = require("cmake-tools")
  local config = cmake.get_config()
  local target = cmake.get_launch_target()
  if not target or target == "" then
    vim.notify("Select a launch target first (:CMakeSelectLaunchTarget).", vim.log.levels.WARN)
    return
  end
  local function apply(path)
    if not path or path == "" then
      return
    end
    if cmake.get_config() ~= config or cmake.get_launch_target() ~= target then
      vim.notify("Project or target changed; run directory was not updated.", vim.log.levels.WARN)
      return
    end
    local stat = vim.uv.fs_stat(path)
    if path ~= "${dir.binary}" and (not stat or stat.type ~= "directory") then
      vim.notify("Run directory does not exist: " .. path, vim.log.levels.WARN)
      return
    end
    config.target_settings[target] = config.target_settings[target] or {}
    config.target_settings[target].working_dir = path
    vim.notify("Run directory · " .. target .. " · " .. path)
  end
  vim.ui.select({ "Project root", "Executable directory", "Custom directory" }, {
    prompt = "Run directory · " .. target,
  }, function(choice)
    if choice == "Project root" then
      apply(config.cwd)
    elseif choice == "Executable directory" then
      apply("${dir.binary}")
    elseif choice == "Custom directory" then
      vim.ui.input({ prompt = "Run directory (absolute): ", default = config.cwd, completion = "dir" }, function(path)
        if path and path ~= "" and not vim.startswith(path, "/") then
          vim.notify("Use an absolute run directory.", vim.log.levels.WARN)
          return
        end
        apply(path)
      end)
    end
  end)
end

return M

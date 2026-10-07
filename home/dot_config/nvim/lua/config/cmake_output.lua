local M = {}

function M.on_new_task(kind)
  return function(task)
    -- Presentation only: never rewrite argv, cwd, environment or exit status.
    local command = type(task.cmd) == "table" and table.concat(task.cmd, " ") or task.cmd
    local display = " " .. command:gsub("['\"]", "") .. " "
    local stage = kind == "runner" and "运行" or "配置"
    if kind == "executor" then
      if display:find(" --build ", 1, true) then
        stage = "构建"
      elseif display:find(" --install ", 1, true) then
        stage = "安装"
      end
      task:add_component({ "on_output_quickfix", open_on_exit = "failure", items_only = true })
    elseif display:match("[%s/]ctest%s") then
      stage = "测试"
    end
    local cmake = require("cmake-tools")
    local config = cmake.get_config()
    local preset = kind == "executor" and stage == "构建" and config.build_preset or config.configure_preset
    local parts = { stage, vim.fs.basename(config.cwd) }
    if preset then
      parts[#parts + 1] = preset
    end
    -- The command line below shows the actual executable. launch_target can
    -- refer to a different target when CMakeQuickRun supplies an explicit one.
    task.name = table.concat(parts, " · ")
    task.metadata.cpp_workflow = true
    task:set_component({ "on_complete_notify", statuses = { "FAILURE" } })
    require("overseer").open({ enter = false, direction = "bottom" })
  end
end

function M.render(task)
  local render = require("overseer.render")
  if not task.metadata.cpp_workflow then
    return render.format_standard(task)
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

return M

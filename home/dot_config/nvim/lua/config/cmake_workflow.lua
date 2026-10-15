-- Compatibility boundary for locked CMakeTools ee807ac: keep its presets,
-- target selection and task execution, but not its unsafe global autosave.
local M = {}
local installed, saving = false, false

-- Resolve existing ancestors too: new files need saving, while symlinks into
-- another project must never give us ownership of that project's drafts.
local function real_path(path)
  local real = vim.uv.fs_realpath(path)
  if real then
    return real
  end
  local stat = vim.uv.fs_lstat(path)
  if stat and stat.type == "link" then
    return nil -- Never write through an unresolved/dangling symlink.
  end
  local parent = vim.fs.dirname(path)
  if parent and parent ~= path then
    local resolved = real_path(parent)
    return resolved and vim.fs.joinpath(resolved, vim.fs.basename(path))
  end
  return path
end

local function modified_buffers(cmake)
  local root = real_path(cmake.get_config().cwd):gsub("/$", "") .. "/"
  local buffers = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" and vim.bo[buf].modified and name ~= "" then
      local path = real_path(name)
      if path and vim.startswith(path, root) then
        buffers[#buffers + 1] = buf
      end
    end
  end
  return buffers
end

function M.setup()
  if installed then
    return
  end
  installed = true
  local cmake = require("cmake-tools")
  local utils = require("cmake-tools.utils")
  local Result = require("cmake-tools.result")
  local Types = require("cmake-tools.types")

  local function fail(callback, message)
    message = "CMake stopped: " .. message
    vim.notify(message, vim.log.levels.ERROR, { title = "CMake" })
    if callback then
      callback(Result:new_error(Types.CMAKE_RUN_FAILED, message))
    end
  end

  -- Save before CMakeTools reads presets, not after it has assembled argv.
  -- Keep normal write/format hooks and verify modified clears; never use !.
  for _, method in ipairs({ "generate", "build" }) do
    local original = cmake[method]
    cmake[method] = function(opts, callback)
      if saving then
        -- CMakeTools regenerates on BufWritePost. Our save belongs to the
        -- pending configure/build already; do not start a nested configure.
        if callback then
          fail(callback, "a project save is already in progress")
        end
        return
      end
      local config = cmake.get_config()
      if utils.has_active_job(config.runner, config.executor) then
        return original(opts, callback)
      end
      saving = true
      local confirm = vim.o.confirm
      vim.o.confirm = false -- Automatic saves must fail, not ask to overwrite.
      local filename
      local ok, err = pcall(function()
        for _, buf in ipairs(modified_buffers(cmake)) do
          filename = vim.api.nvim_buf_get_name(buf)
          vim.api.nvim_buf_call(buf, function()
            vim.cmd("silent keepalt write")
          end)
          if vim.bo[buf].modified then
            error("buffer is still modified: " .. vim.api.nvim_buf_get_name(buf))
          end
        end
      end)
      vim.o.confirm = confirm
      saving = false
      if not ok then
        local reason = tostring(err):match("^[^\n]+")
        return fail(callback, "save failed: " .. (filename or config.cwd) .. "\n" .. reason)
      end
      return original(opts, callback)
    end
  end

  -- These are the shared execution boundaries, including quick-run/debug.
  -- A late edit must stop execution, not save new text and run an old binary.
  utils.save_all_named_buffers = function() end
  for _, method in ipairs({ "execute", "run" }) do
    local original = utils[method]
    utils[method] = function(cmd, env_script, env, args, cwd, backend, callback)
      local modified = modified_buffers(cmake)
      if #modified > 0 then
        return fail(
          callback,
          "unsaved project changes; save and build again: " .. vim.api.nvim_buf_get_name(modified[1])
        )
      end
      if method == "execute" and vim.tbl_contains(args, "--build") then
        -- Observe writes for this actual build, after autosave/configure/pickers.
        -- `modified` alone misses edits saved while the compiler is running,
        -- including newly opened files and buffers unloaded before completion.
        local config = cmake.get_config()
        local root = real_path(config.cwd):gsub("/$", "") .. "/"
        local written
        local watcher = vim.api.nvim_create_autocmd("BufWritePost", {
          desc = "CMake in-flight build writes",
          callback = function(event)
            local path = real_path(event.file)
            if path and vim.startswith(path, root) then
              written = path
            end
          end,
        })
        local function cleanup()
          if watcher then
            vim.api.nvim_del_autocmd(watcher)
            watcher = nil
          end
        end
        local ok, err = pcall(original, cmd, env_script, env, args, cwd, backend, function(result)
          cleanup()
          if result:is_ok() then
            if cmake.get_config() ~= config then
              return fail(callback, "project changed during build; build again")
            end
            if written then
              return fail(callback, "project file saved during build; build again: " .. written)
            end
          end
          if callback then
            callback(result)
          end
        end)
        if not ok then
          cleanup()
          error(err, 0)
        end
        return
      end
      return original(cmd, env_script, env, args, cwd, backend, callback)
    end
  end

  -- Upstream's cold-run branch checks the *old* NOT_CONFIGURED result after
  -- Generate. Continue only on the new result and a real, readable codemodel.
  local run = cmake.run
  cmake.run = function(opts, callback)
    local config = cmake.get_config()
    local result = config:get_launch_target()
    if not (opts and opts.target) and not utils.has_active_job(config.runner, config.executor) then
      if result.code == Types.NOT_CONFIGURED or result.code == Types.CANNOT_FIND_CODEMODEL_FILE then
        return cmake.generate({ bang = false, fargs = vim.deepcopy(opts and opts.fargs or {}) }, function(generated)
          if not generated:is_ok() then
            if callback then
              callback(generated)
            end
            return
          end
          if cmake.get_config() ~= config or not config:get_codemodel_targets():is_ok() then
            return fail(callback, "configure did not produce a codemodel for the current project")
          end
          return run(opts, callback)
        end)
      end
    end
    return run(opts, callback)
  end

  -- plugin/cmake-tools.lua binds function values before lazy calls setup.
  -- Rebind the three public commands too, not just their Lua API entry points.
  for suffix, method in pairs({ Generate = "generate", Build = "build", Run = "run" }) do
    vim.api.nvim_create_user_command("CMake" .. suffix, function(opts)
      return cmake[method](opts)
    end, { nargs = "*", bang = method ~= "run", desc = "CMake " .. method })
  end
end

return M

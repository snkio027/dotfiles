-- Compatibility boundary for locked CMakeTools ee807ac: keep its presets,
-- target selection and task execution, but not its unsafe global autosave.
local M = {}
local installed, saving = false, false
local preset_targets = false

local function build_identity(config)
  return vim.deepcopy({
    cwd = config.cwd,
    configure = config.configure_preset,
    build = config.build_preset,
    test = config.test_preset,
    build_type = config.build_type,
    build_target = config.build_target,
    launch_target = config.launch_target,
    base = config.base_settings,
    targets = config.target_settings,
  })
end

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

  function M.save_project()
    if saving then
      return false, "a project save is already in progress"
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
      return false, "save failed: " .. (filename or cmake.get_config().cwd) .. "\n" .. reason
    end
    return true
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
      if require("config.cmake_native_workflow").is_active(config.cwd) then
        return fail(callback, "wait for the native workflow to finish")
      end
      if utils.has_active_job(config.runner, config.executor) then
        return original(opts, callback)
      end
      local saved, save_error = M.save_project()
      if not saved then
        return fail(callback, save_error)
      end
      if method == "build" and opts and opts.dotfiles_preset_targets then
        local previous = preset_targets
        preset_targets = true
        local called, result = pcall(original, opts, callback)
        preset_targets = previous
        if not called then
          error(result, 0)
        end
        return result
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
        if preset_targets then
          -- BuildTest uses the native preset targets, including macro expansion.
          -- Upstream may append an editor target (or raw preset targets) to argv.
          -- Remove only that CLI override; do not mutate shared target selection.
          local clean, skip = {}, false
          for _, arg in ipairs(args) do
            if arg == "--target" or arg == "-t" then
              skip = true
            elseif skip and arg:sub(1, 1) ~= "-" then
              -- Skip the values of this target override.
            else
              skip = false
              clean[#clean + 1] = arg
            end
          end
          args = clean
        end
        -- Observe writes for this actual build, after autosave/configure/pickers.
        -- `modified` alone misses edits saved while the compiler is running,
        -- including newly opened files and buffers unloaded before completion.
        local config = cmake.get_config()
        local identity = build_identity(config)
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
            if cmake.get_config() ~= config or real_path(config.cwd):gsub("/$", "") .. "/" ~= root then
              return fail(callback, "project changed during build; build again")
            end
            if not vim.deep_equal(build_identity(config), identity) then
              return fail(callback, "presets, targets or settings changed during build; build again")
            end
            if written then
              return fail(callback, "project file saved during build; build again: " .. written)
            end
            local modified = modified_buffers(cmake)
            if #modified > 0 then
              return fail(callback, "unsaved project changes; build again: " .. vim.api.nvim_buf_get_name(modified[1]))
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
  for _, method in ipairs({ "run", "debug" }) do
    local original = cmake[method]
    cmake[method] = function(opts, callback)
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
            return cmake[method](opts, callback)
          end)
        end
      end
      if
        method == "debug"
        and not utils.has_active_job(config.runner, config.executor)
        and config:validate_for_debugging().code == Types.CANNOT_DEBUG_LAUNCH_TARGET
      then
        return cmake.select_build_type(function(selected)
          if selected:is_ok() then
            return cmake.debug(opts, callback)
          elseif callback then
            callback(selected)
          end
        end)
      end
      return original(opts, callback)
    end
  end

  require("config.cmake_test").setup(cmake, fail)

  -- plugin/cmake-tools.lua binds function values before lazy calls setup.
  -- Rebind public commands too, not just their Lua API entry points.
  for suffix, method in pairs({ Generate = "generate", Build = "build", Run = "run", Debug = "debug" }) do
    vim.api.nvim_create_user_command("CMake" .. suffix, function(opts)
      return cmake[method](opts)
    end, { nargs = "*", bang = method == "generate" or method == "build", desc = "CMake " .. method })
  end
end

return M

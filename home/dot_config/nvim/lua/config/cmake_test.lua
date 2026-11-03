-- Keep CMakeTools' native test picker and CTest arguments. The additional
-- command guarantees a matching build before offering that picker.
local M = {}

function M.setup(cmake, fail)
  local ctest = require("cmake-tools.test.ctest")
  local Presets = require("cmake-tools.presets")
  local Job = require("plenary.job")
  local pending

  local function paired(config)
    local hint = "select matching configure/build/test presets with explicit configurePreset; "
      .. "for inherited or other layouts use the project's native cmake --workflow --preset <name>"
    if
      not config.base_settings.use_preset
      or not Presets.exists(config.cwd)
      or not config.build_preset
      or not config.test_preset
    then
      return false, hint
    end
    local presets = Presets:parse(config.cwd)
    local build = presets:get_build_preset(config.build_preset)
    local test = presets:get_test_preset(config.test_preset)
    -- Locked CMakeTools does not resolve build/test preset inheritance. Do
    -- not guess a configure preset and accidentally test another old build.
    if
      not build
      or not build:is_valid()
      or not test
      or not test:isValid()
      or build.inherits
      or test.inherits
      or not build.configurePreset
      or not test.configurePreset
      or build.configurePreset ~= config.configure_preset
      or test.configurePreset ~= config.configure_preset
      or build.configuration ~= test.configuration
    then
      return false, hint
    end
    return true
  end

  -- Upstream omits cwd for discovery, although its execution uses config.cwd.
  -- Use the same native command/preset and retain its labels and test picker.
  ctest.list_all_tests = function(build_dir, preset, callback)
    local config = cmake.get_config()
    local directory = config.cwd
    local args = preset and { "--preset", preset } or { "--test-dir", build_dir }
    args[#args + 1] = "--show-only=json-v1"
    ctest.job = Job:new({
      command = require("cmake-tools.const").ctest_command,
      args = args,
      cwd = directory,
      on_exit = vim.schedule_wrap(function(job, code)
        if cmake.get_config() ~= config or config.cwd ~= directory then
          return fail(nil, "project changed while discovering tests; select the project and test again")
        end
        local ok, data = pcall(vim.json.decode, table.concat(job:result(), "\n"))
        if code ~= 0 or not ok or type(data) ~= "table" or type(data.tests) ~= "table" then
          return fail(nil, "CTest discovery failed: " .. table.concat(job:stderr_result(), "\n"))
        end
        local tests = {}
        for _, test in ipairs(data.tests) do
          local labels = {}
          for _, property in ipairs(test.properties or {}) do
            if property.name == "LABELS" then
              labels = property.value or {}
            end
          end
          tests[#tests + 1] = { name = test.name, labels = labels }
        end
        callback(tests)
      end),
    })
    ctest.job:start()
  end

  -- The test picker is asynchronous. A save after the completed build must
  -- invalidate that build, even if the buffer is no longer modified.
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("dotfiles_cmake_test", { clear = true }),
    callback = function(event)
      if pending then
        local path = vim.uv.fs_realpath(event.file)
        if path and vim.startswith(path, pending.root .. "/") then
          pending.written = path
        end
      end
    end,
  })

  local run = ctest.run
  ctest.run = function(command, env, config, opts)
    -- Upstream carries opts through its asynchronous picker. Keep this
    -- receipt on that invocation, so a manual RunTest cannot consume it.
    local built = opts and opts.dotfiles_build
    if built then
      if
        pending ~= built
        or cmake.get_config() ~= built.config
        or config ~= built.config
        or vim.uv.fs_realpath(config.cwd) ~= built.root
        or config.configure_preset ~= built.configure
        or config.build_preset ~= built.build
        or config.test_preset ~= built.test
        or built.written
      then
        return fail(nil, "project, presets or saved sources changed after build; use CMakeBuildTest again")
      end
      pending = nil
    end
    return run(command, env, config, opts)
  end

  local run_test = cmake.run_test
  M.build_test = function()
    pending = nil
    local config = cmake.get_config()
    local ok, reason = paired(config)
    if not ok then
      return fail(nil, reason)
    end
    cmake.build({ fargs = {}, dotfiles_preset_targets = true }, function(result)
      if not result:is_ok() then
        return
      end
      -- Saving can change the preset file. Check the effective pair again.
      local valid, message = paired(config)
      if not valid then
        return fail(nil, message)
      end
      pending = {
        config = config,
        root = assert(vim.uv.fs_realpath(config.cwd)),
        configure = config.configure_preset,
        build = config.build_preset,
        test = config.test_preset,
      }
      run_test({ fargs = {}, dotfiles_build = pending })
    end)
  end
  vim.api.nvim_create_user_command("CMakeBuildTest", M.build_test, { desc = "Build and test matching CMake presets" })
end

return M

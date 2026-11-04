-- A deliberately small project declaration, not executable project config.
-- Let rust-analyzer produce the Cargo commands consumed by rustaceanvim for
-- tests/debugging; do not maintain a second Cargo command builder here.
local M = {}

function M.settings(root, defaults)
  local settings = vim.deepcopy(require("rustaceanvim.config.server").load_rust_analyzer_settings(root, {
    default_settings = vim.deepcopy(defaults),
  }))
  if not root then
    return settings
  end
  local path = vim.fs.joinpath(root, ".nvim/rust.json")
  local stat, err, code = vim.uv.fs_stat(path)
  if not stat then
    assert(code == "ENOENT", "Cannot read Rust project settings: " .. path .. ": " .. tostring(err))
    return settings
  end
  assert(stat.type == "file" and stat.size <= 65536, "Invalid Rust project settings: " .. path)
  local ok, project = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  assert(ok and type(project) == "table" and not vim.islist(project), "Invalid Rust project JSON: " .. path)
  for key in pairs(project) do
    assert(vim.tbl_contains({ "features", "noDefaultFeatures", "target" }, key), "Unknown Rust project option: " .. key)
  end
  if project.features ~= nil then
    assert(
      project.features == "all" or (type(project.features) == "table" and vim.islist(project.features)),
      "Rust features must be an array or 'all': " .. path
    )
    if type(project.features) == "table" then
      for _, feature in ipairs(project.features) do
        assert(type(feature) == "string" and feature ~= "", "Invalid Rust feature: " .. path)
      end
    end
  end
  if project.noDefaultFeatures ~= nil then
    assert(type(project.noDefaultFeatures) == "boolean", "Rust noDefaultFeatures must be boolean: " .. path)
  end
  if project.target ~= nil then
    assert(type(project.target) == "string" and project.target ~= "", "Rust target must be a triple: " .. path)
  end
  local ra = settings["rust-analyzer"]
  ra.cargo = ra.cargo or {}
  ra.check = ra.check or {}
  if project.features ~= nil then
    -- This deprecated LazyVim option would otherwise override a feature list.
    ra.cargo.allFeatures = false
    ra.cargo.features = vim.deepcopy(project.features)
    ra.check.features = vim.deepcopy(project.features)
  end
  if project.noDefaultFeatures ~= nil then
    ra.cargo.noDefaultFeatures = project.noDefaultFeatures
    ra.check.noDefaultFeatures = project.noDefaultFeatures
  end
  if project.target ~= nil then
    ra.cargo.target = project.target
    ra.check.targets = { project.target }
    -- cargo.target controls analysis, but runnable commands only carry
    -- runnables.extraArgs. Keep native command generation for tests and DAP.
    ra.runnables = ra.runnables or {}
    local previous = ra.runnables.extraArgs or {}
    assert(type(previous) == "table" and vim.islist(previous), "Invalid Rust runnable arguments: " .. path)
    local args, index = {}, 1
    while index <= #previous do
      local arg = previous[index]
      assert(type(arg) == "string", "Invalid Rust runnable argument: " .. path)
      if arg == "--target" then
        assert(
          type(previous[index + 1]) == "string" and previous[index + 1] ~= "",
          "Missing Rust runnable target: " .. path
        )
        index = index + 2
      elseif arg:match("^%-%-target=") then
        index = index + 1
      else
        args[#args + 1] = arg
        index = index + 1
      end
    end
    vim.list_extend(args, { "--target", project.target })
    ra.runnables.extraArgs = args
  end
  return settings
end

return M

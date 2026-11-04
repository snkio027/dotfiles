-- Own only the PATH entry and variables introduced by editor environment selection.
-- Restore against the current environment so later user changes survive.
local M = {}

local function parts(path)
  return vim.split(path or "", ":", { plain = true })
end

local function remove_one(path, directory)
  local entries = parts(path)
  for index, entry in ipairs(entries) do
    if entry == directory then
      table.remove(entries, index)
      return table.concat(entries, ":")
    end
  end
  return path
end

function M.new()
  local owned_path, variables
  variables = {}
  local state = {}

  function state.path_without_owned()
    local path = vim.env.PATH or ""
    return owned_path and remove_one(path, owned_path) or path
  end

  function state.clear_path()
    if owned_path then
      vim.env.PATH = state.path_without_owned()
      owned_path = nil
    end
  end

  function state.prepend(directory)
    if not directory or directory == "" then
      return
    end
    state.clear_path()
    local path = vim.env.PATH or ""
    -- An already-leading inherited path is not ours to remove on deactivation.
    if parts(path)[1] ~= directory then
      vim.env.PATH = directory .. (path == "" and "" or ":" .. path)
      owned_path = directory
    end
  end

  function state.baseline(name)
    local previous = variables[name]
    if previous and vim.env[name] == previous.value then
      return previous.before
    end
    return vim.env[name]
  end

  function state.set(name, value)
    local previous = variables[name]
    if not previous or vim.env[name] ~= previous.value then
      previous = { before = vim.env[name] }
    end
    previous.value = value
    variables[name] = previous
    vim.env[name] = value
  end

  function state.restore_variables()
    for name, previous in pairs(variables) do
      if vim.env[name] == previous.value then
        vim.env[name] = previous.before
      end
    end
    variables = {}
  end

  function state.project_path(python, initial_environment)
    local exclude = {}
    for _, environment in pairs({
      initial = initial_environment,
      venv = state.baseline("VIRTUAL_ENV"),
      conda = state.baseline("CONDA_PREFIX"),
    }) do
      if environment ~= "" then
        exclude[vim.fs.joinpath(environment, "bin")] = true
      end
    end
    local directory = vim.fs.dirname(python)
    exclude[directory] = true
    local entries = { directory }
    for _, entry in ipairs(parts(state.path_without_owned())) do
      if not exclude[entry] then
        entries[#entries + 1] = entry
      end
    end
    return table.concat(entries, ":")
  end

  return state
end

return M

local M = {}

-- These are installed/generated dependency locations, not names such as
-- "vendor" that could also be a project's deliberately editable sources.
local function installed(path)
  return path:find("/vcpkg_installed/", 1, true)
    or path:match("/build/[^/]+/_deps/")
    or path:find("/build/_deps/", 1, true)
    or path:match("^/opt/homebrew/include/")
    or path:match("^/opt/homebrew/Cellar/")
    or path:match("^/usr/local/include/")
    or path:match("^/usr/local/Cellar/")
    or path:match("^/home/linuxbrew/%.linuxbrew/include/")
    or path:match("^/home/linuxbrew/%.linuxbrew/Cellar/")
    or path:match("^/usr/include/")
    or path:match("/[^/]+%.sdk/usr/include/")
    or path:match("/Toolchains/[^/]+%.xctoolchain/usr/include/")
end

function M.is_dependency(path)
  if path == "" then
    return false
  end
  path = vim.fs.normalize(path)
  local real = vim.uv.fs_realpath(path)
  return not not (installed(path) or (real and installed(real)))
end

function M.protect(buf)
  if vim.bo[buf].buftype ~= "" or not M.is_dependency(vim.api.nvim_buf_get_name(buf)) then
    return
  end
  vim.b[buf].autoformat = false
  vim.b[buf].cpp_dependency = true
  vim.bo[buf].readonly = true
  vim.bo[buf].modifiable = false
  vim.diagnostic.show(nil, buf)
end

-- Native per-buffer display options: diagnostic storage, signs, underline,
-- floats and navigation are untouched. This does not fix header parsing.
function M.inline_option(fallback)
  return function(namespace, buf)
    if vim.b[buf].cpp_dependency and not vim.bo[buf].modifiable and not vim.b[buf].cpp_dependency_inline then
      return false
    end
    if type(fallback) == "function" then
      return fallback(namespace, buf)
    end
    return fallback
  end
end

function M.toggle_inline(buf)
  if not vim.b[buf].cpp_dependency then
    vim.notify("This buffer is not a protected C/C++ dependency.", vim.log.levels.INFO)
    return
  end
  if vim.bo[buf].modifiable then
    vim.notify("Dependency is editable; normal diagnostic display remains enabled.", vim.log.levels.INFO)
    return
  end
  vim.b[buf].cpp_dependency_inline = not vim.b[buf].cpp_dependency_inline
  vim.diagnostic.show(nil, buf)
  vim.notify("Dependency inline diagnostics: " .. (vim.b[buf].cpp_dependency_inline and "on" or "off"))
end

function M.edit(buf)
  if not vim.b[buf].cpp_dependency then
    vim.notify("This buffer is not a protected C/C++ dependency.", vim.log.levels.INFO)
    return
  end
  vim.bo[buf].readonly = false
  vim.bo[buf].modifiable = true
  -- An explicit edit is not permission to reformat the dependency on save.
  vim.b[buf].autoformat = false
  vim.diagnostic.show(nil, buf)
  vim.notify(
    "Dependency editing enabled; save-time formatting stays off. Reopen to restore protection.",
    vim.log.levels.WARN
  )
end

return M

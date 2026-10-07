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
end

function M.edit(buf)
  if not vim.b[buf].cpp_dependency then
    vim.notify("当前文件没有启用 C++ 依赖保护。", vim.log.levels.INFO)
    return
  end
  vim.bo[buf].readonly = false
  vim.bo[buf].modifiable = true
  -- An explicit edit is not permission to reformat the dependency on save.
  vim.b[buf].autoformat = false
  vim.notify(
    "已允许编辑当前依赖文件；保存自动格式化仍关闭。重新打开后恢复保护。",
    vim.log.levels.WARN
  )
end

return M

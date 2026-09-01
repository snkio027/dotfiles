local M = {}

local warned_roots = {}

local function is_file(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

function M.compile_database(root)
  return vim.fs.joinpath(root, "build", "dev", "compile_commands.json")
end

function M.configure_buffer(bufnr)
  vim.bo[bufnr].expandtab = true
  vim.bo[bufnr].tabstop = 4
  vim.bo[bufnr].shiftwidth = 4
  vim.bo[bufnr].softtabstop = 4
end

function M.warn_if_compile_database_missing(bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  if filename == "" then
    return
  end

  local root = vim.fs.root(filename, ".cxx.toml")
  if not root then
    return
  end

  local database = M.compile_database(root)
  if is_file(database) or warned_roots[root] then
    return false
  end
  warned_roots[root] = true

  vim.notify(
    (
      "Managed cxx project is missing %s; clangd may have incomplete project flags. Run "
      .. "`cmake --workflow --preset dev`, then `:lsp restart clangd`."
    ):format(vim.fn.fnamemodify(database, ":~")),
    vim.log.levels.WARN,
    { title = "C/C++ compile database" }
  )
  return true
end

function M.setup_buffer(bufnr)
  M.configure_buffer(bufnr)
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      M.warn_if_compile_database_missing(bufnr)
    end
  end)
end

return M

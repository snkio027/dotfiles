local M = {}

local families = {
  biome = "biome",
  ["biome-check"] = "biome",
  oxfmt = "oxfmt",
  prettier = "prettier",
  prettierd = "prettier",
}

-- Use Conform's own config discovery (including package.json/Prettier), not
-- the editor cwd. The closest project config wins, including in monorepos.
local function select_formatter(buf, names)
  local filename = vim.api.nvim_buf_get_name(buf)
  if filename == "" or vim.bo[buf].buftype ~= "" then
    return nil
  end
  local ctx = { buf = buf, filename = filename, dirname = vim.fs.dirname(filename) }
  local project = vim.fs.root(filename, ".git")
  local closest, selected, owners = nil, nil, {}
  for _, name in ipairs(names) do
    if families[name] then
      local config = require("conform").get_formatter_config(name, buf)
      local root = config and config.cwd and config.cwd(config, ctx)
      root = root and vim.fs.normalize(root)
      if root and (not project or root == project or vim.startswith(root, project .. "/")) then
        if not closest or #root > #closest then
          closest, selected, owners = root, name, { [families[name]] = true }
        elseif root == closest then
          owners[families[name]] = true
        end
      end
    end
  end
  if vim.tbl_count(owners) > 1 then
    local conflicting = vim.tbl_keys(owners)
    table.sort(conflicting)
    vim.notify_once(
      "Multiple formatter configs in "
        .. closest
        .. ": "
        .. table.concat(conflicting, ", ")
        .. ". Automatic formatting skipped; select one explicitly with Conform or keep one project formatter.",
      vim.log.levels.WARN,
      { title = "Project formatting" }
    )
    return nil
  end
  return selected
end

local function has_web_formatter(names)
  for _, name in ipairs(names) do
    if families[name] then
      return true
    end
  end
  return false
end

function M.select(buf, names)
  if not has_web_formatter(names) then
    return names
  end
  local selected = select_formatter(buf, names)
  local result = vim.deepcopy(names)
  for index = #result, 1, -1 do
    if families[result[index]] then
      table.remove(result, index)
    end
  end
  if selected then
    -- Keep unrelated pipeline stages, but only one Web formatter.
    local index = 1
    for _, name in ipairs(names) do
      if families[name] then
        break
      end
      index = index + 1
    end
    table.insert(result, index, selected)
  end
  -- Missing/ambiguous project config must not silently fall back to an LSP
  -- formatter and reintroduce a different style. Other filetypes are untouched.
  result.lsp_format = "never"
  return result
end

function M.setup(opts)
  for ft, configured in pairs(opts.formatters_by_ft or {}) do
    if ft ~= "*" and ft ~= "_" and (type(configured) == "function" or has_web_formatter(configured)) then
      opts.formatters_by_ft[ft] = function(buf)
        local names = type(configured) == "function" and configured(buf) or configured
        return M.select(buf, names)
      end
    end
  end
end

return M

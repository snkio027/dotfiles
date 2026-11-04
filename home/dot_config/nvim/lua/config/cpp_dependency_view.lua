local M = {}
local windows = {}
local filetypes = { c = true, cpp = true, objc = true, objcpp = true, cuda = true }

-- Only the whitespace inside a real parser token is concealed. A line-shaped
-- regex alone would also match raw strings, comments and macro continuations.
local function positions(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then
    return {}
  end
  local parsed, trees = pcall(parser.parse, parser, true)
  if not parsed or not trees or not trees[1] then
    return {}
  end
  local root, result = trees[1]:root(), {}
  for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local indent, spaces, word = line:match("^([ \t]*)#([ \t]+)([a-z]+)")
    if word then
      local node = root:descendant_for_range(row - 1, #indent, row - 1, #indent + 1)
      local first_row, first_col, last_row, last_col = node:range()
      if
        (node:type() == "#" .. word or node:type() == "preproc_directive")
        and first_row == row - 1
        and first_col == #indent
        and last_row == row - 1
        and last_col == #indent + 1 + #spaces + #word
      then
        result[#result + 1] = { row, #indent + 2, #spaces }
      end
    end
  end
  return result
end

local function clear(win)
  local state = windows[win]
  if not state then
    return
  end
  windows[win] = nil
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  for _, id in ipairs(state.matches) do
    pcall(vim.fn.matchdelete, id, win)
  end
  for option, value in pairs(state.options) do
    -- Respect a later manual option change instead of overwriting it.
    if vim.wo[win][option] == state.applied[option] then
      vim.wo[win][option] = value
    end
  end
end

function M.refresh()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local enabled = vim.b[buf].cpp_dependency and vim.b[buf].cpp_dependency_compact ~= false
    enabled = enabled and filetypes[vim.bo[buf].filetype] and not vim.bo[buf].modifiable
    local tick = vim.api.nvim_buf_get_changedtick(buf)
    local state = windows[win]
    if not (enabled and state and state.buf == buf and state.tick == tick) then
      clear(win)
      local ranges = enabled and positions(buf) or {}
      if #ranges > 0 then
        state =
          { buf = buf, tick = tick, matches = {}, options = {}, applied = { conceallevel = 2, concealcursor = "nvic" } }
        for option, value in pairs(state.applied) do
          state.options[option] = vim.wo[win][option]
          vim.wo[win][option] = value
        end
        windows[win] = state
        for first = 1, #ranges, 8 do
          state.matches[#state.matches + 1] = vim.fn.matchaddpos(
            "Conceal",
            vim.list_slice(ranges, first, math.min(first + 7, #ranges)),
            10,
            -1,
            { window = win }
          )
        end
      end
    end
  end
end

function M.toggle(buf)
  if not vim.b[buf].cpp_dependency or vim.bo[buf].modifiable or not filetypes[vim.bo[buf].filetype] then
    vim.notify("Compact directives are only available in protected C/C++ dependencies.", vim.log.levels.INFO)
    return
  end
  vim.b[buf].cpp_dependency_compact = vim.b[buf].cpp_dependency_compact == false
  M.refresh()
end

local group = vim.api.nvim_create_augroup("cpp_dependency_view", { clear = true })
vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "FileType" }, { group = group, callback = M.refresh })
vim.api.nvim_create_autocmd("BufWinLeave", {
  group = group,
  callback = function()
    clear(vim.api.nvim_get_current_win())
  end,
})
vim.api.nvim_create_autocmd("WinNew", {
  group = group,
  callback = function()
    -- Splits inherit the source window's conceal options, but not our ownership.
    local win = vim.api.nvim_get_current_win()
    local source = windows[vim.fn.win_getid(vim.fn.winnr("#"))]
    if source then
      for option, value in pairs(source.options) do
        if vim.wo[win][option] == source.applied[option] then
          vim.wo[win][option] = value
        end
      end
    end
  end,
})
vim.api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function(event)
    windows[tonumber(event.match)] = nil
  end,
})
vim.api.nvim_create_autocmd("OptionSet", { group = group, pattern = "modifiable", callback = M.refresh })

return M

-- Test results own a Trouble source and view, never the user's quickfix list.
local M = {}
local failures = {}
local view
local mode = "neotest_results"
local source = "dotfiles_tests"

local function close_owned(owned)
  -- Locked Trouble's View:close() and WinLeave hook both close its global
  -- preview. Close only our preview, then use the window's normal cleanup.
  local preview = require("trouble.view.preview")
  local item = preview.item()
  if item and item.source == source and preview.preview.win == owned.preview_win.win then
    preview.close()
  end
  if vim.api.nvim_get_current_win() == owned.win.win then
    require("trouble.util").noautocmd(function()
      owned:goto_main()
    end)
  end
  owned.win:close()
end

local function has_failures()
  for _, items in pairs(failures) do
    if #items > 0 then
      return true
    end
  end
  return false
end

local function register_source()
  local sources = require("trouble.sources")
  if sources.sources[source] then
    return
  end
  sources.register(source, {
    config = {
      modes = {
        [mode] = {
          desc = "Failed Tests",
          source = source,
          groups = { { "filename", format = "{file_icon} {filename} {count}" } },
          sort = { "filename", "pos", "text" },
          format = "{severity_icon} {text:ts} {pos}",
          focus = false,
          auto_refresh = false,
        },
      },
    },
    get = function(callback)
      local Item = require("trouble.item")
      local items = {}
      for _, adapter_items in pairs(failures) do
        for _, item in ipairs(adapter_items) do
          items[#items + 1] = Item.new(vim.deepcopy(item))
        end
      end
      callback(items)
    end,
  })
end

function M.open()
  if not has_failures() then
    return
  end
  local trouble = require("trouble")
  register_source()
  if view and (view:is_open() or view.first_update:is_pending()) then
    view:refresh()
  else
    -- Keep the exact view we created; never close the last arbitrary Trouble
    -- view or adopt another source's window when the test run finishes.
    view = trouble.open({ mode = mode, new = true, focus = false })
    local opening = view
    -- A fast successful rerun can finish while Trouble is still opening.
    -- Finish closing that same view rather than leaving a stale failure panel.
    opening.first_update:next(function()
      if not has_failures() then
        close_owned(opening)
        if view == opening then
          view = nil
        end
      end
    end)
  end
end

function M.consumer(client)
  client.listeners.results = function(adapter_id, _, partial)
    if partial then
      return
    end
    local tree = client:get_position(nil, { adapter = adapter_id })
    if not tree then
      return
    end
    local items = {}
    -- Use the adapter's complete result state: rerunning one passing test must
    -- not hide another failed test, including failures from other adapters.
    for id, result in pairs(client:get_results(adapter_id)) do
      local node = tree:get_key(id)
      if result.status == "failed" and node and node:data().type == "test" then
        local position = node:data()
        local range = node:closest_value_for("range") or { 0, 0 }
        local errors = result.errors or {}
        if #errors == 0 then
          errors = { { message = position.name .. " failed; see test output" } }
        end
        for index, error in ipairs(errors) do
          items[#items + 1] = {
            id = adapter_id .. ":" .. id .. ":" .. index,
            source = source,
            filename = position.path,
            pos = { (error.line or range[1]) + 1, range[2] },
            text = error.message,
            severity = vim.diagnostic.severity.ERROR,
          }
        end
      end
    end
    vim.schedule(function()
      failures[adapter_id] = items
      if has_failures() then
        M.open()
      elseif view and view:is_open() then
        close_owned(view)
        view = nil
      end
    end)
  end
  return { open = M.open }
end

return M

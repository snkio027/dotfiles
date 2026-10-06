local M = {}

local function notify(message)
  vim.notify(message, vim.log.levels.INFO, { title = "clangd includes" })
end

-- Accept only insertions consisting of literal #include lines in this buffer.
-- Never execute commands, remove headers, rewrite code or edit other files.
local function include_edits(action, uri, version)
  if action.disabled or action.command or not action.edit then
    return
  end
  local edit, edits = action.edit, {}
  local function collect(target, values)
    if type(target) ~= "string" or not target:match("^file:") or vim.uri_to_fname(target) ~= vim.uri_to_fname(uri) then
      return false
    end
    for _, item in ipairs(values) do
      local range = item.range
      if item.annotationId or not range or not vim.deep_equal(range.start, range["end"]) then
        return false
      end
      if range.start.character ~= 0 or type(item.newText) ~= "string" or item.newText:sub(-1) ~= "\n" then
        return false
      end
      local count = 0
      for line in item.newText:gmatch("[^\r\n]+") do
        if not line:match("^%s*$") then
          if
            not line:match("^%s*#%s*include%s*<[^<>\r\n]+>%s*$")
            and not line:match('^%s*#%s*include%s*"[^"\r\n]+"%s*$')
          then
            return false
          end
          count = count + 1
        end
      end
      if count == 0 then
        return false
      end
      edits[#edits + 1] = item
    end
    return true
  end
  if edit.changes and edit.documentChanges then
    return
  end
  for target, values in pairs(edit.changes or {}) do
    if not collect(target, values) then
      return
    end
  end
  for _, change in ipairs(edit.documentChanges or {}) do
    local doc = change.textDocument
    if
      not doc
      or (doc.version and doc.version ~= vim.NIL and doc.version ~= version)
      or not collect(doc.uri, change.edits or {})
    then
      return
    end
  end
  return #edits > 0 and edits or nil
end

function M.choose()
  local buf = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ name = "clangd", bufnr = buf, method = "textDocument/codeAction" })
  if #clients ~= 1 then
    notify("需要当前文件连接到一个 clangd；请先确认项目已配置。")
    return
  end
  local client = clients[1]
  local tick, uri = vim.api.nvim_buf_get_changedtick(buf), vim.uri_from_bufnr(buf)
  local version = vim.lsp.util.buf_versions[buf]
  local function current()
    return vim.api.nvim_buf_is_valid(buf)
      and vim.api.nvim_buf_is_loaded(buf)
      and vim.api.nvim_get_current_buf() == buf
      and vim.uri_from_bufnr(buf) == uri
      and vim.api.nvim_buf_get_changedtick(buf) == tick
      and not client:is_stopped()
      and vim.lsp.buf_is_attached(buf, client.id)
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local diagnostics = {}
  local ns = vim.lsp.diagnostic.get_namespace(client.id)
  for _, diagnostic in ipairs(vim.diagnostic.get(buf, { namespace = ns })) do
    local raw = diagnostic.user_data and diagnostic.user_data.lsp
    if raw then
      diagnostics[#diagnostics + 1] = raw
    end
  end
  local sent = client:request("textDocument/codeAction", {
    textDocument = { uri = uri },
    range = {
      start = { line = 0, character = 0 },
      ["end"] = {
        line = #lines - 1,
        character = vim.str_utfindex(lines[#lines], client.offset_encoding, #lines[#lines], false),
      },
    },
    context = { diagnostics = diagnostics, only = { "quickfix" }, triggerKind = 1 },
  }, function(err, actions)
    if not current() then
      notify("文件或 clangd 状态已变化，已丢弃旧建议；请重新调用。")
      return
    end
    if err then
      notify("clangd 查询失败：" .. err.message)
      return
    end
    local choices = {}
    for _, action in ipairs(actions or {}) do
      local edits = include_edits(action, uri, version)
      if edits then
        choices[#choices + 1] = { title = action.title, edits = edits }
      end
    end
    if #choices == 0 then
      notify(
        "clangd 没有提供可直接插入的 include。请等待诊断／索引，或检查公开头文件与依赖；不会猜测或安装库。"
      )
      return
    end
    -- Even a single suggestion needs confirmation: a provider may propose an
    -- internal header instead of a library's public umbrella header.
    vim.ui.select(choices, {
      prompt = "补头文件（请确认是库的公开头文件）：",
      format_item = function(choice)
        return choice.title
          .. "  "
          .. table.concat(
            vim.tbl_map(function(edit)
              return vim.trim(edit.newText):gsub("\n", " ")
            end, choice.edits),
            " "
          )
      end,
    }, function(choice)
      if not choice then
        return
      end
      if not current() then
        notify("文件或 clangd 状态已变化，未应用旧建议；请重新调用。")
        return
      end
      vim.lsp.util.apply_text_edits(choice.edits, buf, client.offset_encoding)
    end)
  end, buf)
  if not sent then
    notify("clangd 未接受请求；请检查连接后重试。")
  end
end

return M

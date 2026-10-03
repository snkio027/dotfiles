-- A lambda binding is still a clangd variable. Use syntax only to identify a
-- direct `auto` lambda initializer, then let clangd resolve its same-buffer
-- declaration/references. Explicit types can convert a lambda into a non-callable
-- object; copied/factory-returned closures and cross-file uses stay unchanged.
-- No name, hover-text, inferred-type, or workspace-wide recoloring heuristics.
local M = {}
local ns = vim.api.nvim_create_namespace("dx_clangd_lambda")
local states = {}
local query

function M.attach(client, buf)
  if client.name ~= "clangd" or vim.bo[buf].filetype ~= "cpp" or states[buf] then
    return
  end
  local state = { generation = 0, requests = {} }
  states[buf] = state

  local function valid(generation, tick)
    return states[buf] == state
      and state.generation == generation
      and vim.api.nvim_buf_is_loaded(buf)
      and vim.api.nvim_buf_get_changedtick(buf) == tick
      and not client:is_stopped()
      and vim.lsp.buf_is_attached(buf, client.id)
  end

  local function clear()
    state.generation = state.generation + 1
    for id in pairs(state.requests) do
      client:cancel_request(id)
    end
    state.requests = {}
    if state.timer then
      if not state.timer:is_closing() then
        state.timer:stop()
        state.timer:close()
      end
      state.timer = nil
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
  end

  local function refresh()
    clear()
    local generation, tick = state.generation, vim.api.nvim_buf_get_changedtick(buf)
    state.timer = vim.defer_fn(function()
      if not valid(generation, tick) then
        return
      end
      state.timer = nil
      local ok, parser = pcall(vim.treesitter.get_parser, buf, "cpp")
      if not ok or not parser then
        return
      end
      query = query
        or vim.treesitter.query.parse(
          "cpp",
          [[
        (declaration type: (placeholder_type_specifier (auto))
          (init_declarator declarator: (identifier) @binding
          value: (lambda_expression)))
      ]]
        )
      local tree = parser:parse()[1]
      if not tree then
        return
      end
      local uri = vim.uri_from_bufnr(buf)
      for _, node in query:iter_captures(tree:root(), buf) do
        local row, col = node:range()
        local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
        local position = { line = row, character = vim.str_utfindex(line, client.offset_encoding, col, false) }
        local request_id
        local sent
        sent, request_id = client:request("textDocument/references", {
          textDocument = { uri = uri },
          position = position,
          context = { includeDeclaration = true },
        }, function(err, locations)
          state.requests[request_id] = nil
          if err or not valid(generation, tick) or type(locations) ~= "table" then
            return
          end
          -- Require the server to confirm this exact declaration. Inactive or
          -- incomplete syntax must not acquire a role from Tree-sitter alone.
          local confirmed = false
          for _, location in ipairs(locations) do
            if location.uri == uri and vim.deep_equal(location.range.start, position) then
              confirmed = true
            end
          end
          if not confirmed then
            return
          end
          for _, location in ipairs(locations) do
            if location.uri == uri then
              local first, last = location.range.start, location.range["end"]
              if first.line == last.line and last.character > first.character then
                local text = vim.api.nvim_buf_get_lines(buf, first.line, first.line + 1, false)[1]
                if text then
                  vim.api.nvim_buf_set_extmark(
                    buf,
                    ns,
                    first.line,
                    vim.str_byteindex(text, client.offset_encoding, first.character, false),
                    {
                      end_col = vim.str_byteindex(text, client.offset_encoding, last.character, false),
                      hl_group = "DxCallable",
                      priority = vim.hl.priorities.semantic_tokens + 3,
                    }
                  )
                end
              end
            end
          end
        end, buf)
        if sent then
          state.requests[request_id] = true
        end
      end
    end, 200)
  end

  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if states[buf] ~= state then
        return true
      end
      refresh()
    end,
    on_detach = function()
      if states[buf] == state then
        clear()
        states[buf] = nil
      end
    end,
    on_reload = function()
      if states[buf] == state then
        refresh()
      end
    end,
  })
  vim.api.nvim_create_autocmd("LspDetach", {
    buffer = buf,
    callback = function(event)
      if event.data.client_id == client.id and states[buf] == state then
        clear()
        states[buf] = nil
        return true
      end
    end,
  })
  refresh()
end

return M

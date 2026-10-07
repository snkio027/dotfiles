-- clangd keeps callable values classified as variables/parameters/properties.
-- Supplement that identity only with structured AST evidence: a direct lambda,
-- a spelled function pointer/reference, function decay into auto, or a resolved
-- call through the value. Document highlights resolve same-buffer occurrences.
-- No arcana/hover parsing, library-name whitelist, header opening, or inference
-- that a callable initializer necessarily makes its destination callable.
local M = {}
local ns = vim.api.nvim_create_namespace("dx_clangd_callable")
local states = {}

local function before(a, b)
  return a.line < b.line or (a.line == b.line and a.character < b.character)
end

local function key(position)
  return position.line .. ":" .. position.character
end

local function child(node, role)
  for _, value in ipairs(node.children or {}) do
    if value.role == role then
      return value
    end
  end
end

local function unqualified(node)
  while node and (node.kind == "Qualified" or node.kind == "Paren") do
    node = child(node, "type")
  end
  return node
end

local function function_type(node)
  node = unqualified(node)
  if node and (node.kind == "LValueReference" or node.kind == "RValueReference") then
    node = unqualified(child(node, "type"))
  end
  if node and (node.kind == "Pointer" or node.kind == "MemberPointer") then
    node = unqualified(child(node, "type"))
  end
  -- Do not descend into arrays, pointer-to-pointer, or template arguments.
  return node and (node.kind == "FunctionProto" or node.kind == "FunctionNoProto")
end

local transparent = { Paren = true, ExprWithCleanups = true, MaterializeTemporary = true, CXXBindTemporary = true }
local function expression(node)
  while node and (transparent[node.kind] or node.kind == "ImplicitCast") do
    node = child(node, "expression")
  end
  return node
end

local function candidates(ast, data, legend, buf, encoding)
  local tokens, seeds, seen = {}, {}, {}
  local row, col = 0, 0
  local declaration
  for i, modifier in ipairs(legend.tokenModifiers) do
    if modifier == "declaration" then
      declaration = bit.lshift(1, i - 1)
    end
  end
  if not declaration or #data % 5 ~= 0 then
    return seeds
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i = 1, #data, 5 do
    col = data[i] > 0 and data[i + 1] or col + data[i + 1]
    row = row + data[i]
    local kind = legend.tokenTypes[data[i + 3] + 1]
    if (kind == "variable" or kind == "parameter" or kind == "property") and lines[row + 1] then
      local first = { line = row, character = col }
      local last = { line = row, character = col + data[i + 2] }
      tokens[#tokens + 1] = {
        range = { start = first, ["end"] = last },
        name = lines[row + 1]:sub(
          vim.str_byteindex(lines[row + 1], encoding, col, false) + 1,
          vim.str_byteindex(lines[row + 1], encoding, last.character, false)
        ),
        declaration = bit.band(data[i + 4], declaration) ~= 0,
      }
    end
  end
  local function seed(node, is_declaration)
    if not node or not node.range or not node.detail then
      return
    end
    -- Binary search the token stream; never match a spelling outside this AST
    -- range. Ambiguous nested same-name declarations remain unclassified.
    local low, high = 1, #tokens + 1
    while low < high do
      local mid = math.floor((low + high) / 2)
      if before(tokens[mid].range.start, node.range.start) then
        low = mid + 1
      else
        high = mid
      end
    end
    local found
    for i = low, #tokens do
      local token = tokens[i]
      if not before(token.range.start, node.range["end"]) then
        break
      end
      if token.name == node.detail and not before(node.range["end"], token.range["end"]) then
        if
          (is_declaration and token.declaration)
          or (not is_declaration and vim.deep_equal(token.range["end"], node.range["end"]))
        then
          if found then
            return
          end
          found = token.range
        end
      end
    end
    if found and not seen[key(found.start)] then
      seen[key(found.start)] = true
      seeds[#seeds + 1] = found
    end
  end
  local function visit(node)
    if node.role == "declaration" and (node.kind == "Var" or node.kind == "ParmVar" or node.kind == "Field") then
      local ty, init = child(node, "type"), child(node, "expression")
      local base = unqualified(ty)
      while base and (base.kind == "LValueReference" or base.kind == "RValueReference") do
        base = unqualified(child(base, "type"))
      end
      local value = expression(init)
      if
        function_type(ty)
        or (
          base
          and base.kind == "Auto"
          and init
          and (
            (value and value.kind == "Lambda")
            or (init.kind == "ImplicitCast" and init.detail == "FunctionToPointerDecay")
          )
        )
      then
        seed(node, true)
      end
    elseif node.kind == "Call" then
      local callee = child(node, "expression")
      -- Dependent/unresolved template calls do not have this resolved decay.
      if
        callee
        and callee.kind == "ImplicitCast"
        and (callee.detail == "LValueToRValue" or callee.detail == "FunctionToPointerDecay")
      then
        callee = expression(callee)
        if callee and (callee.kind == "DeclRef" or callee.kind == "Member") then
          seed(callee, false)
        end
      end
    elseif node.kind == "CXXOperatorCall" then
      local args = node.children or {}
      local method, object = expression(args[1]), expression(args[2])
      if
        method
        and method.kind == "DeclRef"
        and method.detail == "operator()"
        and object
        and (object.kind == "DeclRef" or object.kind == "Member")
      then
        seed(object, false)
      end
    end
    for _, value in ipairs(node.children or {}) do
      visit(value)
    end
  end
  visit(ast)
  return seeds
end

function M.attach(client, buf)
  if
    client.name ~= "clangd"
    or vim.bo[buf].filetype ~= "cpp"
    or states[buf]
    or not client.server_capabilities.astProvider
    or not client.server_capabilities.semanticTokensProvider
  then
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
      -- Avoid an additional full AST transfer for huge/generated buffers.
      if vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf)) > 512 * 1024 then
        return
      end
      local document = { uri = vim.uri_from_bufnr(buf) }
      local function request(method, params, callback)
        local request_id
        local sent
        sent, request_id = client:request(method, params, function(err, result)
          if request_id then
            state.requests[request_id] = nil
          end
          if valid(generation, tick) then
            callback(err, result)
          end
        end, buf)
        if sent then
          state.requests[request_id] = true
        else
          callback(true)
        end
      end
      local ast, tokens
      local function project()
        if not ast or not tokens then
          return
        end
        local seeds =
          candidates(ast, tokens, client.server_capabilities.semanticTokensProvider.legend, buf, client.offset_encoding)
        local next_seed, pending, painted = 1, 0, {}
        local pump
        pump = function()
          while valid(generation, tick) and pending < 4 and next_seed <= #seeds do
            local origin = seeds[next_seed]
            next_seed = next_seed + 1
            if not painted[key(origin.start)] then
              pending = pending + 1
              request(
                "textDocument/documentHighlight",
                { textDocument = document, position = origin.start },
                function(err, highlights)
                  pending = pending - 1
                  local confirmed = false
                  for _, highlight in ipairs(not err and type(highlights) == "table" and highlights or {}) do
                    if vim.deep_equal(highlight.range, origin) then
                      confirmed = true
                    end
                  end
                  if confirmed then
                    for _, highlight in ipairs(highlights) do
                      local first, last = highlight.range.start, highlight.range["end"]
                      local text = vim.api.nvim_buf_get_lines(buf, first.line, first.line + 1, false)[1]
                      if
                        text
                        and first.line == last.line
                        and last.character > first.character
                        and not painted[key(first)]
                      then
                        painted[key(first)] = true
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
                  vim.schedule(pump)
                end
              )
            end
          end
        end
        pump()
      end
      request("textDocument/ast", { textDocument = document }, function(err, result)
        if not err and type(result) == "table" then
          ast = result
          project()
        end
      end)
      request("textDocument/semanticTokens/full", { textDocument = document }, function(err, result)
        if not err and type(result) == "table" and type(result.data) == "table" then
          tokens = result.data
          project()
        end
      end)
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

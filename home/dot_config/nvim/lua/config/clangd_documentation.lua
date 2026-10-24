local M = {}

-- clangd can return Doxygen commands even with CommentFormat: Doxygen.
-- Adapt only block commands in prose, then use the existing UI renderer.
-- This is not a Doxygen interpreter: unknown commands and Markdown are kept.
local sections = { param = "Parameters", tparam = "Template parameters", returns = "Returns", ["return"] = "Returns" }
local blocks = {
  code = { language = "cpp", close = "endcode" },
  verbatim = { language = "text", close = "endverbatim" },
  -- Documented Poxy aliases, also used by toml++ (docs/aliases.md upstream).
  cpp = { language = "cpp", close = "ecpp", alternate = "endcpp" },
  out = { language = "text", close = "eout", alternate = "endout" },
}

local function command(line)
  -- clangd's Doxygen hover formatter emphasizes unknown commands, including
  -- Poxy aliases: **\cpp**example / **\ecpp**. Preserve unknown names below.
  local emphasized, suffix = line:match("^ ? ? ?%*%*([\\@]+[%a_]+)%*%*(.*)$")
  if emphasized then
    line = emphasized .. " " .. suffix
  end
  local indent, prefix, name, rest = line:match("^( *)([\\@]+)([%a_]+)(.*)$")
  if
    not name
    or #indent > 3
    or (prefix ~= "\\" and prefix ~= "\\\\" and prefix ~= "@")
    or (rest ~= "" and not rest:match("^[%s%[{]"))
  then
    return
  end
  return name, vim.trim(rest), prefix == "\\\\"
end

local function unescape(text)
  -- Reverse Markdown punctuation escaping only when clangd escaped the
  -- opening command too. Never interpret C/C++ escapes such as \n or \t.
  return (text:gsub("\\([%p])", "%1"))
end

function M.normalize(documentation)
  -- A hover MarkedString with a language is literal code, not prose.
  if type(documentation) == "table" and documentation.language then
    return documentation
  end
  local text = type(documentation) == "table" and documentation.value or documentation
  if type(text) ~= "string" then
    return documentation
  end
  local lines = vim.split(text, "\n", { plain = true })
  local result, changed, section, fence = {}, false, nil, nil
  local function blank()
    if #result > 0 and result[#result] ~= "" then
      result[#result + 1] = ""
    end
  end
  local function heading(name)
    if section ~= name then
      blank()
      result[#result + 1] = "**" .. name .. "**"
      result[#result + 1] = ""
    end
    section = name
  end
  local i = 1
  while i <= #lines do
    local line = lines[i]
    local marker, tail = line:match("^ ? ? ?([`~]+)(.*)$")
    if fence then
      result[#result + 1] = line
      if marker and marker:match("^" .. fence:sub(1, 1) .. "+$") and #marker >= #fence and vim.trim(tail) == "" then
        fence = nil
      end
    elseif marker and #marker >= 3 and (marker:match("^`+$") or marker:match("^~+$")) then
      fence = marker
      result[#result + 1] = line
    else
      local name, rest, escaped = command(line)
      -- Poxy's singular detail is an alias for Doxygen's details. A following
      -- code command may share the same line after clangd's paragraph folding.
      if name == "brief" or name == "details" or name == "detail" then
        blank()
        changed, section = true, nil
        line = rest
        name, rest, escaped = command(line)
      end
      local block = blocks[name]
      if block then
        local last
        for j = i + 1, #lines do
          local closer, suffix = command(lines[j])
          if (closer == block.close or closer == block.alternate) and suffix == "" then
            last = j
            break
          end
        end
        -- An incomplete code block must not swallow later prose or directives.
        if not last then
          return documentation
        end
        local language = block.language
        if name == "code" then
          local explicit, body = rest:match("^%{%.?([%w_+%-]+)%}%s*(.*)$")
          if explicit then
            language, rest = explicit, body
          end
        end
        local body = rest ~= "" and { rest } or {}
        for j = i + 1, last - 1 do
          body[#body + 1] = lines[j]
        end
        local fence_size = 3
        for j, value in ipairs(body) do
          body[j] = escaped and unescape(value) or value
          for ticks in body[j]:gmatch("`+") do
            fence_size = math.max(fence_size, #ticks + 1)
          end
        end
        local code_fence = string.rep("`", fence_size)
        blank()
        result[#result + 1] = code_fence .. language
        vim.list_extend(result, body)
        result[#result + 1] = code_fence
        blank()
        changed, section, i = true, nil, last
      elseif name == "param" or name == "tparam" then
        local direction, description = rest:match("^%[([^%]]+)%]%s*(.*)$")
        local parameter, body = (description or rest):match("^(%S+)%s*(.*)$")
        if parameter then
          heading(sections[name])
          parameter = escaped and unescape(parameter) or parameter
          result[#result + 1] = "- `"
            .. parameter
            .. "`"
            .. (direction and " (" .. direction .. ")" or "")
            .. ":"
            .. (body ~= "" and " " .. body or "")
          changed = true
        else
          result[#result + 1] = line
        end
      else
        if sections[name] then
          heading(sections[name])
          line, changed = rest, true
          name, rest = command(line)
        end
        if name == "conditional_return" then
          local condition, body = rest:match("^%{([^{}]+)%}%s*(.*)$")
          if condition then
            blank()
            line, changed = "**" .. condition .. ":**" .. (body ~= "" and " " .. body or ""), true
          end
        end
        if section == "Parameters" or section == "Template parameters" then
          line = line ~= "" and "  " .. line or line
        end
        if line ~= "" or result[#result] ~= "" then
          result[#result + 1] = line
        end
      end
    end
    i = i + 1
  end
  if not changed then
    return documentation
  end
  return { kind = "markdown", value = table.concat(result, "\n") }
end

function M.draw(opts)
  if opts.item.client_name ~= "clangd" then
    return opts.default_implementation()
  end
  -- Resolve has already completed here. Keep the completion item, edit ranges,
  -- snippets and provider cache intact; override only the displayed document.
  opts.default_implementation({ documentation = M.normalize(opts.item.documentation) })
end

local function hover_contents(contents)
  if type(contents) == "table" and vim.islist(contents) then
    return vim.tbl_map(hover_contents, contents)
  end
  return M.normalize(contents)
end

local noice_installed = false
function M.setup_noice()
  if noice_installed then
    return
  end
  -- Noice's explicit requests and auto signature trigger call these same
  -- callbacks. Keep its request, focus, error and rendering behavior intact.
  for _, kind in ipairs({ "hover", "signature" }) do
    local module = require("noice.lsp." .. kind)
    local key = "on_" .. kind
    local handler = module[key]
    module[key] = function(err, result, ctx, ...)
      local client = ctx and ctx.client_id and vim.lsp.get_client_by_id(ctx.client_id)
      if not err and type(result) == "table" and client and client.name == "clangd" then
        -- Noice adds rendering state to signature results; give it a copy so
        -- neither that state nor normalized prose changes the server response.
        result = vim.deepcopy(result)
        if kind == "hover" then
          result.contents = hover_contents(result.contents)
        else
          for _, signature in ipairs(result.signatures or {}) do
            signature.documentation = M.normalize(signature.documentation)
            for _, parameter in ipairs(signature.parameters or {}) do
              parameter.documentation = M.normalize(parameter.documentation)
            end
          end
        end
      end
      return handler(err, result, ctx, ...)
    end
  end
  noice_installed = true
end

return M

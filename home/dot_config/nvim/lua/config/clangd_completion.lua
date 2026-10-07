local M = {}

-- clangd's statement patterns have unindented body placeholders. LuaSnip
-- preserves relative whitespace; it does not infer C/C++ block indentation.
-- Limit this repair to statement/requires snippets, not namespace/class layout,
-- function arguments, header edits or arbitrary snippets from another server.
local block_patterns = {
  ["if"] = true,
  ["for"] = true,
  ["while"] = true,
  ["do"] = true,
  ["switch"] = true,
  ["try"] = true,
  ["catch"] = true,
  ["requires"] = true,
}

local function indent_body(text)
  if type(text) ~= "string" then
    return text
  end
  -- A literal tab is expanded by LuaSnip using the buffer's indentation policy.
  -- Already-indented bodies are unchanged, including on Blink's resolve pass.
  text = text:gsub("({\n)(%$%d+)(\n})", "%1\t%2%3")
  text = text:gsub("({\n)(%${%d+})(\n})", "%1\t%2%3")
  return (text:gsub("({\n)(%${%d+:[^{}\n]*})(\n})", "%1\t%2%3"))
end

function M.transform_items(_, items)
  for _, item in ipairs(items) do
    if
      item.client_name == "clangd"
      and item.kind == 15
      and item.insertTextFormat == 2
      and block_patterns[item.filterText]
    then
      item.insertText = indent_body(item.insertText)
      item.textEditText = indent_body(item.textEditText)
      if item.textEdit then
        item.textEdit.newText = indent_body(item.textEdit.newText)
      end
    end
  end
  return items
end

return M

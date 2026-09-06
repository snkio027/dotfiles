--- DX Semantic Color System (DX-COLOR-003)
--- Storm-derived semantic palette projection.

local M = {}

--- Resolves source-semantic and state colors from TokyoNight's named palette.
--- @param c table TokyoNight Storm palette table
--- @return table
function M.resolve(c)
  local code = {
    variable = c.fg,
    keyword = c.magenta,
    keyword_function = c.blue,
    callable = c.yellow,
    type = c.cyan,
    builtin = c.green,
    lifetime = c.blue1,
    member = c.cyan,
    parameter = c.fg_dark,
    meta = c.magenta,
    namespace = c.blue,
    string = c.green,
    number = c.orange,
    constant = c.yellow,
    label = c.dark5,
    operator = c.blue5,
    punctuation = c.fg_dark,
    comment = c.comment,
    doc = c.dark5,
  }

  return {
    code = code,
    state = {
      error = c.error,
      warn = c.warning,
      success = c.green1,
      info = c.info,
      hint = c.hint,
    },
  }
end

return M

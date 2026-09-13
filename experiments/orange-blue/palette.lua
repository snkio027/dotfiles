-- Trial only: four changes relative to the ordinary C4.4 palette.
local M = {}

function M.apply(p)
  p.code.callable = "#FFAD66"
  p.code.namespace = "#C792EA"
  p.code.keyword = "#6CA6FF"
  p.code.keyword_function = "#6CA6FF"
  return p
end

return M

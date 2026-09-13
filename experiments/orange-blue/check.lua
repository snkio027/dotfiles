-- Independent change-budget and resolved-highlight check, not human acceptance.
assert(vim.g.dotfiles_orange_blue_preview, "Not running in the orange/blue preview")
local colors = require("catppuccin.palettes").get_palette("mocha")
local baseline = dofile(assert(vim.env.DOTFILES_COLOR_BASELINE_CONFIG) .. "/lua/theme/palette.lua").resolve(colors)
local candidate = require("theme.palette").resolve(colors)
local expected = vim.deepcopy(baseline)
expected.code.callable = "#FFAD66"
expected.code.namespace = "#C792EA"
expected.code.keyword = "#6CA6FF"
expected.code.keyword_function = "#6CA6FF"
local function check_palette(p)
  assert(vim.deep_equal(p, expected), "Palette delta is not exactly the four approved values")
end
check_palette(candidate)
local bad = vim.deepcopy(candidate)
bad.code.type = "#FF0000"
assert(not pcall(check_palette, bad), "Fifth palette mutation escaped detection")

local original_graph = require("theme.compose").highlights(baseline, require("theme.visual.c4"))
local graph = require("theme").highlights(colors)
local changes = {
  DxCallable = "#FFAD66",
  DxNamespace = "#C792EA",
  DxKeyword = "#6CA6FF",
  DxFunctionKeyword = "#6CA6FF",
  -- Existing consumers of code.keyword; no new mapping or UI override.
  RenderMarkdownQuote = "#6CA6FF",
  RenderMarkdownH1 = "#6CA6FF",
  RenderMarkdownHint = "#6CA6FF",
}
assert(vim.tbl_count(original_graph) == 226 and vim.tbl_count(graph) == 226, "Group count changed")
for group, previous in pairs(original_graph) do
  local wanted = vim.deepcopy(previous)
  if changes[group] then
    assert(previous.fg ~= changes[group], "Expected a real foreground change: " .. group)
    wanted.fg = changes[group]
  end
  assert(vim.deep_equal(graph[group], wanted), "Unexpected graph/style/link change: " .. group)
  local actual = vim.api.nvim_get_hl(0, { name = group, link = true })
  if wanted.link then
    assert(actual.link == wanted.link, "Applied semantic link drift: " .. group)
  else
    for _, field in ipairs({ "fg", "bg", "sp" }) do
      if wanted[field] and wanted[field] ~= "NONE" then
        assert(actual[field] == tonumber(wanted[field]:sub(2), 16), "Applied color drift: " .. group .. "." .. field)
      end
    end
  end
end
assert(vim.tbl_count(require("theme.domain").roles) == 23)
assert(vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg == 0x1A1B2A)
for group, role in pairs({
  ["@keyword"] = "DxKeyword",
  ["@keyword.function"] = "DxFunctionKeyword",
  ["@module"] = "DxNamespace",
  ["@lsp.type.namespace"] = "DxNamespace",
}) do
  assert(vim.api.nvim_get_hl(0, { name = group, link = true }).link == role, "Distinct identity lost: " .. group)
end
print(
  "Orange/Blue preview passed: exactly 4 palette values, 7 direct foreground changes, 23 roles / 226 groups; background and other colors preserved."
)

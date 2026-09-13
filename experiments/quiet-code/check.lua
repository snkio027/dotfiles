-- Local preview validation, not a replacement for the frozen C4.4 contract.
assert(vim.g.dotfiles_quiet_code_preview, "Not running in the preview")
local baseline = assert(vim.env.DOTFILES_QUIET_BASELINE_CONFIG) .. "/lua/"
local colors = require("catppuccin.palettes").get_palette("mocha")
local original_palette = dofile(baseline .. "theme/palette.lua").resolve(colors)
local graph = require("theme").highlights(colors)
local old_graph = {}
for _, layer in ipairs(require("theme.compose").layers) do
	local owner = layer.module or require("theme.visual.c4")
	if layer.name == "ui" or layer.name == "plugins" then
		owner = dofile(baseline .. "theme/bindings/" .. layer.name .. ".lua")
	end
	for group, spec in pairs(owner[layer.entrypoint](original_palette)) do
		old_graph[group] = spec
	end
end

local expected = {
	DxVariable = "CFD3DD",
	DxParameter = "CFD3DD",
	DxMember = "BAC3D2",
	DxNamespace = "A0AABC",
	DxLabel = "A0AABC",
	DxKeyword = "B5A2D9",
	DxFunctionKeyword = "B5A2D9",
	DxMeta = "B5A2D9",
	DxCallable = "DDB97B",
	DxType = "7DBDB4",
	DxBuiltin = "93B7B1",
	DxLifetime = "93B7B1",
	DxString = "A9B99A",
	DxNumber = "D2AB8D",
	DxConstant = "D2AB8D",
	DxOperator = "A3ACBC",
	DxPunctuation = "8E98AA",
	DxComment = "858D9E",
	DxDocComment = "A2ABB9",
}
local allowed, unique_colors = {}, {}
for role, hex in pairs(expected) do
	allowed[role] = true
	unique_colors[hex] = true
	assert(vim.api.nvim_get_hl(0, { name = role, link = false }).fg == tonumber(hex, 16), role)
end
assert(vim.tbl_count(expected) == 19 and vim.tbl_count(unique_colors) == 13)
for _, group in ipairs({
	"Normal",
	"Visual",
	"CursorLineNr",
	"SnacksIndentScope",
	"NeotestFocused",
	"DapStoppedLine",
	"NeotestMarked",
	"DapBreakpointCondition",
	"RenderMarkdownCodeInline",
	"RenderMarkdownQuote",
	"RenderMarkdownH1",
	"RenderMarkdownH2",
	"RenderMarkdownH3",
	"RenderMarkdownHint",
}) do
	allowed[group] = true
end
assert(vim.tbl_count(graph) == 226 and vim.tbl_count(old_graph) == 226, "Graph group drift")
for group, previous in pairs(old_graph) do
	local current = assert(graph[group], "Missing group: " .. group)
	previous, current = vim.deepcopy(previous), vim.deepcopy(current)
	if allowed[group] then
		previous.fg, previous.bg, current.fg, current.bg = nil, nil, nil, nil
	end
	assert(vim.deep_equal(previous, current), "Non-visual contract drift: " .. group)
end
assert(vim.tbl_count(require("theme.domain").roles) == 23)
for group, role in pairs({
	["@lsp.type.variable"] = "DxVariable",
	["@lsp.type.parameter"] = "DxParameter",
	["@lsp.type.property"] = "DxMember",
	["@variable.parameter"] = "DxParameter",
	["@variable.member"] = "DxMember",
}) do
	assert(vim.api.nvim_get_hl(0, { name = group, link = true }).link == role, "Identity link changed: " .. group)
end
local function hl(name)
	return vim.api.nvim_get_hl(0, { name = name, link = false })
end
assert(hl("Normal").bg == 0x1B1D24 and hl("Normal").fg == 0xCFD3DD)
assert(hl("Visual").bg == 0x303848 and hl("Visual").fg == 0xE4E8F0)
assert(hl("DapStoppedLine").bg == 0x22252D and hl("DapStoppedLine").fg == nil)
for _, name in ipairs({ "CursorLineNr", "SnacksIndentScope", "NeotestFocused" }) do
	assert(hl(name).fg == 0xDDB97B, "Focus must not borrow member gray: " .. name)
end
assert(hl("DxComment").italic and hl("DxDocComment").italic, "Comment style changed")
for _, role in ipairs({ "DxError", "DxWarn", "DxInfo", "DxHint" }) do
	assert(hl(role).fg == tonumber(old_graph[role].fg:sub(2), 16), "State color changed: " .. role)
end
local function luminance(rgb)
	local result = 0
	for index, weight in ipairs({ 0.2126, 0.7152, 0.0722 }) do
		local component = math.floor(rgb / 256 ^ (3 - index)) % 256 / 255
		result = result + weight * (component <= 0.04045 and component / 12.92 or ((component + 0.055) / 1.055) ^ 2.4)
	end
	return result
end
for role in pairs(expected) do
	local ratio = (luminance(hl(role).fg) + 0.05) / (luminance(hl("Normal").bg) + 0.05)
	assert(ratio >= 4.5, "Source contrast below candidate floor: " .. role)
end
print("Quiet Code preview passed: 19 source roles / 13 colors, 23 roles, 226 groups; authority/state/styles preserved.")

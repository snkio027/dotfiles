--- DX-COLOR-004 M1 Storm-host semantic-overlay contract.

local M = {}

local function fail(message)
	error("STORM_VISUAL_CONTRACT_FAILURE: " .. message, 2)
end

local function assert_eq(actual, expected, message)
	if actual ~= expected then
		fail(
			(message or "assertion failed")
				.. (" (expected %s, got %s)"):format(vim.inspect(expected), vim.inspect(actual))
		)
	end
end

local function assert_hex_eq(actual, expected, message)
	if type(actual) ~= "string" or type(expected) ~= "string" or actual:lower() ~= expected:lower() then
		fail(
			(message or "color mismatch")
				.. (" (expected %s, got %s)"):format(vim.inspect(expected), vim.inspect(actual))
		)
	end
end

local function hex_to_rgb(hex)
	local normalized = assert(hex, "color is missing"):gsub("^#", "")
	return tonumber(normalized:sub(1, 2), 16), tonumber(normalized:sub(3, 4), 16), tonumber(normalized:sub(5, 6), 16)
end

local function luminance(hex)
	local r, g, b = hex_to_rgb(hex)
	local function channel(value)
		value = value / 255
		return value <= 0.04045 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
end

local function contrast(left, right)
	local a, b = luminance(left), luminance(right)
	return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)
end

local role_tokens = {
	DxKeyword = "keyword",
	DxFunctionKeyword = "keyword_function",
	DxCallable = "callable",
	DxType = "type",
	DxBuiltin = "builtin",
	DxLifetime = "lifetime",
	DxMember = "member",
	DxParameter = "parameter",
	DxVariable = "variable",
	DxMeta = "meta",
	DxNamespace = "namespace",
	DxString = "string",
	DxNumber = "number",
	DxConstant = "constant",
	DxLabel = "label",
	DxOperator = "operator",
	DxPunctuation = "punctuation",
	DxComment = "comment",
	DxDocComment = "doc",
}

local state_roles = {
	DxError = "error",
	DxWarn = "warn",
	DxInfo = "info",
	DxHint = "hint",
}

local expected_named_primitives = {
	variable = "fg",
	keyword = "magenta",
	keyword_function = "blue",
	callable = "yellow",
	type = "cyan",
	builtin = "green",
	lifetime = "blue1",
	member = "cyan",
	parameter = "fg_dark",
	meta = "magenta",
	namespace = "blue",
	string = "green",
	number = "orange",
	constant = "yellow",
	label = "dark5",
	operator = "blue5",
	punctuation = "fg_dark",
	comment = "comment",
	doc = "dark5",
}

local host_owned_groups = {
	"Normal",
	"NormalNC",
	"CursorLine",
	"CursorLineNr",
	"LineNr",
	"SignColumn",
	"Visual",
	"Search",
	"NormalFloat",
	"FloatBorder",
	"Pmenu",
	"PmenuSel",
	"DiagnosticError",
	"DiagnosticVirtualTextError",
	"DiagnosticUnderlineError",
	"GitSignsAdd",
	"BlinkCmpKindFunction",
	"NeotestPassed",
	"DapBreakpoint",
	"RenderMarkdownH1",
}

---@param context table
function M.verify(context)
	local palette = context.palette
	local roles = context.roles
	local graph = context.graph
	local domain = context.domain
	local host = context.host_colors

	assert_eq(
		vim.tbl_count(palette.code),
		vim.tbl_count(expected_named_primitives),
		"Storm source palette closure changed"
	)
	for token, primitive in pairs(expected_named_primitives) do
		assert_hex_eq(palette.code[token], host[primitive], ("code.%s must use TokyoNight %s"):format(token, primitive))
	end

	for role, token in pairs(role_tokens) do
		assert(domain.roles[role], "Storm visual references an unknown Domain role: " .. role)
		assert_hex_eq(roles[role].fg, palette.code[token], ("%s must project code.%s"):format(role, token))
	end
	for role, token in pairs(state_roles) do
		assert_hex_eq(roles[role].fg, palette.state[token], role .. " state ownership changed")
	end
	assert_eq(vim.tbl_count(roles), vim.tbl_count(domain.roles), "Storm visual role closure changed")

	for _, group in ipairs(host_owned_groups) do
		assert_eq(graph[group], nil, "DX semantic overlay must not own TokyoNight surface: " .. group)
	end
	assert_eq(graph["@lsp.mod.deprecated"].strikethrough, true, "semantic style authority was lost")

	local major_axes = { "variable", "keyword", "callable", "type", "builtin" }
	for i = 1, #major_axes do
		for j = i + 1, #major_axes do
			assert(
				palette.code[major_axes[i]]:lower() ~= palette.code[major_axes[j]]:lower(),
				("major Storm axes collided: %s/%s"):format(major_axes[i], major_axes[j])
			)
		end
	end

	assert(contrast(palette.code.variable, host.bg) >= 8.5, "Storm body readability floor failed")
	assert(contrast(palette.code.parameter, host.bg) >= 6.5, "Storm muted-body readability floor failed")
	assert(contrast(palette.code.doc, host.bg) >= 3.3, "Storm documentation readability floor failed")
	assert(contrast(palette.code.comment, host.bg) >= 2.2, "Storm recessed-comment floor failed")
end

---@param context table
function M.verify_negative_controls(context)
	local function must_reject(mutator, label)
		local bad = vim.deepcopy(context)
		mutator(bad)
		assert(not pcall(M.verify, bad), "negative control unexpectedly passed: " .. label)
	end

	must_reject(function(bad)
		bad.graph.Normal = { bg = bad.host_colors.bg }
	end, "DX surface ownership")
	must_reject(function(bad)
		bad.palette.code.keyword = bad.palette.code.variable
		bad.roles.DxKeyword.fg = bad.palette.code.variable
	end, "major semantic-axis collision")
	must_reject(function(bad)
		bad.graph["@lsp.mod.deprecated"].strikethrough = false
	end, "style authority")
	must_reject(function(bad)
		bad.roles.DxComment = nil
	end, "23-role closure")
end

return M

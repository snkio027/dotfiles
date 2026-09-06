--- DX-COLOR-003 M5 production contract for C4.4 High-Chroma Night.

local M = {}

local function fail(msg)
	error("C4_VISUAL_CONTRACT_FAILURE: " .. msg, 2)
end

local function assert_eq(actual, expected, msg)
	if actual ~= expected then
		fail(
			(msg or "assertion failed") .. (" (expected %s, got %s)"):format(vim.inspect(expected), vim.inspect(actual))
		)
	end
end

local function assert_hex_eq(actual, expected, msg)
	if type(actual) ~= "string" or type(expected) ~= "string" or actual:lower() ~= expected:lower() then
		fail(
			(msg or "hex assertion failed")
				.. (" (expected %s, got %s)"):format(vim.inspect(expected), vim.inspect(actual))
		)
	end
end

local function hex_to_rgb(hex)
	local clean = hex:gsub("^#", "")
	return tonumber(clean:sub(1, 2), 16), tonumber(clean:sub(3, 4), 16), tonumber(clean:sub(5, 6), 16)
end

local function linear_channel(value)
	value = value / 255
	if value <= 0.04045 then
		return value / 12.92
	end
	return ((value + 0.055) / 1.055) ^ 2.4
end

local function luminance(hex)
	local r, g, b = hex_to_rgb(hex)
	return 0.2126 * linear_channel(r) + 0.7152 * linear_channel(g) + 0.0722 * linear_channel(b)
end

local function contrast_ratio(left, right)
	local l1 = luminance(left)
	local l2 = luminance(right)
	if l1 < l2 then
		l1, l2 = l2, l1
	end
	return (l1 + 0.05) / (l2 + 0.05)
end

local function oklab(hex)
	local red, green, blue = hex_to_rgb(hex)
	local r = linear_channel(red)
	local g = linear_channel(green)
	local b = linear_channel(blue)
	local l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
	local m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
	local s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
	l = l ^ (1 / 3)
	m = m ^ (1 / 3)
	s = s ^ (1 / 3)
	return {
		0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
	}
end

local function oklab_distance(left, right)
	local a = oklab(left)
	local b = oklab(right)
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
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

local governed_tokens = {}
for _, token in pairs(role_tokens) do
	governed_tokens[token] = true
end

local must_separate = {
	{ "keyword", "keyword_function", 0.14 },
	{ "keyword_function", "namespace", 0.12 },
	{ "namespace", "type", 0.11 },
	{ "type", "builtin", 0.17 },
	{ "variable", "member", 0.12 },
	{ "variable", "string", 0.14 },
	{ "callable", "constant", 0.04 },
	{ "callable", "number", 0.065 },
}

local should_separate = {
	{ "builtin", "string", 0.035 },
	{ "number", "constant", 0.11 },
	{ "meta", "keyword", 0.10 },
	{ "type", "lifetime", 0.07 },
}

local intentional_near = {
	{ "variable", "parameter", 0.02, 0.10 },
	{ "comment", "punctuation", 0.02, 0.06 },
}

local function assert_ratio_range(name, ratio, minimum, maximum)
	if ratio < minimum or ratio > maximum then
		fail(("C4.4 %s contrast %.2f is outside %.1f–%.1f"):format(name, ratio, minimum, maximum))
	end
end

local function assert_minimum_distance(code, class_name, pairs)
	for _, pair in ipairs(pairs) do
		local left, right, minimum = unpack(pair)
		local distance = oklab_distance(code[left], code[right])
		if distance < minimum then
			fail(
				("%s pairing %s/%s has OKLab distance %.4f below %.4f"):format(
					class_name,
					left,
					right,
					distance,
					minimum
				)
			)
		end
	end
end

local function assert_near_distance(code, pairs)
	for _, pair in ipairs(pairs) do
		local left, right, minimum, maximum = unpack(pair)
		local distance = oklab_distance(code[left], code[right])
		if distance < minimum or distance > maximum then
			fail(
				("INTENTIONAL-NEAR pairing %s/%s has OKLab distance %.4f outside %.4f–%.4f"):format(
					left,
					right,
					distance,
					minimum,
					maximum
				)
			)
		end
	end
end

local function is_green_dominant(hex)
	local r, g, b = hex_to_rgb(hex)
	return g > r + 20 and g > b + 20
end

---@param context table
function M.verify(context)
	local palette = context.palette
	local roles = context.roles
	local graph = context.graph
	local domain = context.domain
	local host_colors = context.host_colors
	local code = palette.code

	if type(code) ~= "table" then
		fail("production palette.code is missing")
	end

	assert_eq(vim.tbl_count(code), vim.tbl_count(governed_tokens), "C4.4 production palette token closure changed")
	for name in pairs(governed_tokens) do
		if type(code[name]) ~= "string" then
			fail("C4.4 production palette is missing token: " .. name)
		end
	end
	for name in pairs(code) do
		if not governed_tokens[name] then
			fail("C4.4 production palette defines an unknown source token: " .. name)
		end
	end

	for role, token in pairs(role_tokens) do
		if not domain.roles[role] then
			fail("C4.4 production visual references a role outside the Domain: " .. role)
		end
		if not roles[role] then
			fail("C4.4 production visual is missing role: " .. role)
		end
		assert_hex_eq(roles[role].fg, code[token], ("C4 role %s does not use palette token %s"):format(role, token))
	end
	for role, token in pairs(state_roles) do
		assert_hex_eq(roles[role].fg, palette.state[token], "C4 state role changed ownership: " .. role)
	end
	assert_eq(vim.tbl_count(roles), vim.tbl_count(domain.roles), "C4 role closure changed")

	local state_values = {}
	for _, value in pairs(palette.state) do
		state_values[value:lower()] = true
	end
	for name, hex in pairs(code) do
		if state_values[hex:lower()] then
			fail(("C4 source/state exact-color separation violation: code.%s reuses %s"):format(name, hex))
		end
		if name ~= "builtin" and name ~= "string" and is_green_dominant(hex) then
			fail(("C4.4 admits green dominance only for builtin/string, found code.%s (%s)"):format(name, hex))
		end
	end
	if not is_green_dominant(code.builtin) or not is_green_dominant(code.string) then
		fail("C4.4 green builtin/string axes are missing")
	end

	assert_eq(palette.state.success:lower(), host_colors.sky:lower(), "state.success must remain Catppuccin Sky")
	assert_eq(graph.DiagnosticUnderlineError.undercurl, true, "C4 must preserve the diagnostic error undercurl")
	assert_eq(graph.DiagnosticUnderlineWarn.undercurl, true, "C4 must preserve the diagnostic warning undercurl")

	assert_hex_eq(palette.ui.normal_bg, "#1A1B2A", "C4.4 must own the dark navy canvas")
	local background = context.resolved_background or palette.ui.normal_bg
	assert_hex_eq(background, palette.ui.normal_bg, "C4.4 contrast input must be the resolved dark navy canvas")
	local ratios = {}
	for name, hex in pairs(code) do
		ratios[name] = contrast_ratio(hex, background)
	end

	if ratios.variable < 10.0 then
		fail(("Soft Primary Body Floor: DxVariable contrast %.2f is below 10.0"):format(ratios.variable))
	end
	local vr, vg, vb = hex_to_rgb(code.variable)
	if math.max(vr, vg, vb) - math.min(vr, vg, vb) > 48 then
		fail("Bright Neutral Body: DxVariable is too chromatic")
	end
	if ratios.member >= ratios.variable or ratios.parameter >= ratios.variable then
		fail("DxMember and DxParameter must remain subordinate to DxVariable")
	end

	assert_ratio_range("DxKeyword", ratios.keyword, 7.1, 7.7)
	assert_ratio_range("DxFunctionKeyword", ratios.keyword_function, 9.6, 10.3)
	assert_ratio_range("DxCallable", ratios.callable, 8.6, 9.2)
	assert_ratio_range("DxType", ratios.type, 7.8, 8.4)
	assert_ratio_range("DxBuiltin", ratios.builtin, 9.0, 9.6)
	assert_ratio_range("DxLifetime", ratios.lifetime, 9.3, 9.9)
	assert_ratio_range("DxMember", ratios.member, 8.0, 8.6)
	assert_ratio_range("DxParameter", ratios.parameter, 8.5, 9.2)
	assert_ratio_range("DxNamespace", ratios.namespace, 6.2, 6.8)
	assert_ratio_range("DxMeta", ratios.meta, 5.3, 5.9)
	assert_ratio_range("DxString", ratios.string, 9.7, 10.3)
	assert_ratio_range("DxNumber", ratios.number, 7.5, 8.0)
	assert_ratio_range("DxConstant", ratios.constant, 9.7, 10.3)
	assert_ratio_range("DxLabel", ratios.label, 5.7, 6.2)
	assert_ratio_range("DxPunctuation", ratios.punctuation, 5.3, 5.8)
	assert_ratio_range("DxComment", ratios.comment, 4.1, 4.6)
	assert_ratio_range("DxDocComment", ratios.doc, 6.0, 6.5)
	if ratios.operator < 10.8 then
		fail("DxOperator must retain high local micro-syntax energy")
	end
	if not (ratios.comment < ratios.doc and ratios.doc < ratios.variable) then
		fail("Prose hierarchy must satisfy DxComment < DxDocComment < DxVariable")
	end
	if not (ratios.comment < ratios.punctuation and ratios.punctuation < ratios.variable) then
		fail("Structural hierarchy must satisfy DxComment < DxPunctuation < DxVariable")
	end

	assert_minimum_distance(code, "MUST-SEPARATE", must_separate)
	assert_minimum_distance(code, "SHOULD-SEPARATE", should_separate)
	assert_near_distance(code, intentional_near)
	for name, hex in pairs(code) do
		local distance = oklab_distance(hex, palette.state.error)
		if distance < 0.035 then
			fail(
				("normal source/Error state pairing code.%s has OKLab distance %.4f below 0.035"):format(name, distance)
			)
		end
	end

	local keyword_r, _, keyword_b = hex_to_rgb(code.keyword)
	local function_r, _, function_b = hex_to_rgb(code.keyword_function)
	local namespace_r, _, namespace_b = hex_to_rgb(code.namespace)
	local type_r, type_g, type_b = hex_to_rgb(code.type)
	local callable_r, _, callable_b = hex_to_rgb(code.callable)
	if
		keyword_b <= keyword_r
		or function_b - function_r < 80
		or namespace_b - namespace_r < 120
		or type_b <= type_g
		or callable_r - callable_b < 100
	then
		fail("C4.4 lost its violet / cyan / pure-blue / bright-cyan / warm axis identities")
	end

	if code.operator:lower() == palette.state.error:lower() or code.operator:lower() == palette.state.warn:lower() then
		fail("DxOperator must not reuse error or warning identity")
	end
end

---@param context table
function M.verify_negative_controls(context)
	local cases = {
		{
			name = "bad_primary_body",
			mutate = function(palette)
				palette.code.variable = palette.code.comment
			end,
		},
		{
			name = "bad_comment",
			mutate = function(palette)
				palette.code.comment = palette.code.variable
			end,
		},
		{
			name = "bad_comment_floor",
			mutate = function(palette)
				palette.code.comment = palette.ui.overlay0
			end,
		},
		{
			name = "bad_background",
			mutate = function(palette)
				palette.ui.normal_bg = palette.ui.base
			end,
		},
		{
			name = "bad_must_pair",
			mutate = function(palette)
				palette.code.keyword_function = palette.code.keyword
			end,
		},
		{
			name = "bad_should_pair",
			mutate = function(palette)
				palette.code.lifetime = palette.code.type
			end,
		},
		{
			name = "bad_intentional_near",
			mutate = function(palette)
				palette.code.parameter = palette.code.callable
			end,
		},
		{
			name = "bad_source_state",
			mutate = function(palette)
				palette.code.member = palette.state.error
			end,
		},
		{
			name = "bad_operator_state",
			mutate = function(palette)
				palette.code.operator = palette.state.warn
			end,
		},
	}

	for _, case in ipairs(cases) do
		local palette = vim.deepcopy(context.palette)
		case.mutate(palette)
		local roles = context.visual.roles(palette)
		local ok = pcall(M.verify, {
			palette = palette,
			roles = roles,
			graph = context.graph,
			domain = context.domain,
			host_colors = context.host_colors,
		})
		if ok then
			fail("negative control did not fail closed: " .. case.name)
		end
	end
end

return M

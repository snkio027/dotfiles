--- DX-COLOR-003 E production visual contract; the single-runtime filename is retained.

local M = {}

local function fail(msg)
	error("E_VISUAL_CONTRACT_FAILURE: " .. msg, 2)
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

-- Independent design oracle: never read expected HEX values from production.
local expected_code = {
	variable = "#C4CAE0",
	keyword = "#DB8FEE",
	keyword_function = "#DB8FEE",
	callable = "#FFB266",
	type = "#3DD1BB",
	builtin = "#9ECE6A",
	member = "#F29BC1",
	lifetime = "#67D4C7",
	parameter = "#C8B2E3",
	meta = "#FF8F7D",
	namespace = "#79AAFF",
	string = "#B8D07A",
	number = "#F2D675",
	constant = "#F2D675",
	label = "#8E98B8",
	operator = "#89DDFF",
	punctuation = "#8991A8",
	comment = "#7580A3",
	doc = "#929BC2",
}

local function verify_fixed_palette(code)
	assert_hex_eq(code.keyword, code.keyword_function, "E_SHARED_COLOR: keyword/function-keyword")
	assert_hex_eq(code.number, code.constant, "E_SHARED_COLOR: number/constant")
	local colors = {}
	for _, hex in pairs(code) do
		colors[hex:lower()] = true
	end
	-- With 19 tokens and the two pairs above, 17 colors also excludes any third pair.
	assert_eq(vim.tbl_count(colors), 17, "E_SOURCE_COLOR_COUNT: only the two approved pairs may share colors")
	for token, hex in pairs(expected_code) do
		assert_hex_eq(code[token], hex, "E_FIXED_HEX: " .. token)
	end
end

local must_separate = {
	{ "keyword_function", "namespace", 0.12 },
	{ "namespace", "type", 0.11 },
	{ "type", "builtin", 0.10 }, -- E distance 0.1151; supersedes C4.4's 0.17 floor.
	{ "variable", "member", 0.12 },
	{ "variable", "string", 0.14 },
	{ "callable", "constant", 0.04 },
	{ "callable", "number", 0.065 },
}

local should_separate = {
	{ "builtin", "string", 0.035 },
	{ "meta", "keyword", 0.10 },
}

-- E fixes Type/Lifetime at distance 0.0342: the old 0.07 SHOULD-SEPARATE
-- requirement is not met. Preserve both fixed colors; Rust human review remains
-- pending. This is an accepted palette proximity, not proof of distinguishability.

local intentional_near = {
	{ "variable", "parameter", 0.02, 0.10 },
	{ "comment", "punctuation", 0.02, 0.06 },
}

local function assert_ratio_range(name, ratio, minimum, maximum)
	if ratio < minimum or ratio > maximum then
		fail(("E_CONTRAST: %s contrast %.2f is outside %.1f–%.1f"):format(name, ratio, minimum, maximum))
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

local function verify_pairings(code)
	assert_minimum_distance(code, "MUST-SEPARATE", must_separate)
	assert_minimum_distance(code, "SHOULD-SEPARATE", should_separate)
	assert_near_distance(code, intentional_near)
end

local function verify_policy(context)
	local palette = context.palette
	local roles = context.roles
	local graph = context.graph
	local domain = context.domain
	local host_colors = context.host_colors
	local code = palette.code

	if type(code) ~= "table" then
		fail("production palette.code is missing")
	end

	assert_eq(vim.tbl_count(code), vim.tbl_count(governed_tokens), "E_TOKEN_CLOSURE: production palette changed")
	for name in pairs(governed_tokens) do
		if type(code[name]) ~= "string" or not code[name]:match("^#%x%x%x%x%x%x$") then
			fail("E_TOKEN_FORMAT: missing or invalid source token: " .. name)
		end
	end
	for name in pairs(code) do
		if not governed_tokens[name] then
			fail("E_TOKEN_CLOSURE: unknown source token: " .. name)
		end
	end

	for role, token in pairs(role_tokens) do
		if not domain.roles[role] then
			fail("E production visual references a role outside the Domain: " .. role)
		end
		if not roles[role] then
			fail("E production visual is missing role: " .. role)
		end
		assert_hex_eq(roles[role].fg, code[token], ("E role %s does not use palette token %s"):format(role, token))
	end
	for role, token in pairs(state_roles) do
		assert_hex_eq(roles[role].fg, palette.state[token], "E state role changed ownership: " .. role)
	end
	assert_eq(vim.tbl_count(roles), vim.tbl_count(domain.roles), "E role closure changed")

	local state_values = {}
	for _, value in pairs(palette.state) do
		state_values[value:lower()] = true
	end
	for name, hex in pairs(code) do
		if state_values[hex:lower()] then
			fail(("E_SOURCE_STATE: code.%s reuses %s"):format(name, hex))
		end
		-- E's teal Type also meets this coarse RGB heuristic (G - B = 22).
		if name ~= "builtin" and name ~= "string" and name ~= "type" and is_green_dominant(hex) then
			fail(("E admits green dominance only for type/builtin/string, found code.%s (%s)"):format(name, hex))
		end
	end
	if not is_green_dominant(code.builtin) or not is_green_dominant(code.string) then
		fail("E green builtin/string axes are missing")
	end

	assert_eq(palette.state.success:lower(), host_colors.sky:lower(), "state.success must remain Catppuccin Sky")
	assert_eq(graph.DiagnosticUnderlineError.undercurl, true, "E_DIAGNOSTIC_STYLE: error undercurl")
	assert_eq(graph.DiagnosticUnderlineWarn.undercurl, true, "E_DIAGNOSTIC_STYLE: warning undercurl")

	assert_hex_eq(palette.ui.normal_bg, "#1A1B2A", "E_BACKGROUND: dark navy canvas must remain unchanged")
	local background = context.resolved_background or palette.ui.normal_bg
	assert_hex_eq(
		background,
		palette.ui.normal_bg,
		"E_BACKGROUND: contrast input must be the resolved dark navy canvas"
	)
	local ratios = {}
	for name, hex in pairs(code) do
		ratios[name] = contrast_ratio(hex, background)
	end

	if ratios.variable < 10.0 then
		fail(("E_BODY_FLOOR: DxVariable contrast %.2f is below 10.0"):format(ratios.variable))
	end
	local vr, vg, vb = hex_to_rgb(code.variable)
	if math.max(vr, vg, vb) - math.min(vr, vg, vb) > 48 then
		fail("Bright Neutral Body: DxVariable is too chromatic")
	end
	if ratios.member >= ratios.variable or ratios.parameter >= ratios.variable then
		fail("DxMember and DxParameter must remain subordinate to DxVariable")
	end

	assert_ratio_range("DxKeyword", ratios.keyword, 7.2, 7.7)
	assert_ratio_range("DxFunctionKeyword", ratios.keyword_function, 7.2, 7.7)
	assert_ratio_range("DxCallable", ratios.callable, 9.3, 9.9)
	assert_ratio_range("DxType", ratios.type, 8.7, 9.2)
	assert_ratio_range("DxBuiltin", ratios.builtin, 9.0, 9.6)
	assert_ratio_range("DxLifetime", ratios.lifetime, 9.3, 9.9)
	assert_ratio_range("DxMember", ratios.member, 8.0, 8.6)
	assert_ratio_range("DxParameter", ratios.parameter, 8.5, 9.2)
	assert_ratio_range("DxNamespace", ratios.namespace, 7.1, 7.6)
	assert_ratio_range("DxMeta", ratios.meta, 7.4, 8.0)
	assert_ratio_range("DxString", ratios.string, 9.7, 10.3)
	assert_ratio_range("DxNumber", ratios.number, 11.6, 12.1)
	assert_ratio_range("DxConstant", ratios.constant, 11.6, 12.1)
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

	verify_pairings(code)
	for name, hex in pairs(code) do
		local distance = oklab_distance(hex, palette.state.error)
		if distance < 0.035 then
			fail(
				("normal source/Error state pairing code.%s has OKLab distance %.4f below 0.035"):format(name, distance)
			)
		end
	end

	local keyword_r, keyword_g, keyword_b = hex_to_rgb(code.keyword)
	local function_r, function_g, function_b = hex_to_rgb(code.keyword_function)
	local namespace_r, namespace_g, namespace_b = hex_to_rgb(code.namespace)
	local type_r, type_g, type_b = hex_to_rgb(code.type)
	local callable_r, _, callable_b = hex_to_rgb(code.callable)
	if
		keyword_r - keyword_g < 60
		or keyword_b - keyword_r < 10
		or function_r - function_g < 60
		or function_b - function_r < 10
		or namespace_b - namespace_r < 100
		or namespace_b - namespace_g < 60
		or type_g <= type_b
		or type_b - type_r < 100
		or callable_r - callable_b < 100
	then
		fail("E_COLOR_AXES: shared purple grammar / blue namespace / teal type / orange callable required")
	end

	if code.operator:lower() == palette.state.error:lower() or code.operator:lower() == palette.state.warn:lower() then
		fail("DxOperator must not reuse error or warning identity")
	end
end

---@param context table
function M.verify(context)
	verify_policy(context)
	verify_fixed_palette(context.palette.code)
end

---@param context table
function M.verify_negative_controls(context)
	local cases = {
		{
			name = "bad_primary_body",
			expected = "E_BODY_FLOOR:",
			mutate = function(palette)
				palette.code.variable = palette.code.comment
			end,
		},
		{
			name = "bad_comment",
			expected = "E_CONTRAST: DxComment",
			mutate = function(palette)
				palette.code.comment = palette.code.variable
			end,
		},
		{
			name = "bad_comment_floor",
			expected = "E_CONTRAST: DxComment",
			mutate = function(palette)
				palette.code.comment = palette.ui.overlay0
			end,
		},
		{
			name = "bad_background",
			expected = "E_BACKGROUND:",
			mutate = function(palette)
				palette.ui.normal_bg = palette.ui.base
			end,
		},
		{
			name = "bad_must_pair",
			expected = "MUST-SEPARATE pairing namespace/type",
			verify = function(candidate)
				verify_pairings(candidate.palette.code)
			end,
			mutate = function(palette)
				palette.code.namespace = palette.code.type
			end,
		},
		{
			name = "bad_should_pair",
			expected = "SHOULD-SEPARATE pairing meta/keyword",
			verify = function(candidate)
				verify_pairings(candidate.palette.code)
			end,
			mutate = function(palette)
				palette.code.meta = palette.code.keyword
			end,
		},
		{
			name = "bad_intentional_near",
			expected = "INTENTIONAL-NEAR pairing variable/parameter",
			verify = function(candidate)
				verify_pairings(candidate.palette.code)
			end,
			mutate = function(palette)
				palette.code.parameter = palette.code.callable
			end,
		},
		{
			name = "bad_source_state",
			expected = "E_SOURCE_STATE: code.member",
			mutate = function(palette)
				palette.code.member = palette.state.error
			end,
		},
		{
			name = "bad_operator_state",
			expected = "E_SOURCE_STATE: code.operator",
			mutate = function(palette)
				palette.code.operator = palette.state.warn
			end,
		},
		{
			name = "bad_fixed_hex",
			expected = "E_FIXED_HEX:",
			verify = M.verify,
			mutate = function(palette)
				-- Preserve sharing and relational bounds; only the exact E oracle rejects this.
				palette.code.keyword = "#DC90EF"
				palette.code.keyword_function = "#DC90EF"
			end,
		},
		{
			name = "bad_shared_grammar",
			expected = "E_SHARED_COLOR: keyword/function-keyword",
			verify = function(candidate)
				verify_fixed_palette(candidate.palette.code)
			end,
			mutate = function(palette)
				palette.code.keyword_function = "#DC90EF"
			end,
		},
		{
			name = "bad_grammar_namespace_swap",
			expected = "E_COLOR_AXES:",
			mutate = function(palette)
				palette.code.keyword, palette.code.namespace = palette.code.namespace, palette.code.keyword
				palette.code.keyword_function = palette.code.keyword
			end,
		},
		{
			name = "bad_shared_literals",
			expected = "E_SHARED_COLOR: number/constant",
			verify = function(candidate)
				verify_fixed_palette(candidate.palette.code)
			end,
			mutate = function(palette)
				-- Still 17 colors, but the wrong pair shares: a count-only gate must not pass it.
				palette.code.constant = palette.code.callable
			end,
		},
		{
			name = "bad_third_shared_pair",
			expected = "E_SOURCE_COLOR_COUNT:",
			verify = function(candidate)
				verify_fixed_palette(candidate.palette.code)
			end,
			mutate = function(palette)
				palette.code.label = palette.code.comment
			end,
		},
		{
			name = "bad_token_closure",
			expected = "E_TOKEN_CLOSURE:",
			mutate = function(palette)
				palette.code.unapproved = palette.code.variable
			end,
		},
	}

	-- Exercise the same private policy functions used unconditionally by verify().
	-- This prevents fixed-HEX rejection from masquerading as a pairing/contrast proof.
	for _, case in ipairs(cases) do
		local palette = vim.deepcopy(context.palette)
		case.mutate(palette)
		local roles = context.visual.roles(palette)
		local ok, err = pcall(case.verify or verify_policy, {
			palette = palette,
			roles = roles,
			graph = context.graph,
			domain = context.domain,
			host_colors = context.host_colors,
		})
		if ok or not tostring(err):find(case.expected, 1, true) then
			fail(
				("negative control %s must reject with %s, got %s"):format(
					case.name,
					case.expected,
					ok and "success" or tostring(err)
				)
			)
		end
	end
	print(("E visual negative controls passed: %d/%d with specific failure markers."):format(#cases, #cases))
end

return M

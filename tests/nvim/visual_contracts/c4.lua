--- DX-COLOR-003 M3-B profile-aware contract for the C4.0 candidate.

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

local function hex_to_rgb(hex)
	local clean = hex:gsub("^#", "")
	return tonumber(clean:sub(1, 2), 16), tonumber(clean:sub(3, 4), 16), tonumber(clean:sub(5, 6), 16)
end

local function luminance(hex)
	local r, g, b = hex_to_rgb(hex)
	local function channel(value)
		value = value / 255
		if value <= 0.04045 then
			return value / 12.92
		end
		return ((value + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
end

local function contrast_ratio(left, right)
	local l1 = luminance(left)
	local l2 = luminance(right)
	if l1 < l2 then
		l1, l2 = l2, l1
	end
	return (l1 + 0.05) / (l2 + 0.05)
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

local changed_tokens = {
	variable = true,
	member = true,
	parameter = true,
	type = true,
	keyword_function = true,
	string = true,
	number = true,
	constant = true,
	namespace = true,
	operator = true,
	punctuation = true,
	comment = true,
	doc = true,
}

---@param context table
function M.verify(context)
	local palette = context.palette
	local roles = context.roles
	local graph = context.graph
	local domain = context.domain
	local host_colors = context.host_colors
	local code = palette.code_profiles and palette.code_profiles.c4

	if type(code) ~= "table" then
		fail("palette.code_profiles.c4 is missing")
	end

	assert_eq(vim.tbl_count(code), vim.tbl_count(palette.code), "C4 palette token closure changed")
	local observed_changed = {}
	for name, c3_value in pairs(palette.code) do
		local c4_value = code[name]
		if type(c4_value) ~= "string" then
			fail("C4 palette is missing token: " .. name)
		end
		if c4_value:lower() ~= c3_value:lower() then
			observed_changed[name] = true
		end
	end
	for name in pairs(code) do
		if palette.code[name] == nil then
			fail("C4 palette defines an unknown source token: " .. name)
		end
	end
	if not vim.deep_equal(observed_changed, changed_tokens) then
		fail(
			("C4.0 must change exactly the 13 authorized visual tokens (expected %s, got %s)"):format(
				vim.inspect(changed_tokens),
				vim.inspect(observed_changed)
			)
		)
	end

	for role, token in pairs(role_tokens) do
		if not domain.roles[role] then
			fail("C4 profile references a role outside the Domain: " .. role)
		end
		if not roles[role] then
			fail("C4 profile is missing role: " .. role)
		end
		assert_eq(roles[role].fg, code[token], ("C4 role %s does not use palette token %s"):format(role, token))
	end
	for role, token in pairs(state_roles) do
		assert_eq(roles[role].fg, palette.state[token], "C4 state role changed ownership: " .. role)
	end
	assert_eq(vim.tbl_count(roles), vim.tbl_count(domain.roles), "C4 role closure changed")

	local state_values = {}
	for _, value in pairs(palette.state) do
		state_values[value:lower()] = true
	end
	for name, hex in pairs(code) do
		if state_values[hex:lower()] then
			fail(("C4 source/state separation violation: code.%s reuses %s"):format(name, hex))
		end
		local r, g, b = hex_to_rgb(hex)
		if g > r + 20 and g > b + 20 then
			fail(("C4 normal source role code.%s (%s) is green-dominant"):format(name, hex))
		end
	end

	assert_eq(palette.state.success:lower(), host_colors.sky:lower(), "state.success must remain Catppuccin Sky")
	assert_eq(graph.DiagnosticUnderlineError.undercurl, true, "C4 must preserve the diagnostic error undercurl")
	assert_eq(graph.DiagnosticUnderlineWarn.undercurl, true, "C4 must preserve the diagnostic warning undercurl")

	local background = palette.ui.base
	local ratios = {}
	for name, hex in pairs(code) do
		ratios[name] = contrast_ratio(hex, background)
	end

	if ratios.variable < 9.0 then
		fail(("Primary Body Floor: DxVariable contrast %.2f is below 9.0"):format(ratios.variable))
	end
	local vr, vg, vb = hex_to_rgb(code.variable)
	if math.max(vr, vg, vb) - math.min(vr, vg, vb) > 48 then
		fail("Bright Neutral Body: DxVariable is too chromatic")
	end
	if code.member == code.variable or ratios.member >= ratios.variable then
		fail("DxMember must be distinct from and visually subordinate to DxVariable")
	end
	if ratios.parameter >= ratios.variable then
		fail("DxParameter must remain subordinate to DxVariable")
	end

	if ratios.comment > 3.8 then
		fail(("Secondary Prose Ceiling: DxComment contrast %.2f exceeds 3.8"):format(ratios.comment))
	end
	if not (ratios.comment < ratios.doc and ratios.doc < ratios.variable) then
		fail("Prose hierarchy must satisfy DxComment < DxDocComment < DxVariable")
	end
	if not (ratios.comment < ratios.punctuation and ratios.punctuation < ratios.variable) then
		fail("Structural hierarchy must satisfy DxComment < DxPunctuation < DxVariable")
	end

	if ratios.type < 7.5 then
		fail(("Structural Separation: DxType contrast %.2f is below 7.5"):format(ratios.type))
	end
	if ratios.type <= ratios.builtin or ratios.type - ratios.builtin < 1.5 then
		fail("Structural Separation: DxType must exceed DxBuiltin by at least 1.5 contrast points")
	end

	local declaration_colors = {
		code.keyword:lower(),
		code.keyword_function:lower(),
		code.callable:lower(),
	}
	if
		declaration_colors[1] == declaration_colors[2]
		or declaration_colors[1] == declaration_colors[3]
		or declaration_colors[2] == declaration_colors[3]
	then
		fail("Function declaration rhythm requires three distinct color families")
	end
	local keyword_r, _, keyword_b = hex_to_rgb(code.keyword)
	local function_r, _, function_b = hex_to_rgb(code.keyword_function)
	local callable_r, _, callable_b = hex_to_rgb(code.callable)
	if keyword_b <= keyword_r or function_b - function_r < 48 or callable_r - callable_b < 48 then
		fail("Function declaration rhythm lost its violet / blue / warm family separation")
	end

	if code.operator:lower() == palette.state.error:lower() or code.operator:lower() == palette.state.warn:lower() then
		fail("DxOperator must not reuse error or warning identity")
	end
	if ratios.operator < 9.0 then
		fail("DxOperator must retain high local micro-syntax energy")
	end
end

---@param context table
function M.verify_negative_controls(context)
	local cases = {
		{
			name = "bad_primary_body",
			mutate = function(palette)
				palette.code_profiles.c4.variable = palette.code_profiles.c4.comment
			end,
		},
		{
			name = "bad_comment",
			mutate = function(palette)
				palette.code_profiles.c4.comment = palette.code_profiles.c4.variable
			end,
		},
		{
			name = "bad_function_keyword",
			mutate = function(palette)
				palette.code_profiles.c4.keyword_function = palette.code_profiles.c4.keyword
			end,
		},
		{
			name = "bad_operator_state",
			mutate = function(palette)
				palette.code_profiles.c4.operator = palette.state.warn
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

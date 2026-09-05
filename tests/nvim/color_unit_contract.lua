--- DX Semantic Color System (DX-COLOR-003)
--- Tier-1 Unit Contract: standalone verification of the domain, composition graph,
--- visual profile, bindings, authority, and sentinel locators.
--- Runnable via:
--- nvim -u NONE -i NONE --headless "+set rtp^=$PWD/home/dot_config/nvim" "+luafile tests/nvim/color_unit_contract.lua" +qa

local function fail(msg)
	error("COLOR_UNIT_CONTRACT_FAILURE: " .. msg, 2)
end

local function assert_eq(actual, expected, msg)
	if actual ~= expected then
		fail(
			(msg or "assertion failed") .. (" (expected %s, got %s)"):format(vim.inspect(expected), vim.inspect(actual))
		)
	end
end

-- Official Catppuccin Mocha palette
local colors = {
	base = "#1e1e2e",
	mantle = "#181825",
	crust = "#11111b",
	surface0 = "#313244",
	surface1 = "#45475a",
	surface2 = "#585b70",
	overlay0 = "#6c7086",
	overlay1 = "#7f849c",
	overlay2 = "#9399b2",
	subtext0 = "#a6adc8",
	subtext1 = "#bac2de",
	text = "#cdd6f4",
	mauve = "#cba6f7",
	lavender = "#b4befe",
	blue = "#89b4fa",
	sapphire = "#74c7ec",
	sky = "#89dceb",
	teal = "#94e2d5",
	green = "#a6e3a1",
	yellow = "#f9e2af",
	peach = "#fab387",
	maroon = "#eba0ac",
	red = "#f38ba8",
	pink = "#f5c2e7",
	flamingo = "#f2cdcd",
	rosewater = "#f5e0dc",
}

-- ==========================================================================
-- 1. Load Theme Modules
-- ==========================================================================

local ok_palette, palette_mod = pcall(require, "theme.palette")
if not ok_palette or type(palette_mod.resolve) ~= "function" then
	fail("theme.palette module could not be loaded or missing resolve()")
end

local ok_domain, domain = pcall(require, "theme.domain")
if not ok_domain or type(domain.roles) ~= "table" then
	fail("theme.domain module could not be loaded or missing role registry")
end

local ok_visual, c3_1 = pcall(require, "theme.visual.c3_1")
if not ok_visual or type(c3_1.roles) ~= "function" then
	fail("theme.visual.c3_1 module could not be loaded or missing roles()")
end

local ok_compose, compose = pcall(require, "theme.compose")
if not ok_compose or type(compose.highlights) ~= "function" then
	fail("theme.compose module could not be loaded or missing highlights()")
end

local ok_theme, theme = pcall(require, "theme")
if not ok_theme or type(theme.highlights) ~= "function" then
	fail("theme module could not be loaded or missing highlights()")
end

local p = palette_mod.resolve(colors)
local roles = c3_1.roles(p)
local full_hl = theme.highlights(colors)
local groups = {}
for group, spec in pairs(full_hl) do
	if not domain.roles[group] then
		groups[group] = spec
	end
end

-- ==========================================================================
-- 2. Validate 23 First-Class Semantic Roles and Domain Metadata
-- ==========================================================================

local required_semantic_roles = {
	"DxKeyword",
	"DxFunctionKeyword",
	"DxCallable",
	"DxType",
	"DxBuiltin",
	"DxLifetime",
	"DxMember",
	"DxParameter",
	"DxVariable",
	"DxMeta",
	"DxNamespace",
	"DxString",
	"DxNumber",
	"DxConstant",
	"DxLabel",
	"DxOperator",
	"DxPunctuation",
	"DxComment",
	"DxDocComment",
	"DxError",
	"DxWarn",
	"DxInfo",
	"DxHint",
}

local role_count = 0
for _, role in ipairs(required_semantic_roles) do
	local registration = domain.roles[role]
	if not registration then
		fail("Missing required domain role registration: " .. role)
	end
	if type(registration.family) ~= "string" or registration.family == "" then
		fail("Domain role is missing family metadata: " .. role)
	end
	if type(registration.description) ~= "string" or registration.description == "" then
		fail("Domain role is missing semantic description: " .. role)
	end
	if not roles[role] then
		fail("C3.1 visual profile is missing required semantic role: " .. role)
	end
	role_count = role_count + 1
end

for role in pairs(domain.roles) do
	if not vim.tbl_contains(required_semantic_roles, role) then
		fail("Unexpected extra semantic role outside 23-role closure: " .. role)
	end
end
for role in pairs(roles) do
	if not domain.roles[role] then
		fail("C3.1 visual profile defines role outside the domain closure: " .. role)
	end
end
assert_eq(role_count, 23, "Expected exactly 23 semantic roles in DX-COLOR-003")

-- ==========================================================================
-- 3. Source Contrast Budget Gate (Calculated Mathematically vs Mocha Base)
-- ==========================================================================

local function hex_to_rgb(hex)
	local clean = hex:gsub("^#", "")
	return tonumber(clean:sub(1, 2), 16), tonumber(clean:sub(3, 4), 16), tonumber(clean:sub(5, 6), 16)
end

local function luminance(r, g, b)
	local function channel(c)
		c = c / 255
		if c <= 0.04045 then
			return c / 12.92
		else
			return ((c + 0.055) / 1.055) ^ 2.4
		end
	end
	return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
end

local function contrast_ratio(hex1, hex2)
	local l1 = luminance(hex_to_rgb(hex1))
	local l2 = luminance(hex_to_rgb(hex2))
	if l1 < l2 then
		l1, l2 = l2, l1
	end
	return (l1 + 0.05) / (l2 + 0.05)
end

local base_hex = colors.base
for name, hex in pairs(p.code) do
	local cr = contrast_ratio(hex, base_hex)
	if cr < 4.5 or cr > 8.8 then
		fail(("Contrast budget violation for code.%s (%s): ratio %.2f outside [4.5, 8.8]"):format(name, hex, cr))
	end
	if name ~= "punctuation" and name ~= "comment" then
		if cr < 5.0 then
			fail(("Primary semantic role code.%s (%s) ratio %.2f is below minimum 5.0:1"):format(name, hex, cr))
		end
	else
		if cr < 4.5 then
			fail(("De-emphasis role code.%s (%s) ratio %.2f is below minimum 4.5:1"):format(name, hex, cr))
		end
	end
end

-- ==========================================================================
-- 4. Source-State Separation Gate & Yellow / Red Scarcity
-- ==========================================================================

local function verify_source_state_separation(palette)
	local state_values = {
		palette.state.error:lower(),
		palette.state.warn:lower(),
		palette.state.info:lower(),
		palette.state.hint:lower(),
		palette.state.success:lower(),
	}
	for name, hex in pairs(palette.code) do
		if vim.tbl_contains(state_values, hex:lower()) then
			error(("Source-State separation violation: code.%s uses state accent %s"):format(name, hex), 2)
		end
	end
end
verify_source_state_separation(p)

local function verify_yellow_scarcity(r, palette)
	local warn_color = palette.state.warn:lower()
	for name, hex in pairs(palette.code) do
		if hex:lower() == warn_color then
			error(("Yellow Scarcity violation: code.%s uses bright state warn yellow"):format(name), 2)
		end
	end
	for role, spec in pairs(r) do
		if role ~= "DxWarn" and spec.fg and spec.fg:lower() == warn_color then
			error(("Yellow Scarcity violation: %s uses bright yellow but is not DxWarn"):format(role), 2)
		end
	end
end
verify_yellow_scarcity(roles, p)

local function verify_red_scarcity(r, palette)
	local err_color = palette.state.error:lower()
	for role, spec in pairs(r) do
		if role ~= "DxError" and spec.fg and spec.fg:lower() == err_color then
			error(("Red Scarcity violation: %s uses red but is not DxError"):format(role), 2)
		end
	end
end
verify_red_scarcity(roles, p)

-- ==========================================================================
-- 4b. CVD-Aware Invariants & Visual Hierarchy Contract (Candidate C3)
-- ==========================================================================

-- P3: No normal source role uses green-dominant hue
for name, hex in pairs(p.code) do
	local r_val, g_val, b_val = hex_to_rgb(hex)
	if g_val > r_val + 20 and g_val > b_val + 20 then
		fail(("Source palette violation: code.%s (%s) uses a green-dominant hue"):format(name, hex))
	end
end

-- P4: state.success != green; state.success == sky/cyan family
assert(p.state.success:lower() ~= colors.green:lower(), "state.success must not use green for CVD safety")
assert_eq(p.state.success:lower(), colors.sky:lower(), "state.success must use Catppuccin Sky")

-- P5: Visual Hierarchy: callable > type > builtin; type - builtin has significant contrast-ratio gap
local cr_callable = contrast_ratio(p.code.callable, base_hex)
local cr_type = contrast_ratio(p.code.type, base_hex)
local cr_builtin = contrast_ratio(p.code.builtin, base_hex)
assert(
	cr_callable > cr_type,
	("Visual hierarchy violation: callable (%.2f) must exceed type (%.2f)"):format(cr_callable, cr_type)
)
assert(
	cr_type > cr_builtin,
	("Visual hierarchy violation: type (%.2f) must exceed builtin (%.2f)"):format(cr_type, cr_builtin)
)
local type_builtin_cr_gap = cr_type - cr_builtin
assert(
	type_builtin_cr_gap >= 1.0,
	("Visual hierarchy violation: type/builtin contrast-ratio gap %.2f must be >= 1.0"):format(type_builtin_cr_gap)
)

-- P6: Scaffolding Ceiling: operator / punctuation / comment must not exceed semantic body
local max_scaffolding_cr = math.max(
	contrast_ratio(p.code.operator, base_hex),
	contrast_ratio(p.code.punctuation, base_hex),
	contrast_ratio(p.code.comment, base_hex)
)
local min_semantic_body_cr = math.min(
	contrast_ratio(p.code.variable, base_hex),
	contrast_ratio(p.code.member, base_hex),
	contrast_ratio(p.code.parameter, base_hex),
	contrast_ratio(p.code.builtin, base_hex)
)
assert(
	max_scaffolding_cr <= min_semantic_body_cr,
	("Scaffolding ceiling violation: max scaffolding (%.2f) exceeds min semantic body (%.2f)"):format(
		max_scaffolding_cr,
		min_semantic_body_cr
	)
)

-- P7: Diagnostic Non-Color Redundancy Contract
assert_eq(
	groups["DiagnosticUnderlineError"].undercurl,
	true,
	"DiagnosticUnderlineError must provide non-color undercurl cue"
)
assert_eq(
	groups["DiagnosticUnderlineWarn"].undercurl,
	true,
	"DiagnosticUnderlineWarn must provide non-color undercurl cue"
)

-- ==========================================================================
-- 5. In-Memory Negative Control (Proves Gates Fail-Closed on Bad Palettes)
-- ==========================================================================

-- Negative Control 1: Yellow Scarcity Catch
local bad_yellow = vim.deepcopy(p)
bad_yellow.code.callable = bad_yellow.state.warn
local bad_yellow_roles = c3_1.roles(bad_yellow)
local ok_y, _ = pcall(verify_yellow_scarcity, bad_yellow_roles, bad_yellow)
assert(not ok_y, "Negative control failure: verify_yellow_scarcity must fail when code.callable uses yellow")

-- Negative Control 2: Source-State Separation Catch
local bad_state = vim.deepcopy(p)
bad_state.code.type = bad_state.state.error
local ok_s, _ = pcall(verify_source_state_separation, bad_state)
assert(not ok_s, "Negative control failure: verify_source_state_separation must fail when code.type uses state.error")

-- Negative Control 3: Red Scarcity Catch
local bad_red = vim.deepcopy(p)
bad_red.code.keyword = bad_red.state.error
local bad_red_roles = c3_1.roles(bad_red)
local ok_r, _ = pcall(verify_red_scarcity, bad_red_roles, bad_red)
assert(not ok_r, "Negative control failure: verify_red_scarcity must fail when DxKeyword uses state.error")

-- ==========================================================================
-- 6. No Raw Source Hex Outside Palette Gate & Namespace Disjointness Gate
-- ==========================================================================

local repo_root = vim.fs.root(0, ".git") or vim.fn.getcwd()

local theme_dir = repo_root .. "/home/dot_config/nvim/lua/theme"
for name, type_str in vim.fs.dir(theme_dir, { depth = math.huge }) do
	if type_str == "file" and name:match("%.lua$") and name ~= "palette.lua" then
		local abspath = theme_dir .. "/" .. name
		local f = io.open(abspath, "r")
		if not f then
			fail("Could not read file for raw hex check: " .. abspath)
		end
		local content = f:read("*a")
		f:close()
		local found = content:match("#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]")
		if found then
			fail(("No Raw Hex Outside Palette violation in %s: found literal %s"):format(name, found))
		end
	end
end

-- Namespace Disjointness
for k, _ in pairs(roles) do
	if not k:match("^Dx") then
		fail(("Namespace Disjointness violation: role key %s must start with 'Dx'"):format(k))
	end
end
for k, _ in pairs(groups) do
	if k:match("^Dx") then
		fail(("Namespace Disjointness violation: mappings group key %s must NOT start with 'Dx'"):format(k))
	end
end

-- ==========================================================================
-- 7. Validate Tree-sitter, LSP Base, Typemod Governance, and Extra Groups
-- ==========================================================================

local required_ts = {
	["@keyword"] = "DxKeyword",
	["@keyword.function"] = "DxFunctionKeyword",
	["@keyword.return"] = "DxKeyword",
	["@function"] = "DxCallable",
	["@function.call"] = "DxCallable",
	["@function.method"] = "DxCallable",
	["@type"] = "DxType",
	["@type.builtin"] = "DxBuiltin",
	["@type.lifetime"] = "DxLifetime",
	["@type.lifetime.rust"] = "DxLifetime",
	["@variable"] = "DxVariable",
	["@variable.parameter"] = "DxParameter",
	["@variable.member"] = "DxMember",
	["@property"] = "DxMember",
	["@module"] = "DxNamespace",
	["@attribute"] = "DxMeta",
	["@attribute.builtin"] = "DxMeta",
	["@function.macro"] = "DxMeta",
	["@constant.macro"] = "DxMeta",
	["@label"] = "DxLabel",
	["@string"] = "DxString",
	["@string.regexp"] = "DxString",
	["@string.escape"] = "DxString",
	["@number"] = "DxNumber",
	["@constant"] = "DxConstant",
	["@operator"] = "DxOperator",
	["@character.special"] = "DxPunctuation",
	["@comment"] = "DxComment",
}

for capture, expected_role in pairs(required_ts) do
	if not groups[capture] or groups[capture].link ~= expected_role then
		fail(
			("Tree-sitter mapping mismatch for %s: expected link %s, got %s"):format(
				capture,
				expected_role,
				vim.inspect(groups[capture])
			)
		)
	end
end

local required_lsp = {
	["@lsp.type.keyword"] = "DxKeyword",
	["@lsp.type.modifier"] = "DxKeyword",
	["@lsp.type.function"] = "DxCallable",
	["@lsp.type.method"] = "DxCallable",
	["@lsp.type.class"] = "DxType",
	["@lsp.type.struct"] = "DxType",
	["@lsp.type.enum"] = "DxType",
	["@lsp.type.interface"] = "DxType",
	["@lsp.type.type"] = "DxType",
	["@lsp.type.typeParameter"] = "DxType",
	["@lsp.type.property"] = "DxMember",
	["@lsp.type.parameter"] = "DxParameter",
	["@lsp.type.variable"] = "DxVariable",
	["@lsp.type.namespace"] = "DxNamespace",
	["@lsp.type.macro"] = "DxMeta",
	["@lsp.type.decorator"] = "DxMeta",
	["@lsp.type.enumMember"] = "DxConstant",
	["@lsp.type.string"] = "DxString",
	["@lsp.type.regexp"] = "DxString",
	["@lsp.type.number"] = "DxNumber",
	["@lsp.type.operator"] = "DxOperator",
	["@lsp.type.comment"] = "DxComment",
	["@lsp.type.event"] = "DxMember",
	["@lsp.type.label"] = "DxLabel",
	["@lsp.type.lifetime"] = "DxLifetime",
	["@lsp.type.builtinType"] = "DxBuiltin",
	["@lsp.type.typeAlias"] = "DxType",
	["@lsp.type.union"] = "DxType",
	["@lsp.type.selfTypeKeyword"] = "DxType",
	["@lsp.type.concept"] = "DxType",
	["@lsp.type.builtin"] = "DxMeta",
	["@lsp.type.keywordLiteral"] = "DxConstant",
	["@lsp.type.errorTag"] = "DxConstant",
	["@lsp.type.escapeSequence"] = "DxString",
}

for token, expected_role in pairs(required_lsp) do
	if not groups[token] or groups[token].link ~= expected_role then
		fail(
			("LSP mapping mismatch for %s: expected link %s, got %s"):format(
				token,
				expected_role,
				vim.inspect(groups[token])
			)
		)
	end
end

-- Typemod Precedence Governance (Neutralization of overriding modifiers)
local required_typemods = {
	["@lsp.typemod.variable.readonly"] = "DxVariable",
	["@lsp.typemod.variable.defaultLibrary"] = "DxVariable",
	["@lsp.typemod.variable.static"] = "DxVariable",
	["@lsp.typemod.property.readonly"] = "DxMember",
	["@lsp.typemod.function.defaultLibrary"] = "DxCallable",
	["@lsp.typemod.function.async"] = "DxCallable",
	["@lsp.typemod.method.defaultLibrary"] = "DxCallable",
	["@lsp.typemod.method.async"] = "DxCallable",
}

for token, expected_role in pairs(required_typemods) do
	if not groups[token] or groups[token].link ~= expected_role then
		fail(
			("Typemod governance mapping mismatch for %s: expected link %s, got %s"):format(
				token,
				expected_role,
				vim.inspect(groups[token])
			)
		)
	end
end

-- DX-COLOR Semantic Authority Model Contract
assert_eq(groups["LspForegroundPassthrough"].fg, nil, "LspForegroundPassthrough must have no foreground")
assert_eq(groups["LspForegroundPassthrough"].link, nil, "LspForegroundPassthrough must have no link")
assert_eq(
	groups["@lsp.type.type.c"].link,
	"LspForegroundPassthrough",
	"@lsp.type.type.c must link to LspForegroundPassthrough"
)
assert_eq(
	groups["@lsp.type.type.cpp"].link,
	"LspForegroundPassthrough",
	"@lsp.type.type.cpp must link to LspForegroundPassthrough"
)
assert_eq(
	groups["@lsp.type.type.zig"].link,
	"LspForegroundPassthrough",
	"@lsp.type.type.zig must link to LspForegroundPassthrough"
)
assert_eq(
	groups["@lsp.type.keyword.zig"].link,
	"LspForegroundPassthrough",
	"@lsp.type.keyword.zig must link to LspForegroundPassthrough"
)
assert_eq(
	groups["@lsp.typemod.namespace.attribute.rust"].link,
	"DxMeta",
	"@lsp.typemod.namespace.attribute.rust must link to DxMeta"
)
assert_eq(groups["@lsp.mod.attribute"], nil, "@lsp.mod.attribute must not be globally defined")
assert_eq(
	groups["@lsp.typemod.namespace.attribute"],
	nil,
	"@lsp.typemod.namespace.attribute must not be globally defined"
)

-- Deprecated Style-Only Composition Contract
assert_eq(groups["@lsp.mod.deprecated"].strikethrough, true, "@lsp.mod.deprecated must have strikethrough enabled")
assert_eq(groups["@lsp.mod.deprecated"].fg, nil, "@lsp.mod.deprecated must not force a foreground color")
assert_eq(groups["@lsp.mod.deprecated"].link, nil, "@lsp.mod.deprecated must not link to another highlight")

local governed_lsp_types = {
	"function",
	"method",
	"class",
	"struct",
	"enum",
	"interface",
	"type",
	"typeParameter",
	"property",
	"parameter",
	"variable",
	"namespace",
	"macro",
	"decorator",
	"enumMember",
	"string",
	"number",
}
for _, token_type in ipairs(governed_lsp_types) do
	local key = "@lsp.typemod." .. token_type .. ".deprecated"
	if not groups[key] then
		fail("Missing governed deprecated typemod mapping: " .. key)
	end
	if not groups[key].strikethrough then
		fail(key .. " must have strikethrough enabled")
	end
	if groups[key].fg ~= nil then
		fail(key .. " must not override foreground color")
	end
	if groups[key].link ~= nil then
		fail(key .. " must not define a link")
	end
end

-- Completion, Editor UI, Diagnostics, Git, DAP, Neotest, Markdown Groups
local required_extras = {
	"BlinkCmpKindFunction",
	"BlinkCmpKindClass",
	"BlinkCmpKindField",
	"BlinkCmpKindVariable",
	"CursorLine",
	"CursorLineNr",
	"CurSearch",
	"NormalFloat",
	"FloatBorder",
	"SnacksIndent",
	"SnacksIndentScope",
	"DiagnosticError",
	"DiagnosticUnderlineError",
	"DiagnosticWarn",
	"DiagnosticUnderlineWarn",
	"GitSignsAdd",
	"GitSignsChange",
	"GitSignsDelete",
	"diffAdded",
	"diffChanged",
	"diffRemoved",
	"NeotestPassed",
	"NeotestFailed",
	"NeotestRunning",
	"DapBreakpoint",
	"DapStopped",
	"RenderMarkdownCodeInline",
	"RenderMarkdownDash",
	"RenderMarkdownQuote",
}

for _, extra in ipairs(required_extras) do
	if not groups[extra] then
		fail("Missing required extra highlight group mapping: " .. extra)
	end
end

-- Theme Highlights Final Assembly Completeness
for role, _ in pairs(roles) do
	if not full_hl[role] then
		fail("Combined theme.highlights() is missing semantic role: " .. role)
	end
end
for group, _ in pairs(groups) do
	if not full_hl[group] then
		fail("Combined theme.highlights() is missing mapping group: " .. group)
	end
end

-- ==========================================================================
-- 8. M1 Architecture Topology and C3.1 Graph Equivalence
-- ==========================================================================

local expected_layers = {
	"authority",
	"visual",
	"treesitter",
	"lsp",
	"zls",
	"clangd",
	"rust_analyzer",
	"pyright",
	"ui",
	"plugins",
}

assert_eq(#compose.layers, #expected_layers, "Unexpected number of composition layers")
for index, expected_name in ipairs(expected_layers) do
	assert_eq(compose.layers[index].name, expected_name, ("Composition layer %d changed"):format(index))
end

local generic_lsp_groups = require("theme.bindings.lsp").groups()
local rust_analyzer_groups = require("theme.adapters.rust_analyzer").groups()
assert_eq(generic_lsp_groups["@lsp.type.label"].link, "DxLabel", "Audited cross-provider label ownership changed")
assert_eq(generic_lsp_groups["@lsp.type.lifetime"], nil, "rust-analyzer lifetime leaked into generic LSP bindings")
assert_eq(
	generic_lsp_groups["@lsp.type.builtinType"],
	nil,
	"rust-analyzer builtinType leaked into generic LSP bindings"
)
assert_eq(rust_analyzer_groups["@lsp.type.lifetime"].link, "DxLifetime", "rust-analyzer must own lifetime")
assert_eq(rust_analyzer_groups["@lsp.type.builtinType"].link, "DxBuiltin", "rust-analyzer must own builtinType")

local normalized_fields = {
	"link",
	"fg",
	"bg",
	"sp",
	"bold",
	"italic",
	"underline",
	"undercurl",
	"strikethrough",
	"nocombine",
}

local normalized_field_set = {}
for _, field in ipairs(normalized_fields) do
	normalized_field_set[field] = true
end

local M1_BASE_SHA = "19f0570ee33025832ff1d1d49269d303677d9c0f"
local M1_BASE_GRAPH_COUNT = 221
local M1_BASE_GRAPH_SHA256 = "05ff81df9019ace7bee14a494db1a9e39c7d18426f3b78bae1ef3012a068a276"

local function assert_governed_graph_fields(graph)
	for group, spec in pairs(graph) do
		for field in pairs(spec) do
			if not normalized_field_set[field] then
				fail(("C3.1 graph equivalence does not govern field %s on %s"):format(field, group))
			end
		end
	end
end

local function normalized_graph_digest(graph)
	assert_governed_graph_fields(graph)

	local names = {}
	for name in pairs(graph) do
		table.insert(names, name)
	end
	table.sort(names)

	local normalized = {}
	for _, name in ipairs(names) do
		local fields = { name }
		for _, field in ipairs(normalized_fields) do
			local value = graph[name][field]
			if type(value) == "string" and value:match("^#") then
				value = value:lower()
			end
			table.insert(fields, field .. "=" .. (value == nil and "<nil>" or tostring(value)))
		end
		table.insert(normalized, table.concat(fields, "|"))
	end

	return #names, vim.fn.sha256(table.concat(normalized, "\n"))
end

local graph_count, graph_digest = normalized_graph_digest(full_hl)
assert_eq(graph_count, M1_BASE_GRAPH_COUNT, ("C3.1 highlight group count changed from %s"):format(M1_BASE_SHA))
assert_eq(graph_digest, M1_BASE_GRAPH_SHA256, ("C3.1 normalized highlight graph changed from %s"):format(M1_BASE_SHA))
print(("C3.1 graph equivalence verified: %d groups, sha256=%s"):format(graph_count, graph_digest))

local bad_graph_field = vim.deepcopy(full_hl)
bad_graph_field.DxVariable.reverse = true
local ok_unknown_field = pcall(assert_governed_graph_fields, bad_graph_field)
assert(not ok_unknown_field, "Negative control failure: unknown highlight attributes must fail closed")

-- ==========================================================================
-- 9. Shared Manifest Symbolic Sentinel Locator Test across 5 Languages
-- ==========================================================================

local ok_manifest, manifest = pcall(dofile, repo_root .. "/tests/nvim/color_manifest.lua")
if not ok_manifest or not manifest.languages then
	fail("Failed to load tests/nvim/color_manifest.lua")
end

local function is_comment_line(trimmed, lang)
	if
		trimmed:sub(1, 2) == "//"
		or trimmed:sub(1, 3) == "///"
		or trimmed:sub(1, 2) == "/*"
		or trimmed:sub(1, 1) == "*"
	then
		return true
	end
	if lang == "python" and trimmed:sub(1, 1) == "#" then
		return true
	end
	return false
end

local function locate_symbolic_sentinel(bufnr, tag, token, lang)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for i, line in ipairs(lines) do
		if line:find(tag, 1, true) then
			for j = i + 1, math.min(#lines, i + 10) do
				local target_line = lines[j]
				local trimmed = target_line:match("^%s*(.-)%s*$") or ""
				if not is_comment_line(trimmed, lang) then
					local pattern = "%f[%w_]" .. vim.pesc(token) .. "%f[^%w_]"
					local s_start = target_line:find(pattern)
					if s_start then
						assert(j > i, "Sentinel token must not be found on the marker comment line")
						return j - 1, s_start - 1, target_line, i - 1
					end
				end
			end
		end
	end
	fail(("Symbolic sentinel not found: tag=%s, token=%s, lang=%s"):format(tag, token, tostring(lang)))
end

local verified_sentinels = 0
local expected_total = 0

for lang_name, lang_spec in pairs(manifest.languages) do
	local filepath = repo_root .. "/" .. lang_spec.path
	if vim.fn.filereadable(filepath) ~= 1 then
		fail(("Fixture unreadable or missing for %s: %s"):format(lang_name, filepath))
	end
	local buf = vim.fn.bufadd(filepath)
	vim.fn.bufload(buf)

	for _, s in ipairs(lang_spec.sentinels) do
		expected_total = expected_total + 1
		local r, c, line_text, comment_r = locate_symbolic_sentinel(buf, s.tag, s.token, lang_name)
		if r <= comment_r then
			fail(("Locator regression: %s matched comment row %d"):format(s.tag, comment_r))
		end
		local trimmed = line_text:match("^%s*(.-)%s*$") or ""
		if is_comment_line(trimmed, lang_name) then
			fail(("Locator regression: %s matched comment line: %s"):format(s.tag, line_text))
		end
		verified_sentinels = verified_sentinels + 1
	end
	vim.api.nvim_buf_delete(buf, { force = true })
end

assert(
	verified_sentinels == expected_total and verified_sentinels > 0,
	("Sentinel count mismatch: verified %d, expected %d"):format(verified_sentinels, expected_total)
)
print(
	("Verified all %d/%d symbolic sentinels from color_manifest.lua with 100%% precision."):format(
		verified_sentinels,
		expected_total
	)
)

print("Tier-1 Color Unit Contract passed cleanly.")

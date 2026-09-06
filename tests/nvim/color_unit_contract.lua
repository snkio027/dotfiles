--- DX Semantic Color System (DX-COLOR-003)
--- Tier-1 Unit Contract: standalone verification of the domain, composition graph,
--- production visual projection, bindings, authority, and sentinel locators.
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

local ok_visual, visual = pcall(require, "theme.visual.c4")
if not ok_visual or type(visual.roles) ~= "function" then
	fail("theme.visual.c4 module could not be loaded or missing roles()")
end

local ok_compose, compose = pcall(require, "theme.compose")
if not ok_compose or type(compose.highlights) ~= "function" then
	fail("theme.compose module could not be loaded or missing highlights()")
end

local ok_theme, theme = pcall(require, "theme")
if not ok_theme or type(theme.highlights) ~= "function" then
	fail("theme module could not be loaded or missing highlights()")
end
if theme.default_profile ~= nil or theme.resolve_profile ~= nil or theme.active_profile ~= nil then
	fail("M5 retirement left a runtime profile-selection entrypoint")
end

local p = palette_mod.resolve(colors)
local roles = visual.roles(p)
local full_hl = theme.highlights(colors)
local composed_hl = compose.highlights(p, visual)
assert(vim.deep_equal(full_hl, composed_hl), "theme.highlights() must resolve directly to C4.4")
print("M5 single-production-visual contract passed: theme.highlights() -> C4.4.")

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
		fail("C4.4 production visual is missing required semantic role: " .. role)
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
		fail("C4.4 production visual defines role outside the domain closure: " .. role)
	end
end
assert_eq(role_count, 23, "Expected exactly 23 semantic roles in DX-COLOR-003")

-- ==========================================================================
-- 3. C4.4 Production Visual Contract and Negative Controls
-- ==========================================================================

local repo_root = vim.fs.root(0, ".git") or vim.fn.getcwd()
local c4_contract = dofile(repo_root .. "/tests/nvim/visual_contracts/c4.lua")
c4_contract.verify({
	palette = p,
	roles = roles,
	graph = full_hl,
	domain = domain,
	host_colors = colors,
})
c4_contract.verify_negative_controls({
	palette = p,
	visual = visual,
	graph = full_hl,
	domain = domain,
	host_colors = colors,
})
print("C4.4 High-Chroma Night visual contract and negative controls passed.")

-- ==========================================================================
-- 4. No Raw Source Hex Outside Palette Gate & Namespace Disjointness Gate
-- ==========================================================================

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

local retired_visual = repo_root .. "/home/dot_config/nvim/lua/theme/visual/c3_1.lua"
if vim.uv.fs_stat(retired_visual) ~= nil then
	fail("M5 retirement left the C3.1 runtime module in place")
end
for _, relative_path in ipairs({ "init.lua", "palette.lua", "visual/c4.lua" }) do
	local path = theme_dir .. "/" .. relative_path
	local file = assert(io.open(path, "r"))
	local content = file:read("*a")
	file:close()
	for _, retired_term in ipairs({ "c3_1", "code_profiles", "dx_color_profile", "resolve_profile", "active_profile" }) do
		if content:find(retired_term, 1, true) then
			fail(("M5 retirement left %s in live runtime file %s"):format(retired_term, relative_path))
		end
	end
end
print("M5 executable compatibility surface is absent: C3.1 module, selector, and profile palette removed.")

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
-- 5. Validate Tree-sitter, LSP Base, Typemod Governance, and Extra Groups
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
-- 6. M5 Production Graph and Historical Provenance
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
local clangd_groups = require("theme.adapters.clangd").groups()
local rust_analyzer_groups = require("theme.adapters.rust_analyzer").groups()
local authority = require("theme.authority")
assert_eq(generic_lsp_groups["@lsp.type.label"].link, "DxLabel", "Audited cross-provider label ownership changed")
assert_eq(generic_lsp_groups["@lsp.type.lifetime"], nil, "rust-analyzer lifetime leaked into generic LSP bindings")
assert_eq(
	generic_lsp_groups["@lsp.type.builtinType"],
	nil,
	"rust-analyzer builtinType leaked into generic LSP bindings"
)
assert_eq(rust_analyzer_groups["@lsp.type.lifetime"].link, "DxLifetime", "rust-analyzer must own lifetime")
assert_eq(rust_analyzer_groups["@lsp.type.builtinType"].link, "DxBuiltin", "rust-analyzer must own builtinType")
assert_eq(
	generic_lsp_groups["@lsp.typemod.variable.static"].link,
	"DxVariable",
	"M2B-B must not redefine provider-independent static semantics"
)
assert_eq(
	generic_lsp_groups["@lsp.typemod.variable.readonly"].link,
	"DxVariable",
	"M2B-B must not redefine provider-independent readonly semantics"
)
assert_eq(
	generic_lsp_groups["@lsp.typemod.variable.defaultLibrary"].link,
	"DxVariable",
	"M2B-B must not redefine provider-independent defaultLibrary semantics"
)
assert_eq(
	clangd_groups["@lsp.typemod.variable.static"],
	nil,
	"clangd adapter must not own the generic variable.static group"
)
assert_eq(
	clangd_groups["@lsp.typemod.variable.readonly"],
	nil,
	"clangd adapter must not own the generic variable.readonly group"
)
assert_eq(
	clangd_groups["@lsp.typemod.variable.defaultLibrary"],
	nil,
	"clangd adapter must not own the generic variable.defaultLibrary group"
)
assert_eq(
	clangd_groups["@lsp.typemod.variable.classScope.cpp"].link,
	"DxMember",
	"clangd/C++ classScope ownership must resolve to DxMember"
)
assert_eq(
	clangd_groups["@lsp.typemod.variable.static.cpp"].link,
	authority.foreground_passthrough,
	"clangd/C++ static storage must suppress foreground authority"
)
assert_eq(
	clangd_groups["@lsp.typemod.variable.readonly.cpp"].link,
	authority.foreground_passthrough,
	"clangd/C++ readonly mutability must suppress foreground authority"
)
assert_eq(
	clangd_groups["@lsp.typemod.variable.defaultLibrary.cpp"].link,
	authority.foreground_passthrough,
	"clangd/C++ defaultLibrary provenance must suppress foreground authority"
)

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
local M2B_BASE_SHA = "6d44ffe3108311396ceaedef527a24c6d3b1cebd"
local M2B_GRAPH_COUNT = 225
local M2B_GRAPH_SHA256 = "a2db03bf6a138c0784d74277adf6f7ee706a5398336305385ced7d3725c0dedf"
local M3B_BASE_SHA = "6348cc2fd99457f2ecf0cb574c46a07db45d6e75"
local C4_0_GRAPH_COUNT = 225
local C4_0_GRAPH_SHA256 = "311ac3566f816d0fc03ad4ec92c74477d4ac82bf8cc2ab5cd82f95a12688c043"
local M4_C4_3_HEAD_SHA = "86d10b4fa938d377840d2b46c49b6da195ff9080"
local C4_3_GRAPH_COUNT = 226
local C4_3_GRAPH_SHA256 = "12d9299d27f50cc96bc056662ce13eed1bb1e46d7fc154f7bd5655216c7a8cc8"
local M4_C4_4_BASE_SHA = M4_C4_3_HEAD_SHA
local C4_4_GRAPH_COUNT = 226
local C4_4_GRAPH_SHA256 = "1ac13a349234d5926a250a82c6beb1135fe4483bfe1208f0e24245d4f0022fc8"
local M5_BASE_SHA = "65b61ee03bef0bc0bb8bee945d1bbc32a6a829b5"
local M5_PRODUCTION_GRAPH_COUNT = 226
local M5_PRODUCTION_GRAPH_SHA256 = "51cfaae3c02ec25551f1a8afd27427d3919d6b53c3b05f5ae26ff6c125aa6666"
local C4_4_AUTHORIZED_FOREGROUND_DELTA = {
	DxVariable = "#C9D4F2",
	DxKeyword = "#C08CFF",
	DxFunctionKeyword = "#9BCBFF",
	DxType = "#79D2F2",
	DxBuiltin = "#82D887",
	DxParameter = "#D7B3E8",
	DxMeta = "#D98FD6",
	DxNamespace = "#5C96FF",
	DxLabel = "#9AA3BA",
	DxComment = "#7D8496",
	DxDocComment = "#969EB4",
}
local C4_0_FOREGROUND_BASELINE = {
	DxKeyword = "#B298CE",
	DxFunctionKeyword = "#86B7F7",
	DxCallable = "#D8A972",
	DxType = "#74C7EC",
	DxBuiltin = "#7393B7",
	DxLifetime = "#7DA6C8",
	DxMember = "#B5BDFC",
	DxParameter = "#A6ADC8",
	DxVariable = "#CDD6F4",
	DxMeta = "#C395B9",
	DxNamespace = "#79A7DC",
	DxString = "#C7B8A6",
	DxNumber = "#E09A7B",
	DxConstant = "#D6A0BA",
	DxLabel = "#8D91A4",
	DxOperator = "#8BDCEB",
	DxPunctuation = "#9399B2",
	DxComment = "#6C7086",
	DxDocComment = "#9399B2",
}
local C3_1_FOREGROUND_BASELINE = {
	DxKeyword = "#B298CE",
	DxFunctionKeyword = "#82AEDB",
	DxCallable = "#D8A972",
	DxType = "#78B6CC",
	DxBuiltin = "#7393B7",
	DxLifetime = "#7DA6C8",
	DxMember = "#AA91DF",
	DxParameter = "#AA94BE",
	DxVariable = "#989FCC",
	DxMeta = "#C395B9",
	DxNamespace = "#75A0D8",
	DxString = "#ADA497",
	DxNumber = "#C18975",
	DxConstant = "#B78EAF",
	DxLabel = "#8D91A4",
	DxOperator = "#898FA6",
	DxPunctuation = "#858A9F",
	DxComment = "#81869E",
	DxDocComment = "#9298AD",
}
local M5_AUTHORIZED_CONSUMER_DELTA = {
	CursorLineNr = "#AA91DF",
	DapBreakpointCondition = "#C18975",
	NeotestFocused = "#AA91DF",
	NeotestMarked = "#C18975",
	RenderMarkdownCodeInline = "#C18975",
	RenderMarkdownH1 = "#B298CE",
	RenderMarkdownH2 = "#AA91DF",
	RenderMarkdownH3 = "#78B6CC",
	RenderMarkdownHint = "#B298CE",
	RenderMarkdownQuote = "#B298CE",
	SnacksIndentScope = "#AA91DF",
}
local C4_PROFILE_AUTHORIZED_GROUP_DELTA = { "Normal" }
local M2B_AUTHORIZED_GRAPH_DELTA = {
	"@lsp.typemod.variable.classScope.cpp",
	"@lsp.typemod.variable.static.cpp",
	"@lsp.typemod.variable.readonly.cpp",
	"@lsp.typemod.variable.defaultLibrary.cpp",
}

local function assert_governed_graph_fields(graph)
	for group, spec in pairs(graph) do
		for field in pairs(spec) do
			if not normalized_field_set[field] then
				fail(("DX graph governance does not recognize field %s on %s"):format(field, group))
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

local production_count, production_digest = normalized_graph_digest(full_hl)
assert_eq(
	production_count,
	M5_PRODUCTION_GRAPH_COUNT,
	("M5 production highlight-group count changed from %s"):format(M5_BASE_SHA)
)
assert_eq(
	production_digest,
	M5_PRODUCTION_GRAPH_SHA256,
	("M5 production resolved graph changed from %s"):format(M5_BASE_SHA)
)
print(("M5 production C4.4 graph frozen: %d groups, sha256=%s"):format(production_count, production_digest))

assert_eq(full_hl.Normal.bg, p.ui.normal_bg, "M5 production Normal background does not use its owned canvas token")
assert_eq(vim.tbl_count(full_hl.Normal), 1, "M5 production Normal override must own only the canvas background")

local accepted_c4_4_graph = vim.deepcopy(full_hl)
local consumer_delta_count = 0
for group, old_foreground in pairs(M5_AUTHORIZED_CONSUMER_DELTA) do
	local spec = accepted_c4_4_graph[group]
	if spec == nil or spec.fg == nil then
		fail("M5 authorized C4.4 consumer is missing: " .. group)
	end
	if spec.fg:lower() == old_foreground:lower() then
		fail("M5 palette promotion did not update governed consumer: " .. group)
	end
	spec.fg = old_foreground
	consumer_delta_count = consumer_delta_count + 1
end
assert_eq(consumer_delta_count, 11, "M5 must change exactly eleven palette.code consumers")
local accepted_c4_4_count, accepted_c4_4_digest = normalized_graph_digest(accepted_c4_4_graph)
assert_eq(accepted_c4_4_count, C4_4_GRAPH_COUNT, "M5 consumer rollback changed accepted C4.4 count")
assert_eq(
	accepted_c4_4_digest,
	C4_4_GRAPH_SHA256,
	("M5 consumer rollback did not reconstruct accepted C4.4 from %s"):format(M4_C4_4_BASE_SHA)
)
print(
	("Accepted C4.4 candidate reconstructed after M5 consumer rollback: %d groups, sha256=%s"):format(
		accepted_c4_4_count,
		accepted_c4_4_digest
	)
)

local historical_c4_3_graph = vim.deepcopy(accepted_c4_4_graph)
for role, old_foreground in pairs(C4_4_AUTHORIZED_FOREGROUND_DELTA) do
	local spec = historical_c4_3_graph[role]
	if spec == nil or spec.fg == nil then
		fail("C4.4 authorized foreground role is missing: " .. role)
	end
	if spec.fg:lower() == old_foreground:lower() then
		fail("C4.4 authorized foreground did not change: " .. role)
	end
	spec.fg = old_foreground
end
historical_c4_3_graph.Normal.bg = "#181A1F"
local c4_3_count, c4_3_digest = normalized_graph_digest(historical_c4_3_graph)
assert_eq(c4_3_count, C4_3_GRAPH_COUNT, ("C4.4 reconstruction changed C4.3 count from %s"):format(M4_C4_3_HEAD_SHA))
assert_eq(
	c4_3_digest,
	C4_3_GRAPH_SHA256,
	("C4.4 authorized visual rollback did not reconstruct C4.3 from %s"):format(M4_C4_3_HEAD_SHA)
)
print(("C4.3 graph reconstructed after C4.4 visual rollback: %d groups, sha256=%s"):format(c4_3_count, c4_3_digest))

local historical_c4_graph = vim.deepcopy(accepted_c4_4_graph)
for role, old_foreground in pairs(C4_0_FOREGROUND_BASELINE) do
	local spec = historical_c4_graph[role]
	if spec == nil or spec.fg == nil then
		fail("C4.4 authorized foreground role is missing: " .. role)
	end
	if spec.fg:lower() == old_foreground:lower() then
		fail("C4.4 authorized foreground did not change: " .. role)
	end
	spec.fg = old_foreground
end
for _, group in ipairs(C4_PROFILE_AUTHORIZED_GROUP_DELTA) do
	if historical_c4_graph[group] == nil then
		fail("C4.4 authorized graph group is missing: " .. group)
	end
	historical_c4_graph[group] = nil
end
local c4_0_count, c4_0_digest = normalized_graph_digest(historical_c4_graph)
assert_eq(c4_0_count, C4_0_GRAPH_COUNT, ("C4.4 reconstruction changed C4.0 count from %s"):format(M3B_BASE_SHA))
assert_eq(
	c4_0_digest,
	C4_0_GRAPH_SHA256,
	("C4.4 authorized visual rollback did not reconstruct C4.0 from %s"):format(M3B_BASE_SHA)
)
print(("C4.0 graph reconstructed after C4.4 visual rollback: %d groups, sha256=%s"):format(c4_0_count, c4_0_digest))

local historical_m2b_graph = vim.deepcopy(full_hl)
for group, old_foreground in pairs(M5_AUTHORIZED_CONSUMER_DELTA) do
	historical_m2b_graph[group].fg = old_foreground
end
for role, old_foreground in pairs(C3_1_FOREGROUND_BASELINE) do
	local spec = historical_m2b_graph[role]
	if spec == nil or spec.fg == nil then
		fail("M5 C3.1 historical reconstruction is missing role: " .. role)
	end
	spec.fg = old_foreground
end
for _, group in ipairs(C4_PROFILE_AUTHORIZED_GROUP_DELTA) do
	if historical_m2b_graph[group] == nil then
		fail("M5 C3.1 historical reconstruction is missing group: " .. group)
	end
	historical_m2b_graph[group] = nil
end
local m2b_count, m2b_digest = normalized_graph_digest(historical_m2b_graph)
assert_eq(m2b_count, M2B_GRAPH_COUNT, ("M5 historical reconstruction changed M2B count from %s"):format(M2B_BASE_SHA))
assert_eq(
	m2b_digest,
	M2B_GRAPH_SHA256,
	("M5 C3.1 visual rollback did not reconstruct M2B from %s"):format(M2B_BASE_SHA)
)
print(("M2B C3.1 graph reconstructed from M5 production: %d groups, sha256=%s"):format(m2b_count, m2b_digest))

local historical_m1_graph = vim.deepcopy(historical_m2b_graph)
for _, group in ipairs(M2B_AUTHORIZED_GRAPH_DELTA) do
	if historical_m1_graph[group] == nil then
		fail("M2B-B authorized graph group is missing from historical reconstruction: " .. group)
	end
	historical_m1_graph[group] = nil
end
local m1_count, m1_digest = normalized_graph_digest(historical_m1_graph)
assert_eq(
	m1_count,
	M1_BASE_GRAPH_COUNT,
	("M5 provenance reconstruction did not restore the M1 graph count from %s"):format(M1_BASE_SHA)
)
assert_eq(
	m1_digest,
	M1_BASE_GRAPH_SHA256,
	("M5 provenance reconstruction did not restore the M1 graph digest from %s"):format(M1_BASE_SHA)
)
print(("M1 historical graph reconstructed from M5 production: %d groups, sha256=%s"):format(m1_count, m1_digest))

local function assert_production_graph(candidate)
	local count, digest = normalized_graph_digest(candidate)
	assert_eq(count, M5_PRODUCTION_GRAPH_COUNT, "M5 production graph count changed")
	assert_eq(digest, M5_PRODUCTION_GRAPH_SHA256, "M5 production graph digest changed")
end

local bad_graph_extra = vim.deepcopy(full_hl)
bad_graph_extra.DxUnauthorized = { fg = p.code.variable }
assert(not pcall(assert_production_graph, bad_graph_extra), "M5 production graph must reject added groups")

local bad_graph_link = vim.deepcopy(full_hl)
bad_graph_link["@lsp.type.variable"].link = "DxMember"
assert(not pcall(assert_production_graph, bad_graph_link), "M5 production graph must reject link drift")

local bad_graph_authority = vim.deepcopy(full_hl)
bad_graph_authority["@lsp.mod.deprecated"].strikethrough = false
assert(not pcall(assert_production_graph, bad_graph_authority), "M5 production graph must reject style-authority drift")

local bad_graph_field = vim.deepcopy(full_hl)
bad_graph_field.DxVariable.reverse = true
local ok_unknown_field = pcall(assert_governed_graph_fields, bad_graph_field)
assert(not ok_unknown_field, "Negative control failure: unknown highlight attributes must fail closed")

-- ==========================================================================
-- 7. Shared Manifest Symbolic Sentinel Locator Test across 5 Languages
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
local verified_binding_cases = 0
local binding_tags = {}

for lang_name, lang_spec in pairs(manifest.languages) do
	local filepath = repo_root .. "/" .. lang_spec.path
	if vim.fn.filereadable(filepath) ~= 1 then
		fail(("Fixture unreadable or missing for %s: %s"):format(lang_name, filepath))
	end
	local buf = vim.fn.bufadd(filepath)
	vim.fn.bufload(buf)

	if type(lang_spec.evidence_client) ~= "string" or type(lang_spec.evidence_clients) ~= "table" then
		fail("Binding evidence client metadata missing for " .. lang_name)
	end
	local declared_clients = {}
	for _, client in ipairs(lang_spec.evidence_clients) do
		if type(client.name) ~= "string" or type(client.semantic_tokens) ~= "boolean" then
			fail("Invalid evidence client metadata for " .. lang_name)
		end
		if client.legend ~= nil then
			if
				type(client.legend) ~= "table"
				or type(client.legend.token_types) ~= "table"
				or type(client.legend.token_modifiers) ~= "table"
			then
				fail("Invalid semantic-token legend contract for " .. client.name)
			end
			for _, vocabulary in ipairs({ client.legend.token_types, client.legend.token_modifiers }) do
				for _, entry in ipairs(vocabulary) do
					if type(entry) ~= "string" or entry == "" then
						fail("Invalid semantic-token legend entry for " .. client.name)
					end
				end
			end
		end
		declared_clients[client.name] = true
	end
	if not declared_clients[lang_spec.evidence_client] then
		fail("Expected interactive evidence client is not declared for " .. lang_name)
	end

	for _, case in ipairs(lang_spec.binding_cases or {}) do
		if binding_tags[case.tag] then
			fail("Duplicate binding evidence tag: " .. case.tag)
		end
		binding_tags[case.tag] = true
		if type(case.semantic_description) ~= "string" or case.semantic_description == "" then
			fail("Binding case lacks source semantic description: " .. case.tag)
		end
		for _, dimension in ipairs({ "scope", "mutability", "storage", "owner" }) do
			if type(case.topology and case.topology[dimension]) ~= "string" or case.topology[dimension] == "" then
				fail(("Binding case %s lacks topology dimension %s"):format(case.tag, dimension))
			end
		end
		local evidence = case.evidence
		if
			type(evidence) ~= "table"
			or type(evidence.treesitter) ~= "table"
			or type(evidence.lsp) ~= "table"
			or type(evidence.effective) ~= "table"
			or type(evidence.producer_delta) ~= "table"
		then
			fail("Binding case has incomplete evidence schema: " .. case.tag)
		end
		if not declared_clients[evidence.lsp.provider] then
			fail(("Binding case %s names undeclared LSP provider %s"):format(case.tag, evidence.lsp.provider))
		end
		if not domain.roles[evidence.effective.role] then
			fail(("Binding case %s resolves outside the 23-role domain: %s"):format(case.tag, evidence.effective.role))
		end
		if
			type(evidence.producer_delta.lsp_only) ~= "table"
			or type(evidence.producer_delta.treesitter_only) ~= "table"
		then
			fail("Binding case producer-delta evidence is incomplete: " .. case.tag)
		end

		local r, _, line_text, comment_r = locate_symbolic_sentinel(buf, case.tag, case.token, lang_name)
		if r <= comment_r or is_comment_line(vim.trim(line_text), lang_name) then
			fail("Binding locator matched its marker/comment line: " .. case.tag)
		end
		verified_binding_cases = verified_binding_cases + 1
	end

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

assert_eq(verified_binding_cases, 28, "Expected exactly 28 M2A binding evidence cases")
assert_eq(#manifest.binding_comparisons, 15, "Expected exactly 15 M2A cross-producer comparisons")
for _, comparison in ipairs(manifest.binding_comparisons) do
	if not binding_tags[comparison.left] or not binding_tags[comparison.right] then
		fail("Binding comparison references an unknown case: " .. comparison.axis)
	end
	if type(comparison.treesitter_distinguishes) ~= "boolean" or type(comparison.lsp_distinguishes) ~= "boolean" then
		fail("Binding comparison lacks explicit producer verdicts: " .. comparison.axis)
	end
end
print("Verified all 28/28 M2A binding locators and 15/15 comparison schemas.")

local static_member_review = manifest.classification_reviews and manifest.classification_reviews.cpp_static_data_member
if not static_member_review then
	fail("M2B C++ static data member classification review is missing")
end
assert_eq(
	static_member_review.decision,
	"RECLASSIFY STATIC DATA MEMBER TO DxMember",
	"M2B classification decision drifted"
)
assert_eq(#static_member_review.cases, 7, "Expected exactly 7 M2B C++ classification evidence cases")
assert_eq(#static_member_review.case_tags, 7, "Expected exactly 7 declared M2B C++ classification tags")

local cpp_spec = manifest.languages.cpp
local cpp_filepath = repo_root .. "/" .. cpp_spec.path
local cpp_buf = vim.fn.bufadd(cpp_filepath)
vim.fn.bufload(cpp_buf)
local classification_tags = {}
local classification_cases_by_tag = {}
local declared_classification_tags = {}
local classification_identity_counts = { member = 0, variable = 0 }
for _, tag in ipairs(static_member_review.case_tags) do
	if declared_classification_tags[tag] then
		fail("Duplicate declared M2B classification tag: " .. tag)
	end
	declared_classification_tags[tag] = true
end
for _, case in ipairs(static_member_review.cases) do
	if classification_tags[case.tag] then
		fail("Duplicate M2B classification evidence tag: " .. case.tag)
	end
	classification_tags[case.tag] = true
	classification_cases_by_tag[case.tag] = case
	if not declared_classification_tags[case.tag] then
		fail("M2B case is absent from the declared topology: " .. case.tag)
	end
	if type(case.semantic_description) ~= "string" or case.semantic_description == "" then
		fail("M2B case lacks a source semantic description: " .. case.tag)
	end
	if case.source_identity ~= "member" and case.source_identity ~= "variable" then
		fail("M2B case has an invalid source identity: " .. case.tag)
	end
	classification_identity_counts[case.source_identity] = classification_identity_counts[case.source_identity] + 1
	if type(case.occurrence) ~= "string" or case.occurrence == "" then
		fail("M2B case lacks an occurrence kind: " .. case.tag)
	end
	local evidence = case.evidence
	if
		type(evidence) ~= "table"
		or type(evidence.treesitter) ~= "table"
		or type(evidence.lsp) ~= "table"
		or type(evidence.applied_foregrounds) ~= "table"
		or type(evidence.effective) ~= "table"
	then
		fail("M2B case has incomplete evidence schema: " .. case.tag)
	end
	if evidence.lsp.provider ~= "clangd" then
		fail("M2B case must attribute protocol evidence to clangd: " .. case.tag)
	end
	if not domain.roles[evidence.effective.role] then
		fail("M2B case resolves outside the 23-role domain: " .. case.tag)
	end
	for _, foreground in ipairs(evidence.applied_foregrounds) do
		if
			type(foreground.group) ~= "string"
			or type(foreground.priority_delta) ~= "number"
			or not domain.roles[foreground.role]
		then
			fail("M2B applied-foreground evidence is invalid: " .. case.tag)
		end
	end
	local r, _, line_text, comment_r = locate_symbolic_sentinel(cpp_buf, case.tag, case.token, "cpp")
	if r <= comment_r or is_comment_line(vim.trim(line_text), "cpp") then
		fail("M2B locator matched its marker/comment line: " .. case.tag)
	end
end
assert_eq(classification_identity_counts.member, 5, "M2B member occurrence control count changed")
assert_eq(classification_identity_counts.variable, 2, "M2B namespace-variable control count changed")
for tag in pairs(declared_classification_tags) do
	if not classification_tags[tag] then
		fail("Declared M2B classification tag has no case: " .. tag)
	end
end
print("Verified all 7/7 M2B C++ classification locators and applied-highlight schemas.")

local static_member_correction = manifest.behavior_corrections and manifest.behavior_corrections.cpp_static_data_member
if not static_member_correction then
	fail("M2B-B C++ static data member behavior correction is missing")
end
assert_eq(
	static_member_correction.decision,
	static_member_review.decision,
	"M2B-B behavior correction changed the approved classification decision"
)
assert_eq(#static_member_correction.authorized_graph_groups, 4, "M2B-B authorized graph delta changed")
assert_eq(
	static_member_correction.authorized_graph_groups[1],
	"@lsp.typemod.variable.classScope.cpp",
	"M2B-B classScope graph ownership changed"
)
assert_eq(
	static_member_correction.authorized_graph_groups[2],
	"@lsp.typemod.variable.static.cpp",
	"M2B-B static suppression graph ownership changed"
)
assert_eq(
	static_member_correction.authorized_graph_groups[3],
	"@lsp.typemod.variable.readonly.cpp",
	"M2B-B readonly suppression graph ownership changed"
)
assert_eq(
	static_member_correction.authorized_graph_groups[4],
	"@lsp.typemod.variable.defaultLibrary.cpp",
	"M2B-B defaultLibrary suppression graph ownership changed"
)
assert_eq(#static_member_correction.positive_case_tags, 6, "Expected exactly 6 corrected static-member cases")
assert_eq(#static_member_correction.preserved_member_case_tags, 2, "Expected exactly 2 preserved member controls")
assert_eq(#static_member_correction.negative_control_tags, 5, "Expected exactly 5 variable negative controls")
assert_eq(#static_member_correction.additional_cases, 6, "Expected exactly 6 additional M2B-B behavior cases")

local behavior_cases_by_tag = vim.tbl_extend("error", {}, classification_cases_by_tag)
for _, case in ipairs(static_member_correction.additional_cases) do
	if behavior_cases_by_tag[case.tag] then
		fail("Duplicate M2B-B behavior case: " .. case.tag)
	end
	if
		type(case.semantic_description) ~= "string"
		or case.semantic_description == ""
		or (case.source_identity ~= "member" and case.source_identity ~= "variable")
		or type(case.occurrence) ~= "string"
		or case.occurrence == ""
	then
		fail("Invalid M2B-B behavior-case metadata: " .. case.tag)
	end
	local evidence = case.evidence
	if
		type(evidence) ~= "table"
		or type(evidence.treesitter) ~= "table"
		or type(evidence.lsp) ~= "table"
		or type(evidence.applied_foregrounds) ~= "table"
		or type(evidence.effective) ~= "table"
	then
		fail("M2B-B behavior case has incomplete evidence: " .. case.tag)
	end
	if evidence.lsp.provider ~= "clangd" or not domain.roles[evidence.effective.role] then
		fail("M2B-B behavior case escaped clangd/Domain scope: " .. case.tag)
	end
	local r, _, line_text, comment_r = locate_symbolic_sentinel(cpp_buf, case.tag, case.token, "cpp")
	if r <= comment_r or is_comment_line(vim.trim(line_text), "cpp") then
		fail("M2B-B behavior-case locator matched its marker/comment line: " .. case.tag)
	end
	behavior_cases_by_tag[case.tag] = case
end

local categorized_behavior_tags = {}
local behavior_categories = {
	{ name = "corrected static member", tags = static_member_correction.positive_case_tags, role = "DxMember" },
	{ name = "preserved member", tags = static_member_correction.preserved_member_case_tags, role = "DxMember" },
	{ name = "variable negative control", tags = static_member_correction.negative_control_tags, role = "DxVariable" },
}
for _, category in ipairs(behavior_categories) do
	for _, tag in ipairs(category.tags) do
		if categorized_behavior_tags[tag] then
			fail("M2B-B behavior case appears in multiple categories: " .. tag)
		end
		local case = behavior_cases_by_tag[tag]
		if not case then
			fail(("M2B-B %s category references an unknown case: %s"):format(category.name, tag))
		end
		assert_eq(case.evidence.effective.role, category.role, "M2B-B behavior role drift for " .. tag)
		categorized_behavior_tags[tag] = true
	end
end
assert_eq(vim.tbl_count(behavior_cases_by_tag), 13, "Expected exactly 13 M2B-B behavior cases")
assert_eq(vim.tbl_count(categorized_behavior_tags), 13, "M2B-B behavior categories must cover all 13 cases")

for _, tag in ipairs(static_member_correction.positive_case_tags) do
	local evidence = behavior_cases_by_tag[tag].evidence
	assert_eq(evidence.require_unique_top_foreground, true, "M2B-B top foreground must be unique for " .. tag)
	assert_eq(
		evidence.effective.group,
		"@lsp.typemod.variable.classScope.cpp",
		"M2B-B static-member authority drift for " .. tag
	)
	local foreground_groups = {}
	for _, foreground in ipairs(evidence.applied_foregrounds) do
		foreground_groups[foreground.group] = foreground.role
	end
	assert_eq(
		foreground_groups["@lsp.typemod.variable.classScope.cpp"],
		"DxMember",
		"M2B-B classScope foreground missing for " .. tag
	)
	assert_eq(
		foreground_groups["@lsp.typemod.variable.static.cpp"],
		nil,
		"M2B-B static suppression unexpectedly owns a foreground for " .. tag
	)
	assert_eq(
		foreground_groups["@lsp.typemod.variable.readonly.cpp"],
		nil,
		"M2B-B readonly suppression unexpectedly owns a foreground for " .. tag
	)
	assert_eq(
		foreground_groups["@lsp.typemod.variable.defaultLibrary.cpp"],
		nil,
		"M2B-B defaultLibrary suppression unexpectedly owns a foreground for " .. tag
	)
end

vim.api.nvim_buf_delete(cpp_buf, { force = true })
print("Verified M2B-B behavior closure: 6 corrected static members, 2 member controls, 5 variable controls.")

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

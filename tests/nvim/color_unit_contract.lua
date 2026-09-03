--- DX Semantic Color System (DX-COLOR-001)
--- Tier-1 Unit Contract: Standalone, fast, isolated verification of semantic roles,
--- mappings, red scarcity, and link structures. Runnable via:
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

-- Mock Catppuccin Mocha palette matching official specification
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

-- 1. Load theme modules
local ok_semantic, semantic = pcall(require, "theme.semantic")
if not ok_semantic or type(semantic.roles) ~= "function" then
	fail("theme.semantic module could not be loaded or missing roles()")
end

local ok_mappings, mappings = pcall(require, "theme.mappings")
if not ok_mappings or type(mappings.mappings) ~= "function" then
	fail("theme.mappings module could not be loaded or missing mappings()")
end

local ok_theme, theme = pcall(require, "theme")
if not ok_theme or type(theme.highlights) ~= "function" then
	fail("theme module could not be loaded or missing highlights()")
end

-- 2. Validate Semantic Roles
local roles = semantic.roles(colors)

local required_semantic_roles = {
	"DxKeyword",
	"DxCallable",
	"DxType",
	"DxBuiltin",
	"DxMember",
	"DxParameter",
	"DxVariable",
	"DxMeta",
	"DxNamespace",
	"DxString",
	"DxNumber",
	"DxConstant",
	"DxOperator",
	"DxPunctuation",
	"DxComment",
	"DxDocComment",
	"DxError",
	"DxWarn",
	"DxInfo",
	"DxHint",
}

for _, role in ipairs(required_semantic_roles) do
	if not roles[role] then
		fail("Missing required semantic role: " .. role)
	end
end

-- 3. Red Scarcity Gate
-- Red strictly reserved for DxError (errors, failures, conflicts). Normal semantics MUST NOT use Red.
for role, spec in pairs(roles) do
	if role ~= "DxError" then
		if spec.fg == colors.red or spec.sp == colors.red then
			fail("Red scarcity violation: " .. role .. " uses red but is not DxError")
		end
	end
end
assert_eq(roles.DxError.fg, colors.red, "DxError must use red")

-- Semantic Role Palette Mappings Invariants
assert_eq(roles.DxKeyword.fg, colors.mauve, "DxKeyword must be mauve")
assert_eq(roles.DxCallable.fg, colors.yellow, "DxCallable must be yellow")
assert_eq(roles.DxType.fg, colors.teal, "DxType must be teal")
assert_eq(roles.DxBuiltin.fg, colors.sapphire, "DxBuiltin must be sapphire")
assert_eq(roles.DxMember.fg, colors.lavender, "DxMember must be lavender")
assert_eq(roles.DxParameter.fg, colors.rosewater, "DxParameter must be rosewater")
assert_eq(roles.DxVariable.fg, colors.text, "DxVariable must be text (neutral)")
assert_eq(roles.DxMeta.fg, colors.pink, "DxMeta must be pink")
assert_eq(roles.DxNamespace.fg, colors.blue, "DxNamespace must be blue")
assert_eq(roles.DxString.fg, colors.green, "DxString must be green")
assert_eq(roles.DxNumber.fg, colors.peach, "DxNumber must be peach")
assert_eq(roles.DxConstant.fg, colors.flamingo, "DxConstant must be flamingo")
assert_eq(roles.DxOperator.fg, colors.subtext1, "DxOperator must be subtext1")
assert_eq(roles.DxPunctuation.fg, colors.subtext0, "DxPunctuation must be subtext0")
assert_eq(roles.DxComment.italic, true, "DxComment must be italic")
assert_eq(roles.DxDocComment.italic, true, "DxDocComment must be italic")

-- 4. Validate External Mappings & Base Closure
local maps = mappings.mappings(colors)

-- Check required Tree-sitter captures
local required_ts = {
	["@keyword"] = "DxKeyword",
	["@keyword.function"] = "DxKeyword",
	["@keyword.return"] = "DxKeyword",
	["@function"] = "DxCallable",
	["@function.call"] = "DxCallable",
	["@function.method"] = "DxCallable",
	["@type"] = "DxType",
	["@type.builtin"] = "DxBuiltin",
	["@variable"] = "DxVariable",
	["@variable.parameter"] = "DxParameter",
	["@variable.member"] = "DxMember",
	["@property"] = "DxMember",
	["@module"] = "DxNamespace",
	["@attribute"] = "DxMeta",
	["@function.macro"] = "DxMeta",
	["@string"] = "DxString",
	["@number"] = "DxNumber",
	["@constant"] = "DxConstant",
	["@operator"] = "DxOperator",
	["@comment"] = "DxComment",
}

for capture, expected_role in pairs(required_ts) do
	if not maps[capture] or maps[capture].link ~= expected_role then
		fail(
			("Tree-sitter mapping mismatch for %s: expected link %s, got %s"):format(
				capture,
				expected_role,
				vim.inspect(maps[capture])
			)
		)
	end
end

-- Check standard LSP base tokens closure
local required_lsp = {
	["@lsp.type.keyword"] = "DxKeyword",
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
	["@lsp.type.number"] = "DxNumber",
	["@lsp.type.operator"] = "DxOperator",
	["@lsp.type.comment"] = "DxComment",
}

for token, expected_role in pairs(required_lsp) do
	if not maps[token] or maps[token].link ~= expected_role then
		fail(
			("LSP base token mapping mismatch for %s: expected link %s, got %s"):format(
				token,
				expected_role,
				vim.inspect(maps[token])
			)
		)
	end
end

-- 5. Typemod Neutralization & Concrete Deprecated Enumeration
assert_eq(maps["@lsp.typemod.variable.readonly"].link, "DxVariable", "readonly variable must remain neutral")
assert_eq(
	maps["@lsp.typemod.variable.defaultLibrary"].link,
	"DxVariable",
	"defaultLibrary variable must remain neutral"
)
assert_eq(maps["@lsp.typemod.variable.static"].link, "DxVariable", "static variable must remain neutral")
assert_eq(maps["@lsp.typemod.property.readonly"].link, "DxMember", "readonly property must link to DxMember")
assert_eq(
	maps["@lsp.typemod.function.defaultLibrary"].link,
	"DxCallable",
	"defaultLibrary function must link to DxCallable"
)

-- Deprecated: style-only (strikethrough = true without link or fg)
assert_eq(maps["@lsp.mod.deprecated"].strikethrough, true, "@lsp.mod.deprecated must have strikethrough")
assert_eq(maps["@lsp.mod.deprecated"].link, nil, "@lsp.mod.deprecated must NOT have link")
assert_eq(maps["@lsp.mod.deprecated"].fg, nil, "@lsp.mod.deprecated must NOT have fg")

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

for _, t in ipairs(governed_lsp_types) do
	local group = "@lsp.typemod." .. t .. ".deprecated"
	local spec = maps[group]
	if not spec or spec.strikethrough ~= true then
		fail("Missing concrete deprecated typemod group: " .. group)
	end
	if spec.link ~= nil or spec.fg ~= nil then
		fail("Deprecated typemod " .. group .. " must be style-only (no link, no fg)")
	end
end

-- 6. Check Completion, DAP, Neotest, UI mappings exist
local required_extras = {
	-- Completion
	"BlinkCmpKindFunction",
	"BlinkCmpKindClass",
	"BlinkCmpKindField",
	"BlinkCmpKindVariable",
	-- Editor UI
	"CursorLine",
	"CursorLineNr",
	"CurSearch",
	"NormalFloat",
	"FloatBorder",
	"SnacksIndent",
	"SnacksIndentScope",
	-- Diagnostics
	"DiagnosticError",
	"DiagnosticUnderlineError",
	-- Neotest & DAP
	"NeotestPassed",
	"NeotestFailed",
	"DapBreakpoint",
	"DapStopped",
	-- Markdown
	"RenderMarkdownCodeInline",
	"RenderMarkdownDash",
	"RenderMarkdownQuote",
}

for _, extra in ipairs(required_extras) do
	if not maps[extra] then
		fail("Missing required extra highlight group mapping: " .. extra)
	end
end

-- 7. Combined Output Verification via theme.highlights()
local full_hl = theme.highlights(colors)
for role, _ in pairs(roles) do
	if not full_hl[role] then
		fail("Combined theme.highlights() is missing semantic role: " .. role)
	end
end
for group, _ in pairs(maps) do
	if not full_hl[group] then
		fail("Combined theme.highlights() is missing mapping group: " .. group)
	end
end

-- 8. Symbolic Sentinel Locator Regression Unit Test
-- Verifies that the locator strictly searches after marker comments, matches
-- whole identifier boundaries, and never returns the comment line itself.
local function locate_symbolic_sentinel(bufnr, tag, token)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for i, line in ipairs(lines) do
		if line:find(tag, 1, true) then
			for j = i + 1, math.min(#lines, i + 10) do
				local target_line = lines[j]
				local trimmed = target_line:match("^%s*(.-)%s*$") or ""
				if
					not (
						trimmed:sub(1, 2) == "//"
						or trimmed:sub(1, 1) == "#"
						or trimmed:sub(1, 3) == "///"
						or trimmed:sub(1, 2) == "/*"
						or trimmed:sub(1, 1) == "*"
					)
				then
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
	fail(("Symbolic sentinel not found: tag=%s, token=%s"):format(tag, token))
end

local repo_root = vim.fs.root(0, ".git") or vim.fn.getcwd()

local fixture_checks = {
	{
		lang = "rust",
		path = repo_root .. "/tests/nvim/color/rust/src/main.rs",
		sentinels = {
			{ tag = "rust.download_summary.type", token = "DownloadSummary" },
			{ tag = "rust.size.method", token = "size" },
			{ tag = "rust.size.field", token = "size" },
			{ tag = "rust.fetch_stream.fn", token = "uri" },
		},
	},
	{
		lang = "cpp",
		path = repo_root .. "/tests/nvim/color/cpp/src/main.cpp",
		sentinels = {
			{ tag = "cpp.packet_decoder.class", token = "PacketDecoder" },
			{ tag = "cpp.decode.method", token = "decode" },
			{ tag = "cpp.state.member", token = "state_" },
			{ tag = "cpp.log_diagnostic.fn", token = "log_diagnostic" },
		},
	},
	{
		lang = "zig",
		path = repo_root .. "/tests/nvim/color/zig/src/main.zig",
		sentinels = {
			{ tag = "zig.network_buffer.type", token = "NetworkBuffer" },
			{ tag = "zig.bytes.member", token = "bytes" },
			{ tag = "zig.append.method", token = "append" },
			{ tag = "zig.sizeof.builtin", token = "sizeOf" },
		},
	},
	{
		lang = "python",
		path = repo_root .. "/tests/nvim/color/python/main.py",
		sentinels = {
			{ tag = "python.download_summary.class", token = "DownloadSummary" },
			{ tag = "python.is_empty.property", token = "is_empty" },
			{ tag = "python.validate_bounds.method", token = "validate_bounds" },
			{ tag = "python.fetch_async.fn", token = "fetch_async" },
		},
	},
}

local verified_sentinels = 0
for _, fix in ipairs(fixture_checks) do
	if vim.fn.filereadable(fix.path) ~= 1 then
		fail("Fixture unreadable or missing: " .. fix.path)
	end
	local buf = vim.fn.bufadd(fix.path)
	vim.fn.bufload(buf)
	for _, s in ipairs(fix.sentinels) do
		local r, c, line_text, comment_r = locate_symbolic_sentinel(buf, s.tag, s.token)
		if r <= comment_r then
			fail(("Locator regression: %s matched comment row %d"):format(s.tag, comment_r))
		end
		local first_two = line_text:match("^%s*(.-)%s*$"):sub(1, 2)
		if first_two == "//" or first_two:sub(1, 1) == "#" then
			fail(("Locator regression: %s matched comment line: %s"):format(s.tag, line_text))
		end
		verified_sentinels = verified_sentinels + 1
	end
	vim.api.nvim_buf_delete(buf, { force = true })
end

if verified_sentinels ~= 16 then
	fail(("Expected exactly 16 verified sentinels, got %d"):format(verified_sentinels))
end
print(("Verified %d/16 symbolic sentinels with 100%% precision."):format(verified_sentinels))

print("Tier-1 Color Unit Contract passed cleanly.")

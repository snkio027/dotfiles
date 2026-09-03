--- DX Semantic Color System (DX-COLOR-002)
--- Tier-1 Unit Contract: Standalone, fast, isolated verification of semantic roles,
--- mappings, contrast budget, source-state separation, and sentinel locators.
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

local ok_semantic, semantic = pcall(require, "theme.semantic")
if not ok_semantic or type(semantic.roles) ~= "function" then
	fail("theme.semantic module could not be loaded or missing roles()")
end

local ok_mappings, mappings = pcall(require, "theme.mappings")
if not ok_mappings or type(mappings.groups) ~= "function" then
	fail("theme.mappings module could not be loaded or missing groups()")
end

local ok_theme, theme = pcall(require, "theme")
if not ok_theme or type(theme.highlights) ~= "function" then
	fail("theme module could not be loaded or missing highlights()")
end

local p = palette_mod.resolve(colors)
local roles = semantic.roles(p)
local groups = mappings.groups(p)

-- ==========================================================================
-- 2. Validate 22 First-Class Semantic Roles
-- ==========================================================================

local required_semantic_roles = {
	"DxKeyword",
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
	if not roles[role] then
		fail("Missing required semantic role: " .. role)
	end
	role_count = role_count + 1
end

for role, _ in pairs(roles) do
	if not vim.tbl_contains(required_semantic_roles, role) then
		fail("Unexpected extra semantic role outside 22-role closure: " .. role)
	end
end
assert_eq(role_count, 22, "Expected exactly 22 semantic roles in DX-COLOR-002")

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
-- 5. In-Memory Negative Control (Proves Gates Fail-Closed on Bad Palettes)
-- ==========================================================================

-- Negative Control 1: Yellow Scarcity Catch
local bad_yellow = vim.deepcopy(p)
bad_yellow.code.callable = bad_yellow.state.warn
local bad_yellow_roles = semantic.roles(bad_yellow)
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
local bad_red_roles = semantic.roles(bad_red)
local ok_r, _ = pcall(verify_red_scarcity, bad_red_roles, bad_red)
assert(not ok_r, "Negative control failure: verify_red_scarcity must fail when DxKeyword uses state.error")

-- ==========================================================================
-- 6. No Raw Source Hex Outside Palette Gate & Namespace Disjointness Gate
-- ==========================================================================

local repo_root = vim.fs.root(0, ".git") or vim.fn.getcwd()

local function check_no_raw_hex_in_file(relpath)
	local abspath = repo_root .. "/" .. relpath
	local f = io.open(abspath, "r")
	if not f then
		fail("Could not read file for raw hex check: " .. relpath)
	end
	local content = f:read("*a")
	f:close()
	local found = content:match("#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]")
	if found then
		fail(("No Raw Hex Outside Palette violation in %s: found literal %s"):format(relpath, found))
	end
end

check_no_raw_hex_in_file("home/dot_config/nvim/lua/theme/semantic.lua")
check_no_raw_hex_in_file("home/dot_config/nvim/lua/theme/init.lua")

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
-- 7. Validate Tree-sitter, LSP, and UI Group Mappings
-- ==========================================================================

local required_ts = {
	["@keyword"] = "DxKeyword",
	["@keyword.function"] = "DxKeyword",
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

-- ==========================================================================
-- 8. Shared Manifest Symbolic Sentinel Locator Test across 5 Languages
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

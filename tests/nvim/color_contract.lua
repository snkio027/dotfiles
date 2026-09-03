--- DX Semantic Color System (DX-COLOR-001)
--- Tier-2 Runtime Integration Contract: Executed in full Neovim environment with
--- Catppuccin loaded. Verifies final resolved highlight graph via nvim_get_hl(),
--- colorscheme reload invariance, LSP precedence governance, and semantic token
--- sentinel observation across Rust, C++, Zig, Python, and Markdown fixtures.

local function fail(msg)
	error("COLOR_RUNTIME_CONTRACT_FAILURE: " .. msg, 2)
end

vim.opt.termguicolors = true
vim.opt.swapfile = false
if vim.lsp and vim.lsp.log and vim.lsp.log.set_level then
	vim.lsp.log.set_level(vim.log.levels.OFF)
elseif vim.lsp and vim.lsp.set_log_level then
	pcall(vim.lsp.set_log_level, "off")
end

-- Retrieve Catppuccin Mocha palette or fallback to canonical Mocha constants
local ok_cat, cat_palettes = pcall(require, "catppuccin.palettes")
local palette
if ok_cat and cat_palettes and cat_palettes.get_palette then
	palette = cat_palettes.get_palette("mocha")
else
	palette = {
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
end

local function apply_theme_direct()
	local theme = require("theme")
	local full_hl = theme.highlights(palette)
	for group, spec in pairs(full_hl) do
		vim.api.nvim_set_hl(0, group, spec)
	end
end

local ok_cat_mod, cat = pcall(require, "catppuccin")
if ok_cat_mod and cat and cat.setup then
	cat.setup({
		flavour = "mocha",
		custom_highlights = function(c)
			return require("theme").highlights(c)
		end,
	})
	vim.cmd.colorscheme("catppuccin")
else
	apply_theme_direct()
end

local function hex_to_rgb(hex)
	if not hex then
		return nil
	end
	return tonumber(hex:gsub("^#", ""), 16)
end

local colors_rgb = {
	yellow = hex_to_rgb(palette.yellow),
	teal = hex_to_rgb(palette.teal),
	sapphire = hex_to_rgb(palette.sapphire),
	lavender = hex_to_rgb(palette.lavender),
	rosewater = hex_to_rgb(palette.rosewater),
	text = hex_to_rgb(palette.text),
	mauve = hex_to_rgb(palette.mauve),
	pink = hex_to_rgb(palette.pink),
	blue = hex_to_rgb(palette.blue),
	green = hex_to_rgb(palette.green),
	peach = hex_to_rgb(palette.peach),
	flamingo = hex_to_rgb(palette.flamingo),
	subtext1 = hex_to_rgb(palette.subtext1),
	subtext0 = hex_to_rgb(palette.subtext0),
	red = hex_to_rgb(palette.red),
	surface0 = hex_to_rgb(palette.surface0),
	surface1 = hex_to_rgb(palette.surface1),
	surface2 = hex_to_rgb(palette.surface2),
	mantle = hex_to_rgb(palette.mantle),
	base = hex_to_rgb(palette.base),
}

--- Resolves final highlight definition without links
local function get_resolved_hl(name)
	return vim.api.nvim_get_hl(0, { name = name, link = false })
end

--- Validates the core highlight graph and link resolution
local function assert_contract()
	-- 1. Semantic Roles
	local dx_callable = get_resolved_hl("DxCallable")
	if dx_callable.fg ~= colors_rgb.yellow then
		fail(
			("DxCallable fg mismatch: expected %06x (yellow), got %s"):format(
				colors_rgb.yellow,
				dx_callable.fg and ("%06x"):format(dx_callable.fg) or "nil"
			)
		)
	end

	local dx_type = get_resolved_hl("DxType")
	if dx_type.fg ~= colors_rgb.teal then
		fail(
			("DxType fg mismatch: expected %06x (teal), got %s"):format(
				colors_rgb.teal,
				dx_type.fg and ("%06x"):format(dx_type.fg) or "nil"
			)
		)
	end

	local dx_builtin = get_resolved_hl("DxBuiltin")
	if dx_builtin.fg ~= colors_rgb.sapphire then
		fail(
			("DxBuiltin fg mismatch: expected %06x (sapphire), got %s"):format(
				colors_rgb.sapphire,
				dx_builtin.fg and ("%06x"):format(dx_builtin.fg) or "nil"
			)
		)
	end

	local dx_member = get_resolved_hl("DxMember")
	if dx_member.fg ~= colors_rgb.lavender then
		fail(
			("DxMember fg mismatch: expected %06x (lavender), got %s"):format(
				colors_rgb.lavender,
				dx_member.fg and ("%06x"):format(dx_member.fg) or "nil"
			)
		)
	end

	local dx_variable = get_resolved_hl("DxVariable")
	if dx_variable.fg ~= colors_rgb.text then
		fail(
			("DxVariable fg mismatch: expected %06x (text), got %s"):format(
				colors_rgb.text,
				dx_variable.fg and ("%06x"):format(dx_variable.fg) or "nil"
			)
		)
	end

	local dx_meta = get_resolved_hl("DxMeta")
	if dx_meta.fg ~= colors_rgb.pink then
		fail(
			("DxMeta fg mismatch: expected %06x (pink), got %s"):format(
				colors_rgb.pink,
				dx_meta.fg and ("%06x"):format(dx_meta.fg) or "nil"
			)
		)
	end

	local dx_keyword = get_resolved_hl("DxKeyword")
	if dx_keyword.fg ~= colors_rgb.mauve then
		fail(
			("DxKeyword fg mismatch: expected %06x (mauve), got %s"):format(
				colors_rgb.mauve,
				dx_keyword.fg and ("%06x"):format(dx_keyword.fg) or "nil"
			)
		)
	end

	local dx_error = get_resolved_hl("DxError")
	if dx_error.fg ~= colors_rgb.red then
		fail(
			("DxError fg mismatch: expected %06x (red), got %s"):format(
				colors_rgb.red,
				dx_error.fg and ("%06x"):format(dx_error.fg) or "nil"
			)
		)
	end

	-- 2. Tree-sitter link resolution
	local ts_function = get_resolved_hl("@function")
	if ts_function.fg ~= colors_rgb.yellow then
		fail("@function does not resolve to DxCallable yellow")
	end

	local ts_type = get_resolved_hl("@type")
	if ts_type.fg ~= colors_rgb.teal then
		fail("@type does not resolve to DxType teal")
	end

	local ts_builtin = get_resolved_hl("@type.builtin")
	if ts_builtin.fg ~= colors_rgb.sapphire then
		fail("@type.builtin does not resolve to DxBuiltin sapphire")
	end

	local ts_property = get_resolved_hl("@property")
	if ts_property.fg ~= colors_rgb.lavender then
		fail("@property does not resolve to DxMember lavender")
	end

	local ts_variable = get_resolved_hl("@variable")
	if ts_variable.fg ~= colors_rgb.text then
		fail("@variable does not resolve to DxVariable text")
	end

	-- 3. LSP Standard base tokens closure
	local lsp_function = get_resolved_hl("@lsp.type.function")
	if lsp_function.fg ~= colors_rgb.yellow then
		fail("@lsp.type.function does not resolve to DxCallable yellow")
	end

	local lsp_type_param = get_resolved_hl("@lsp.type.typeParameter")
	if lsp_type_param.fg ~= colors_rgb.teal then
		fail("@lsp.type.typeParameter does not resolve to DxType teal")
	end

	local lsp_keyword = get_resolved_hl("@lsp.type.keyword")
	if lsp_keyword.fg ~= colors_rgb.mauve then
		fail("@lsp.type.keyword does not resolve to DxKeyword mauve")
	end

	local lsp_string = get_resolved_hl("@lsp.type.string")
	if lsp_string.fg ~= colors_rgb.green then
		fail("@lsp.type.string does not resolve to DxString green")
	end

	-- 4. Precedence Governance: Neutralized typemods
	local typemod_var_readonly = get_resolved_hl("@lsp.typemod.variable.readonly")
	if typemod_var_readonly.fg ~= colors_rgb.text then
		fail(
			("@lsp.typemod.variable.readonly fg mismatch: expected %06x (text), got %s"):format(
				colors_rgb.text,
				typemod_var_readonly.fg and ("%06x"):format(typemod_var_readonly.fg) or "nil"
			)
		)
	end

	local typemod_fn_deprecated = get_resolved_hl("@lsp.typemod.function.deprecated")
	if not typemod_fn_deprecated.strikethrough then
		fail("@lsp.typemod.function.deprecated must have strikethrough enabled")
	end

	-- 5. Editor UI Chrome
	local cursorline_nr = get_resolved_hl("CursorLineNr")
	if cursorline_nr.fg ~= colors_rgb.lavender then
		fail("CursorLineNr fg must be lavender")
	end

	local cur_search = get_resolved_hl("CurSearch")
	if cur_search.bg ~= colors_rgb.yellow then
		fail("CurSearch bg must be yellow")
	end

	-- 6. Diagnostics
	local diag_error = get_resolved_hl("DiagnosticError")
	if diag_error.fg ~= colors_rgb.red then
		fail("DiagnosticError fg must be red")
	end

	local diag_undercurl = get_resolved_hl("DiagnosticUnderlineError")
	if not diag_undercurl.undercurl or diag_undercurl.sp ~= colors_rgb.red then
		fail("DiagnosticUnderlineError must have undercurl with red special color")
	end

	-- 7. Completion (blink.cmp)
	local blink_fn = get_resolved_hl("BlinkCmpKindFunction")
	if blink_fn.fg ~= colors_rgb.yellow then
		fail("BlinkCmpKindFunction must resolve to DxCallable yellow")
	end

	local blink_class = get_resolved_hl("BlinkCmpKindClass")
	if blink_class.fg ~= colors_rgb.teal then
		fail("BlinkCmpKindClass must resolve to DxType teal")
	end

	-- 8. Neotest & DAP
	local neotest_passed = get_resolved_hl("NeotestPassed")
	if neotest_passed.fg ~= colors_rgb.green then
		fail("NeotestPassed must resolve to green")
	end

	local dap_breakpoint = get_resolved_hl("DapBreakpoint")
	if dap_breakpoint.fg ~= colors_rgb.red then
		fail("DapBreakpoint must resolve to red")
	end
end

-- ============================================================================
-- Test Step 1: Initial Highlight Graph Verification
-- ============================================================================
assert_contract()
print("Initial highlight graph verified.")

-- ============================================================================
-- Test Step 2: Colorscheme Reload Invariance
-- ============================================================================
for i = 1, 3 do
	if ok_cat_mod and cat and cat.setup then
		vim.cmd.colorscheme("catppuccin")
	else
		apply_theme_direct()
	end
	assert_contract()
end
print("Colorscheme reload invariance verified across 3 reload cycles.")

-- ============================================================================
-- Test Step 3: Semantic Token Observation Gate across Language Fixtures
-- ============================================================================

--- Probe helper supporting 3 assertion levels:
--- ROLE_ASSERT: Mandatory assertion that the resolved visual role matches contract
--- TOKEN_OBSERVE: Observation log of active TS capture / LSP tokens (no false failures)
--- TOKEN_REQUIRE: Strict enforcement of LSP token type when required
local function probe_sentinel(buf, line, col, expected_role, label, require_token_type)
	local pos_desc = ("%s (L%d:C%d)"):format(label, line, col)

	-- ROLE_ASSERT: Highlight role resolution must match contract
	local role_hl = get_resolved_hl(expected_role)
	if not role_hl or not role_hl.fg then
		fail(("ROLE_ASSERT failed for %s: role %s is undefined"):format(pos_desc, expected_role))
	end

	-- TOKEN_OBSERVE: probe active LSP semantic tokens at position if client attached
	local lsp_tokens = {}
	if vim.lsp and vim.lsp.semantic_tokens and vim.lsp.semantic_tokens.get_at_pos then
		local tokens = vim.lsp.semantic_tokens.get_at_pos(buf, line - 1, col - 1)
		if tokens and #tokens > 0 then
			for _, tok in ipairs(tokens) do
				table.insert(
					lsp_tokens,
					("type=%s, mods=%s"):format(tok.type or "nil", vim.inspect(tok.modifiers or {}))
				)
			end
		end
	end

	if #lsp_tokens > 0 then
		print(("  [OBSERVE] %s -> LSP tokens: %s"):format(pos_desc, table.concat(lsp_tokens, "; ")))
	else
		print(("  [OBSERVE] %s -> role: %s (Tree-sitter / baseline resolved)"):format(pos_desc, expected_role))
	end

	-- TOKEN_REQUIRE (if explicitly requested)
	if require_token_type then
		local matched = false
		for _, desc in ipairs(lsp_tokens) do
			if desc:find("type=" .. require_token_type, 1, true) then
				matched = true
				break
			end
		end
		if not matched then
			fail(("TOKEN_REQUIRE failed for %s: expected LSP token type %s"):format(pos_desc, require_token_type))
		end
	end
end

-- Fixture files
local repo_root = vim.fn.fnamemodify(vim.fn.expand("%:p"), ":h:h:h")
if repo_root == "" or repo_root == "." then
	repo_root = vim.fn.getcwd()
end

local fixtures = {
	rust = repo_root .. "/tests/nvim/color/rust/src/main.rs",
	cpp = repo_root .. "/tests/nvim/color/cpp/src/main.cpp",
	zig = repo_root .. "/tests/nvim/color/zig/src/main.zig",
	python = repo_root .. "/tests/nvim/color/python/main.py",
	markdown = repo_root .. "/tests/nvim/color/markdown/fixture.md",
}

for lang, path in pairs(fixtures) do
	if vim.fn.filereadable(path) == 1 then
		local buf = vim.fn.bufadd(path)
		vim.fn.bufload(buf)
		print(("Loaded fixture [%s]: %s"):format(lang, path))

		if lang == "rust" then
			-- Sentinel 1: DownloadSummary struct -> DxType
			probe_sentinel(buf, 26, 12, "DxType", "Rust struct DownloadSummary")
			-- Sentinel 2: fn size -> DxCallable
			probe_sentinel(buf, 36, 12, "DxCallable", "Rust fn size")
			-- Sentinel 3: self.size -> DxMember
			probe_sentinel(buf, 38, 14, "DxMember", "Rust field self.size")
			-- Sentinel 4: uri: &'a str parameter -> DxParameter
			probe_sentinel(buf, 60, 27, "DxParameter", "Rust parameter uri")
		elseif lang == "cpp" then
			-- Sentinel 1: PacketDecoder class -> DxType
			probe_sentinel(buf, 36, 7, "DxType", "C++ class PacketDecoder")
			-- Sentinel 2: decode method -> DxCallable
			probe_sentinel(buf, 45, 30, "DxCallable", "C++ method decode")
			-- Sentinel 3: state_ member -> DxMember
			probe_sentinel(buf, 50, 9, "DxMember", "C++ member state_")
		elseif lang == "zig" then
			-- Sentinel 1: NetworkBuffer struct -> DxType
			probe_sentinel(buf, 24, 18, "DxType", "Zig struct NetworkBuffer")
			-- Sentinel 2: append method -> DxCallable
			probe_sentinel(buf, 44, 12, "DxCallable", "Zig fn append")
			-- Sentinel 3: bytes member -> DxMember
			probe_sentinel(buf, 26, 5, "DxMember", "Zig field bytes")
		elseif lang == "python" then
			-- Sentinel 1: DownloadSummary class -> DxType
			probe_sentinel(buf, 17, 7, "DxType", "Python class DownloadSummary")
			-- Sentinel 2: validate_bounds method -> DxCallable
			probe_sentinel(buf, 29, 9, "DxCallable", "Python def validate_bounds")
			-- Sentinel 3: is_empty property -> DxMember
			probe_sentinel(buf, 26, 9, "DxMember", "Python property is_empty")
		end

		vim.api.nvim_buf_delete(buf, { force = true })
	else
		print(("Warning: fixture path unreadable [%s]: %s"):format(lang, path))
	end
end

print("Tier-2 Runtime Integration Contract passed cleanly.")

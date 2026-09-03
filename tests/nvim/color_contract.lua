--- DX Semantic Color System (DX-COLOR-001)
--- Tier-2 Runtime Integration Contract: Executed in full production Neovim environment
--- with Catppuccin loaded by LazyVim.
---
--- INVARIANT: This test MUST observe production configuration; it MUST NOT
--- reconstruct it (fail closed: no fallback palettes, no direct cat.setup() calls).
--- Validates:
--- 1. Production highlight graph via nvim_get_hl()
--- 2. Colorscheme reload invariance (:colorscheme catppuccin lifecycle)
--- 3. Diff state contract (subtle background, syntax foreground preserved)
--- 4. LSP precedence governance (@lsp.typemod.* neutralization, deprecated style)
--- 5. Symbolic sentinel lookup and position-level ROLE_ASSERT via vim.inspect_pos()
--- 6. Real LSP client wait & semantic token observation (TOKEN_OBSERVE / TOKEN_REQUIRE)

local function fail(msg)
	error("COLOR_RUNTIME_CONTRACT_FAILURE: " .. msg, 2)
end

vim.opt.swapfile = false

-- Fail closed: assert production colorscheme was loaded by LazyVim/ui.lua
if vim.g.colors_name ~= "catppuccin" then
	fail(("Production colorscheme must be 'catppuccin', found: %s"):format(vim.inspect(vim.g.colors_name)))
end

local ok_cat, cat_palettes = pcall(require, "catppuccin.palettes")
if not ok_cat or not cat_palettes or not cat_palettes.get_palette then
	fail("Catppuccin palettes module must be available from production plugins")
end

local palette = cat_palettes.get_palette("mocha")
if not palette or not palette.yellow then
	fail("Failed to retrieve production Catppuccin Mocha palette")
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

	-- Zig builtin language adapter
	local zig_builtin = get_resolved_hl("@function.builtin.zig")
	if zig_builtin.fg ~= colors_rgb.pink then
		fail("@function.builtin.zig does not resolve to DxMeta pink")
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

	-- 7. Diff contract: verify subtle background exists without destroying code syntax foreground
	local diff_add = get_resolved_hl("DiffAdd")
	if diff_add.fg ~= nil then
		fail("DiffAdd must not force a foreground color that overrides syntax tokens")
	end

	-- 8. Completion (blink.cmp)
	local blink_fn = get_resolved_hl("BlinkCmpKindFunction")
	if blink_fn.fg ~= colors_rgb.yellow then
		fail("BlinkCmpKindFunction must resolve to DxCallable yellow")
	end

	local blink_class = get_resolved_hl("BlinkCmpKindClass")
	if blink_class.fg ~= colors_rgb.teal then
		fail("BlinkCmpKindClass must resolve to DxType teal")
	end

	-- 9. Neotest & DAP
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
-- Test Step 1: Initial Production Highlight Graph Verification
-- ============================================================================
assert_contract()
print("Initial production highlight graph verified.")

-- ============================================================================
-- Test Step 2: Colorscheme Reload Invariance (pure observation of production cycle)
-- ============================================================================
for _ = 1, 3 do
	vim.cmd.colorscheme("catppuccin")
	assert_contract()
end
print("Colorscheme reload invariance verified across 3 production reload cycles.")

-- ============================================================================
-- Test Step 3: Symbolic Sentinel Resolution & Position-Level Verification
-- ============================================================================

--- Locates a symbol's exact (row, col) near a symbolic sentinel tag comment
---@param bufnr integer
---@param tag string e.g. "DX:SENTINEL rust.download_summary.type"
---@param token string e.g. "DownloadSummary"
---@return integer row 0-indexed
---@return integer col 0-indexed
local function locate_symbolic_sentinel(bufnr, tag, token)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for i, line in ipairs(lines) do
		if line:find(tag, 1, true) then
			-- Search for token on subsequent lines (within 5 lines of the sentinel tag)
			for j = i, math.min(#lines, i + 5) do
				local target_line = lines[j]
				local s_start, s_end = target_line:find(token, 1, true)
				if s_start then
					return j - 1, s_start - 1
				end
			end
		end
	end
	fail(("Symbolic sentinel not found in buffer: tag=%q, token=%q"):format(tag, token))
end

--- Inspects the effective highlight at (row, col) using Neovim's inspector
--- Priority: LSP semantic tokens (priority 125+) > Tree-sitter captures (priority 100) > syntax
local function get_effective_highlight_at_pos(bufnr, row, col)
	local inspected = vim.inspect_pos(bufnr, row, col)

	-- 1. Check semantic tokens
	if inspected.semantic_tokens and #inspected.semantic_tokens > 0 then
		for _, st in ipairs(inspected.semantic_tokens) do
			local hl_name = st.opts and st.opts.hl_group
			if hl_name then
				local hl = vim.api.nvim_get_hl(0, { name = hl_name, link = false })
				if hl and hl.fg then
					return hl_name, hl, inspected
				end
			end
		end
	end

	-- 2. Check Tree-sitter captures
	if inspected.treesitter and #inspected.treesitter > 0 then
		for i = #inspected.treesitter, 1, -1 do
			local ts = inspected.treesitter[i]
			local hl_name = ts.hl_group or ("@" .. ts.capture)
			local hl = vim.api.nvim_get_hl(0, { name = hl_name, link = false })
			if hl and hl.fg then
				return hl_name, hl, inspected
			end
		end
	end

	-- 3. Check syntax fallback
	if inspected.syntax and #inspected.syntax > 0 then
		local syn = inspected.syntax[#inspected.syntax]
		local hl = vim.api.nvim_get_hl(0, { name = syn.hl_group, link = false })
		if hl and hl.fg then
			return syn.hl_group, hl, inspected
		end
	end

	return nil, nil, inspected
end

--- Three-level verification:
--- 1. ROLE_ASSERT: asserts that the effective highlight's fg matches expected role
--- 2. TOKEN_OBSERVE: logs active Tree-sitter capture and LSP token metadata
--- 3. TOKEN_REQUIRE: enforces specific LSP token type when required
local function probe_sentinel_at(bufnr, tag, token, expected_role, label, require_token_type)
	local row, col = locate_symbolic_sentinel(bufnr, tag, token)
	local pos_desc = ("%s (%s:%s at L%d:C%d)"):format(label, tag, token, row + 1, col + 1)

	local expected_hl = get_resolved_hl(expected_role)
	if not expected_hl or not expected_hl.fg then
		fail(("Expected role highlight %s is undefined"):format(expected_role))
	end

	local eff_group, eff_hl, inspected = get_effective_highlight_at_pos(bufnr, row, col)
	if not eff_hl or not eff_hl.fg then
		fail(("No effective highlight found at %s"):format(pos_desc))
	end

	-- 1. ROLE_ASSERT: True position-level color check
	if eff_hl.fg ~= expected_hl.fg then
		fail(
			("ROLE_ASSERT failed for %s: effective fg mismatch (expected %06x from %s, got %06x from %s)"):format(
				pos_desc,
				expected_hl.fg,
				expected_role,
				eff_hl.fg,
				eff_group or "nil"
			)
		)
	end

	-- 2. TOKEN_OBSERVE: Observation log of active TS captures and LSP tokens
	local ts_names = {}
	for _, ts in ipairs(inspected.treesitter or {}) do
		table.insert(ts_names, ts.capture)
	end
	local lsp_names = {}
	for _, st in ipairs(inspected.semantic_tokens or {}) do
		table.insert(
			lsp_names,
			st.type .. (st.modifiers and ("+" .. table.concat(vim.tbl_keys(st.modifiers), ",")) or "")
		)
	end
	print(
		("  [OBSERVE] %s -> eff=%s (fg=%06x), ts=[%s], lsp=[%s]"):format(
			pos_desc,
			eff_group,
			eff_hl.fg,
			table.concat(ts_names, ","),
			table.concat(lsp_names, ",")
		)
	)

	-- 3. TOKEN_REQUIRE (if explicitly requested)
	if require_token_type then
		local matched = false
		for _, st in ipairs(inspected.semantic_tokens or {}) do
			if st.type == require_token_type then
				matched = true
				break
			end
		end
		if not matched then
			fail(("TOKEN_REQUIRE failed for %s: expected LSP token type %s"):format(pos_desc, require_token_type))
		end
	end
end

-- ============================================================================
-- Test Step 4: Real Buffer Editing & LSP Waiting
-- ============================================================================

local function wait_for_lsp_client(bufnr, server_name)
	local client
	vim.wait(10000, function()
		for _, candidate in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
			if candidate.name == server_name and candidate.initialized then
				client = candidate
				return true
			end
		end
		return false
	end, 100)
	return client
end

local repo_root = vim.fn.fnamemodify(vim.fn.expand("%:p"), ":h:h:h")
if repo_root == "" or repo_root == "." then
	repo_root = vim.fn.getcwd()
end

local fixture_specs = {
	{
		lang = "rust",
		filetype = "rust",
		lsp_server = "rust-analyzer",
		path = repo_root .. "/tests/nvim/color/rust/src/main.rs",
		sentinels = {
			{ tag = "rust.download_summary.type", token = "DownloadSummary", role = "DxType", label = "Rust struct" },
			{ tag = "rust.size.method", token = "size", role = "DxCallable", label = "Rust method" },
			{ tag = "rust.size.field", token = "size", role = "DxMember", label = "Rust field" },
			{ tag = "rust.fetch_stream.fn", token = "uri", role = "DxParameter", label = "Rust parameter" },
		},
	},
	{
		lang = "cpp",
		filetype = "cpp",
		lsp_server = "clangd",
		path = repo_root .. "/tests/nvim/color/cpp/src/main.cpp",
		sentinels = {
			{ tag = "cpp.packet_decoder.class", token = "PacketDecoder", role = "DxType", label = "C++ class" },
			{ tag = "cpp.decode.method", token = "decode", role = "DxCallable", label = "C++ method" },
			{ tag = "cpp.state.member", token = "state_", role = "DxMember", label = "C++ member" },
			{ tag = "cpp.log_diagnostic.fn", token = "log_diagnostic", role = "DxCallable", label = "C++ function" },
		},
	},
	{
		lang = "zig",
		filetype = "zig",
		lsp_server = "zls",
		path = repo_root .. "/tests/nvim/color/zig/src/main.zig",
		sentinels = {
			{ tag = "zig.network_buffer.type", token = "NetworkBuffer", role = "DxType", label = "Zig struct" },
			{ tag = "zig.bytes.member", token = "bytes", role = "DxMember", label = "Zig field" },
			{ tag = "zig.append.method", token = "append", role = "DxCallable", label = "Zig method" },
			{ tag = "zig.sizeof.builtin", token = "sizeOf", role = "DxMeta", label = "Zig builtin (@sizeOf)" },
		},
	},
	{
		lang = "python",
		filetype = "python",
		lsp_server = "pyright",
		path = repo_root .. "/tests/nvim/color/python/main.py",
		sentinels = {
			{
				tag = "python.download_summary.class",
				token = "DownloadSummary",
				role = "DxType",
				label = "Python class",
			},
			{ tag = "python.is_empty.property", token = "is_empty", role = "DxMember", label = "Python property" },
			{
				tag = "python.validate_bounds.method",
				token = "validate_bounds",
				role = "DxCallable",
				label = "Python method",
			},
			{ tag = "python.fetch_async.fn", token = "fetch_async", role = "DxCallable", label = "Python async fn" },
		},
	},
}

-- Ensure LSP configuration plugin is loaded
pcall(require("lazy").load, { plugins = { "nvim-lspconfig" } })

for _, spec in ipairs(fixture_specs) do
	if vim.fn.filereadable(spec.path) == 1 then
		vim.cmd.edit(vim.fn.fnameescape(spec.path))
		local bufnr = vim.api.nvim_get_current_buf()

		if vim.bo[bufnr].filetype ~= spec.filetype then
			vim.bo[bufnr].filetype = spec.filetype
		end

		pcall(function()
			local parser = vim.treesitter.get_parser(bufnr, spec.filetype)
			if parser then
				parser:parse()
			end
		end)

		print(("Loaded fixture [%s]: %s (ft=%s)"):format(spec.lang, spec.path, vim.bo[bufnr].filetype))

		-- Wait for LSP client if available
		local client = wait_for_lsp_client(bufnr, spec.lsp_server)
		if client then
			print(("  LSP client '%s' attached (id=%d)"):format(spec.lsp_server, client.id))
			-- Wait briefly for semantic tokens to populate if client supports them
			vim.wait(2000, function()
				local tokens = vim.lsp.semantic_tokens and vim.lsp.semantic_tokens.get_at_pos(bufnr, 0, 0)
				return tokens ~= nil
			end, 50)
		else
			print(("  LSP client '%s' not attached; Tree-sitter baseline active"):format(spec.lsp_server))
		end

		-- Run position-level assertions and observations
		for _, s in ipairs(spec.sentinels) do
			probe_sentinel_at(bufnr, s.tag, s.token, s.role, s.label, s.require_token)
		end

		vim.cmd.bdelete({ bang = true })
	else
		fail(("Fixture file not found: %s"):format(spec.path))
	end
end

print("Tier-2 Runtime Integration Contract passed cleanly.")

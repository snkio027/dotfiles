--- DX Semantic Color System (DX-COLOR-001)
--- Tier-2 Runtime Integration Contract: Executed in production Neovim environment
--- with Catppuccin loaded by LazyVim.
---
--- INVARIANTS:
--- 1. Must fail closed: observes production configuration, NEVER reconstructs it.
--- 2. Must ensure CI failure propagation: errors exit via :cquit 1 with full traceback.
--- 3. Symbolic sentinels must strictly search after marker comments on identifier boundaries.
--- 4. Real LSP Gate: lane-aware (Tier-2A in minimal locked lane, Tier-2B strict in devcontainer);
---    attached servers with semanticTokensProvider MUST generate tokens bound to client.id.
--- 5. Priority-based foreground resolution: inspect_pos extmarks & treesitter sorted by priority;
---    style-only groups (fg = nil) never shadow semantic foregrounds.
--- 6. Raw token observation from vim.lsp.semantic_tokens.get_at_pos().

local function main()
	local function fail(msg)
		error("COLOR_RUNTIME_CONTRACT_FAILURE: " .. msg, 2)
	end

	vim.opt.swapfile = false

	-- Fail closed: assert production colorscheme was loaded by LazyVim/ui.lua
	local name = vim.g.colors_name
	if name ~= "catppuccin" and name ~= "catppuccin-mocha" then
		fail(("Production colorscheme must be 'catppuccin' or 'catppuccin-mocha', found: %s"):format(vim.inspect(name)))
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
	local function get_resolved_hl(hl_name)
		return vim.api.nvim_get_hl(0, { name = hl_name, link = false })
	end

	-- Verify production theme is truly using Mocha base palette
	local normal = get_resolved_hl("Normal")
	if normal.bg ~= colors_rgb.base then
		fail(
			("Production theme is not using Catppuccin Mocha base (expected %06x, got %s)"):format(
				colors_rgb.base,
				normal.bg and ("%06x"):format(normal.bg) or "nil"
			)
		)
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

		-- Zig builtin language adapter (@function.builtin.zig -> DxMeta)
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
		for _, diff_grp in ipairs({ "DiffAdd", "DiffChange", "DiffDelete", "DiffText" }) do
			local diff_hl = get_resolved_hl(diff_grp)
			if diff_hl.fg ~= nil then
				fail(("%s must not force a foreground color that overrides syntax tokens"):format(diff_grp))
			end
			if diff_hl.bg == nil then
				fail(("%s must define a background state"):format(diff_grp))
			end
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
	-- Test Step 3: Symbolic Sentinel Resolution
	-- ============================================================================

	--- Locates a symbol's exact (row, col) strictly AFTER the symbolic sentinel marker comment
	---@param bufnr integer
	---@param tag string e.g. "DX:SENTINEL rust.size.method"
	---@param token string e.g. "size"
	---@return integer row 0-indexed
	---@return integer col 0-indexed
	---@return string target_line
	---@return integer comment_row 0-indexed
	local function locate_symbolic_sentinel(bufnr, tag, token)
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		for i, line in ipairs(lines) do
			if line:find(tag, 1, true) then
				-- MUST search lines strictly AFTER the marker comment (i + 1 onwards)
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
		fail(("Symbolic sentinel not found in buffer: tag=%q, token=%q"):format(tag, token))
	end

	--- Priority-based foreground resolution:
	--- Collects all candidate groups with a non-nil fg from:
	--- 1. LSP semantic tokens extmarks (priority 125+)
	--- 2. Tree-sitter captures (priority 100 via Neovim :Inspect hierarchy)
	--- 3. Syntax items (priority 50)
	--- Sorts by priority descending. Highest priority candidate wins.
	--- Style-only groups (like deprecated with fg = nil) do not shadow semantic fg.
	local function get_effective_highlight_at_pos(bufnr, row, col)
		local inspected = vim.inspect_pos(bufnr, row, col)
		local candidates = {}

		local sem_default_prio = (vim.hl and vim.hl.priorities and vim.hl.priorities.semantic_tokens) or 125
		local ts_default_prio = (vim.hl and vim.hl.priorities and vim.hl.priorities.treesitter) or 100
		local syn_default_prio = (vim.hl and vim.hl.priorities and vim.hl.priorities.syntax) or 50

		-- 1. Semantic token extmarks
		for i, st in ipairs(inspected.semantic_tokens or {}) do
			local hl_name = st.opts and st.opts.hl_group
			if hl_name then
				local hl = vim.api.nvim_get_hl(0, { name = hl_name, link = false })
				if hl and hl.fg then
					table.insert(candidates, {
						hl_name = hl_name,
						priority = tonumber(st.opts and st.opts.priority) or sem_default_prio,
						fg = hl.fg,
						order = i,
						source = "semantic_tokens",
					})
				end
			end
		end

		-- 2. General extmarks in semantic tokens namespace
		for i, ext in ipairs(inspected.extmarks or {}) do
			local hl_name = ext.opts and ext.opts.hl_group
			local ext_prio = tonumber(ext.opts and ext.opts.priority)
			if hl_name and ((ext.ns and ext.ns:find("semantic_tokens")) or (ext_prio and ext_prio >= 120)) then
				local hl = vim.api.nvim_get_hl(0, { name = hl_name, link = false })
				if hl and hl.fg then
					table.insert(candidates, {
						hl_name = hl_name,
						priority = ext_prio or sem_default_prio,
						fg = hl.fg,
						order = i,
						source = "semantic_tokens",
					})
				end
			end
		end

		-- 3. Tree-sitter captures (using Neovim :Inspect priority hierarchy)
		-- Later captures in traversal order override earlier captures at equal priority
		for i, ts in ipairs(inspected.treesitter or {}) do
			local hl_name = ts.hl_group or ("@" .. ts.capture)
			local hl = vim.api.nvim_get_hl(0, { name = hl_name, link = false })
			if hl and hl.fg then
				local raw_prio = (ts.metadata and ts.metadata.priority)
					or (ts.metadata and ts.id and ts.metadata[ts.id] and ts.metadata[ts.id].priority)
				local prio = tonumber(raw_prio) or ts_default_prio
				table.insert(candidates, {
					hl_name = hl_name,
					priority = prio,
					fg = hl.fg,
					order = i,
					source = "treesitter",
				})
			end
		end

		-- 4. Syntax items fallback
		for i, syn in ipairs(inspected.syntax or {}) do
			local hl_name = syn.hl_group
			if hl_name then
				local hl = vim.api.nvim_get_hl(0, { name = hl_name, link = false })
				if hl and hl.fg then
					table.insert(candidates, {
						hl_name = hl_name,
						priority = syn_default_prio,
						fg = hl.fg,
						order = i,
						source = "syntax",
					})
				end
			end
		end

		if #candidates == 0 then
			return nil, nil, inspected, candidates
		end

		-- Sort by priority descending; on tie, later traversal order wins
		table.sort(candidates, function(a, b)
			local pa = tonumber(a.priority) or 0
			local pb = tonumber(b.priority) or 0
			if pa ~= pb then
				return pa > pb
			end
			local oa = tonumber(a.order) or 0
			local ob = tonumber(b.order) or 0
			return oa > ob
		end)

		local best = candidates[1]
		local resolved_hl = vim.api.nvim_get_hl(0, { name = best.hl_name, link = false })
		return best.hl_name, resolved_hl, inspected, candidates
	end

	--- Three-level verification:
	--- 1. ROLE_ASSERT: asserts that the effective highlight's fg matches expected role
	--- 2. TOKEN_OBSERVE: logs active Tree-sitter captures and raw LSP tokens from get_at_pos()
	--- 3. TOKEN_REQUIRE: enforces specific raw LSP token type when required
	local function probe_sentinel_at(bufnr, tag, token, expected_role, label, require_token_type)
		local row, col, target_line, comment_row = locate_symbolic_sentinel(bufnr, tag, token)
		local pos_desc = ("%s (%s:%s at L%d:C%d)"):format(label, tag, token, row + 1, col + 1)

		-- Guard: sentinel must never resolve to the comment marker line
		if row <= comment_row then
			fail(("LOCATOR ERROR: %s resolved to comment row %d"):format(pos_desc, comment_row + 1))
		end

		local expected_hl = get_resolved_hl(expected_role)
		if not expected_hl or not expected_hl.fg then
			fail(("Expected role highlight %s is undefined"):format(expected_role))
		end

		local eff_group, eff_hl, inspected, candidates = get_effective_highlight_at_pos(bufnr, row, col)
		if not eff_hl or not eff_hl.fg then
			fail(("No effective highlight found at %s (line: %s)"):format(pos_desc, vim.trim(target_line)))
		end

		-- 1. ROLE_ASSERT: True position-level color check
		if eff_hl.fg ~= expected_hl.fg then
			fail(
				("ROLE_ASSERT failed for %s: effective fg mismatch (expected %06x from %s, got %06x from %s, prio=%d)"):format(
					pos_desc,
					expected_hl.fg,
					expected_role,
					eff_hl.fg,
					eff_group or "nil",
					candidates and candidates[1] and candidates[1].priority or -1
				)
			)
		end

		-- 2. TOKEN_OBSERVE: Fetch raw tokens directly from vim.lsp.semantic_tokens.get_at_pos()
		local raw_lsp_tokens = {}
		if vim.lsp and vim.lsp.semantic_tokens and vim.lsp.semantic_tokens.get_at_pos then
			local raw = vim.lsp.semantic_tokens.get_at_pos(bufnr, row, col)
			for _, tok in ipairs(raw or {}) do
				local mod_list = {}
				if tok.modifiers then
					for m, active in pairs(tok.modifiers) do
						if active then
							table.insert(mod_list, m)
						end
					end
				end
				table.insert(
					raw_lsp_tokens,
					("type=%s, mods=[%s], client=%s"):format(
						tok.type or "nil",
						table.concat(mod_list, ","),
						tostring(tok.client_id or "nil")
					)
				)
			end
		end

		local ts_captures = {}
		for _, ts in ipairs(inspected.treesitter or {}) do
			table.insert(
				ts_captures,
				ts.capture .. "(prio=" .. tostring((ts.metadata and ts.metadata.priority) or 100) .. ")"
			)
		end

		print(
			("  [OBSERVE] %s -> eff=%s (fg=%06x, prio=%d), ts=[%s], lsp=[%s]"):format(
				pos_desc,
				eff_group,
				eff_hl.fg,
				candidates[1].priority,
				table.concat(ts_captures, ", "),
				table.concat(raw_lsp_tokens, "; ")
			)
		)

		-- 3. TOKEN_REQUIRE (if explicitly requested)
		if require_token_type then
			local matched = false
			if vim.lsp and vim.lsp.semantic_tokens and vim.lsp.semantic_tokens.get_at_pos then
				local raw = vim.lsp.semantic_tokens.get_at_pos(bufnr, row, col)
				for _, tok in ipairs(raw or {}) do
					if tok.type == require_token_type then
						matched = true
						break
					end
				end
			end
			if not matched then
				fail(
					("TOKEN_REQUIRE failed for %s: expected raw LSP token type %s"):format(pos_desc, require_token_type)
				)
			end
		end
	end

	-- ============================================================================
	-- Test Step 4: Real Buffer Editing & Lane-Aware LSP Gate
	-- ============================================================================

	local strict_lsp = (vim.env.DOTFILES_STRICT_LSP == "1")
	if strict_lsp then
		print("Strict LSP Gate active: All 4 language servers required.")
	else
		print("Standard LSP Gate active: Attached servers verified; Tree-sitter baseline authoritative.")
	end

	local function wait_for_lsp_client(bufnr, expected_names, required)
		local client
		local attached = vim.wait(10000, function()
			for _, candidate in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
				for _, name in ipairs(expected_names) do
					if candidate.name == name and candidate.initialized then
						client = candidate
						return true
					end
				end
			end
			return false
		end, 100)
		if required then
			assert(
				attached and client,
				("Strict LSP Gate: required client %s did not attach to fixture (bufnr=%d)"):format(
					vim.inspect(expected_names),
					bufnr
				)
			)
		end
		return client
	end

	local function wait_for_semantic_tokens(bufnr, client, sentinels)
		assert(
			client.server_capabilities.semanticTokensProvider ~= nil,
			("LSP server %s does not advertise semanticTokensProvider"):format(client.name)
		)

		-- Force refresh semantic tokens for this buffer
		if vim.lsp.semantic_tokens and vim.lsp.semantic_tokens.force_refresh then
			vim.lsp.semantic_tokens.force_refresh(bufnr)
		elseif vim.lsp.semantic_tokens and vim.lsp.semantic_tokens.refresh then
			vim.lsp.semantic_tokens.refresh(bufnr)
		end

		-- Wait until semantic tokens from this client are returned on at least one sentinel
		local tokens_ready = vim.wait(15000, function()
			for _, s in ipairs(sentinels) do
				local r, c = locate_symbolic_sentinel(bufnr, s.tag, s.token)
				local raw_toks = vim.lsp.semantic_tokens.get_at_pos(bufnr, r, c)
				for _, tok in ipairs(raw_toks or {}) do
					if tok.client_id == client.id then
						return true
					end
				end
			end
			return false
		end, 100)

		assert(
			tokens_ready,
			("Semantic tokens from client %s (id=%d) were not populated for buffer %d"):format(
				client.name,
				client.id,
				bufnr
			)
		)
	end

	local repo_root = vim.fs.root(0, ".git") or vim.fn.getcwd()

	local fixture_specs = {
		{
			lang = "rust",
			filetype = "rust",
			lsp_servers = { "rust-analyzer", "rust_analyzer" },
			path = repo_root .. "/tests/nvim/color/rust/src/main.rs",
			sentinels = {
				{
					tag = "rust.download_summary.type",
					token = "DownloadSummary",
					role = "DxType",
					label = "Rust struct",
				},
				{ tag = "rust.size.method", token = "size", role = "DxCallable", label = "Rust method" },
				{ tag = "rust.size.field", token = "size", role = "DxMember", label = "Rust field" },
				{ tag = "rust.fetch_stream.fn", token = "uri", role = "DxParameter", label = "Rust parameter" },
			},
		},
		{
			lang = "cpp",
			filetype = "cpp",
			lsp_servers = { "clangd" },
			path = repo_root .. "/tests/nvim/color/cpp/src/main.cpp",
			sentinels = {
				{ tag = "cpp.packet_decoder.class", token = "PacketDecoder", role = "DxType", label = "C++ class" },
				{ tag = "cpp.decode.method", token = "decode", role = "DxCallable", label = "C++ method" },
				{ tag = "cpp.state.member", token = "state_", role = "DxMember", label = "C++ member" },
				{
					tag = "cpp.log_diagnostic.fn",
					token = "log_diagnostic",
					role = "DxCallable",
					label = "C++ function",
				},
			},
		},
		{
			lang = "zig",
			filetype = "zig",
			lsp_servers = { "zls" },
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
			lsp_servers = { "pyright" },
			path = repo_root .. "/tests/nvim/color/python/main.py",
			sentinels = {
				{
					tag = "python.download_summary.class",
					token = "DownloadSummary",
					role = "DxType",
					label = "Python class",
				},
				{ tag = "python.size.member", token = "size", role = "DxMember", label = "Python member" },
				{
					tag = "python.validate_bounds.method",
					token = "validate_bounds",
					role = "DxCallable",
					label = "Python method",
				},
				{
					tag = "python.fetch_async.fn",
					token = "fetch_async",
					role = "DxCallable",
					label = "Python async fn",
				},
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

			-- Trigger Tree-sitter parse
			pcall(function()
				local parser = vim.treesitter.get_parser(bufnr, spec.filetype)
				if parser then
					parser:parse()
				end
			end)

			print(("Loaded fixture [%s]: %s (ft=%s)"):format(spec.lang, spec.path, vim.bo[bufnr].filetype))

			-- Lane-aware LSP check
			local client = wait_for_lsp_client(bufnr, spec.lsp_servers, strict_lsp)
			if client then
				print(("  LSP client '%s' attached (id=%d)"):format(client.name, client.id))
				-- If server supports semantic tokens, require real token generation from this client
				if client.server_capabilities.semanticTokensProvider ~= nil then
					wait_for_semantic_tokens(bufnr, client, spec.sentinels)
					print(("  Semantic tokens populated and verified for %s (id=%d)"):format(client.name, client.id))
				else
					print(
						("  LSP server '%s' does not provide semantic tokens (capability-aware); Tree-sitter active"):format(
							client.name
						)
					)
				end
			else
				print(
					("  LSP client %s not installed in minimal profile; Tree-sitter baseline verified"):format(
						vim.inspect(spec.lsp_servers)
					)
				)
			end

			vim.cmd.redraw()

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
end

-- Top-level failure trap ensuring non-zero exit code on failure
local ok, err = xpcall(main, debug.traceback)
if not ok then
	io.stderr:write(("\n!!! TIER-2 CONTRACT FAILURE !!!\n%s\n"):format(tostring(err)))
	vim.api.nvim_err_writeln(("\n!!! TIER-2 CONTRACT FAILURE !!!\n%s\n"):format(tostring(err)))
	vim.cmd("cquit 1")
end

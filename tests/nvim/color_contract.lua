--- DX Semantic Color System (DX-COLOR-002)
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
--- 7. Capture-Level Proof: Tree-sitter query extension captures lifetime ('a, 'static) as
---    @type.lifetime.rust while leaving normal attributes (#[must_use]) as DxMeta.

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

	local cat_mocha = cat_palettes.get_palette("mocha")
	if not cat_mocha or not cat_mocha.yellow then
		fail("Failed to retrieve production Catppuccin Mocha palette")
	end

	local ok_pal, palette_mod = pcall(require, "theme.palette")
	if not ok_pal or not palette_mod.resolve then
		fail("theme.palette module must be available from production theme")
	end

	local p = palette_mod.resolve(cat_mocha)

	local function hex_to_rgb(hex)
		if not hex then
			return nil
		end
		return tonumber(hex:gsub("^#", ""), 16)
	end

	local colors_rgb = {
		-- Source Semantic Roles (DX-COLOR-002 Muted Palette)
		variable = hex_to_rgb(p.code.variable),
		callable = hex_to_rgb(p.code.callable),
		type = hex_to_rgb(p.code.type),
		lifetime = hex_to_rgb(p.code.lifetime),
		string = hex_to_rgb(p.code.string),
		member = hex_to_rgb(p.code.member),
		operator = hex_to_rgb(p.code.operator),
		keyword = hex_to_rgb(p.code.keyword),
		meta = hex_to_rgb(p.code.meta),
		builtin = hex_to_rgb(p.code.builtin),
		parameter = hex_to_rgb(p.code.parameter),
		constant = hex_to_rgb(p.code.constant),
		doc = hex_to_rgb(p.code.doc),
		namespace = hex_to_rgb(p.code.namespace),
		number = hex_to_rgb(p.code.number),
		label = hex_to_rgb(p.code.label),
		punctuation = hex_to_rgb(p.code.punctuation),
		comment = hex_to_rgb(p.code.comment),

		-- State & Transient Roles
		error = hex_to_rgb(p.state.error),
		warn = hex_to_rgb(p.state.warn),
		info = hex_to_rgb(p.state.info),
		hint = hex_to_rgb(p.state.hint),
		success = hex_to_rgb(p.state.success),

		-- UI Chrome
		base = hex_to_rgb(p.ui.base),
		mantle = hex_to_rgb(p.ui.mantle),
		surface0 = hex_to_rgb(p.ui.surface0),
		surface1 = hex_to_rgb(p.ui.surface1),
		surface2 = hex_to_rgb(p.ui.surface2),
		text = hex_to_rgb(p.ui.text),
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
		-- 1. All 22 Semantic Roles
		local role_assertions = {
			{ "DxKeyword", colors_rgb.keyword, "keyword" },
			{ "DxCallable", colors_rgb.callable, "callable" },
			{ "DxType", colors_rgb.type, "type" },
			{ "DxBuiltin", colors_rgb.builtin, "builtin" },
			{ "DxLifetime", colors_rgb.lifetime, "lifetime" },
			{ "DxMember", colors_rgb.member, "member" },
			{ "DxParameter", colors_rgb.parameter, "parameter" },
			{ "DxVariable", colors_rgb.variable, "variable" },
			{ "DxMeta", colors_rgb.meta, "meta" },
			{ "DxNamespace", colors_rgb.namespace, "namespace" },
			{ "DxString", colors_rgb.string, "string" },
			{ "DxNumber", colors_rgb.number, "number" },
			{ "DxConstant", colors_rgb.constant, "constant" },
			{ "DxLabel", colors_rgb.label, "label" },
			{ "DxOperator", colors_rgb.operator, "operator" },
			{ "DxPunctuation", colors_rgb.punctuation, "punctuation" },
			{ "DxComment", colors_rgb.comment, "comment" },
			{ "DxDocComment", colors_rgb.doc, "doc" },
			{ "DxError", colors_rgb.error, "error" },
			{ "DxWarn", colors_rgb.warn, "warn" },
			{ "DxInfo", colors_rgb.info, "info" },
			{ "DxHint", colors_rgb.hint, "hint" },
		}

		for _, item in ipairs(role_assertions) do
			local hl = get_resolved_hl(item[1])
			if hl.fg ~= item[2] then
				fail(
					("%s fg mismatch: expected %06x (%s), got %s"):format(
						item[1],
						item[2],
						item[3],
						hl.fg and ("%06x"):format(hl.fg) or "nil"
					)
				)
			end
		end

		-- Yellow Scarcity Check on production theme: DxCallable must NOT use yellow
		if colors_rgb.callable == colors_rgb.warn then
			fail("Yellow Scarcity violation: DxCallable is mapped to state yellow")
		end

		-- 2. Tree-sitter link resolution
		local ts_assertions = {
			{ "@keyword", colors_rgb.keyword },
			{ "@function", colors_rgb.callable },
			{ "@function.call", colors_rgb.callable },
			{ "@function.method", colors_rgb.callable },
			{ "@type", colors_rgb.type },
			{ "@type.builtin", colors_rgb.builtin },
			{ "@type.lifetime", colors_rgb.lifetime },
			{ "@type.lifetime.rust", colors_rgb.lifetime },
			{ "@property", colors_rgb.member },
			{ "@variable.member", colors_rgb.member },
			{ "@variable", colors_rgb.variable },
			{ "@function.macro", colors_rgb.meta },
			{ "@constant.macro", colors_rgb.meta },
			{ "@label", colors_rgb.label },
			{ "@string", colors_rgb.string },
			{ "@string.regexp", colors_rgb.string },
			{ "@function.builtin.zig", colors_rgb.meta },
		}
		for _, item in ipairs(ts_assertions) do
			local hl = get_resolved_hl(item[1])
			if hl.fg ~= item[2] then
				fail(
					("Tree-sitter mapping mismatch for %s: expected fg %06x, got %s"):format(
						item[1],
						item[2],
						hl.fg and ("%06x"):format(hl.fg) or "nil"
					)
				)
			end
		end

		-- 3. LSP Standard base tokens closure
		local lsp_assertions = {
			{ "@lsp.type.keyword", colors_rgb.keyword },
			{ "@lsp.type.modifier", colors_rgb.keyword },
			{ "@lsp.type.function", colors_rgb.callable },
			{ "@lsp.type.method", colors_rgb.callable },
			{ "@lsp.type.class", colors_rgb.type },
			{ "@lsp.type.struct", colors_rgb.type },
			{ "@lsp.type.typeParameter", colors_rgb.type },
			{ "@lsp.type.property", colors_rgb.member },
			{ "@lsp.type.string", colors_rgb.string },
			{ "@lsp.type.regexp", colors_rgb.string },
			{ "@lsp.type.label", colors_rgb.label },
			{ "@lsp.type.lifetime", colors_rgb.lifetime },
			{ "@lsp.type.builtinType", colors_rgb.builtin },
			{ "@lsp.type.typeAlias", colors_rgb.type },
			{ "@lsp.type.union", colors_rgb.type },
			{ "@lsp.type.selfTypeKeyword", colors_rgb.type },
			{ "@lsp.type.concept", colors_rgb.type },
			{ "@lsp.type.builtin", colors_rgb.meta },
			{ "@lsp.type.keywordLiteral", colors_rgb.constant },
			{ "@lsp.type.errorTag", colors_rgb.constant },
			{ "@lsp.type.escapeSequence", colors_rgb.string },
		}
		for _, item in ipairs(lsp_assertions) do
			local hl = get_resolved_hl(item[1])
			if hl.fg ~= item[2] then
				fail(
					("LSP mapping mismatch for %s: expected fg %06x, got %s"):format(
						item[1],
						item[2],
						hl.fg and ("%06x"):format(hl.fg) or "nil"
					)
				)
			end
		end

		-- 4. Precedence Governance: Neutralized typemods & Type-Family Governance
		local typemod_var_readonly = get_resolved_hl("@lsp.typemod.variable.readonly")
		if typemod_var_readonly.fg ~= colors_rgb.variable then
			fail(
				("@lsp.typemod.variable.readonly fg mismatch: expected %06x (variable), got %s"):format(
					colors_rgb.variable,
					typemod_var_readonly.fg and ("%06x"):format(typemod_var_readonly.fg) or "nil"
				)
			)
		end

		local typemod_struct_decl = get_resolved_hl("@lsp.typemod.struct.declaration")
		if typemod_struct_decl.fg ~= colors_rgb.type then
			fail("@lsp.typemod.struct.declaration fg mismatch: expected type")
		end

		local typemod_class_deflib = get_resolved_hl("@lsp.typemod.class.defaultLibrary")
		if typemod_class_deflib.fg ~= colors_rgb.type then
			fail("@lsp.typemod.class.defaultLibrary fg mismatch: expected type")
		end

		local typemod_c_primitive = get_resolved_hl("@lsp.typemod.type.defaultLibrary.c")
		if typemod_c_primitive.fg ~= colors_rgb.builtin then
			fail("@lsp.typemod.type.defaultLibrary.c fg mismatch: expected builtin")
		end

		local typemod_cpp_primitive = get_resolved_hl("@lsp.typemod.type.defaultLibrary.cpp")
		if typemod_cpp_primitive.fg ~= colors_rgb.builtin then
			fail("@lsp.typemod.type.defaultLibrary.cpp fg mismatch: expected builtin")
		end

		local typemod_fn_deprecated = get_resolved_hl("@lsp.typemod.function.deprecated")
		if not typemod_fn_deprecated.strikethrough then
			fail("@lsp.typemod.function.deprecated must have strikethrough enabled")
		end

		-- 5. Editor UI Chrome (Yellow Scarcity applied: CurSearch uses state warn yellow)
		local cur_search = get_resolved_hl("CurSearch")
		if cur_search.bg ~= colors_rgb.warn then
			fail("CurSearch bg must be state yellow")
		end

		-- 6. Diagnostics
		local diag_error = get_resolved_hl("DiagnosticError")
		if diag_error.fg ~= colors_rgb.error then
			fail("DiagnosticError fg must be state error red")
		end

		local diag_warn = get_resolved_hl("DiagnosticWarn")
		if diag_warn.fg ~= colors_rgb.warn then
			fail("DiagnosticWarn fg must be state warn yellow")
		end

		local diag_undercurl = get_resolved_hl("DiagnosticUnderlineError")
		if not diag_undercurl.undercurl or diag_undercurl.sp ~= colors_rgb.error then
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
		if blink_fn.fg ~= colors_rgb.callable then
			fail("BlinkCmpKindFunction must resolve to DxCallable")
		end

		local blink_class = get_resolved_hl("BlinkCmpKindClass")
		if blink_class.fg ~= colors_rgb.type then
			fail("BlinkCmpKindClass must resolve to DxType")
		end

		-- 9. Neotest & DAP
		local neotest_passed = get_resolved_hl("NeotestPassed")
		if neotest_passed.fg ~= colors_rgb.success then
			fail("NeotestPassed must resolve to success green")
		end

		local dap_breakpoint = get_resolved_hl("DapBreakpoint")
		if dap_breakpoint.fg ~= colors_rgb.error then
			fail("DapBreakpoint must resolve to error red")
		end

		local dap_stopped = get_resolved_hl("DapStopped")
		if dap_stopped.fg ~= colors_rgb.warn then
			fail("DapStopped must resolve to warn yellow")
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

	--- Locates a symbol's exact (row, col) strictly AFTER the symbolic sentinel marker comment
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
		fail(("Symbolic sentinel not found in buffer: tag=%q, token=%q, lang=%q"):format(tag, token, tostring(lang)))
	end

	--- Priority-based foreground resolution:
	--- Collects all candidate groups with a non-nil fg from extmarks, treesitter, and syntax.
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
	--- 2. CAPTURE_PROOF: asserts required or forbidden Tree-sitter captures (e.g. lifetime vs attribute)
	--- 3. TOKEN_OBSERVE: logs active Tree-sitter captures and raw LSP tokens from get_at_pos()
	local function probe_sentinel_at(bufnr, sentinel, lang)
		local row, col, target_line, comment_row = locate_symbolic_sentinel(bufnr, sentinel.tag, sentinel.token, lang)
		local pos_desc = ("%s (%s:%s at L%d:C%d)"):format(
			sentinel.desc or sentinel.tag,
			sentinel.tag,
			sentinel.token,
			row + 1,
			col + 1
		)

		if row <= comment_row then
			fail(("LOCATOR ERROR: %s resolved to comment row %d"):format(pos_desc, comment_row + 1))
		end

		local expected_hl = get_resolved_hl(sentinel.role)
		if not expected_hl or not expected_hl.fg then
			fail(("Expected role highlight %s is undefined"):format(sentinel.role))
		end

		local eff_group, eff_hl, inspected, candidates = get_effective_highlight_at_pos(bufnr, row, col)
		if not eff_hl or not eff_hl.fg then
			fail(("No effective highlight found at %s (line: %s)"):format(pos_desc, vim.trim(target_line)))
		end

		-- 1. ROLE_ASSERT: True position-level color check
		if eff_hl.fg ~= expected_hl.fg then
			local cand_summary = {}
			for _, c in ipairs(candidates or {}) do
				table.insert(
					cand_summary,
					("%s(src=%s, prio=%d, fg=%06x, ord=%d)"):format(c.hl_name, c.source, c.priority, c.fg, c.order or 0)
				)
			end
			fail(
				(
					"ROLE_ASSERT mismatch for %s:\n"
					.. "  Expected fg: %06x (%s)\n"
					.. "  Actual fg:   %06x (from group: %s)\n"
					.. "  Candidates:  %s"
				):format(
					pos_desc,
					expected_hl.fg,
					sentinel.role,
					eff_hl.fg,
					eff_group or "nil",
					table.concat(cand_summary, " -> ")
				)
			)
		end

		-- 2. CAPTURE_PROOF: Tree-sitter query extension validation
		if sentinel.required_ts_capture then
			local found_capture = false
			for _, ts in ipairs(inspected.treesitter or {}) do
				if
					ts.hl_group == ("@" .. sentinel.required_ts_capture)
					or (ts.capture .. "." .. lang) == sentinel.required_ts_capture
				then
					found_capture = true
					break
				end
			end
			if not found_capture then
				local actual_caps = {}
				for _, ts in ipairs(inspected.treesitter or {}) do
					table.insert(actual_caps, ts.hl_group or ts.capture)
				end
				fail(
					(
						"CAPTURE_PROOF FAILED for %s:\n"
						.. "  Expected required capture: %s\n"
						.. "  Actual captures:           [%s]"
					):format(pos_desc, sentinel.required_ts_capture, table.concat(actual_caps, ", "))
				)
			end
		end

		if sentinel.forbidden_ts_capture then
			for _, ts in ipairs(inspected.treesitter or {}) do
				if
					ts.hl_group == ("@" .. sentinel.forbidden_ts_capture)
					or (ts.capture .. "." .. lang) == sentinel.forbidden_ts_capture
				then
					fail(
						("CAPTURE_PROOF FAILED for %s: contains forbidden capture %s"):format(
							pos_desc,
							sentinel.forbidden_ts_capture
						)
					)
				end
			end
		end

		-- 3. TOKEN_OBSERVE: Raw inspection logging
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
	end

	-- ============================================================================
	-- Test Step 4: Real Buffer Editing & Lane-Aware LSP Gate
	-- ============================================================================

	local strict_lsp = (vim.env.DOTFILES_STRICT_LSP == "1")
	if strict_lsp then
		print("Strict LSP Gate active: All 4 language servers required across 5 fixtures.")
	else
		print("Standard LSP Gate active: Attached servers verified; Tree-sitter baseline authoritative.")
	end

	local function wait_for_lsp_client(bufnr, expected_names, required)
		local client
		local attached = vim.wait(10000, function()
			for _, candidate in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
				for _, c_name in ipairs(expected_names) do
					if candidate.name == c_name and candidate.initialized then
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

	local function wait_for_semantic_tokens(bufnr, client, sentinels, lang)
		assert(
			client.server_capabilities.semanticTokensProvider ~= nil,
			("LSP server %s does not advertise semanticTokensProvider"):format(client.name)
		)

		if vim.lsp.semantic_tokens and vim.lsp.semantic_tokens.force_refresh then
			vim.lsp.semantic_tokens.force_refresh(bufnr)
		elseif vim.lsp.semantic_tokens and vim.lsp.semantic_tokens.refresh then
			vim.lsp.semantic_tokens.refresh(bufnr)
		end

		local tokens_ready = vim.wait(15000, function()
			for _, s in ipairs(sentinels) do
				local r, c = locate_symbolic_sentinel(bufnr, s.tag, s.token, lang)
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

	local ok_manifest, manifest = pcall(dofile, repo_root .. "/tests/nvim/color_manifest.lua")
	if not ok_manifest or not manifest.languages then
		fail("Failed to load tests/nvim/color_manifest.lua")
	end

	-- Language execution order: rust, c, cpp, zig, python
	local lang_order = { "rust", "c", "cpp", "zig", "python" }

	-- Ensure LSP configuration plugin is loaded
	pcall(require("lazy").load, { plugins = { "nvim-lspconfig" } })

	for _, lang_key in ipairs(lang_order) do
		local spec = manifest.languages[lang_key]
		if not spec then
			fail("Missing language spec in manifest: " .. lang_key)
		end
		local fixture_path = repo_root .. "/" .. spec.path

		if vim.fn.filereadable(fixture_path) == 1 then
			vim.cmd.edit(vim.fn.fnameescape(fixture_path))
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

			print(("Loaded fixture [%s]: %s (ft=%s)"):format(lang_key, fixture_path, vim.bo[bufnr].filetype))

			-- Lane-aware LSP check
			local client = wait_for_lsp_client(bufnr, spec.lsp, strict_lsp)
			if client then
				print(("  LSP client '%s' attached (id=%d)"):format(client.name, client.id))
				if client.server_capabilities.semanticTokensProvider ~= nil then
					wait_for_semantic_tokens(bufnr, client, spec.sentinels, lang_key)
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
						vim.inspect(spec.lsp)
					)
				)
			end

			vim.cmd.redraw()

			-- Run position-level assertions and capture proofs
			for _, s in ipairs(spec.sentinels) do
				probe_sentinel_at(bufnr, s, lang_key)
			end

			vim.cmd.bdelete({ bang = true })
		else
			fail(("Fixture file not found: %s"):format(fixture_path))
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

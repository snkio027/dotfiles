-- Native clangd evidence, independent expected roles and actual foregrounds.
-- Empty vendor macros reproduce parser recovery without an SDK dependency.
return function(effective, repo_root)
	local evidence = dofile(repo_root .. "/tests/nvim/highlight_evidence.lua")
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	local source = {
		"#define VENDOR_ATTR",
		"#define VENDOR_BEGIN namespace vendor {",
		"#define VENDOR_END }",
		"struct Record {};",
		"using Plain = int;",
		"using Scalar VENDOR_ATTR = int;",
		"using Object VENDOR_ATTR = Record;",
		"template<class T> using Pointer VENDOR_ATTR = T*;",
		"VENDOR_BEGIN",
		"using Wrapped VENDOR_ATTR = int;",
		"VENDOR_END",
		"Plain plain; Scalar scalar; Object object; Pointer<int> pointer; vendor::Wrapped wrapped;",
		"int number = 0;",
		"bool boolean = false;",
		"unsigned long width = 0;",
		"auto inferred = 1;",
		"decltype(number) exact = 2;",
		"decltype(auto) reference = (number);",
		"int shadow() { int Scalar = 3; return Scalar; }",
		"#if 0",
		"using Dormant VENDOR_ATTR = int;",
		"Dormant sleeping;",
		"auto inactive_auto = 1;",
		"decltype(number) inactive_decltype;",
		"#endif",
	}
	vim.fn.writefile(source, root .. "/types.cpp")
	vim.fn.writefile({ "-std=c++23" }, root .. "/compile_flags.txt")
	local previous, foldenable = vim.api.nvim_get_current_buf(), vim.wo.foldenable
	local buf, client
	local ok, err = xpcall(function()
		vim.cmd("noautocmd edit " .. vim.fn.fnameescape(root .. "/types.cpp"))
		buf = vim.api.nvim_get_current_buf()
		vim.cmd("noautocmd setlocal filetype=cpp")
		vim.wo.foldenable = false
		vim.treesitter.start(buf, "cpp")
		local config = vim.deepcopy(vim.lsp.config.clangd)
		assert(config.on_attach == require("theme.adapters.clangd").attach, "Missing clangd authority adapter")
		config.root_dir = root
		client = assert(vim.lsp.get_client_by_id(assert(vim.lsp.start(config, { bufnr = buf }))))
		local function check(line, word, role, kind, deduced, from)
			local col = assert(source[line]:find(word, from or 1, true)) - 1
			local last_error
			assert(
				vim.wait(15000, function()
					vim.api.nvim_win_set_cursor(0, { line, col })
					vim.cmd("normal! zz")
					vim.cmd.redraw()
					local matched, failure = pcall(function()
						assert(client.initialized, "clangd not initialized")
						local found, inactive = false, false
						for _, token in ipairs(vim.lsp.semantic_tokens.get_at_pos(buf, line - 1, col) or {}) do
							if token.client_id == client.id then
								inactive = inactive or token.type == "comment"
								if token.type == kind then
									assert((token.modifiers.deduced == true) == deduced, "Deduced modifier mismatch")
									found = true
								end
							end
						end
						assert(not kind or found, "Missing native " .. tostring(kind) .. " token")
						assert(inactive == (role == "DxComment"), "Native inactive state mismatch")
						local group, hl, _, candidates = effective(buf, line - 1, col)
						assert(hl, "Missing foreground")
						evidence.assert_role(group, role, hl.fg)
						if kind == "type" and not deduced then
							assert(candidates[1].source == "semantic_tokens", "Alias must have semantic authority")
							assert(candidates[1].priority == vim.hl.priorities.semantic_tokens, "Type priority drift")
						elseif role == "DxComment" then
							assert(hl.italic, "Inactive style lost")
						end
					end)
					last_error = failure
					return matched
				end, 30),
				("types.cpp:%d %s: %s"):format(line, word, tostring(last_error))
			)
		end
		for _, point in ipairs({ { 5, "Plain" }, { 6, "Scalar" }, { 8, "Pointer" }, { 10, "Wrapped" } }) do
			check(point[1], point[2], "DxType", "type", false)
			check(12, point[2], "DxType", "type", false)
		end
		check(7, "Object", "DxType", "class", false)
		check(12, "Object", "DxType", "class", false)
		for _, point in ipairs({ { 13, "int" }, { 14, "bool" }, { 15, "unsigned" }, { 15, "long" } }) do
			check(point[1], point[2], "DxBuiltin", nil, false)
		end
		check(16, "auto", "DxBuiltin", "type", true)
		check(17, "decltype", "DxKeyword", "type", true)
		-- clangd currently emits no type token for decltype(auto); syntax still
		-- owns both words. Ordinary auto/decltype above exercise deduced tokens.
		check(18, "decltype", "DxKeyword", nil, false)
		check(18, "auto", "DxBuiltin", nil, false)
		check(19, "Scalar", "DxVariable", "variable", false)
		check(19, "Scalar", "DxVariable", "variable", false, assert(source[19]:find("return", 1, true)))
		for _, active in ipairs({ false, true, false }) do
			source[20] = active and "#if 1" or "#if 0"
			vim.api.nvim_buf_set_lines(buf, 19, 20, false, { source[20] })
			for _, line in ipairs({ 21, 22 }) do
				check(line, "Dormant", active and "DxType" or "DxComment", active and "type" or "comment", false)
			end
			check(23, "auto", active and "DxBuiltin" or "DxComment", active and "type" or "comment", active)
			check(24, "decltype", active and "DxKeyword" or "DxComment", active and "type" or "comment", active)
		end
		vim.lsp.buf_detach_client(buf, client.id)
		assert(not vim.lsp.buf_is_attached(buf, client.id), "clangd still attached")
		assert(vim.fn.exists("#dx_clangd_tokens_" .. client.id .. "_" .. buf) == 0, "Token callback survived detach")
		local col = assert(source[6]:find("Scalar", 1, true)) - 1
		local _, _, inspected = effective(buf, 5, col)
		assert(#(inspected.semantic_tokens or {}) == 0, "Semantic marks survived detach")
	end, debug.traceback)
	if client then
		dofile(repo_root .. "/tests/nvim/lsp_shutdown.lua")({ client }, "cpp-type-runtime", 10000)
	end
	vim.api.nvim_set_current_buf(previous)
	vim.wo.foldenable = foldenable
	if buf then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
	vim.fn.delete(root, "rf")
	assert(ok, err)
	print("C++ type runtime passed: macro aliases, builtin/deduced syntax, native inactive transitions and detach.")
end

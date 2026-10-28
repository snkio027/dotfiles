-- Actual prose, builtin, operator and parameter positions across native semantic tokens.
-- The caller supplies an already attached fixture; edits remain buffer-local.
return function(effective, language, buf, client)
	local evidence = dofile("tests/nvim/highlight_evidence.lua")
	local cases = {
		c = {
			{ "/// LineDocs", "LineDocs", "DxDocComment" },
			{ "//! BangDocs", "BangDocs", "DxDocComment" },
			{ "/** BlockDocs */", "BlockDocs", "DxDocComment" },
			{ "/*! BlockBangDocs */", "BlockBangDocs", "DxDocComment" },
			{ "// PlainLine", "PlainLine", "DxComment" },
			{ "/* PlainBlock */", "PlainBlock", "DxComment" },
			{ "//// Separator", "Separator", "DxComment" },
			{ "/*** SeparatorBlock */", "SeparatorBlock", "DxComment" },
			{ 'const char *literal = "/// Literal";', "Literal", "DxString" },
			{ "int marker = 1;" },
			{ "#if 0" },
			{ "/// DormantDocs", "DormantDocs", "DxDocComment", "inactive" },
			{ "int dormant = 2;" },
			{ "#endif" },
			{ "int builtin_value = 1;", "int", "DxBuiltin" },
			{ "int add_value(int value) { return value + 2; }", "+", "DxOperator" },
			{ "int parameter_probe(int input) {", "input", "DxParameter", "parameter-declaration" },
			{ "    int local_value = input;", "input", "DxVariable", "parameter-reference" },
			{ "    return local_value;", "local_value", "DxVariable" },
			{ "}" },
		},
		zig = {
			{ "//! ModuleDocs", "ModuleDocs", "DxDocComment" },
			{ "/// ItemDocs", "ItemDocs", "DxDocComment" },
			{ "const documented = 1;" },
			{ "// PlainLine", "PlainLine", "DxComment" },
			{ "//// Separator", "Separator", "DxComment" },
			{ 'const literal = "/// Literal";', "Literal", "DxString" },
			{ "pub fn main() void { _ = documented; _ = literal; }" },
			{ "const builtin_value: u8 = 1;", "u8", "DxBuiltin" },
			{ "const sum = builtin_value + 2;", "+", "DxOperator" },
			{ "fn parameter_probe(input: u8) u8 {", "input", "DxParameter", "parameter-declaration" },
			{ "    const local_value = input;", "input", "DxVariable", "parameter-reference" },
			{ "    return local_value;", "local_value", "DxVariable" },
			{ "}" },
		},
		rust = {
			{ "//! ModuleDocs", "ModuleDocs", "DxDocComment" },
			{ "/*! ModuleBlockDocs */", "ModuleBlockDocs", "DxDocComment" },
			{ "/// ItemDocs", "ItemDocs", "DxDocComment" },
			{ "/** ItemBlockDocs */", "ItemBlockDocs", "DxDocComment" },
			{ "pub fn documented() {}" },
			{ "// PlainLine", "PlainLine", "DxComment" },
			{ "/* PlainBlock */", "PlainBlock", "DxComment" },
			{ "//// Separator", "Separator", "DxComment" },
			{ "/*** SeparatorBlock */", "SeparatorBlock", "DxComment" },
			{ 'fn main() { documented(); let _ = "/// Literal"; }', "Literal", "DxString" },
			{ "const COUNT: u32 = 1;", "u32", "DxBuiltin" },
			{ "const SUM: u32 = COUNT + 2;", "+", "DxOperator" },
			{ "fn parameter_probe(input: u32) -> u32 {", "input", "DxParameter", "parameter-declaration" },
			{ "    let local_value = input;", "input", "DxVariable", "parameter-reference" },
			{ "    local_value", "local_value", "DxVariable" },
			{ "}" },
		},
		python = {
			{ '"""ModuleDocs"""', "ModuleDocs", "DxDocComment" },
			{ "# PlainLine", "PlainLine", "DxComment" },
			{ "class Example:", "Example", "DxType" },
			{ '    """ClassDocs"""', "ClassDocs", "DxDocComment" },
			{ "    def method(self):" },
			{ '        """MethodDocs"""', "MethodDocs", "DxDocComment" },
			{ '        return "Literal"', "Literal", "DxString" },
			{ "def documented():" },
			{ '    """FunctionDocs"""', "FunctionDocs", "DxDocComment" },
			{ '    return "Literal"', "Literal", "DxString" },
			{ 'data = """AssignedMultiline"""', "AssignedMultiline", "DxString" },
			-- ty reports builtin classes exactly like user classes (class, no
			-- defaultLibrary modifier). Preserve that semantic authority; do not
			-- guess by spelling and miscolor a user class shadowing `int`.
			{ "count: int = 1", "int", "DxBuiltin", "python-class" },
			{ "sum_value = count + 2", "+", "DxOperator" },
			{ "def parameter_probe(input: int) -> int:", "input", "DxParameter", "parameter-declaration" },
			{ "    local_value = input", "input", "DxVariable", "parameter-reference" },
			{ "    return local_value", "local_value", "DxVariable" },
		},
	}
	cases.cpp = cases.c
	local rows = assert(cases[language], "Missing documentation fixture: " .. language)
	local original = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local modified = vim.bo[buf].modified
	local semantic_clients = vim.tbl_filter(function(c)
		return c.server_capabilities.semanticTokensProvider ~= nil
	end, vim.lsp.get_clients({ bufnr = buf }))
	local function semantic(start)
		for _, c in ipairs(semantic_clients) do
			if start then
				vim.lsp.semantic_tokens.start(buf, c.id)
			else
				vim.lsp.semantic_tokens.stop(buf, c.id)
			end
		end
	end
	local ok, err = xpcall(function()
		semantic(false)
		vim.api.nvim_buf_set_lines(
			buf,
			0,
			-1,
			false,
			vim.tbl_map(function(row)
				return row[1]
			end, rows)
		)
		vim.treesitter.get_parser(buf, language):parse()
		local function check(stage)
			for line, row in ipairs(rows) do
				if row[2] then
					local col = assert(row[1]:find(row[2], 1, true)) - 1
					vim.api.nvim_win_set_cursor(0, { line, col })
					vim.cmd.redraw()
					local group, hl = effective(buf, line - 1, col)
					local context = ("DOC_COMMENT [%s/%s/%s]"):format(language, stage, row[2])
					assert(hl, context .. ": no foreground")
					local role = row[3]
					if row[4] == "inactive" and stage == "semantic" and client then
						role = "DxComment"
					end
					if row[4] == "python-class" and stage == "semantic" and client and client.name == "ty" then
						local native_class = false
						for _, token in ipairs(vim.lsp.semantic_tokens.get_at_pos(buf, line - 1, col) or {}) do
							if token.client_id == client.id and token.type == "class" then
								assert(
									not token.modifiers.defaultLibrary,
									context .. ": revisit builtin classification"
								)
								native_class = true
							end
						end
						assert(native_class, context .. ": expected ty class evidence")
						role = "DxType"
					end
					local native = stage == "semantic" and client and client.server_capabilities.semanticTokensProvider
					-- References need the language server to resolve their binding.
					-- Syntax-only references remain ordinary variables in all five parsers.
					if row[4] == "parameter-reference" and native then
						role = "DxParameter"
					end
					evidence.assert_role(group, role, hl.fg)
					-- Independent approved palette values, not copied from live role groups.
					local expected = {
						DxDocComment = 0xAAA67A,
						DxComment = 0x8490AE,
						DxString = 0xB8D07A,
						DxBuiltin = 0x8FBCE6,
						DxOperator = 0xA7B5CC,
						DxType = 0x3DD1BB,
						DxParameter = 0xCBB79A,
						DxVariable = 0xC4CAE0,
					}
					assert(hl.fg == expected[role], context .. ": wrong final foreground")
					if
						native
						and (
							row[4] == "parameter-declaration"
							or row[4] == "parameter-reference"
							or row[2] == "local_value"
						)
					then
						local token_type = row[2] == "local_value" and "variable" or "parameter"
						local found = false
						for _, token in ipairs(vim.lsp.semantic_tokens.get_at_pos(buf, line - 1, col) or {}) do
							found = found or (token.client_id == client.id and token.type == token_type)
						end
						assert(found, context .. ": missing native " .. token_type .. " evidence")
					end
					if row[4] == "parameter-declaration" then
						local builtin = ({ c = "int", cpp = "int", rust = "u32", zig = "u8", python = "int" })[language]
						local type_col = (language == "c" or language == "cpp")
								and row[1]:find(builtin .. " " .. row[2], 1, true)
							or row[1]:find(builtin, col + #row[2] + 1, true)
						type_col = assert(type_col) - 1
						vim.api.nvim_win_set_cursor(0, { line, type_col })
						vim.cmd.redraw()
						local type_group, type_hl = effective(buf, line - 1, type_col)
						local type_role = language == "python" and native and client.name == "ty" and "DxType"
							or "DxBuiltin"
						evidence.assert_role(type_group, type_role, type_hl.fg)
						assert(type_hl.fg == expected[type_role], context .. ": adjacent type foreground changed")
						assert(type_hl.fg ~= hl.fg, context .. ": parameter merged with adjacent type")
					end
					if row[3] == "DxDocComment" or row[3] == "DxComment" then
						assert(hl.italic and not hl.bold, context .. ": comment style changed")
					else
						assert(not hl.italic and not hl.bold, context .. ": source style changed")
					end
					if
						stage == "semantic"
						and client
						and client.server_capabilities.semanticTokensProvider
						and row[3] == "DxDocComment"
						and language ~= "c"
						and language ~= "cpp"
					then
						local found = false
						for _, token in ipairs(vim.lsp.semantic_tokens.get_at_pos(buf, line - 1, col) or {}) do
							if token.client_id == client.id and token.modifiers.documentation then
								assert(token.type == (language == "python" and "string" or "comment"), context)
								found = true
							end
						end
						assert(found, context .. ": native documentation modifier absent")
					end
				end
			end
		end
		check("syntax")
		semantic(true)
		local last_error
		assert(
			vim.wait(15000, function()
				local passed, failure = pcall(function()
					if client and client.server_capabilities.semanticTokensProvider then
						local anchors = {
							c = { 10, "marker" },
							cpp = { 10, "marker" },
							zig = { 3, "documented" },
							rust = { 5, "documented" },
							python = { 3, "Example" },
						}
						local anchor = anchors[language]
						local col = assert(rows[anchor[1]][1]:find(anchor[2], 1, true)) - 1
						local found = false
						for _, token in ipairs(vim.lsp.semantic_tokens.get_at_pos(buf, anchor[1] - 1, col) or {}) do
							found = found or token.client_id == client.id
						end
						assert(found, "Documentation fixture has no fresh native semantic tokens")
					end
					check("semantic")
				end)
				last_error = failure
				return passed
			end, 30),
			("DOC_COMMENT [%s/semantic]: %s"):format(language, tostring(last_error))
		)
		semantic(false)
		check("syntax-after-stop")
	end, debug.traceback)
	semantic(false)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, original)
	vim.bo[buf].modified = modified
	semantic(true)
	assert(ok, err)
	io.stdout:write(("DOC_COMMENT_COMPLETE %s (%s)\n"):format(language, client and client.name or "syntax-only"))
	io.stdout:write(("COLOR_HIERARCHY_COMPLETE %s (syntax/semantic/syntax-after-stop)\n"):format(language))
	io.stdout:write(("PARAMETER_COMPLETE %s (declaration/reference/local control)\n"):format(language))
	io.stdout:flush()
end

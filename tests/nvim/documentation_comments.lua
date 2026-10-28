-- Actual comment positions, before and after native semantic tokens arrive.
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
		},
		zig = {
			{ "//! ModuleDocs", "ModuleDocs", "DxDocComment" },
			{ "/// ItemDocs", "ItemDocs", "DxDocComment" },
			{ "const documented = 1;" },
			{ "// PlainLine", "PlainLine", "DxComment" },
			{ "//// Separator", "Separator", "DxComment" },
			{ 'const literal = "/// Literal";', "Literal", "DxString" },
			{ "pub fn main() void { _ = documented; _ = literal; }" },
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
		},
		python = {
			{ '"""ModuleDocs"""', "ModuleDocs", "DxDocComment" },
			{ "# PlainLine", "PlainLine", "DxComment" },
			{ "class Example:" },
			{ '    """ClassDocs"""', "ClassDocs", "DxDocComment" },
			{ "    def method(self):" },
			{ '        """MethodDocs"""', "MethodDocs", "DxDocComment" },
			{ '        return "Literal"', "Literal", "DxString" },
			{ "def documented():" },
			{ '    """FunctionDocs"""', "FunctionDocs", "DxDocComment" },
			{ '    return "Literal"', "Literal", "DxString" },
			{ 'data = """AssignedMultiline"""', "AssignedMultiline", "DxString" },
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
					evidence.assert_role(group, role, hl.fg)
					local expected = { DxDocComment = 0xAAA67A, DxComment = 0x7580A3, DxString = 0xB8D07A }
					assert(hl.fg == expected[role], context .. ": wrong final foreground")
					if row[3] ~= "DxString" then
						assert(hl.italic and not hl.bold, context .. ": comment style changed")
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
	io.stdout:flush()
end

-- Actual screen cells, parser tokens and native LSP locations, not a formatter
-- mock. Runs inside cpp_dependency.lua with server startup disabled.
return function()
	local view = require("config.cpp_dependency_view")
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	local header = root .. "/build/_deps/vendor/include/header.cpp"
	local own = root .. "/main.cpp"
	local lines = {
		"#  if FEATURE",
		"int active;",
		"#\telse",
		"int inactive;",
		"#    endif",
		"  #  pragma once",
		"/*",
		"#  if COMMENT",
		"*/",
		'const char* text = R"raw(',
		"#  if STRING",
		')raw";',
		"#define STRINGIFY(x) \\",
		"#  x",
		"// #  if COMMENT",
		"#  define VALUE 1",
		"#  undef VALUE",
		"#  include <header.h>",
		"#define BODY \\",
		"#  if CONTINUATION",
		"#  if OTHER",
		"#  elif ANOTHER",
		"#  else",
		"#  endif",
	}
	vim.fn.mkdir(vim.fs.dirname(header), "p")
	vim.fn.writefile(lines, header)
	vim.fn.writefile(lines, own)
	local original_win, original_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
	local notify = vim.notify
	local buffers = {}
	local ns = vim.api.nvim_create_namespace("dependency-view-coordinate-control")
	local options = {}
	for _, name in ipairs({
		"number",
		"relativenumber",
		"signcolumn",
		"foldcolumn",
		"wrap",
		"conceallevel",
		"concealcursor",
	}) do
		options[name] = vim.wo[name]
	end
	local function screen(row, col, count)
		vim.cmd.redraw()
		local result = {}
		for offset = 0, count - 1 do
			result[#result + 1] = vim.fn.screenstring(row, col + offset)
		end
		return table.concat(result)
	end
	local function matches()
		return vim.tbl_filter(function(match)
			return match.group == "Conceal"
		end, vim.fn.getmatches())
	end
	local function jump(path, line, col)
		assert(vim.lsp.util.show_document({
			uri = vim.uri_from_fname(path),
			range = { start = { line = line, character = col }, ["end"] = { line = line, character = col + 1 } },
		}, "utf-16", { focus = true }))
		local buf = vim.api.nvim_get_current_buf()
		buffers[buf] = true
		return buf
	end
	local ok, err = xpcall(function()
		vim.notify = function() end
		vim.wo.number, vim.wo.relativenumber = false, false
		vim.wo.signcolumn, vim.wo.foldcolumn = "no", "0"
		vim.wo.wrap, vim.wo.conceallevel, vim.wo.concealcursor = false, 0, ""
		local buf = jump(header, 0, 4)
		vim.treesitter.start(buf, "cpp")
		vim.treesitter.get_parser(buf, "cpp"):parse(true)
		assert(vim.bo.readonly and not vim.bo.modifiable)
		local tick = vim.api.nvim_buf_get_changedtick(buf)
		vim.api.nvim_buf_set_extmark(buf, ns, 2, 0, {
			end_col = #lines[3],
			hl_group = "@lsp.type.comment.cpp",
			priority = 129,
		})
		vim.diagnostic.set(ns, buf, { { lnum = 1, col = 4, severity = 1, message = "coordinate control" } })
		local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
		local diagnostics = vim.diagnostic.get(buf, { namespace = ns })
		assert(screen(1, 1, 11) == "#if FEATURE", "COMPACT_DIRECTIVE_NOT_RENDERED")
		assert(screen(3, 1, 5) == "#else", "Tab whitespace was not concealed")
		assert(screen(5, 1, 6) == "#endif")
		assert(screen(6, 1, 14) == "  #pragma once", "Leading indentation was changed")
		assert(screen(8, 1, #lines[8]) == lines[8], "Block comment was concealed")
		assert(screen(11, 1, #lines[11]) == lines[11], "Raw string was concealed")
		assert(screen(14, 1, #lines[14]) == lines[14], "Macro body was concealed")
		assert(screen(16, 1, 15) == "#define VALUE 1")
		assert(screen(18, 1, 19) == "#include <header.h>")
		assert(screen(20, 1, #lines[20]) == lines[20], "Macro continuation was concealed")
		local keyword_attr, inactive_attr, builtin_attr =
			vim.fn.screenattr(1, 2), vim.fn.screenattr(3, 2), vim.fn.screenattr(2, 1)
		assert(keyword_attr ~= inactive_attr, "Inactive directive lost its separate style")
		assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 4 }), "Native LSP byte column changed")
		vim.cmd.CppDependencyCompact()
		assert(#matches() == 0 and screen(1, 1, #lines[1]) == lines[1], "Original view was not restored")
		assert(vim.wo.conceallevel == 0 and vim.wo.concealcursor == "", "Original window options lost")
		assert(vim.fn.screenattr(1, 4) == keyword_attr, "Active keyword color changed")
		assert(
			vim.fn.screenattr(3, vim.fn.strdisplaywidth("#\t") + 1) == inactive_attr,
			"Inactive color/italic changed"
		)
		assert(vim.fn.screenattr(2, 1) == builtin_attr, "Builtin color changed")
		vim.cmd.CppDependencyCompact()
		assert(screen(1, 1, 3) == "#if")
		-- Repeated enter/reload notifications must not accumulate matches.
		local count = #matches()
		view.refresh()
		view.refresh()
		assert(#matches() == count)
		assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), lines))
		assert(vim.deep_equal(vim.fn.readfile(header), lines), "Display wrote dependency bytes")
		assert(vim.api.nvim_buf_get_changedtick(buf) == tick and not vim.bo.modified)
		assert(vim.deep_equal(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }), marks))
		assert(vim.deep_equal(vim.diagnostic.get(buf, { namespace = ns }), diagnostics))
		-- Two windows, shared buffer toggle, then dependency -> own-source switch.
		vim.cmd.vsplit()
		local split = vim.api.nvim_get_current_win()
		assert(#matches() == count)
		vim.cmd.CppDependencyCompact()
		assert(#matches() == 0 and #vim.fn.getmatches(original_win) == 0)
		vim.cmd.CppDependencyCompact()
		jump(own, 0, 4)
		assert(
			#matches() == 0 and vim.wo.conceallevel == 0 and vim.wo.concealcursor == "",
			"Conceal leaked to own source"
		)
		vim.cmd.CppDependencyCompact()
		assert(#matches() == 0, "Own source toggle was accepted")
		vim.api.nvim_win_close(split, true)
		vim.api.nvim_set_current_win(original_win)
		assert(screen(1, 1, 3) == "#if", "Other window lost its dependency view")
		vim.cmd.CppDependencyEdit()
		assert(#matches() == 0 and screen(1, 1, #lines[1]) == lines[1], "Editing kept compact display")
		vim.cmd.edit()
		assert(screen(1, 1, 3) == "#if", "Reopen failed to restore compact view")
		-- Parser-unavailable path fails closed, never falls back to a text regex.
		vim.cmd.CppDependencyCompact()
		local get_parser = vim.treesitter.get_parser
		vim.treesitter.get_parser = function()
			error("parser unavailable")
		end
		local refreshed, refresh_error = pcall(vim.cmd.CppDependencyCompact)
		vim.treesitter.get_parser = get_parser
		assert(refreshed, refresh_error)
		assert(#matches() == 0 and screen(1, 1, #lines[1]) == lines[1])
		view.refresh()
		assert(screen(1, 1, 3) == "#if")
		-- Existing window matches survive our cleanup; C uses its own parser.
		local unrelated = vim.fn.matchaddpos("Search", { { 2, 5, 6 } })
		vim.cmd.CppDependencyCompact()
		assert(vim.fn.getmatches()[1].id == unrelated, "Unrelated window match was deleted")
		vim.fn.matchdelete(unrelated)
		vim.cmd("setlocal filetype=c")
		vim.cmd.CppDependencyCompact()
		assert(screen(1, 1, 3) == "#if", "C parser directive support missing")
		-- Re-read external changes without leaving stale conceal ranges behind.
		vim.fn.writefile({ "// reloaded", "#  if NEW", "#  endif" }, header)
		vim.cmd.edit()
		vim.cmd("normal! ggzt")
		assert(screen(1, 1, 11) == "// reloaded" and screen(2, 1, 7) == "#if NEW")
		vim.fn.writefile(lines, header)
		vim.cmd.edit()
		-- Explicit navigation still lands on the original source byte column.
		jump(header, 15, 9)
		assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 16, 9 }))
	end, debug.traceback)
	vim.notify = notify
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if win ~= original_win and buffers[vim.api.nvim_win_get_buf(win)] then
			vim.api.nvim_win_close(win, true)
		end
	end
	vim.api.nvim_set_current_win(original_win)
	vim.api.nvim_set_current_buf(original_buf)
	for buf in pairs(buffers) do
		vim.diagnostic.reset(ns, buf)
		vim.api.nvim_buf_delete(buf, { force = true })
	end
	for name, value in pairs(options) do
		vim.wo[name] = value
	end
	vim.fn.delete(root, "rf")
	assert(ok, err)
	print("Dependency compact view passed: rendered cells, syntax boundaries, colors, coordinates, windows, toggles.")
end

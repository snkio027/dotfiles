-- Real provider identity, including shadowing: syntax finds the lambda;
-- clangd references decide which occurrences belong to that binding.
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local source = root .. "/main.cpp"
local lines = {
	"struct Sink { template <class T> Sink(T) {} }; template <class T> void consume(T) {}",
	"int main() {",
	"  int cnt = 10;",
	"  auto by_value = [cnt] { return cnt; };",
	"  auto by_ref = [&cnt] { return ++cnt; };",
	"  const auto unused = [] { return 0; };",
	"  auto immediate = [] { return 1; }();",
	"  auto number = cnt;",
	"  auto copied = by_value;",
	"  auto pointer = +[] { return 1; };",
	"  struct Callable { int operator()() { return 1; } };",
	"  Callable object;",
	"  int sum = by_value() + by_ref();",
	"  consume(by_value);",
	"  { int by_value = 0; sum += by_value; }",
	"  /* 中文 😺 */ auto unicode = [] { return 2; };",
	"  sum += unicode();",
	"#if 0",
	"  auto inactive = [] { return 0; };",
	"#endif",
	"  Sink stored = [] { return 3; };",
	"  (void)stored;",
	"  auto produced = by_value();",
	"  (void)produced;",
	"  return sum + immediate + number + copied() + pointer() + object();",
	"}",
}
vim.fn.writefile(lines, source)
vim.fn.writefile({ "-std=c++23", "-Wall", "-Wextra" }, root .. "/compile_flags.txt")
local client, buf
local original_request
local ns = vim.api.nvim_create_namespace("dx_clangd_lambda")
local evidence = dofile("tests/nvim/highlight_evidence.lua")
local function marks()
	return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
end
local function wait_for(predicate, message)
	assert(vim.wait(15000, predicate, 20), message)
end
local function key(row, name, from)
	return (row - 1) .. ":" .. (assert(lines[row]:find(name, from or 1, true)) - 1)
end
local expected = {
	[key(4, "by_value")] = "by_value",
	[key(5, "by_ref")] = "by_ref",
	[key(6, "unused")] = "unused",
	[key(9, "by_value")] = "by_value",
	[key(13, "by_value")] = "by_value",
	[key(13, "by_ref")] = "by_ref",
	[key(14, "by_value")] = "by_value",
	[key(16, "unicode")] = "unicode",
	[key(17, "unicode")] = "unicode",
	[key(23, "by_value")] = "by_value",
}
local function assert_projection()
	local actual = {}
	for _, mark in ipairs(marks()) do
		actual[mark[2] .. ":" .. mark[3]] = lines[mark[2] + 1]:sub(mark[3] + 1, mark[4].end_col)
		assert(mark[4].hl_group == "DxCallable", "lambda mark lost semantic identity")
		assert(mark[4].priority == vim.hl.priorities.semantic_tokens + 3, "lambda lost LSP foreground authority")
		evidence.assert_role(
			mark[4].hl_group,
			"DxCallable",
			vim.api.nvim_get_hl(0, { name = mark[4].hl_group, link = false }).fg
		)
	end
	assert(vim.deep_equal(actual, expected), "lambda projection/negative controls: " .. vim.inspect(actual))
end
local ok, err = xpcall(function()
	require("lazy").load({ plugins = { "nvim-lspconfig" } })
	assert(vim.lsp.config.clangd.on_attach == require("theme.adapters.clangd_lambda").attach)
	vim.cmd.edit(vim.fn.fnameescape(source))
	buf = vim.api.nvim_get_current_buf()
	wait_for(function()
		client = vim.lsp.get_clients({ bufnr = buf, name = "clangd" })[1]
		return client and client.initialized
	end, "lambda clangd did not attach")
	wait_for(function()
		return #marks() == vim.tbl_count(expected)
	end, "lambda declaration/references missing")
	assert_projection()
	local reply = client:request_sync("textDocument/semanticTokens/full", {
		textDocument = vim.lsp.util.make_text_document_params(buf),
	}, 15000, buf)
	assert(reply and reply.result and not reply.err, "missing raw semantic tokens")
	local row, col, found = 0, 0, false
	local types = client.server_capabilities.semanticTokensProvider.legend.tokenTypes
	for i = 1, #reply.result.data, 5 do
		local data = reply.result.data
		if data[i] > 0 then
			col = 0
		end
		row, col = row + data[i], col + data[i + 1]
		if row == 3 and col == 7 then
			assert(types[data[i + 3] + 1] == "variable", "provider evidence no longer describes a variable")
			found = true
		end
	end
	assert(found, "declaration raw token missing")

	wait_for(function()
		for _, diagnostic in ipairs(vim.diagnostic.get(buf)) do
			if diagnostic.lnum == 5 and diagnostic._tags and diagnostic._tags.unnecessary then
				return true
			end
		end
		return false
	end, "real unused-lambda diagnostic missing")
	local unused = vim.api.nvim_get_hl(0, { name = "DiagnosticUnnecessary", link = false })
	assert(
		unused.italic and unused.fg == nil and unused.bg == nil and not unused.nocombine,
		"unused state must not replace semantic foreground"
	)
	local warn = vim.api.nvim_get_hl(0, { name = "DiagnosticUnderlineWarn", link = false })
	assert(warn.undercurl and warn.sp == vim.api.nvim_get_hl(0, { name = "DxWarn", link = false }).fg)
	assert_projection()

	-- Edits immediately discard old marks; changing a binding to a scalar must
	-- not reuse a same-name result. Restore, then restart the real client.
	vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "  auto by_value = 1;" })
	assert(#marks() == 0, "edit retained stale lambda marks")
	wait_for(function()
		return #marks() > 0
	end, "remaining lambdas did not refresh")
	for _, mark in ipairs(marks()) do
		assert(mark[2] ~= 3 and mark[2] ~= 8 and mark[2] ~= 13, "scalar was recolored by a stale lambda result")
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	wait_for(function()
		return #marks() == vim.tbl_count(expected)
	end, "restored lambda failed to refresh")
	assert_projection()

	-- Keep actual clangd requests, but hold their callbacks across an edit.
	-- Old successful replies and current server failures must both fail closed.
	original_request = client.request
	local held = {}
	client.request = function(self, method, params, handler, ...)
		if method ~= "textDocument/references" then
			return original_request(self, method, params, handler, ...)
		end
		return original_request(self, method, params, function(request_err, result, context)
			held[#held + 1] = function(injected_err)
				handler(injected_err or request_err, result, context)
			end
		end, ...)
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	wait_for(function()
		return #held == 5
	end, "reference callbacks were not captured")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "int main() { int scalar = 1; return scalar; }" })
	for _, handler in ipairs(held) do
		handler()
	end
	assert(#marks() == 0, "stale server response repainted edited code")
	held = {}
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	wait_for(function()
		return #held == 5
	end, "second reference request batch missing")
	for _, handler in ipairs(held) do
		handler({ code = -32603, message = "injected reference failure" })
	end
	assert(#marks() == 0, "server error guessed a callable role")
	client.request = original_request
	original_request = nil
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	wait_for(function()
		return #marks() == vim.tbl_count(expected)
	end, "projection did not recover after failure")
	assert_projection()
	vim.cmd("lsp restart clangd")
	local old_id = client.id
	wait_for(function()
		return #marks() == 0
	end, "client detach retained stale lambda marks")
	wait_for(function()
		client = vim.lsp.get_clients({ bufnr = buf, name = "clangd" })[1]
		return client and client.initialized and client.id ~= old_id and #marks() == vim.tbl_count(expected)
	end, "lambda adapter did not recover after clangd restart")
	assert_projection()
	vim.cmd("edit!")
	wait_for(function()
		return #marks() == vim.tbl_count(expected)
	end, "buffer reload lost lambda projection")
	assert_projection()
	print(
		"Clangd lambda contract passed: declarations/calls/references, shadowing, Unicode, unused diagnostics, edit/restart."
	)
end, debug.traceback)
if original_request then
	client.request = original_request
end
if buf and vim.api.nvim_buf_is_valid(buf) then
	vim.api.nvim_buf_delete(buf, { force = true })
end
if client then
	dofile("tests/nvim/lsp_shutdown.lua")({ client }, "lambda-contract", 10000)
end
vim.fn.delete(root, "rf")
assert(ok, err)

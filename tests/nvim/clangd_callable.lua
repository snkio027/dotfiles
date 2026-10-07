-- Actual clangd AST, semantic tokens, and document highlights; no mock type oracle.
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
	"#include <functional>",
	"#include <memory>",
	'#include "callables.hpp"',
	"int step(int n) { return n; }",
	"struct Functor { int operator()(int n) const { return n; } };",
	"struct Derived : Functor {};",
	"struct Templated { template <class T> T operator()(T n) { return n; } };",
	"struct Worker { int method(int n) { return n; } int data = 0; int (*callback)(int) = step; };",
	"struct Deleted { void operator()() = delete; };",
	"struct Private { private: void operator()(); };",
	"template <class T> auto unresolved(T unknown) { return unknown(1); }",
	"auto factory() { return [](int n) { return n; }; }",
	"int parameters(int (*param_pointer)(int), int (&param_ref)(int), std::function<int(int)> param_wrapper) {",
	"  return param_pointer(1) + param_ref(2) + param_wrapper(3);",
	"}",
	"int examples() {",
	"  int (*explicit_pointer)(int) = step;",
	"  int (&function_ref)(int) = step;",
	"  auto inferred_pointer = step;",
	"  int (**indirect)(int) = &explicit_pointer;",
	"  int (*array[1])(int) = {step};",
	"  int scalar = 1; int *ordinary_pointer = &scalar;",
	"  using Fn = int (*)(int); Fn alias_pointer = step; Fn unused_alias = step;",
	"  auto fn_obj = std::ranges::less{};",
	"  std::ranges::less unused_object;",
	"  std::function<int(int)> wrapper = step;",
	"  auto move_wrapper = [state = std::make_unique<int>(1)](int n) { return *state + n; };",
	"  Functor functor; Derived inherited; Templated templated;",
	"  auto reference_wrapper = std::ref(functor);",
	"  // bind_front is checked in its own C++20 translation unit below.",
	"  auto returned = factory(); auto unused_copy = returned;",
	"  auto ordinary_object = std::make_unique<Functor>();",
	"  Deleted deleted; Private inaccessible;",
	"  Worker worker; int (Worker::*method_pointer)(int) = &Worker::method;",
	"  int Worker::*data_pointer = &Worker::data;",
	"  auto&& reference_lambda = [] { return 1; };",
	"  int result = explicit_pointer(1) + function_ref(2) + alias_pointer(3);",
	"  result += fn_obj(1,2) + wrapper(3) + move_wrapper(4);",
	"  result += functor(1) + inherited(2) + templated(3) + reference_wrapper(4);",
	"  result += returned(2) + worker.callback(3) + (worker.*method_pointer)(4);",
	"  result += (**indirect)(1) + array[0](1) + (*ordinary_object)(2) + reference_lambda();",
	"  return result + *ordinary_pointer + worker.*data_pointer + external_callback(1);",
	"}",
}
vim.fn.writefile(lines, source)
vim.fn.writefile({ "inline auto external_callback = [](int n) { return n; };" }, root .. "/callables.hpp")
vim.fn.writefile({ "-std=c++23", "-Wall", "-Wextra" }, root .. "/compile_flags.txt")
local client, buf
local original_request
local ns = vim.api.nvim_create_namespace("dx_clangd_callable")
local evidence = dofile("tests/nvim/highlight_evidence.lua")
local function marks()
	return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
end
local function wait_for(predicate, message)
	if not vim.wait(15000, predicate, 20) then
		local actual = {}
		for _, mark in ipairs(marks()) do
			actual[mark[2] .. ":" .. mark[3]] = lines[mark[2] + 1]:sub(mark[3] + 1, mark[4].end_col)
		end
		error(message .. ": " .. vim.inspect({
			actual = actual,
			server = client and client.server_info,
			diagnostics = vim.diagnostic.get(buf),
		}))
	end
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
	[key(9, "copied")] = "copied",
	[key(10, "pointer")] = "pointer",
	[key(12, "object")] = "object",
	[key(25, "copied")] = "copied",
	[key(25, "pointer")] = "pointer",
	[key(25, "object")] = "object",
}
-- These exact, independently listed binding names must be Callable at every
-- occurrence. Unlisted names (including unused/unknown objects) must not be.
local callable_names = {
	"callback",
	"param_pointer",
	"param_ref",
	"param_wrapper",
	"explicit_pointer",
	"function_ref",
	"inferred_pointer",
	"alias_pointer",
	"fn_obj",
	"wrapper",
	"move_wrapper",
	"functor",
	"inherited",
	"templated",
	"reference_wrapper",
	"returned",
	"method_pointer",
	"reference_lambda",
	"external_callback",
}
for row = 27, #lines do
	for _, name in ipairs(callable_names) do
		local from = 1
		while true do
			local first, last = lines[row]:find("%f[%w_]" .. name .. "%f[^%w_]", from)
			if not first then
				break
			end
			expected[key(row, name, first)] = name
			from = last + 1
		end
	end
end
local function assert_projection()
	local actual = {}
	for _, mark in ipairs(marks()) do
		actual[mark[2] .. ":" .. mark[3]] = lines[mark[2] + 1]:sub(mark[3] + 1, mark[4].end_col)
		assert(mark[4].hl_group == "DxCallable", "callable mark lost semantic identity")
		assert(mark[4].priority == vim.hl.priorities.semantic_tokens + 3, "callable lost LSP foreground authority")
		evidence.assert_role(
			mark[4].hl_group,
			"DxCallable",
			vim.api.nvim_get_hl(0, { name = mark[4].hl_group, link = false }).fg
		)
	end
	assert(vim.deep_equal(actual, expected), "callable projection/negative controls: " .. vim.inspect(actual))
end
local function idle()
	for _, request in pairs(client.requests) do
		if
			request.type == "pending"
			and (
				request.method == "textDocument/ast"
				or request.method == "textDocument/semanticTokens/full"
				or request.method == "textDocument/documentHighlight"
			)
		then
			return false
		end
	end
	return true
end
local function projection_ready()
	return #marks() == vim.tbl_count(expected) and idle()
end
local ok, err = xpcall(function()
	require("lazy").load({ plugins = { "nvim-lspconfig" } })
	assert(vim.lsp.config.clangd.on_attach == require("theme.adapters.clangd_callable").attach)
	vim.cmd.edit(vim.fn.fnameescape(source))
	buf = vim.api.nvim_get_current_buf()
	wait_for(function()
		client = vim.lsp.get_clients({ bufnr = buf, name = "clangd" })[1]
		return client and client.initialized
	end, "lambda clangd did not attach")
	wait_for(function()
		return projection_ready()
	end, "callable declaration/references missing: " .. vim.tbl_count(expected))
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
	for _, diagnostic in ipairs(vim.diagnostic.get(buf)) do
		assert(diagnostic.severity ~= vim.diagnostic.severity.ERROR, "invalid callable fixture: " .. diagnostic.message)
	end
	for _, other in ipairs(vim.api.nvim_list_bufs()) do
		assert(vim.api.nvim_buf_get_name(other) ~= root .. "/callables.hpp", "adapter opened a header buffer")
	end

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
		return #marks() > 0 and idle()
	end, "remaining lambdas did not refresh")
	for _, mark in ipairs(marks()) do
		assert(mark[2] ~= 3 and mark[2] ~= 8 and mark[2] ~= 13, "scalar was recolored by a stale lambda result")
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	wait_for(function()
		return projection_ready()
	end, "restored lambda failed to refresh")
	assert_projection()

	-- Keep actual clangd requests, but hold their callbacks across an edit.
	-- Old successful replies and current server failures must both fail closed.
	original_request = client.request
	local held = {}
	client.request = function(self, method, params, handler, ...)
		if method ~= "textDocument/documentHighlight" then
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
		return #held == 4
	end, "bounded document highlight callbacks were not captured")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "int main() { int scalar = 1; return scalar; }" })
	for _, handler in ipairs(held) do
		handler()
	end
	assert(#marks() == 0, "stale server response repainted edited code")
	client.request = original_request
	local stale_ast
	client.request = function(self, method, params, handler, ...)
		if method ~= "textDocument/ast" then
			return original_request(self, method, params, handler, ...)
		end
		return original_request(self, method, params, function(request_err, result, context)
			stale_ast = function()
				handler(request_err, result, context)
			end
		end, ...)
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	wait_for(function()
		return stale_ast and idle()
	end, "AST callback was not captured")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "int main() { int scalar = 1; return scalar; }" })
	stale_ast()
	assert(#marks() == 0, "stale AST paired with newer tokens")
	client.request = original_request
	-- All three provider stages must fail closed; actual requests still run.
	for _, failed_method in ipairs({
		"textDocument/ast",
		"textDocument/semanticTokens/full",
		"textDocument/documentHighlight",
	}) do
		local failures = 0
		client.request = function(self, method, params, handler, ...)
			if method ~= failed_method or not handler then
				return original_request(self, method, params, handler, ...)
			end
			return original_request(self, method, params, function(_, _, context)
				failures = failures + 1
				handler({ code = -32603, message = "injected provider failure" }, nil, context)
			end, ...)
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		wait_for(function()
			return failures > 0 and idle()
		end, failed_method .. " failure was not observed")
		assert(#marks() == 0, failed_method .. " error guessed a callable role")
	end
	local unconfirmed = 0
	client.request = function(self, method, params, handler, ...)
		if method ~= "textDocument/documentHighlight" or not handler then
			return original_request(self, method, params, handler, ...)
		end
		return original_request(self, method, params, function(request_err, result, context)
			unconfirmed = unconfirmed + 1
			handler(
				request_err,
				vim.tbl_filter(function(highlight)
					return not vim.deep_equal(highlight.range.start, params.position)
				end, result or {}),
				context
			)
		end, ...)
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	wait_for(function()
		return unconfirmed > 0 and idle()
	end, "unconfirmed response control did not run")
	assert(#marks() == 0, "response without the evidenced occurrence painted a role")
	local ast_requests = 0
	client.request = function(self, method, ...)
		if method == "textDocument/ast" then
			ast_requests = ast_requests + 1
		end
		return original_request(self, method, ...)
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "/*" .. string.rep(" ", 512 * 1024) .. "*/" })
	vim.wait(400, function()
		return ast_requests > 0
	end, 20)
	assert(ast_requests == 0 and #marks() == 0, "oversized buffer bypassed the AST budget")
	client.request = original_request
	original_request = nil
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	wait_for(function()
		return projection_ready()
	end, "projection did not recover after failure")
	assert_projection()
	vim.cmd("lsp restart clangd")
	local old_id = client.id
	wait_for(function()
		return #marks() == 0
	end, "client detach retained stale lambda marks")
	wait_for(function()
		client = vim.lsp.get_clients({ bufnr = buf, name = "clangd" })[1]
		return client and client.initialized and client.id ~= old_id and projection_ready()
	end, "lambda adapter did not recover after clangd restart")
	assert_projection()
	vim.cmd("edit!")
	wait_for(function()
		return projection_ready()
	end, "buffer reload lost lambda projection")
	assert_projection()
	local positions = vim.tbl_count(expected)
	vim.api.nvim_buf_delete(buf, { force = true })
	dofile("tests/nvim/lsp_shutdown.lua")({ client }, "callable-core", 10000)
	client, buf = nil, nil

	-- GCC 14.2's C++23 bind_front path uses a deduced-return forward_like
	-- that clangd 23 cannot resolve. Do not classify its RecoveryExpr as a
	-- valid call or mask diagnostics. Exercise the real C++20 wrapper in a
	-- separate translation unit; the other 55 positions stay under C++23.
	local binder = root .. "/binder"
	vim.fn.mkdir(binder, "p")
	vim.fn.writefile({ "-std=c++20", "-Wall", "-Wextra" }, binder .. "/compile_flags.txt")
	lines = {
		"#include <functional>",
		"static_assert(__cplusplus == 202002L);",
		"int step(int n) { return n; }",
		"int main() {",
		"  int unused_binder = 0;",
		"  auto bound = std::bind_front(step, 1);",
		"  return bound();",
		"}",
	}
	expected = { [key(6, "bound")] = "bound", [key(7, "bound")] = "bound" }
	vim.fn.writefile(lines, binder .. "/main.cpp")
	vim.cmd.edit(vim.fn.fnameescape(binder .. "/main.cpp"))
	buf = vim.api.nvim_get_current_buf()
	wait_for(function()
		client = vim.lsp.get_clients({ bufnr = buf, name = "clangd" })[1]
		return client and client.initialized and projection_ready()
	end, "C++20 bind_front declaration/references missing")
	assert_projection()
	-- Require an actual diagnostic publication, not an initially empty store.
	wait_for(function()
		for _, diagnostic in ipairs(vim.diagnostic.get(buf)) do
			if diagnostic.lnum == 4 and diagnostic.message:find("unused_binder", 1, true) then
				return true
			end
		end
		return false
	end, "bind_front fixture diagnostics missing")
	for _, diagnostic in ipairs(vim.diagnostic.get(buf)) do
		assert(
			diagnostic.severity ~= vim.diagnostic.severity.ERROR,
			"invalid bind_front fixture: " .. diagnostic.message
		)
	end
	print(
		("Clangd callable contract passed: %d positions (C++23 core + C++20 bind_front), typed pointers/references, resolved functors/wrappers, negatives, Unicode, failures, edit/restart."):format(
			positions + vim.tbl_count(expected)
		)
	)
end, debug.traceback)
if original_request then
	client.request = original_request
end
if buf and vim.api.nvim_buf_is_valid(buf) then
	vim.api.nvim_buf_delete(buf, { force = true })
end
if client then
	dofile("tests/nvim/lsp_shutdown.lua")({ client }, "callable-contract", 10000)
end
vim.fn.delete(root, "rf")
assert(ok, err)
